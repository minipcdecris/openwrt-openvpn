#!/bin/sh

echo ""
echo "🔧 ACTUALIZANDO SISTEMA - SOLO BLOQUEO POR NOMBRE"
echo "================================================="

# Actualizar el script
cat > /usr/bin/gestion << 'EOF'
#!/bin/sh

# Archivos de configuración
NOMBRES_FILE="/etc/openvpn/clientes/nombres.txt"
SUSPENDED_FILE="/etc/openvpn/clientes/suspended.txt"
LOG_FILE="/etc/openvpn/clientes/vpn_gestion.log"
CRL_FILE="/etc/openvpn/crl.pem"

# Crear archivos si no existen
mkdir -p /etc/openvpn/clientes
mkdir -p /etc/openvpn/scripts
touch "$NOMBRES_FILE"
touch "$SUSPENDED_FILE"
touch "$LOG_FILE"

# Función para escribir en log
escribir_log() {
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" >> "$LOG_FILE"
}

# Función para limpiar nombre de certificado (quitar /CN=)
limpiar_nombre() {
    echo "$1" | sed 's|/CN=||'
}

# Función para obtener nombre descriptivo
obtener_nombre() {
    cliente="$1"
    cliente_limpio=$(limpiar_nombre "$cliente")
    
    if [ -f "$NOMBRES_FILE" ]; then
        nombre=$(grep "^$cliente_limpio:" "$NOMBRES_FILE" 2>/dev/null | cut -d: -f2-)
        if [ -n "$nombre" ]; then
            echo "$nombre"
            return
        fi
    fi
    echo "$cliente_limpio"
}

# Función para encontrar directorio easy-rsa
encontrar_easyrsa() {
    for dir in /etc/easy-rsa /etc/openvpn/easy-rsa /root/easy-rsa; do
        if [ -f "$dir/easyrsa" ] || [ -f "$dir/vars" ]; then
            echo "$dir"
            return
        fi
    done
    echo ""
}

# ==============================================
# FUNCIONES PRINCIPALES DE BLOQUEO POR NOMBRE
# ==============================================

# Función para revocar certificado (BLOQUEO POR NOMBRE)
revocar_certificado() {
    cliente="$1"
    cliente_limpio=$(limpiar_nombre "$cliente")
    
    EASYRSA_DIR=$(encontrar_easyrsa)
    
    if [ -z "$EASYRSA_DIR" ]; then
        escribir_log "⚠️  No se encuentra easy-rsa, usando método alternativo para $cliente_limpio"
        echo "⚠️  No se encuentra easy-rsa, usando bloqueo por nombre en scripts"
        return 1
    fi
    
    echo "   📝 Revocando certificado de $cliente_limpio..."
    escribir_log "📝 Iniciando revocación de certificado para $cliente_limpio"
    
    # Cambiar al directorio easy-rsa
    cd "$EASYRSA_DIR" 2>/dev/null || return 1
    
    # Verificar si el certificado existe
    if [ ! -f "pki/issued/$cliente_limpio.crt" ]; then
        escribir_log "⚠️  Certificado $cliente_limpio.crt no encontrado"
        echo "   ⚠️  Certificado no encontrado, usando solo bloqueo por nombre"
        return 1
    fi
    
    # Hacer backup antes de revocar
    if [ ! -f "pki/issued/$cliente_limpio.crt.backup" ]; then
        cp "pki/issued/$cliente_limpio.crt" "pki/issued/$cliente_limpio.crt.backup" 2>/dev/null
        cp "pki/private/$cliente_limpio.key" "pki/private/$cliente_limpio.key.backup" 2>/dev/null
        escribir_log "✅ Backup de certificado $cliente_limpio creado"
    fi
    
    # Revocar certificado
    if [ -f "easyrsa" ]; then
        echo "yes" | ./easyrsa revoke "$cliente_limpio" > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            # Actualizar CRL
            ./easyrsa gen-crl > /dev/null 2>&1
            # Copiar CRL a OpenVPN
            cp pki/crl.pem /etc/openvpn/ 2>/dev/null
            escribir_log "✅ Certificado de $cliente_limpio revocado exitosamente"
            echo "   ✅ Certificado revocado"
            return 0
        fi
    fi
    
    escribir_log "❌ Error revocando certificado de $cliente_limpio"
    echo "   ❌ Error revocando certificado"
    return 1
}

# Función para restaurar certificado (DESBLOQUEO POR NOMBRE)
restaurar_certificado() {
    cliente="$1"
    cliente_limpio=$(limpiar_nombre "$cliente")
    
    EASYRSA_DIR=$(encontrar_easyrsa)
    
    if [ -z "$EASYRSA_DIR" ]; then
        escribir_log "⚠️  No se encuentra easy-rsa para restaurar $cliente_limpio"
        echo "⚠️  No se encuentra easy-rsa"
        return 1
    fi
    
    echo "   📝 Restaurando certificado de $cliente_limpio..."
    escribir_log "📝 Iniciando restauración de certificado para $cliente_limpio"
    
    cd "$EASYRSA_DIR" 2>/dev/null || return 1
    
    # Verificar si hay backup del certificado
    if [ -f "pki/issued/$cliente_limpio.crt.backup" ]; then
        # Restaurar desde backup
        cp "pki/issued/$cliente_limpio.crt.backup" "pki/issued/$cliente_limpio.crt" 2>/dev/null
        cp "pki/private/$cliente_limpio.key.backup" "pki/private/$cliente_limpio.key" 2>/dev/null
        
        # Eliminar línea de revocación del índice
        sed -i "/\/CN=$cliente_limpio$/d" pki/index.txt 2>/dev/null
        # Añadir como válido
        serial=$(openssl x509 -in "pki/issued/$cliente_limpio.crt" -serial -noout 2>/dev/null | cut -d= -f2)
        if [ -n "$serial" ]; then
            echo "V\t$(date +'%y%m%d%H%M%SZ')\t\t$serial\tunknown\t/CN=$cliente_limpio" >> pki/index.txt
        fi
        
        # Actualizar CRL
        ./easyrsa gen-crl > /dev/null 2>&1
        cp pki/crl.pem /etc/openvpn/ 2>/dev/null
        escribir_log "✅ Certificado de $cliente_limpio restaurado exitosamente"
        echo "   ✅ Certificado restaurado"
        return 0
    else
        escribir_log "⚠️  No hay backup del certificado para $cliente_limpio"
        echo "   ⚠️  No hay backup del certificado"
        return 1
    fi
}

# Función para configurar script de verificación en OpenVPN
configurar_script_verificacion() {
    cliente="$1"
    cliente_limpio=$(limpiar_nombre "$cliente")
    
    echo "   🔄 Configurando verificación en OpenVPN..."
    
    # Crear script de verificación
    cat > /etc/openvpn/scripts/verificar_cliente.sh << 'EOF'
#!/bin/sh
# Script para verificar si cliente está bloqueado por nombre
# Se ejecuta en cada conexión mediante client-connect

CLIENT_NAME="$1"
SUSPENDED_FILE="/etc/openvpn/clientes/suspended.txt"

# Limpiar nombre (quitar /CN= si existe)
CLIENT_CLEAN=$(echo "$CLIENT_NAME" | sed 's|/CN=||')

# Verificar si está en lista de bloqueados
if grep -q "^$CLIENT_CLEAN:" "$SUSPENDED_FILE"; then
    # Registrar intento bloqueado
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Conexión BLOQUEADA: $CLIENT_CLEAN" >> /etc/openvpn/clientes/conexiones_bloqueadas.log
    # Rechazar conexión
    exit 1
fi

# Permitir conexión
exit 0
EOF
    
    chmod +x /etc/openvpn/scripts/verificar_cliente.sh
    escribir_log "✅ Script de verificación creado/actualizado"
    
    # Configurar OpenVPN para usar el script
    if [ -f "/etc/openvpn/server.conf" ]; then
        # Asegurar que tiene permisos de script
        if ! grep -q "script-security" /etc/openvpn/server.conf; then
            echo "script-security 2" >> /etc/openvpn/server.conf
        fi
        
        # Añadir client-connect si no está
        if ! grep -q "client-connect" /etc/openvpn/server.conf; then
            echo "client-connect /etc/openvpn/scripts/verificar_cliente.sh" >> /etc/openvpn/server.conf
            escribir_log "✅ client-connect añadido a OpenVPN"
            echo "   ✅ OpenVPN configurado para verificar bloqueos"
            
            # Recargar OpenVPN si está corriendo
            if systemctl reload openvpn 2>/dev/null; then
                escribir_log "✅ OpenVPN recargado"
            elif /etc/init.d/openvpn reload 2>/dev/null; then
                escribir_log "✅ OpenVPN recargado"
            fi
        fi
    else
        escribir_log "⚠️  No se encontró server.conf de OpenVPN"
    fi
}

# Función para verificar estado del cliente (certificado)
estado_cliente() {
    cliente="$1"
    cliente_limpio=$(limpiar_nombre "$cliente")
    
    EASYRSA_DIR=$(encontrar_easyrsa)
    
    if [ -z "$EASYRSA_DIR" ]; then
        echo "unknown"
        return
    fi
    
    if grep -q "^R.*/CN=$cliente_limpio$" "$EASYRSA_DIR/pki/index.txt" 2>/dev/null; then
        echo "revocado"
    elif grep -q "^V.*/CN=$cliente_limpio$" "$EASYRSA_DIR/pki/index.txt" 2>/dev/null; then
        echo "activo"
    else
        echo "no_encontrado"
    fi
}

# Función para verificar si está bloqueado en nuestro sistema
esta_bloqueado() {
    cliente="$1"
    cliente_limpio=$(limpiar_nombre "$cliente")
    
    if grep -q "^$cliente_limpio:" "$SUSPENDED_FILE" 2>/dev/null; then
        echo "si"
    else
        echo "no"
    fi
}

# ==============================================
# FUNCIONES DE VISUALIZACIÓN Y MENÚ
# ==============================================

# Función para mostrar menú
mostrar_menu() {
    clear
    echo ""
    echo "🔧 GESTIÓN VPN - BLOQUEO POR NOMBRE"
    echo "==================================="
    echo ""
    echo "1) 👁️  Ver clientes conectados"
    echo "2) 📋 Listar todos los clientes"
    echo "3) 🚫 BLOQUEAR cliente (por nombre)"
    echo "4) ✅ DESBLOQUEAR cliente (por nombre)"
    echo "5) 🏷️  Gestionar nombres descriptivos"
    echo "6) 🔍 Estado del sistema"
    echo "7) 📊 Ver LOG del sistema"
    echo "8) ❌ Salir"
    echo ""
    echo -n "Selecciona [1-8]: "
}

# Función para ver clientes conectados
ver_conectados() {
    echo ""
    echo "📊 CLIENTES CONECTADOS"
    echo "======================"
    echo ""
    
    # Usar el archivo correcto
    if [ -f "/var/log/openvpn-status.log" ]; then
        STATUS_FILE="/var/log/openvpn-status.log"
    else
        echo "❌ No se encuentra /var/log/openvpn-status.log"
        escribir_log "❌ No se encuentra /var/log/openvpn-status.log"
        return
    fi
    
    # Buscar clientes conectados
    if ! grep "^CLIENT_LIST" "$STATUS_FILE" | grep -v "HEADER" | grep -q "."; then
        echo "ℹ️  No hay clientes conectados en este momento"
        escribir_log "ℹ️  No hay clientes conectados"
        return
    fi
    
    contador=0
    echo "┌─────────────────────────────────────────────────────────┐"
    echo "│                    CLIENTES CONECTADOS                  │"
    echo "├─────────────────────────────────────────────────────────┤"
    
    grep "^CLIENT_LIST" "$STATUS_FILE" | grep -v "HEADER" | while read linea; do
        cliente=$(echo "$linea" | awk '{print $2}')
        ip_puerto=$(echo "$linea" | awk '{print $3}')
        ip_virtual=$(echo "$linea" | awk '{print $4}')
        fecha_conexion=$(echo "$linea" | awk '{print $8" "$9}')
        
        if [ -n "$cliente" ] && [ "$cliente" != "UNDEF" ]; then
            cliente_limpio=$(echo "$cliente" | sed 's|/CN=||')
            nombre_descriptivo=$(obtener_nombre "$cliente_limpio")
            
            contador=$((contador + 1))
            
            # Verificar estado
            estado_cert=$(estado_cliente "$cliente_limpio")
            estado_bloqueo=$(esta_bloqueado "$cliente_limpio")
            
            estado_icono="🟢"
            if [ "$estado_cert" = "revocado" ]; then
                estado_icono="🔴"
            elif [ "$estado_bloqueo" = "si" ]; then
                estado_icono="🚫"
            fi
            
            echo "│ $estado_icono Cliente $contador"
            echo "│ ├─👤 Nombre: $nombre_descriptivo"
            echo "│ ├─🔑 Certificado: $cliente_limpio"
            echo "│ ├─🌐 IP Real: $ip_puerto"
            echo "│ ├─🔗 IP VPN: $ip_virtual"
            echo "│ └─🕒 Conectado desde: $fecha_conexion"
            echo "├─────────────────────────────────────────────────────────┤"
            
            escribir_log "📡 Cliente $nombre_descriptivo ($cliente_limpio) conectado - Estado: $estado_cert/$estado_bloqueo"
        fi
    done
    
    echo "│                    RESUMEN FINAL                         │"
    echo "├─────────────────────────────────────────────────────────┤"
    
    if [ $contador -eq 0 ]; then
        echo "│ ℹ️  No se encontraron clientes conectados              │"
    else
        echo "│ ✅ Total de clientes conectados: $contador               │"
    fi
    
    echo "└─────────────────────────────────────────────────────────┘"
    echo ""
}

# Función para listar todos los clientes
listar_clientes() {
    echo ""
    echo "📋 ESTADO COMPLETO DE CLIENTES"
    echo "=============================="
    echo ""
    escribir_log "📋 Mostrando estado completo de clientes"
    
    # Buscar base de datos de certificados
    INDEX_FILE=""
    EASYRSA_DIR=$(encontrar_easyrsa)
    if [ -n "$EASYRSA_DIR" ] && [ -f "$EASYRSA_DIR/pki/index.txt" ]; then
        INDEX_FILE="$EASYRSA_DIR/pki/index.txt"
    fi
    
    if [ -z "$INDEX_FILE" ]; then
        echo "   ℹ️  No se encuentra base de datos de certificados"
        echo "   🔍 Solo se mostrarán clientes bloqueados por nombre"
    fi
    
    echo "🎯 CLIENTES ACTIVOS (certificado válido):"
    echo ""
    activos=0
    
    if [ -n "$INDEX_FILE" ]; then
        grep "^V" "$INDEX_FILE" 2>/dev/null | while read linea; do
            if echo "$linea" | grep -q "/CN="; then
                cliente=$(echo "$linea" | sed 's/.*\/CN=//' | awk '{print $1}')
            else
                cliente=$(echo "$linea" | awk '{print $NF}')
            fi
            
            if [ -n "$cliente" ] && [ "$cliente" != "unknown" ] && [ "$cliente" != "server" ]; then
                activos=$((activos + 1))
                nombre_descriptivo=$(obtener_nombre "$cliente")
                bloqueado=$(esta_bloqueado "$cliente")
                
                bloqueado_icono=""
                if [ "$bloqueado" = "si" ]; then
                    bloqueado_icono="🚫"
                fi
                
                echo "   $activos) 🟢 $nombre_descriptivo ($cliente) $bloqueado_icono"
            fi
        done
    fi
    
    if [ $activos -eq 0 ]; then
        echo "   Ninguno"
    fi
    
    echo ""
    echo "🔴 CLIENTES REVOCADOS (certificado inválido):"
    echo ""
    revocados=0
    
    if [ -n "$INDEX_FILE" ]; then
        grep "^R" "$INDEX_FILE" 2>/dev/null | while read linea; do
            if echo "$linea" | grep -q "/CN="; then
                cliente=$(echo "$linea" | sed 's/.*\/CN=//' | awk '{print $1}')
            else
                cliente=$(echo "$linea" | awk '{print $NF}')
            fi
            
            if [ -n "$cliente" ] && [ "$cliente" != "unknown" ] && [ "$cliente" != "server" ]; then
                revocados=$((revocados + 1))
                nombre_descriptivo=$(obtener_nombre "$cliente")
                bloqueado=$(esta_bloqueado "$cliente")
                
                bloqueado_icono=""
                if [ "$bloqueado" = "si" ]; then
                    bloqueado_icono="🚫"
                fi
                
                echo "   $revocados) 🔴 $nombre_descriptivo ($cliente) $bloqueado_icono"
            fi
        done
    fi
    
    if [ $revocados -eq 0 ]; then
        echo "   Ninguno"
    fi
    
    echo ""
    echo "🚫 CLIENTES BLOQUEADOS POR NOMBRE (en nuestro sistema):"
    echo ""
    bloqueados_sistema=0
    
    if [ -s "$SUSPENDED_FILE" ]; then
        while IFS=: read -r cliente fecha resto; do
            if [ -n "$cliente" ]; then
                bloqueados_sistema=$((bloqueados_sistema + 1))
                nombre_descriptivo=$(obtener_nombre "$cliente")
                estado_cert=$(estado_cliente "$cliente")
                
                estado_icono="❓"
                if [ "$estado_cert" = "revocado" ]; then
                    estado_icono="🔴"
                elif [ "$estado_cert" = "activo" ]; then
                    estado_icono="⚠️ "
                fi
                
                echo "   $bloqueados_sistema) $estado_icono $nombre_descriptivo ($cliente) - $fecha"
            fi
        done < "$SUSPENDED_FILE"
    fi
    
    if [ $bloqueados_sistema -eq 0 ]; then
        echo "   Ninguno"
    fi
    
    echo ""
    echo "📊 RESUMEN:"
    echo "   🟢 Certificados activos: $activos"
    echo "   🔴 Certificados revocados: $revocados"
    echo "   🚫 Bloqueados por nombre: $bloqueados_sistema"
    echo ""
    echo "💡 LEYENDA:"
    echo "   🟢 = Certificado válido"
    echo "   🔴 = Certificado revocado"
    echo "   🚫 = Bloqueado por nombre (independiente de IP)"
    echo "   ⚠️  = Certificado válido pero bloqueado por nombre"
}

# ==============================================
# FUNCIONES DE BLOQUEO/DESBLOQUEO POR NOMBRE
# ==============================================

# Función para BLOQUEAR CLIENTE POR NOMBRE
bloquear_cliente() {
    echo ""
    echo "🚫 BLOQUEAR CLIENTE (POR NOMBRE)"
    echo "================================"
    echo "⚠️  Esto hará:"
    echo "   1. 📝 Revocar certificado (si es posible)"
    echo "   2. 📋 Añadir a lista de bloqueos por nombre"
    echo "   3. 🔄 Configurar OpenVPN para verificar"
    echo ""
    echo "💡 EFECTO: El cliente NO podrá conectarse aunque cambie de IP"
    echo ""
    
    escribir_log "🚫 Iniciando bloqueo por nombre"
    
    # Listar clientes activos
    echo "Clientes disponibles para BLOQUEAR:"
    echo ""
    
    EASYRSA_DIR=$(encontrar_easyrsa)
    if [ -z "$EASYRSA_DIR" ] || [ ! -f "$EASYRSA_DIR/pki/index.txt" ]; then
        echo "   ℹ️  No se encuentra easy-rsa, usando solo bloqueo por nombre"
    fi
    
    # Crear lista de clientes
    clientes_lista=""
    if [ -n "$EASYRSA_DIR" ] && [ -f "$EASYRSA_DIR/pki/index.txt" ]; then
        grep "^V" "$EASYRSA_DIR/pki/index.txt" 2>/dev/null | while read linea; do
            if echo "$linea" | grep -q "/CN="; then
                cliente=$(echo "$linea" | sed 's/.*\/CN=//' | awk '{print $1}')
            else
                cliente=$(echo "$linea" | awk '{print $NF}')
            fi
            
            if [ -n "$cliente" ] && [ "$cliente" != "unknown" ] && [ "$cliente" != "server" ]; then
                echo "$cliente" >> /tmp/clientes_raw.txt
            fi
        done
    else
        # Si no hay easy-rsa, mostrar clientes conectados recientemente
        if [ -f "/var/log/openvpn-status.log" ]; then
            grep "^CLIENT_LIST" /var/log/openvpn-status.log 2>/dev/null | grep -v "HEADER" | awk '{print $2}' | sed 's|/CN=||' | sort -u > /tmp/clientes_raw.txt
        fi
    fi
    
    if [ ! -f /tmp/clientes_raw.txt ] || [ ! -s /tmp/clientes_raw.txt ]; then
        echo "   ℹ️  No hay clientes disponibles para bloquear"
        escribir_log "ℹ️  No hay clientes disponibles para bloquear"
        return
    fi
    
    # Mostrar clientes numerados
    num=0
    while read cliente; do
        num=$((num + 1))
        nombre_descriptivo=$(obtener_nombre "$cliente")
        
        # Verificar si ya está bloqueado
        if grep -q "^$cliente:" "$SUSPENDED_FILE"; then
            echo "   $num) $nombre_descriptivo ($cliente) [YA BLOQUEADO]"
        else
            echo "   $num) $nombre_descriptivo ($cliente)"
        fi
        
        echo "$num:$cliente" >> /tmp/clientes_index.txt
    done < /tmp/clientes_raw.txt
    
    echo ""
    echo -n "Selecciona cliente (número): "
    read seleccion
    
    # Obtener cliente seleccionado
    cliente_seleccionado=""
    if [ -f /tmp/clientes_index.txt ]; then
        while IFS=: read -r num cliente; do
            if [ "$num" = "$seleccion" ]; then
                cliente_seleccionado="$cliente"
                break
            fi
        done < /tmp/clientes_index.txt
    fi
    
    # Limpiar archivos temporales
    rm -f /tmp/clientes_raw.txt /tmp/clientes_index.txt 2>/dev/null
    
    if [ -z "$cliente_seleccionado" ]; then
        escribir_log "❌ Selección inválida en bloqueo"
        echo "❌ Selección inválida"
        return
    fi
    
    # Verificar si ya está bloqueado
    if grep -q "^$cliente_seleccionado:" "$SUSPENDED_FILE"; then
        echo ""
        echo "⚠️  Este cliente YA está bloqueado por nombre"
        echo -n "¿Forzar nuevo bloqueo? (s/N): "
        read reconfirmar
        if [ "$reconfirmar" != "s" ] && [ "$reconfirmar" != "S" ]; then
            escribir_log "❌ Operación de bloqueo cancelada para $cliente_seleccionado"
            echo "❌ Operación cancelada"
            return
        fi
    fi
    
    echo ""
    echo "⚠️  CONFIRMACIÓN FINAL"
    echo "Cliente: $cliente_seleccionado"
    echo "Nombre: $(obtener_nombre "$cliente_seleccionado")"
    echo ""
    echo "Este bloqueo es EFECTIVO incluso si el cliente:"
    echo "  • Cambia de IP/router"
    echo "  • Reinicia su dispositivo"
    echo "  • Cambia de red"
    echo ""
    echo -n "¿Confirmar BLOQUEO POR NOMBRE? (s/N): "
    read confirmar
    
    if [ "$confirmar" != "s" ] && [ "$confirmar" != "S" ]; then
        escribir_log "❌ Bloqueo cancelado por usuario para $cliente_seleccionado"
        echo "❌ Operación cancelada"
        return
    fi
    
    echo ""
    echo "🛡️  EJECUTANDO BLOQUEO POR NOMBRE..."
    echo ""
    escribir_log "🛡️  Iniciando bloqueo por nombre para $cliente_seleccionado"
    
    # 1. Revocar certificado (si es posible)
    echo "📝 Revocando certificado..."
    revocar_certificado "$cliente_seleccionado"
    
    # 2. Configurar script de verificación en OpenVPN
    configurar_script_verificacion "$cliente_seleccionado"
    
    # 3. Añadir a lista de bloqueados por nombre
    echo ""
    echo "📋 Añadiendo a lista de bloqueos por nombre..."
    grep -v "^$cliente_seleccionado:" "$SUSPENDED_FILE" > /tmp/suspended.tmp 2>/dev/null
    echo "$cliente_seleccionado:$(date '+%Y-%m-%d %H:%M:%S'):bloqueo_nombre" >> /tmp/suspended.tmp
    mv /tmp/suspended.tmp "$SUSPENDED_FILE"
    
    echo ""
    echo "✅ BLOQUEO POR NOMBRE COMPLETADO"
    echo "   👤 Cliente: $cliente_seleccionado"
    echo "   📝 Certificado: REVOCADO (si era posible)"
    echo "   🔄 OpenVPN: Configurado para verificar"
    echo ""
    echo "💡 El cliente NO podrá conectarse aunque cambie de IP/router"
    echo "   Para desbloquear, usa la opción 4 del menú"
    
    escribir_log "✅ BLOQUEO POR NOMBRE COMPLETADO para $cliente_seleccionado"
}

# Función para DESBLOQUEAR CLIENTE POR NOMBRE
desbloquear_cliente() {
    echo ""
    echo "✅ DESBLOQUEAR CLIENTE (POR NOMBRE)"
    echo "=================================="
    
    escribir_log "✅ Iniciando desbloqueo por nombre"
    
    echo "Clientes BLOQUEADOS POR NOMBRE:"
    echo ""
    
    if [ ! -s "$SUSPENDED_FILE" ]; then
        escribir_log "ℹ️  No hay clientes bloqueados"
        echo "   ℹ️  No hay clientes bloqueados"
        return
    fi
    
    # Mostrar clientes bloqueados
    num=0
    while IFS=: read -r cliente fecha tipo resto; do
        if [ -n "$cliente" ]; then
            num=$((num + 1))
            nombre_descriptivo=$(obtener_nombre "$cliente")
            echo "   $num) $nombre_descriptivo ($cliente) - $fecha"
            echo "$num:$cliente" >> /tmp/bloqueados_index.txt
        fi
    done < "$SUSPENDED_FILE"
    
    echo ""
    echo -n "Selecciona cliente (número): "
    read seleccion
    
    # Obtener cliente seleccionado
    cliente_seleccionado=""
    if [ -f /tmp/bloqueados_index.txt ]; then
        while IFS=: read -r num cliente; do
            if [ "$num" = "$seleccion" ]; then
                cliente_seleccionado="$cliente"
                break
            fi
        done < /tmp/bloqueados_index.txt
        rm -f /tmp/bloqueados_index.txt
    fi
    
    if [ -z "$cliente_seleccionado" ]; then
        escribir_log "❌ Selección inválida en desbloqueo"
        echo "❌ Selección inválida"
        return
    fi
    
    echo ""
    echo "🔓 DESBLOQUEANDO: $cliente_seleccionado"
    echo ""
    escribir_log "🔓 Iniciando desbloqueo para $cliente_seleccionado"
    
    # 1. Restaurar certificado (si es posible)
    echo "📝 Restaurando certificado..."
    restaurar_certificado "$cliente_seleccionado"
    
    # 2. Eliminar de lista de bloqueados por nombre
    echo ""
    echo "📋 Eliminando de lista de bloqueados..."
    grep -v "^$cliente_seleccionado:" "$SUSPENDED_FILE" > /tmp/suspended.tmp 2>/dev/null
    mv /tmp/suspended.tmp "$SUSPENDED_FILE"
    
    # 3. Verificar si hay más clientes bloqueados
    if [ ! -s "$SUSPENDED_FILE" ]; then
        echo "   ℹ️  No quedan clientes bloqueados, puedes desactivar la verificación"
        echo "   💡 Para desactivar completamente:"
        echo "      Edita /etc/openvpn/server.conf y elimina las líneas:"
        echo "      script-security 2"
        echo "      client-connect /etc/openvpn/scripts/verificar_cliente.sh"
    fi
    
    echo ""
    echo "✅ CLIENTE DESBLOQUEADO POR NOMBRE"
    echo "   👤 Cliente: $cliente_seleccionado"
    echo "   📝 Certificado: RESTAURADO (si era posible)"
    echo "   🔓 Acceso: RESTAURADO"
    echo ""
    echo "💡 El cliente podrá conectarse normalmente"
    
    escribir_log "✅ CLIENTE $cliente_seleccionado DESBLOQUEADO POR NOMBRE"
}

# ==============================================
# FUNCIONES ADICIONALES
# ==============================================

# Función para gestionar nombres
gestionar_nombres() {
    while true; do
        echo ""
        echo "🏷️  GESTIONAR NOMBRES DESCRIPTIVOS"
        echo "=================================="
        echo ""
        echo "⚠️  IMPORTANTE: Usa el nombre SIN /CN="
        echo "   Ejemplo: 'client1' no '/CN=client1'"
        echo ""
        echo "1) Ver nombres asignados"
        echo "2) Añadir/Modificar nombre"
        echo "3) Eliminar nombre"
        echo "4) Volver al menú"
        echo ""
        echo -n "Selecciona [1-4]: "
        read opcion
        
        case $opcion in
            1)
                echo ""
                echo "📋 NOMBRES ASIGNADOS:"
                echo ""
                escribir_log "📋 Mostrando nombres asignados"
                if [ -s "$NOMBRES_FILE" ]; then
                    while IFS=: read -r cliente nombre; do
                        echo "   🏷️  $nombre ($cliente)"
                    done < "$NOMBRES_FILE"
                else
                    echo "   📭 No hay nombres asignados"
                fi
                ;;
                
            2)
                echo ""
                echo "✏️  AÑADIR/MODIFICAR NOMBRE"
                echo ""
                echo -n "Nombre del certificado (SIN /CN=): "
                read cliente
                echo -n "Nombre descriptivo: "
                read nombre
                
                cliente=$(echo "$cliente" | sed 's|/CN=||')
                
                if [ -n "$cliente" ] && [ -n "$nombre" ]; then
                    grep -v "^$cliente:" "$NOMBRES_FILE" > /tmp/nombres.tmp
                    echo "$cliente:$nombre" >> /tmp/nombres.tmp
                    mv /tmp/nombres.tmp "$NOMBRES_FILE"
                    echo ""
                    echo "✅ NOMBRE ASIGNADO:"
                    echo "   📋 Certificado: $cliente"
                    echo "   🏷️  Nombre: $nombre"
                    echo ""
                    escribir_log "🏷️  Nombre asignado: $nombre para $cliente"
                else
                    escribir_log "❌ Error asignando nombre (datos incompletos)"
                    echo "❌ Error: Debes ingresar ambos valores"
                fi
                ;;
                
            3)
                echo ""
                echo "🗑️  ELIMINAR NOMBRE"
                echo ""
                
                if [ ! -s "$NOMBRES_FILE" ]; then
                    echo "   📭 No hay nombres para eliminar"
                    continue
                fi
    
                echo "Selecciona nombre a eliminar:"
                echo ""
                num=0
                while IFS=: read -r cliente nombre; do
                    num=$((num + 1))
                    echo "   $num) $nombre ($cliente)"
                    echo "$num:$cliente" >> /tmp/eliminar_index.txt
                done < "$NOMBRES_FILE"
                
                echo ""
                echo -n "Número: "
                read seleccion
                
                cliente_eliminar=""
                if [ -f /tmp/eliminar_index.txt ]; then
                    while IFS=: read -r num cliente; do
                        if [ "$num" = "$seleccion" ]; then
                            cliente_eliminar="$cliente"
                            break
                        fi
                    done < /tmp/eliminar_index.txt
                    rm -f /tmp/eliminar_index.txt
                fi
    
                if [ -z "$cliente_eliminar" ]; then
                    echo "❌ Selección inválida"
                    continue
                fi
                
                echo ""
                echo -n "¿Eliminar nombre de '$cliente_eliminar'? (s/N): "
                read confirmar
                
                if [ "$confirmar" = "s" ] || [ "$confirmar" = "S" ]; then
                    grep -v "^$cliente_eliminar:" "$NOMBRES_FILE" > /tmp/nombres.tmp
                    mv /tmp/nombres.tmp "$NOMBRES_FILE"
                    escribir_log "🗑️  Nombre eliminado para cliente $cliente_eliminar"
                    echo "✅ Nombre eliminado"
                else
                    echo "❌ Cancelado"
                fi
                ;;
                
            4)
                return
                ;;
                
            *)
                echo "❌ Opción inválida"
                ;;
        esac
        
        echo ""
        echo "Presiona Enter para continuar..."
        read dummy
    done
}

# Función para estado del sistema
estado_servicio() {
    echo ""
    echo "🔍 ESTADO DEL SISTEMA"
    echo "===================="
    echo ""
    
    escribir_log "🔍 Mostrando estado del sistema"
    
    # OpenVPN
    if pgrep openvpn >/dev/null; then
        echo "✅ OpenVPN: ACTIVO"
        escribir_log "✅ OpenVPN: ACTIVO"
    else
        echo "❌ OpenVPN: INACTIVO"
        escribir_log "❌ OpenVPN: INACTIVO"
    fi
    
    # easy-rsa
    echo ""
    echo "📝 EASY-RSA:"
    EASYRSA_DIR=$(encontrar_easyrsa)
    if [ -n "$EASYRSA_DIR" ]; then
        echo "   ✅ Encontrado en: $EASYRSA_DIR"
        if [ -f "$EASYRSA_DIR/pki/index.txt" ]; then
            activos=$(grep -c "^V" "$EASYRSA_DIR/pki/index.txt")
            revocados=$(grep -c "^R" "$EASYRSA_DIR/pki/index.txt")
            echo "   📊 Certificados: $activos activos, $revocados revocados"
            escribir_log "📝 EASY-RSA: Encontrado, $activos activos, $revocados revocados"
        fi
    else
        echo "   ⚠️  No encontrado (solo bloqueo por nombre)"
        escribir_log "⚠️  EASY-RSA: No encontrado"
    fi
    
    # Script de verificación
    echo ""
    echo "🔄 SCRIPT DE VERIFICACIÓN:"
    if [ -f "/etc/openvpn/scripts/verificar_cliente.sh" ]; then
        echo "   ✅ Instalado en: /etc/openvpn/scripts/verificar_cliente.sh"
        if [ -f "/etc/openvpn/server.conf" ] && grep -q "client-connect" /etc/openvpn/server.conf; then
            echo "   ✅ Configurado en OpenVPN"
        else
            echo "   ⚠️  NO configurado en OpenVPN"
            echo "   💡 Se activará automáticamente al bloquear primer cliente"
        fi
    else
        echo "   ❌ No instalado"
        echo "   💡 Se creará automáticamente al bloquear primer cliente"
    fi
    
    # Estadísticas
    echo ""
    echo "📊 ESTADÍSTICAS GESTOR:"
    nombres=$(grep -c ":" "$NOMBRES_FILE" 2>/dev/null || echo 0)
    echo "   👥 Nombres asignados: $nombres"
    
    bloqueados=$(wc -l < "$SUSPENDED_FILE" 2>/dev/null || echo 0)
    echo "   🚫 Clientes bloqueados por nombre: $bloqueados"
    
    log_size=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)
    echo "   📜 Entradas en log: $log_size"
    
    # Listar clientes bloqueados
    echo ""
    echo "📋 CLIENTES BLOQUEADOS ACTUALMENTE:"
    if [ -s "$SUSPENDED_FILE" ]; then
        count=0
        while IFS=: read -r cliente fecha tipo; do
            if [ -n "$cliente" ]; then
                count=$((count + 1))
                nombre=$(obtener_nombre "$cliente")
                if [ $count -le 5 ]; then
                    echo "   $count) $nombre ($cliente) - $fecha"
                fi
            fi
        done < "$SUSPENDED_FILE"
        
        if [ $count -gt 5 ]; then
            echo "   ... y $((count - 5)) más"
        fi
    else
        echo "   ℹ️  Ninguno"
    fi
    
    escribir_log "📊 ESTADÍSTICAS: $nombres nombres, $bloqueados bloqueados, $log_size logs"
}

# Función para ver LOG del sistema
ver_log() {
    echo ""
    echo "📜 REGISTRO DEL SISTEMA (LOG)"
    echo "============================="
    echo ""
    echo "Mostrando las últimas 30 entradas:"
    echo ""
    
    if [ ! -f "$LOG_FILE" ] || [ ! -s "$LOG_FILE" ]; then
        echo "   📭 El archivo de log está vacío o no existe"
        return
    fi
    
    tail -30 "$LOG_FILE" | while read linea; do
        echo "   $linea"
    done
    
    echo ""
    echo "📊 Estadísticas del log:"
    total_lineas=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)
    echo "   Total de entradas: $total_lineas"
}

# ==============================================
# PROGRAMA PRINCIPAL
# ==============================================

escribir_log "🚀 Sistema de gestión VPN (solo bloqueo por nombre) iniciado"

while true; do
    mostrar_menu
    read opcion
    
    escribir_log "📱 Opción seleccionada en menú: $opcion"
    
    case $opcion in
        1)
            ver_conectados
            ;;
        2)
            listar_clientes
            ;;
        3)
            bloquear_cliente
            ;;
        4)
            desbloquear_cliente
            ;;
        5)
            gestionar_nombres
            ;;
        6)
            estado_servicio
            ;;
        7)
            ver_log
            ;;
        8)
            escribir_log "👋 Sistema de gestión VPN finalizado"
            echo ""
            echo "👋 Saliendo..."
            exit 0
            ;;
        *)
            escribir_log "❌ Opción inválida seleccionada: $opcion"
            echo "❌ Opción inválida"
            ;;
    esac
    
    echo ""
    echo "Presiona Enter para continuar..."
    read dummy
done
EOF

# Dar permisos
chmod +x /usr/bin/gestion

echo ""
echo "✅ SISTEMA ACTUALIZADO - SOLO BLOQUEO POR NOMBRE"
echo ""
echo "🔧 CAMBIOS PRINCIPALES:"
echo "   1. 🚫 ELIMINADO todo bloqueo por IP"
echo "   2. ✅ IMPLEMENTADO bloqueo por nombre (Common Name)"
echo "   3. 🔄 Configuración automática de OpenVPN"
echo "   4. 📋 Sistema simplificado y más efectivo"
echo ""
echo "🎯 VENTAJAS DEL NUEVO SISTEMA:"
echo "   • ✅ Efectivo aunque el cliente cambie de IP"
echo "   • ✅ Persistente tras reinicios"
echo "   • ✅ Integrado con certificados OpenVPN"
echo "   • ✅ Más simple de mantener"
echo ""
echo "🚀 PARA USAR:"
echo "   1. Ejecuta: gestion"
echo "   2. Usa opción 3 para bloquear por nombre"
echo "   3. El script configurará OpenVPN automáticamente"
echo ""
echo "💡 RECOMENDACIÓN:"
echo "   Verifica que OpenVPN esté instalado y funcionando"
echo "   Si tienes problemas, revisa: /etc/openvpn/server.conf"
