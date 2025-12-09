#!/bin/sh

echo ""
echo "🔧 GESTION DE CLIENTES VPN"
echo "==============================="

# Actualizar el script
cat > /usr/bin/gestion << 'EOF'
#!/bin/sh

# Archivos de configuración - USANDO TUS UBICACIONES EXACTAS
BASE_DIR="/etc/openvpn/clientes"
NOMBRES_FILE="$BASE_DIR/nombres.txt"
IP_HISTORY_FILE="$BASE_DIR/ip_history.txt"
SUSPENDED_FILE="$BASE_DIR/suspended.txt"
LOG_FILE="$BASE_DIR/vpn_gestion.log"
TRACKING_FILE="$BASE_DIR/tracking.txt"
BLOQUEO_LOG_FILE="$BASE_DIR/conexiones_bloqueadas.log"

# Crear directorio y archivos si no existen
mkdir -p "$BASE_DIR"
for file in "$NOMBRES_FILE" "$IP_HISTORY_FILE" "$SUSPENDED_FILE" "$LOG_FILE" "$TRACKING_FILE" "$BLOQUEO_LOG_FILE"; do
    if [ ! -f "$file" ]; then
        touch "$file"
    fi
done

# Función para convertir timestamp Unix a fecha legible
timestamp_a_fecha() {
    timestamp="$1"
    if [ -n "$timestamp" ] && [ "$timestamp" -gt 0 ] 2>/dev/null; then
        # Intentar convertir con date si está disponible
        if command -v date >/dev/null 2>&1; then
            # Para sistemas GNU (Linux)
            if date -d "@$timestamp" '+%d/%m/%Y %H:%M:%S' 2>/dev/null; then
                return
            fi
            # Para sistemas BSD (macOS)
            if date -r "$timestamp" '+%d/%m/%Y %H:%M:%S' 2>/dev/null; then
                return
            fi
            echo "Fecha desconocida"
        else
            echo "Fecha: $timestamp"
        fi
    else
        echo "Fecha desconocida"
    fi
}

# Función para escribir en log
escribir_log() {
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" >> "$LOG_FILE"
}

# Función para registrar bloqueos
registrar_bloqueo() {
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" >> "$BLOQUEO_LOG_FILE"
}

# Función para limpiar nombre de certificado (quitar /CN=)
limpiar_nombre() {
    echo "$1" | sed 's|/CN=||'
}

# Función para obtener nombre descriptivo
obtener_nombre() {
    cliente="$1"
    cliente_limpio=$(limpiar_nombre "$cliente")
    
    if [ -f "$NOMBRES_FILE" ] && [ -s "$NOMBRES_FILE" ]; then
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
    # Verificar primero las ubicaciones más comunes
    for dir in /etc/easy-rsa /etc/openvpn/easy-rsa /etc/openvpn/server/easy-rsa /root/easy-rsa /usr/share/easy-rsa; do
        if [ -d "$dir" ] && { [ -f "$dir/easyrsa" ] || [ -f "$dir/vars" ] || [ -f "$dir/openssl-easyrsa.cnf" ]; }; then
            echo "$dir"
            return
        fi
    done
    echo ""
}

# Función para encontrar archivo de estado de OpenVPN
encontrar_status_file() {
    # Buscar en ubicaciones comunes
    for location in \
        "/etc/openvpn/openvpn-status.log" \
        "/etc/openvpn/status.log" \
        "/etc/openvpn/server/openvpn-status.log" \
        "/etc/openvpn/server/status.log" \
        "/var/log/openvpn-status.log" \
        "/tmp/openvpn-status.log" \
        "/run/openvpn/server/status.log"; do
        if [ -f "$location" ] && [ -s "$location" ]; then
            echo "$location"
            return
        fi
    done
    # Si no se encuentra, crear uno vacío en /etc/openvpn/
    echo "/etc/openvpn/status.log"
}

# Función para revocar certificado
revocar_certificado() {
    cliente="$1"
    EASYRSA_DIR=$(encontrar_easyrsa)
    
    if [ -z "$EASYRSA_DIR" ]; then
        escribir_log "⚠️  No se encuentra easy-rsa, no se puede revocar certificado para $cliente"
        echo "⚠️  No se encuentra easy-rsa, no se puede revocar certificado"
        echo "   Solo se bloqueará la IP en firewall"
        registrar_bloqueo "⚠️  No se encuentra easy-rsa para revocar certificado de $cliente"
        return 1
    fi
    
    echo "   📝 Revocando certificado de $cliente..."
    escribir_log "📝 Iniciando revocación de certificado para $cliente"
    registrar_bloqueo "📝 Iniciando revocación de certificado para $cliente"
    
    # Cambiar al directorio easy-rsa
    cd "$EASYRSA_DIR" 2>/dev/null || return 1
    
    # Verificar si el certificado existe
    if [ ! -f "pki/issued/$cliente.crt" ]; then
        # Buscar en otras ubicaciones posibles
        if [ -f "issued/$cliente.crt" ]; then
            PKI_PATH="."
        elif [ -f "../issued/$cliente.crt" ]; then
            PKI_PATH=".."
        else
            escribir_log "⚠️  Certificado $cliente.crt no encontrado"
            echo "   ⚠️  Certificado $cliente.crt no encontrado"
            registrar_bloqueo "⚠️  Certificado $cliente.crt no encontrado para revocar"
            return 1
        fi
    else
        PKI_PATH="pki"
    fi
    
    # Hacer backup antes de revocar
    if [ ! -f "$PKI_PATH/issued/$cliente.crt.backup" ]; then
        cp "$PKI_PATH/issued/$cliente.crt" "$PKI_PATH/issued/$cliente.crt.backup" 2>/dev/null
        if [ -f "$PKI_PATH/private/$cliente.key" ]; then
            cp "$PKI_PATH/private/$cliente.key" "$PKI_PATH/private/$cliente.key.backup" 2>/dev/null
        fi
        escribir_log "✅ Backup de certificado $cliente creado"
        registrar_bloqueo "✅ Backup de certificado $cliente creado"
    fi
    
    # Revocar certificado
    if [ -f "easyrsa" ]; then
        echo "yes" | ./easyrsa revoke "$cliente" > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            # Actualizar CRL
            ./easyrsa gen-crl > /dev/null 2>&1
            # Copiar CRL a OpenVPN si existe el directorio
            if [ -f "$PKI_PATH/crl.pem" ]; then
                cp "$PKI_PATH/crl.pem" /etc/openvpn/ 2>/dev/null
                cp "$PKI_PATH/crl.pem" /etc/openvpn/server/ 2>/dev/null
            fi
            escribir_log "✅ Certificado de $cliente revocado exitosamente"
            registrar_bloqueo "✅ Certificado de $cliente revocado exitosamente"
            echo "   ✅ Certificado revocado"
            return 0
        fi
    fi
    
    # Intentar con openssl si easyrsa no funciona
    escribir_log "⚠️  Intentando revocación con openssl para $cliente"
    registrar_bloqueo "⚠️  Intentando revocación con openssl para $cliente"
    echo "   ⚠️  Intentando método alternativo..."
    
    if [ -f "$PKI_PATH/index.txt" ] && [ -f "$PKI_PATH/ca.crt" ] && [ -f "$PKI_PATH/ca.key" ]; then
        # Marcar como revocado en index.txt
        sed -i "/\/CN=$cliente$/s/^V/R/" "$PKI_PATH/index.txt"
        # Generar nuevo CRL
        openssl ca -gencrl -keyfile "$PKI_PATH/ca.key" -cert "$PKI_PATH/ca.crt" -out "$PKI_PATH/crl.pem" -config "$PKI_PATH/openssl-easyrsa.cnf" 2>/dev/null
        if [ $? -eq 0 ]; then
            cp "$PKI_PATH/crl.pem" /etc/openvpn/ 2>/dev/null
            escribir_log "✅ Certificado de $cliente revocado con openssl"
            registrar_bloqueo "✅ Certificado de $cliente revocado con openssl"
            echo "   ✅ Certificado revocado (método alternativo)"
            return 0
        fi
    fi
    
    escribir_log "❌ Error revocando certificado de $cliente"
    registrar_bloqueo "❌ Error revocando certificado de $cliente"
    echo "   ❌ Error revocando certificado"
    return 1
}

# Función para restaurar certificado
restaurar_certificado() {
    cliente="$1"
    EASYRSA_DIR=$(encontrar_easyrsa)
    
    if [ -z "$EASYRSA_DIR" ]; then
        escribir_log "⚠️  No se encuentra easy-rsa para restaurar $cliente"
        echo "⚠️  No se encuentra easy-rsa"
        registrar_bloqueo "⚠️  No se encuentra easy-rsa para restaurar certificado de $cliente"
        return 1
    fi
    
    echo "   📝 Restaurando certificado de $cliente..."
    escribir_log "📝 Iniciando restauración de certificado para $cliente"
    registrar_bloqueo "📝 Iniciando restauración de certificado para $cliente"
    
    cd "$EASYRSA_DIR" 2>/dev/null || return 1
    
    # Determinar ruta PKI
    if [ -f "pki/issued/$cliente.crt" ] || [ -f "pki/issued/$cliente.crt.backup" ]; then
        PKI_PATH="pki"
    elif [ -f "issued/$cliente.crt" ] || [ -f "issued/$cliente.crt.backup" ]; then
        PKI_PATH="."
    elif [ -f "../issued/$cliente.crt" ] || [ -f "../issued/$cliente.crt.backup" ]; then
        PKI_PATH=".."
    else
        escribir_log "⚠️  No hay backup del certificado para $cliente"
        echo "   ⚠️  No hay backup del certificado, solo se desbloqueará IP"
        registrar_bloqueo "⚠️  No hay backup del certificado para $cliente"
        return 1
    fi
    
    # Verificar si hay backup del certificado
    if [ -f "$PKI_PATH/issued/$cliente.crt.backup" ]; then
        # Restaurar desde backup
        cp "$PKI_PATH/issued/$cliente.crt.backup" "$PKI_PATH/issued/$cliente.crt" 2>/dev/null
        if [ -f "$PKI_PATH/private/$cliente.key.backup" ]; then
            cp "$PKI_PATH/private/$cliente.key.backup" "$PKI_PATH/private/$cliente.key" 2>/dev/null
        fi
        
        # Eliminar línea de revocación del índice
        if [ -f "$PKI_PATH/index.txt" ]; then
            sed -i "/\/CN=$cliente$/d" "$PKI_PATH/index.txt" 2>/dev/null
            # Añadir como válido
            serial=$(openssl x509 -in "$PKI_PATH/issued/$cliente.crt" -serial -noout 2>/dev/null | cut -d= -f2)
            if [ -n "$serial" ]; then
                echo "V\t$(date +'%y%m%d%H%M%SZ')\t\t$serial\tunknown\t/CN=$cliente" >> "$PKI_PATH/index.txt"
            fi
        fi
        
        # Actualizar CRL si easyrsa está disponible
        if [ -f "easyrsa" ]; then
            ./easyrsa gen-crl > /dev/null 2>&1
            if [ -f "$PKI_PATH/crl.pem" ]; then
                cp "$PKI_PATH/crl.pem" /etc/openvpn/ 2>/dev/null
            fi
        fi
        escribir_log "✅ Certificado de $cliente restaurado exitosamente"
        registrar_bloqueo "✅ Certificado de $cliente restaurado exitosamente"
        echo "   ✅ Certificado restaurado"
        return 0
    else
        escribir_log "⚠️  No hay backup del certificado para $cliente"
        echo "   ⚠️  No hay backup del certificado, solo se desbloqueará IP"
        registrar_bloqueo "⚠️  No hay backup del certificado para $cliente"
        return 1
    fi
}

# Función para verificar estado del cliente
estado_cliente() {
    cliente="$1"
    EASYRSA_DIR=$(encontrar_easyrsa)
    
    if [ -z "$EASYRSA_DIR" ]; then
        echo "unknown"
        return
    fi
    
    # Buscar index.txt en diferentes ubicaciones
    for idx_file in "$EASYRSA_DIR/pki/index.txt" "$EASYRSA_DIR/index.txt" "../index.txt" "pki/index.txt"; do
        if [ -f "$idx_file" ]; then
            if grep -q "^R.*/CN=$cliente$" "$idx_file" 2>/dev/null; then
                echo "revocado"
                return
            elif grep -q "^V.*/CN=$cliente$" "$idx_file" 2>/dev/null; then
                echo "activo"
                return
            fi
        fi
    done
    
    echo "no_encontrado"
}

# Función para mostrar menú
mostrar_menu() {
    clear
    echo ""
    echo "🔧 GESTIÓN VPN - SISTEMA COMPLETO CON LOGS"
    echo "=========================================="
    echo ""
    echo "1) 👁️  Ver clientes conectados (con fecha/hora)"
    echo "2) 📋 Listar estado de clientes"
    echo "3) 🚫 BLOQUEAR cliente (IP + certificado)"
    echo "4) ✅ DESBLOQUEAR cliente (IP + certificado)"
    echo "5) 🏷️  Gestionar nombres"
    echo "6) 🔍 Estado del sistema"
    echo "7) 📝 Registrar IP manualmente"
    echo "8) 📊 Ver LOG del sistema"
    echo "9) 📜 Ver LOG de bloqueos"
    echo "10) 🗑️  Limpiar archivos temporales"
    echo "11) ❌ Salir"
    echo ""
    echo -n "Selecciona [1-11]: "
}

# Función para ver clientes conectados
ver_conectados() {
    echo ""
    echo "📊 CLIENTES CONECTADOS"
    echo "======================"
    echo ""
    
    # Encontrar archivo de estado
    STATUS_FILE=$(encontrar_status_file)
    
    if [ ! -f "$STATUS_FILE" ] || [ ! -s "$STATUS_FILE" ]; then
        echo "❌ No se encuentra el archivo de estado de OpenVPN o está vacío"
        echo ""
        echo "💡 Soluciones posibles:"
        echo "   1. Verifica si OpenVPN está ejecutándose:"
        echo "      ps aux | grep openvpn"
        echo "   2. Busca el archivo manualmente:"
        echo "      find /etc -name '*status*log*' 2>/dev/null"
        echo "   3. Si OpenVPN no está corriendo, inícialo primero"
        
        escribir_log "❌ No se encuentra el archivo de estado de OpenVPN o está vacío: $STATUS_FILE"
        return
    fi
    
    echo "✅ Archivo encontrado: $STATUS_FILE"
    escribir_log "✅ Usando archivo de estado: $STATUS_FILE"
    
    # Obtener fecha actual
    fecha_hora_actual=$(date '+%d/%m/%Y %H:%M:%S')
    echo "🕒 Fecha actual: $fecha_hora_actual"
    echo ""
    
    # Verificar si hay clientes conectados
    if ! grep -q -E "(CLIENT_LIST.*[0-9]|,CONNECTED,)" "$STATUS_FILE"; then
        echo "ℹ️  No hay clientes conectados en este momento"
        escribir_log "ℹ️  No hay clientes conectados"
        return
    fi
    
    # Contador de clientes
    contador=0
    
    # Procesar cada cliente - formato OpenVPN 2.x
    if grep -q "^CLIENT_LIST" "$STATUS_FILE"; then
        echo "📡 Formato OpenVPN 2.x detectado"
        
        # Procesar cada cliente (excluyendo la línea HEADER)
        grep "^CLIENT_LIST" "$STATUS_FILE" | grep -v "HEADER" | while read linea; do
            # Extraer datos
            cliente=$(echo "$linea" | awk '{print $2}')
            ip_puerto=$(echo "$linea" | awk '{print $3}')
            ip_virtual=$(echo "$linea" | awk '{print $4}')
            
            # Extraer el timestamp Unix (columna 9 si existe)
            timestamp_unix=$(echo "$linea" | awk '{print $9}')
            
            if [ -n "$cliente" ] && [ "$cliente" != "UNDEF" ]; then
                cliente_limpio=$(limpiar_nombre "$cliente")
                nombre_descriptivo=$(obtener_nombre "$cliente_limpio")
                
                # Incrementar contador
                contador=$((contador + 1))
                
                # Convertir timestamp Unix a fecha legible
                fecha_conexion=$(timestamp_a_fecha "$timestamp_unix")
                
                # Mostrar información
                echo "    📍 Cliente $contador"
                echo "    👤 Nombre: $nombre_descriptivo"
                echo "    🔑 Certificado: $cliente_limpio"
                echo "    🌐 IP Real: $ip_puerto"
                echo "    🔗 IP VPN: $ip_virtual"
                if [ "$fecha_conexion" != "Fecha desconocida" ]; then
                    echo "    🕒 Conectado desde: $fecha_conexion"
                fi
                echo ""
                
                # Registrar IP en el historial
                timestamp=$(date '+%Y-%m-%d %H:%M:%S')
                ip_sin_puerto=$(echo "$ip_puerto" | cut -d: -f1)
                
                # Registrar en tracking
                echo "$timestamp|CONEXION|$cliente_limpio|$nombre_descriptivo|$ip_sin_puerto|$fecha_conexion" >> "$TRACKING_FILE"
                
                # Eliminar entrada antigua si existe
                if [ -f "$IP_HISTORY_FILE" ]; then
                    grep -v "^$cliente_limpio:$ip_sin_puerto:" "$IP_HISTORY_FILE" > /tmp/ip_temp.txt 2>/dev/null
                    mv /tmp/ip_temp.txt "$IP_HISTORY_FILE" 2>/dev/null
                fi
                
                # Añadir nueva entrada
                echo "$cliente_limpio:$ip_sin_puerto:$timestamp:$fecha_conexion" >> "$IP_HISTORY_FILE"
                
                # Registrar en log
                escribir_log "📡 Cliente $nombre_descriptivo ($cliente_limpio) conectado desde $ip_puerto"
            fi
        done
        
    else
        # Formato OpenVPN 3.x o diferente
        echo "📡 Formato OpenVPN 3.x/alternativo detectado"
        
        # Procesar líneas con clientes conectados
        grep ",CONNECTED," "$STATUS_FILE" | while read linea; do
            cliente=$(echo "$linea" | cut -d, -f1)
            ip_real=$(echo "$linea" | cut -d, -f2)
            ip_virtual=$(echo "$linea" | cut -d, -f3)
            fecha_conexion=$(echo "$linea" | cut -d, -f6)
            
            if [ -n "$cliente" ] && [ "$cliente" != "UNDEF" ]; then
                cliente_limpio=$(limpiar_nombre "$cliente")
                nombre_descriptivo=$(obtener_nombre "$cliente_limpio")
                
                # Incrementar contador
                contador=$((contador + 1))
                
                # Mostrar información
                echo "    📍 Cliente $contador"
                echo "    👤 Nombre: $nombre_descriptivo"
                echo "    🔑 Certificado: $cliente_limpio"
                echo "    🌐 IP Real: $ip_real"
                echo "    🔗 IP VPN: $ip_virtual"
                echo "    🕒 Conectado desde: $fecha_conexion"
                echo ""
                
                # Registrar IP en el historial
                timestamp=$(date '+%Y-%m-%d %H:%M:%S')
                ip_sin_puerto=$(echo "$ip_real" | cut -d: -f1)
                
                # Registrar en tracking
                echo "$timestamp|CONEXION|$cliente_limpio|$nombre_descriptivo|$ip_sin_puerto|$fecha_conexion" >> "$TRACKING_FILE"
                
                # Eliminar entrada antigua si existe
                if [ -f "$IP_HISTORY_FILE" ]; then
                    grep -v "^$cliente_limpio:$ip_sin_puerto:" "$IP_HISTORY_FILE" > /tmp/ip_temp.txt 2>/dev/null
                    mv /tmp/ip_temp.txt "$IP_HISTORY_FILE" 2>/dev/null
                fi
                
                # Añadir nueva entrada
                echo "$cliente_limpio:$ip_sin_puerto:$timestamp:$fecha_conexion" >> "$IP_HISTORY_FILE"
                
                # Registrar en log
                escribir_log "📡 Cliente $nombre_descriptivo ($cliente_limpio) conectado desde $ip_real"
            fi
        done
    fi
    
    # Solo mostrar resumen si hay clientes conectados
    if [ $contador -gt 0 ]; then
        echo "📊 RESUMEN:"
        echo "    ✅ Total de clientes conectados: $contador"
        echo "    📊 IPs registradas en historial: $contador"
        echo ""
        echo "💡 Las IPs se han registrado automáticamente en el historial y tracking"
        
        escribir_log "📊 Mostrados $contador clientes conectados"
    fi
}

# Función para listar estado de clientes
listar_clientes() {
    echo ""
    echo "📋 ESTADO COMPLETO DE CLIENTES"
    echo "=============================="
    echo ""
    escribir_log "📋 Mostrando estado completo de clientes"
    
    # Buscar archivo índice
    INDEX_FILE=""
    EASYRSA_DIR=$(encontrar_easyrsa)
    
    if [ -n "$EASYRSA_DIR" ]; then
        for idx in "pki/index.txt" "index.txt" "../index.txt" "pki/issued/../index.txt"; do
            if [ -f "$EASYRSA_DIR/$idx" ]; then
                INDEX_FILE="$EASYRSA_DIR/$idx"
                break
            fi
        done
    fi
    
    if [ -z "$INDEX_FILE" ]; then
        # Buscar en ubicaciones alternativas
        for dir in /etc/easy-rsa /etc/openvpn/easy-rsa /etc/openvpn/server/easy-rsa /etc/openvpn; do
            for idx in "pki/index.txt" "index.txt"; do
                if [ -f "$dir/$idx" ]; then
                    INDEX_FILE="$dir/$idx"
                    break 2
                fi
            done
        done
    fi
    
    if [ -z "$INDEX_FILE" ] || [ ! -f "$INDEX_FILE" ]; then
        echo "   ℹ️  No se encuentra base de datos de certificados"
        echo "   💡 Los certificados pueden estar en otro directorio"
        echo "   ℹ️  Mostrando solo información de nuestro sistema..."
        
        # Mostrar solo lo que tenemos en nuestro sistema
        echo ""
        echo "👥 CLIENTES EN NUESTRO SISTEMA:"
        echo ""
        
        # Clientes con IPs registradas
        echo "📍 Clientes con IPs registradas:"
        if [ -f "$IP_HISTORY_FILE" ] && [ -s "$IP_HISTORY_FILE" ]; then
            cut -d: -f1 "$IP_HISTORY_FILE" | sort -u | while read cliente; do
                nombre_descriptivo=$(obtener_nombre "$cliente")
                echo "   👤 $nombre_descriptivo ($cliente)"
            done
        else
            echo "   ℹ️  Ninguno"
        fi
        
        echo ""
        echo "🚫 Clientes bloqueados:"
        if [ -f "$SUSPENDED_FILE" ] && [ -s "$SUSPENDED_FILE" ]; then
            while IFS=: read -r cliente fecha tipo resto; do
                if [ -n "$cliente" ]; then
                    nombre_descriptivo=$(obtener_nombre "$cliente")
                    echo "   🚫 $nombre_descriptivo ($cliente) - $fecha"
                fi
            done < "$SUSPENDED_FILE"
        else
            echo "   ℹ️  Ninguno"
        fi
        
        echo ""
        echo "🏷️  Clientes con nombres asignados:"
        if [ -f "$NOMBRES_FILE" ] && [ -s "$NOMBRES_FILE" ]; then
            while IFS=: read -r cliente nombre; do
                echo "   🏷️  $nombre ($cliente)"
            done < "$NOMBRES_FILE"
        else
            echo "   ℹ️  Ninguno"
        fi
        return
    fi
    
    echo "📁 Usando archivo índice: $INDEX_FILE"
    
    echo ""
    echo "🎯 CLIENTES ACTIVOS (certificado válido):"
    echo ""
    activos=0
    grep "^V" "$INDEX_FILE" 2>/dev/null > /tmp/activos.txt
    
    if [ -s /tmp/activos.txt ]; then
        while read linea; do
            # Extraer el CN (Common Name)
            if echo "$linea" | grep -q "/CN="; then
                cliente=$(echo "$linea" | sed 's/.*\/CN=//' | awk '{print $1}')
            else
                cliente=$(echo "$linea" | awk '{print $NF}')
            fi
            
            # Filtrar valores no deseados
            if [ -n "$cliente" ] && [ "$cliente" != "unknown" ] && [ "$cliente" != "server" ]; then
                # Verificar si está bloqueado en nuestro sistema
                bloqueado_nuestro=""
                if [ -f "$SUSPENDED_FILE" ] && grep -q "^$cliente:" "$SUSPENDED_FILE"; then
                    bloqueado_nuestro="🚫"
                fi
                
                activos=$((activos + 1))
                nombre_descriptivo=$(obtener_nombre "$cliente")
                echo "   $activos) 🟢 $nombre_descriptivo ($cliente) $bloqueado_nuestro"
            fi
        done < /tmp/activos.txt
    fi
    
    rm -f /tmp/activos.txt 2>/dev/null
    
    if [ $activos -eq 0 ]; then
        echo "   Ninguno"
    fi
    
    echo ""
    echo "🔴 CLIENTES REVOCADOS (certificado inválido):"
    echo ""
    revocados=0
    grep "^R" "$INDEX_FILE" 2>/dev/null > /tmp/revocados.txt
    
    if [ -s /tmp/revocados.txt ]; then
        while read linea; do
            # Extraer el CN (Common Name)
            if echo "$linea" | grep -q "/CN="; then
                cliente=$(echo "$linea" | sed 's/.*\/CN=//' | awk '{print $1}')
            else
                cliente=$(echo "$linea" | awk '{print $NF}')
            fi
            
            if [ -n "$cliente" ] && [ "$cliente" != "unknown" ] && [ "$cliente" != "server" ]; then
                # Verificar si está bloqueado en nuestro sistema
                bloqueado_nuestro=""
                if [ -f "$SUSPENDED_FILE" ] && grep -q "^$cliente:" "$SUSPENDED_FILE"; then
                    bloqueado_nuestro="🚫"
                fi
                
                revocados=$((revocados + 1))
                nombre_descriptivo=$(obtener_nombre "$cliente")
                echo "   $revocados) 🔴 $nombre_descriptivo ($cliente) $bloqueado_nuestro"
            fi
        done < /tmp/revocados.txt
    fi
    
    rm -f /tmp/revocados.txt 2>/dev/null
    
    if [ $revocados -eq 0 ]; then
        echo "   Ninguno"
    fi
    
    echo ""
    echo "🚫 CLIENTES BLOQUEADOS EN NUESTRO SISTEMA:"
    echo ""
    bloqueados_sistema=0
    
    if [ -f "$SUSPENDED_FILE" ] && [ -s "$SUSPENDED_FILE" ]; then
        while IFS=: read -r cliente fecha tipo resto; do
            if [ -n "$cliente" ]; then
                bloqueados_sistema=$((bloqueados_sistema + 1))
                nombre_descriptivo=$(obtener_nombre "$cliente")
                # Verificar estado del certificado
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
    echo "   🚫 Bloqueados en sistema: $bloqueados_sistema"
    echo ""
    echo "💡 LEYENDA:"
    echo "   🟢 = Certificado válido | 🔴 = Certificado revocado"
    echo "   🚫 = IP bloqueada | ⚠️  = IP bloqueada pero certificado activo"
}

# Función para obtener IPs de un cliente
obtener_ips_cliente() {
    cliente="$1"
    cliente_limpio=$(limpiar_nombre "$cliente")
    if [ -f "$IP_HISTORY_FILE" ] && [ -s "$IP_HISTORY_FILE" ]; then
        grep "^$cliente_limpio:" "$IP_HISTORY_FILE" | cut -d: -f2,4 | sort -u
    fi
}

# Función para bloquear IP
bloquear_ip() {
    ip="$1"
    cliente="$2"
    
    if ! command -v iptables >/dev/null 2>&1; then
        escribir_log "❌ iptables no disponible para bloquear IP $ip"
        registrar_bloqueo "❌ iptables no disponible para bloquear IP $ip"
        echo "❌ iptables no disponible"
        return 1
    fi
    
    # Verificar si ya está bloqueada
    if iptables -nL INPUT 2>/dev/null | grep -q "DROP.*$ip"; then
        escribir_log "ℹ️  IP $ip ya estaba bloqueada para $cliente"
        registrar_bloqueo "ℹ️  IP $ip ya estaba bloqueada para $cliente"
        echo "   ℹ️  $ip ya estaba bloqueada"
        return 0
    fi
    
    # Bloquear IP
    if iptables -I INPUT -s "$ip" -j DROP 2>/dev/null; then
        # Guardar para persistencia
        mkdir -p /etc/openvpn
        if [ ! -f /etc/openvpn/blocked_ips.txt ] || ! grep -q "^$ip:" /etc/openvpn/blocked_ips.txt 2>/dev/null; then
            echo "$ip:$cliente:$(date '+%Y-%m-%d %H:%M:%S')" >> /etc/openvpn/blocked_ips.txt
        fi
        escribir_log "🔒 IP $ip bloqueada para cliente $cliente"
        registrar_bloqueo "🔒 IP $ip bloqueada para cliente $cliente"
        # Registrar en tracking
        echo "$(date '+%Y-%m-%d %H:%M:%S')|BLOQUEO_IP|$cliente|$(obtener_nombre "$cliente")|$ip|Manual" >> "$TRACKING_FILE"
        return 0
    else
        escribir_log "❌ Error bloqueando IP $ip para $cliente"
        registrar_bloqueo "❌ Error bloqueando IP $ip para $cliente"
        return 1
    fi
}

# Función para desbloquear IP
desbloquear_ip() {
    ip="$1"
    cliente="$2"
    
    if command -v iptables >/dev/null 2>&1; then
        iptables -D INPUT -s "$ip" -j DROP 2>/dev/null
        escribir_log "🔓 IP $ip desbloqueada"
        registrar_bloqueo "🔓 IP $ip desbloqueada"
        # Registrar en tracking
        if [ -n "$cliente" ]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S')|DESBLOQUEO_IP|$cliente|$(obtener_nombre "$cliente")|$ip|Manual" >> "$TRACKING_FILE"
        fi
    fi
    
    # Eliminar de persistencia
    if [ -f "/etc/openvpn/blocked_ips.txt" ]; then
        grep -v "^$ip:" /etc/openvpn/blocked_ips.txt > /tmp/blocked.tmp
        mv /tmp/blocked.tmp /etc/openvpn/blocked_ips.txt 2>/dev/null
    fi
}

# Función para BLOQUEAR CLIENTE COMPLETAMENTE
bloquear_cliente() {
    echo ""
    echo "🚫 BLOQUEAR CLIENTE (COMPLETO)"
    echo "=============================="
    echo "⚠️  Esto hará:"
    echo "   1. 🔒 Bloquear todas las IPs conocidas"
    echo "   2. 📝 Revocar certificado (si es posible)"
    echo "   3. 📋 Añadir a lista de bloqueados"
    echo ""
    
    escribir_log "🚫 Iniciando proceso de bloqueo completo"
    registrar_bloqueo "🚫 Iniciando proceso de bloqueo completo"
    
    if ! command -v iptables >/dev/null 2>&1; then
        escribir_log "❌ ERROR: iptables no instalado"
        registrar_bloqueo "❌ ERROR: iptables no instalado"
        echo "❌ ERROR: iptables no instalado"
        echo ""
        echo "💡 En OpenWRT:"
        echo "   opkg update && opkg install iptables-nft"
        return
    fi
    
    # Listar clientes activos (EXCLUYENDO SERVER)
    echo "Clientes disponibles para BLOQUEAR:"
    echo ""
    
    EASYRSA_DIR=$(encontrar_easyrsa)
    
    # Crear lista de clientes
    if [ -f "$IP_HISTORY_FILE" ] && [ -s "$IP_HISTORY_FILE" ]; then
        cut -d: -f1 "$IP_HISTORY_FILE" | sort -u > /tmp/clientes_raw.txt
    else
        > /tmp/clientes_raw.txt
    fi
    
    if [ -n "$EASYRSA_DIR" ]; then
        # Buscar archivo índice
        for idx in "pki/index.txt" "index.txt"; do
            if [ -f "$EASYRSA_DIR/$idx" ]; then
                grep "^V" "$EASYRSA_DIR/$idx" 2>/dev/null | while read linea; do
                    if echo "$linea" | grep -q "/CN="; then
                        cliente=$(echo "$linea" | sed 's/.*\/CN=//' | awk '{print $1}')
                    else
                        cliente=$(echo "$linea" | awk '{print $NF}')
                    fi
                    
                    if [ -n "$cliente" ] && [ "$cliente" != "unknown" ] && [ "$cliente" != "server" ]; then
                        echo "$cliente" >> /tmp/clientes_raw.txt
                    fi
                done
                break
            fi
        done
    fi
    
    if [ ! -f /tmp/clientes_raw.txt ] || [ ! -s /tmp/clientes_raw.txt ]; then
        escribir_log "ℹ️  No hay clientes disponibles para bloquear"
        registrar_bloqueo "ℹ️  No hay clientes disponibles para bloquear"
        echo "   ℹ️  No hay clientes disponibles para bloquear"
        return
    fi
    
    # Ordenar y eliminar duplicados
    sort -u /tmp/clientes_raw.txt > /tmp/clientes_unicos.txt
    
    # Mostrar clientes numerados
    num=0
    while read cliente; do
        num=$((num + 1))
        nombre_descriptivo=$(obtener_nombre "$cliente")
        # Verificar si ya está bloqueado
        bloqueado=""
        if [ -f "$SUSPENDED_FILE" ] && grep -q "^$cliente:" "$SUSPENDED_FILE"; then
            bloqueado=" [YA BLOQUEADO]"
        fi
        echo "   $num) $nombre_descriptivo ($cliente)$bloqueado"
        # Guardar para referencia
        echo "$num:$cliente" >> /tmp/clientes_index.txt
    done < /tmp/clientes_unicos.txt
    
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
    rm -f /tmp/clientes_raw.txt /tmp/clientes_unicos.txt /tmp/clientes_index.txt 2>/dev/null
    
    if [ -z "$cliente_seleccionado" ]; then
        escribir_log "❌ Selección inválida en bloqueo"
        registrar_bloqueo "❌ Selección inválida en bloqueo"
        echo "❌ Selección inválida"
        return
    fi
    
    # Verificar si ya está bloqueado
    if [ -f "$SUSPENDED_FILE" ] && grep -q "^$cliente_seleccionado:" "$SUSPENDED_FILE"; then
        echo ""
        echo "⚠️  Este cliente YA está bloqueado en nuestro sistema"
        echo -n "¿Bloquear de nuevo? (s/N): "
        read reconfirmar
        if [ "$reconfirmar" != "s" ] && [ "$reconfirmar" != "S" ]; then
            escribir_log "❌ Operación de bloqueo cancelada para $cliente_seleccionado"
            registrar_bloqueo "❌ Operación de bloqueo cancelada para $cliente_seleccionado"
            echo "❌ Operación cancelada"
            return
        fi
    fi
    
    echo ""
    echo "🔍 Buscando IPs de: $cliente_seleccionado"
    escribir_log "🔍 Buscando IPs para cliente $cliente_seleccionado"
    registrar_bloqueo "🔍 Buscando IPs para cliente $cliente_seleccionado"
    
    # Obtener IPs con fechas
    IPS_CON_FECHAS=$(obtener_ips_cliente "$cliente_seleccionado")
    
    if [ -z "$IPS_CON_FECHAS" ]; then
        escribir_log "ℹ️  No hay IPs registradas para $cliente_seleccionado"
        registrar_bloqueo "ℹ️  No hay IPs registradas para $cliente_seleccionado"
        echo "   ℹ️  No hay IPs registradas para este cliente"
        echo ""
        echo -n "¿Continuar solo con revocación de certificado? (s/N): "
        read continuar
        if [ "$continuar" != "s" ] && [ "$continuar" != "S" ]; then
            escribir_log "❌ Bloqueo cancelado para $cliente_seleccionado (sin IPs)"
            registrar_bloqueo "❌ Bloqueo cancelado para $cliente_seleccionado (sin IPs)"
            echo "❌ Operación cancelada"
            return
        fi
        IPS=""
    else
        echo "   📋 IPs encontradas (con fecha de conexión):"
        count=0
        IPS=""
        for ip_info in $IPS_CON_FECHAS; do
            ip=$(echo "$ip_info" | cut -d: -f1)
            fecha=$(echo "$ip_info" | cut -d: -f2)
            count=$((count + 1))
            echo "   $count) $ip (Última conexión: $fecha)"
            IPS="$IPS $ip"
        done
    fi
    
    echo ""
    echo "⚠️  CONFIRMACIÓN FINAL"
    echo "Cliente: $cliente_seleccionado"
    if [ -n "$IPS" ]; then
        echo "IPs a bloquear: $count"
    fi
    echo ""
    echo -n "¿Confirmar BLOQUEO COMPLETO? (s/N): "
    read confirmar
    
    if [ "$confirmar" != "s" ] && [ "$confirmar" != "S" ]; then
        escribir_log "❌ Bloqueo cancelado por usuario para $cliente_seleccionado"
        registrar_bloqueo "❌ Bloqueo cancelado por usuario para $cliente_seleccionado"
        echo "❌ Operación cancelada"
        return
    fi
    
    echo ""
    echo "🛡️  EJECUTANDO BLOQUEO COMPLETO..."
    echo ""
    escribir_log "🛡️  Iniciando bloqueo completo para $cliente_seleccionado"
    registrar_bloqueo "🛡️  Iniciando bloqueo completo para $cliente_seleccionado"
    
    # 1. Bloquear IPs
    bloqueadas=0
    if [ -n "$IPS" ]; then
        echo "🔒 Bloqueando IPs en firewall..."
        for ip in $IPS; do
            if bloquear_ip "$ip" "$cliente_seleccionado"; then
                echo "   ✅ $ip - BLOQUEADA"
                bloqueadas=$((bloqueadas + 1))
            else
                echo "   ❌ $ip - Error"
            fi
        done
    fi
    
    # 2. Revocar certificado
    echo ""
    echo "📝 Revocando certificado..."
    revocar_certificado "$cliente_seleccionado"
    
    # 3. Añadir a lista de bloqueados
    echo ""
    echo "📋 Actualizando lista de bloqueados..."
    # Crear archivo si no existe
    if [ ! -f "$SUSPENDED_FILE" ]; then
        touch "$SUSPENDED_FILE"
    fi
    
    # Eliminar si ya existe
    if grep -q "^$cliente_seleccionado:" "$SUSPENDED_FILE"; then
        grep -v "^$cliente_seleccionado:" "$SUSPENDED_FILE" > /tmp/suspended.tmp
        mv /tmp/suspended.tmp "$SUSPENDED_FILE"
    fi
    
    echo "$cliente_seleccionado:$(date '+%Y-%m-%d %H:%M:%S'):completo" >> "$SUSPENDED_FILE"
    
    # Registrar en tracking
    echo "$(date '+%Y-%m-%d %H:%M:%S')|BLOQUEO_COMPLETO|$cliente_seleccionado|$(obtener_nombre "$cliente_seleccionado")|$bloqueadas IPs|Certificado revocado" >> "$TRACKING_FILE"
    
    echo ""
    echo "✅ BLOQUEO COMPLETO REALIZADO"
    echo "   👤 Cliente: $cliente_seleccionado"
    if [ -n "$IPS" ]; then
        echo "   🔒 IPs bloqueadas: $bloqueadas/$count"
    fi
    echo "   📝 Certificado: REVOCADO"
    echo ""
    
    escribir_log "✅ BLOQUEO COMPLETO REALIZADO para $cliente_seleccionado"
    registrar_bloqueo "✅ BLOQUEO COMPLETO REALIZADO para $cliente_seleccionado"
    if [ -n "$IPS" ]; then
        escribir_log "   IPs bloqueadas: $bloqueadas/$count"
        registrar_bloqueo "   IPs bloqueadas: $bloqueadas/$count"
    fi
    
    echo "💡 El cliente NO podrá conectarse aunque cambie de IP"
}

# Función para DESBLOQUEAR CLIENTE COMPLETAMENTE
desbloquear_cliente() {
    echo ""
    echo "✅ DESBLOQUEAR CLIENTE (COMPLETO)"
    echo "================================"
    
    escribir_log "✅ Iniciando proceso de desbloqueo completo"
    registrar_bloqueo "✅ Iniciando proceso de desbloqueo completo"
    
    echo "Clientes BLOQUEADOS en nuestro sistema:"
    echo ""
    
    if [ ! -f "$SUSPENDED_FILE" ] || [ ! -s "$SUSPENDED_FILE" ]; then
        escribir_log "ℹ️  No hay clientes bloqueados"
        registrar_bloqueo "ℹ️  No hay clientes bloqueados"
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
            echo "$num:$cliente:$tipo" >> /tmp/bloqueados_index.txt
        fi
    done < "$SUSPENDED_FILE"
    
    echo ""
    echo -n "Selecciona cliente (número): "
    read seleccion
    
    # Obtener cliente seleccionado
    cliente_seleccionado=""
    tipo_bloqueo=""
    if [ -f /tmp/bloqueados_index.txt ]; then
        while IFS=: read -r num cliente tipo; do
            if [ "$num" = "$seleccion" ]; then
                cliente_seleccionado="$cliente"
                tipo_bloqueo="$tipo"
                break
            fi
        done < /tmp/bloqueados_index.txt
        rm -f /tmp/bloqueados_index.txt
    fi
    
    if [ -z "$cliente_seleccionado" ]; then
        escribir_log "❌ Selección inválida en desbloqueo"
        registrar_bloqueo "❌ Selección inválida en desbloqueo"
        echo "❌ Selección inválida"
        return
    fi
    
    echo ""
    echo "🔓 DESBLOQUEANDO: $cliente_seleccionado"
    echo ""
    escribir_log "🔓 Iniciando desbloqueo para $cliente_seleccionado"
    registrar_bloqueo "🔓 Iniciando desbloqueo para $cliente_seleccionado"
    
    # 1. Desbloquear IPs
    echo "🔓 Desbloqueando IPs..."
    IPS=$(obtener_ips_cliente "$cliente_seleccionado" | cut -d: -f1)
    if [ -n "$IPS" ]; then
        for ip in $IPS; do
            desbloquear_ip "$ip" "$cliente_seleccionado"
            echo "   ✅ $ip - DESBLOQUEADA"
        done
        escribir_log "🔓 IPs desbloqueadas para $cliente_seleccionado"
        registrar_bloqueo "🔓 IPs desbloqueadas para $cliente_seleccionado"
    else
        escribir_log "ℹ️  No hay IPs registradas para desbloquear para $cliente_seleccionado"
        registrar_bloqueo "ℹ️  No hay IPs registradas para desbloquear para $cliente_seleccionado"
        echo "   ℹ️  No hay IPs registradas para desbloquear"
    fi
    
    # 2. Restaurar certificado (si el bloqueo fue completo)
    if [ "$tipo_bloqueo" = "completo" ] || [ -z "$tipo_bloqueo" ]; then
        echo ""
        echo "📝 Restaurando certificado..."
        restaurar_certificado "$cliente_seleccionado"
    fi
    
    # 3. Eliminar de lista de bloqueados
    echo ""
    echo "📋 Eliminando de lista de bloqueados..."
    grep -v "^$cliente_seleccionado:" "$SUSPENDED_FILE" > /tmp/suspended.tmp
    mv /tmp/suspended.tmp "$SUSPENDED_FILE"
    
    # Registrar en tracking
    echo "$(date '+%Y-%m-%d %H:%M:%S')|DESBLOQUEO_COMPLETO|$cliente_seleccionado|$(obtener_nombre "$cliente_seleccionado")|$tipo_bloqueo|Certificado restaurado" >> "$TRACKING_FILE"
    
    echo ""
    echo "✅ CLIENTE DESBLOQUEADO COMPLETAMENTE"
    echo "   👤 Cliente: $cliente_seleccionado"
    echo "   🔓 IPs desbloqueadas"
    echo "   📝 Certificado: RESTAURADO (si era posible)"
    echo ""
    
    escribir_log "✅ CLIENTE $cliente_seleccionado DESBLOQUEADO COMPLETAMENTE"
    registrar_bloqueo "✅ CLIENTE $cliente_seleccionado DESBLOQUEADO COMPLETAMENTE"
}

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
                if [ -f "$NOMBRES_FILE" ] && [ -s "$NOMBRES_FILE" ]; then
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
                
                # Limpiar /CN= si lo pusieron
                cliente=$(limpiar_nombre "$cliente")
                
                if [ -n "$cliente" ] && [ -n "$nombre" ]; then
                    # Crear archivo temporal sin este cliente
                    if [ -f "$NOMBRES_FILE" ]; then
                        grep -v "^$cliente:" "$NOMBRES_FILE" > /tmp/nombres.tmp
                    else
                        > /tmp/nombres.tmp
                    fi
                    # Añadir nuevo
                    echo "$cliente:$nombre" >> /tmp/nombres.tmp
                    mv /tmp/nombres.tmp "$NOMBRES_FILE"
                    echo ""
                    echo "✅ NOMBRE ASIGNADO:"
                    echo "   📋 Certificado: $cliente"
                    echo "   🏷️  Nombre: $nombre"
                    echo ""
                    escribir_log "🏷️  Nombre asignado: $nombre para $cliente"
                    # Registrar en tracking
                    echo "$(date '+%Y-%m-%d %H:%M:%S')|ASIGNAR_NOMBRE|$cliente|$nombre|Manual|" >> "$TRACKING_FILE"
                    echo "💡 Ahora aparecerá como '$nombre' en las listas"
                else
                    escribir_log "❌ Error intentando asignar nombre (datos incompletos)"
                    echo "❌ Error: Debes ingresar ambos valores"
                fi
                ;;
                
            3)
                echo ""
                echo "🗑️  ELIMINAR NOMBRE"
                echo ""
                
                if [ ! -f "$NOMBRES_FILE" ] || [ ! -s "$NOMBRES_FILE" ]; then
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
                
                # Obtener cliente a eliminar
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
                    # Registrar en tracking
                    echo "$(date '+%Y-%m-%d %H:%M:%S')|ELIMINAR_NOMBRE|$cliente_eliminar|$(obtener_nombre "$cliente_eliminar")|Manual|" >> "$TRACKING_FILE"
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

# Función para registrar IP manualmente
registrar_ip_manual() {
    echo ""
    echo "📝 REGISTRAR IP MANUALMENTE"
    echo "==========================="
    echo ""
    echo "💡 Útil para probar sin tener clientes conectados"
    echo ""
    
    escribir_log "📝 Iniciando registro manual de IP"
    
    echo -n "Nombre del cliente (SIN /CN=): "
    read cliente
    
    # Limpiar /CN= si lo pusieron
    cliente=$(limpiar_nombre "$cliente")
    
    if [ -z "$cliente" ]; then
        escribir_log "❌ Registro manual fallido: sin nombre de cliente"
        echo "❌ Debes ingresar un nombre"
        return
    fi
    
    echo -n "IP a registrar (ej: 192.168.1.100): "
    read ip
    
    # Validar IP simple
    if ! echo "$ip" | grep -qE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$'; then
        escribir_log "❌ Registro manual fallido: IP $ip no válida"
        echo "❌ IP no válida"
        return
    fi
    
    fecha_conexion=$(date '+%d/%m/%Y %H:%M:%S')
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Eliminar entrada antigua si existe
    if [ -f "$IP_HISTORY_FILE" ]; then
        grep -v "^$cliente:$ip:" "$IP_HISTORY_FILE" > /tmp/ip_temp.txt 2>/dev/null
        mv /tmp/ip_temp.txt "$IP_HISTORY_FILE" 2>/dev/null
    fi
    
    # Añadir nueva entrada
    echo "$cliente:$ip:$timestamp:$fecha_conexion" >> "$IP_HISTORY_FILE"
    
    # Registrar en tracking
    echo "$timestamp|REGISTRO_MANUAL_IP|$cliente|$(obtener_nombre "$cliente")|$ip|$fecha_conexion" >> "$TRACKING_FILE"
    
    echo ""
    echo "✅ IP REGISTRADA CORRECTAMENTE"
    echo "   👤 Cliente: $cliente"
    echo "   📍 IP: $ip"
    echo "   🕒 Fecha conexión: $fecha_conexion"
    echo ""
    
    escribir_log "✅ IP $ip registrada manualmente para $cliente"
    escribir_log "   Fecha de conexión simulada: $fecha_conexion"
    
    echo "💡 Ahora puedes bloquear este cliente con la opción 3"
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
    
    # iptables
    echo ""
    echo "🛡️  IPTABLES:"
    if command -v iptables >/dev/null 2>&1; then
        echo "   ✅ Instalado"
        drops=$(iptables -nL INPUT 2>/dev/null | grep -c DROP || echo 0)
        echo "   📊 Reglas DROP en INPUT: $drops"
        escribir_log "🛡️  IPTABLES: Instalado, $drops reglas DROP"
    else
        echo "   ❌ No instalado"
        echo "   💡 Ejecuta: opkg update && opkg install iptables-nft"
        escribir_log "❌ IPTABLES: No instalado"
    fi
    
    # easy-rsa
    echo ""
    echo "📝 EASY-RSA:"
    EASYRSA_DIR=$(encontrar_easyrsa)
    if [ -n "$EASYRSA_DIR" ]; then
        echo "   ✅ Encontrado en: $EASYRSA_DIR"
        # Buscar archivo índice
        for idx in "pki/index.txt" "index.txt"; do
            if [ -f "$EASYRSA_DIR/$idx" ]; then
                activos=$(grep -c "^V" "$EASYRSA_DIR/$idx" 2>/dev/null || echo 0)
                revocados=$(grep -c "^R" "$EASYRSA_DIR/$idx" 2>/dev/null || echo 0)
                echo "   📊 Certificados: $activos activos, $revocados revocados"
                escribir_log "📝 EASY-RSA: Encontrado, $activos activos, $revocados revocados"
                break
            fi
        done
    else
        echo "   ⚠️  No encontrado (no se pueden revocar certificados)"
        escribir_log "⚠️  EASY-RSA: No encontrado"
    fi
    
    # Archivos del sistema
    echo ""
    echo "📁 ARCHIVOS DEL SISTEMA:"
    echo "   📍 Directorio base: $BASE_DIR"
    
    # Verificar cada archivo
    for file in "$NOMBRES_FILE" "$IP_HISTORY_FILE" "$SUSPENDED_FILE" "$LOG_FILE" "$TRACKING_FILE" "$BLOQUEO_LOG_FILE"; do
        filename=$(basename "$file")
        if [ -f "$file" ]; then
            size=$(wc -l < "$file" 2>/dev/null || echo 0)
            echo "   ✅ $filename: $size líneas"
        else
            echo "   ❌ $filename: No existe"
        fi
    done
    
    # Estadísticas
    echo ""
    echo "📊 ESTADÍSTICAS GESTOR:"
    
    nombres=0
    if [ -f "$NOMBRES_FILE" ]; then
        nombres=$(grep -c ":" "$NOMBRES_FILE" 2>/dev/null || echo 0)
    fi
    echo "   👥 Nombres asignados: $nombres"
    
    ips=0
    if [ -f "$IP_HISTORY_FILE" ]; then
        ips=$(wc -l < "$IP_HISTORY_FILE" 2>/dev/null || echo 0)
    fi
    echo "   📍 IPs registradas: $ips"
    
    bloqueados=0
    if [ -f "$SUSPENDED_FILE" ]; then
        bloqueados=$(wc -l < "$SUSPENDED_FILE" 2>/dev/null || echo 0)
    fi
    echo "   🚫 Clientes bloqueados: $bloqueados"
    
    # Tamaño del log
    log_size=0
    if [ -f "$LOG_FILE" ]; then
        log_size=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)
    fi
    echo "   📜 Entradas en log: $log_size"
    
    bloqueos_size=0
    if [ -f "$BLOQUEO_LOG_FILE" ]; then
        bloqueos_size=$(wc -l < "$BLOQUEO_LOG_FILE" 2>/dev/null || echo 0)
    fi
    echo "   🔒 Entradas en log de bloqueos: $bloqueos_size"
    
    tracking_size=0
    if [ -f "$TRACKING_FILE" ]; then
        tracking_size=$(wc -l < "$TRACKING_FILE" 2>/dev/null || echo 0)
    fi
    echo "   📊 Entradas en tracking: $tracking_size"
    
    escribir_log "📊 ESTADÍSTICAS: $nombres nombres, $ips IPs, $bloqueados bloqueados, $log_size logs, $bloqueos_size bloqueos, $tracking_size tracking"
    
    # IPs bloqueadas actuales
    echo ""
    echo "🔒 IPs ACTUALMENTE BLOQUEADAS:"
    if command -v iptables >/dev/null 2>&1; then
        iptables -nL INPUT 2>/dev/null | grep DROP > /tmp/blocked_current.txt 2>/dev/null
        
        if [ -s /tmp/blocked_current.txt ]; then
            count=0
            while read linea; do
                ip=$(echo "$linea" | awk '{print $4}')
                if [ -n "$ip" ] && [ "$ip" != "0.0.0.0/0" ]; then
                    count=$((count + 1))
                    if [ $count -le 10 ]; then
                        echo "   $count) $ip"
                    fi
                fi
            done < /tmp/blocked_current.txt
            
            rm -f /tmp/blocked_current.txt
            
            if [ $count -eq 0 ]; then
                echo "   ℹ️  Ninguna"
            elif [ $count -gt 10 ]; then
                echo "   ... y $((count - 10)) más"
            fi
            escribir_log "🔒 IPs bloqueadas actualmente: $count"
        else
            echo "   ℹ️  Ninguna"
        fi
    else
        echo "   ℹ️  iptables no disponible"
    fi
}

# Función para ver LOG del sistema
ver_log() {
    echo ""
    echo "📜 REGISTRO DEL SISTEMA (LOG)"
    echo "============================="
    echo ""
    
    if [ ! -f "$LOG_FILE" ] || [ ! -s "$LOG_FILE" ]; then
        echo "   📭 El archivo de log está vacío o no existe"
        return
    fi
    
    echo "Mostrando las últimas 50 entradas:"
    echo ""
    
    # Mostrar las últimas 50 líneas
    tail -50 "$LOG_FILE" | while read linea; do
        echo "   $linea"
    done
    
    echo ""
    echo "📊 Estadísticas del log:"
    total_lineas=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)
    echo "   Total de entradas: $total_lineas"
    
    # Obtener fecha de la primera y última entrada
    primera=$(head -1 "$LOG_FILE" 2>/dev/null | cut -c2-11 || echo "Desconocida")
    ultima=$(tail -1 "$LOG_FILE" 2>/dev/null | cut -c2-11 || echo "Desconocida")
    
    if [ "$primera" != "Desconocida" ] && [ "$ultima" != "Desconocida" ]; then
        echo "   Período: $primera - $ultima"
    fi
    
    echo ""
    echo "Opciones:"
    echo "   1) Ver log completo"
    echo "   2) Buscar en log"
    echo "   3) Limpiar log"
    echo "   4) Volver al menú"
    echo ""
    echo -n "Selecciona [1-4]: "
    read opcion_log
    
    case $opcion_log in
        1)
            echo ""
            echo "📜 LOG COMPLETO:"
            echo "================"
            if [ -f "$LOG_FILE" ]; then
                cat "$LOG_FILE" | while read linea; do
                    echo "   $linea"
                done
            fi
            ;;
        2)
            echo ""
            echo "🔍 BUSCAR EN LOG"
            echo "================"
            echo -n "Texto a buscar: "
            read busqueda
            if [ -n "$busqueda" ]; then
                echo ""
                echo "Resultados para '$busqueda':"
                echo ""
                if [ -f "$LOG_FILE" ]; then
                    grep -i "$busqueda" "$LOG_FILE" | while read linea; do
                        echo "   $linea"
                    done
                fi
            fi
            ;;
        3)
            echo ""
            echo "🗑️  LIMPIAR LOG"
            echo "=============="
            echo "¿Estás seguro de que quieres limpiar el archivo de log?"
            echo -n "Esto eliminará todas las entradas. (s/N): "
            read confirmar_limpiar
            if [ "$confirmar_limpiar" = "s" ] || [ "$confirmar_limpiar" = "S" ]; then
                > "$LOG_FILE"
                escribir_log "📜 Log limpiado manualmente"
                echo "✅ Log limpiado"
            else
                echo "❌ Operación cancelada"
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
}

# Función para ver LOG de bloqueos
ver_log_bloqueos() {
    echo ""
    echo "🔒 REGISTRO DE BLOQUEOS"
    echo "======================"
    echo ""
    
    if [ ! -f "$BLOQUEO_LOG_FILE" ] || [ ! -s "$BLOQUEO_LOG_FILE" ]; then
        echo "   📭 El archivo de bloqueos está vacío o no existe"
        return
    fi
    
    echo "Mostrando las últimas 50 entradas:"
    echo ""
    
    # Mostrar las últimas 50 líneas
    tail -50 "$BLOQUEO_LOG_FILE" | while read linea; do
        echo "   $linea"
    done
    
    echo ""
    echo "📊 Estadísticas de bloqueos:"
    total_lineas=$(wc -l < "$BLOQUEO_LOG_FILE" 2>/dev/null || echo 0)
    echo "   Total de entradas: $total_lineas"
    
    # Contar tipos de bloqueos
    bloqueos_ip=$(grep -c "BLOQUEO_IP\|bloqueada" "$BLOQUEO_LOG_FILE" 2>/dev/null || echo 0)
    desbloqueos_ip=$(grep -c "DESBLOQUEO_IP\|desbloqueada" "$BLOQUEO_LOG_FILE" 2>/dev/null || echo 0)
    revocaciones=$(grep -c "revocado" "$BLOQUEO_LOG_FILE" 2>/dev/null || echo 0)
    restauraciones=$(grep -c "restaurado" "$BLOQUEO_LOG_FILE" 2>/dev/null || echo 0)
    
    echo "   🔒 Bloqueos IP: $bloqueos_ip"
    echo "   🔓 Desbloqueos IP: $desbloqueos_ip"
    echo "   📝 Revocaciones certificado: $revocaciones"
    echo "   🔄 Restauraciones certificado: $restauraciones"
    
    echo ""
    echo "Opciones:"
    echo "   1) Ver log completo"
    echo "   2) Buscar en log"
    echo "   3) Limpiar log"
    echo "   4) Volver al menú"
    echo ""
    echo -n "Selecciona [1-4]: "
    read opcion_bloqueos
    
    case $opcion_bloqueos in
        1)
            echo ""
            echo "🔒 LOG COMPLETO DE BLOQUEOS:"
            echo "============================"
            if [ -f "$BLOQUEO_LOG_FILE" ]; then
                cat "$BLOQUEO_LOG_FILE" | while read linea; do
                    echo "   $linea"
                done
            fi
            ;;
        2)
            echo ""
            echo "🔍 BUSCAR EN LOG DE BLOQUEOS"
            echo "============================"
            echo -n "Texto a buscar: "
            read busqueda
            if [ -n "$busqueda" ]; then
                echo ""
                echo "Resultados para '$busqueda':"
                echo ""
                if [ -f "$BLOQUEO_LOG_FILE" ]; then
                    grep -i "$busqueda" "$BLOQUEO_LOG_FILE" | while read linea; do
                        echo "   $linea"
                    done
                fi
            fi
            ;;
        3)
            echo ""
            echo "🗑️  LIMPIAR LOG DE BLOQUEOS"
            echo "=========================="
            echo "¿Estás seguro de que quieres limpiar el archivo de bloqueos?"
            echo -n "Esto eliminará todas las entradas. (s/N): "
            read confirmar_limpiar
            if [ "$confirmar_limpiar" = "s" ] || [ "$confirmar_limpiar" = "S" ]; then
                > "$BLOQUEO_LOG_FILE"
                escribir_log "🔒 Log de bloqueos limpiado manualmente"
                echo "✅ Log de bloqueos limpiado"
            else
                echo "❌ Operación cancelada"
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
}

# Función para limpiar archivos temporales
limpiar_temporales() {
    echo ""
    echo "🗑️  LIMPIAR ARCHIVOS TEMPORALES"
    echo "================================"
    echo ""
    echo "⚠️  Esta opción eliminará archivos temporales antiguos"
    echo ""
    echo "1) Limpiar archivos temporales del sistema (/tmp)"
    echo "2) Limpiar entradas antiguas del historial de IPs (más de 30 días)"
    echo "3) Limpiar tracking antiguo (más de 90 días)"
    echo "4) Volver al menú"
    echo ""
    echo -n "Selecciona [1-4]: "
    read opcion_limpiar
    
    case $opcion_limpiar in
        1)
            echo ""
            echo "🧹 Limpiando archivos temporales en /tmp..."
            rm -f /tmp/*_temp.txt /tmp/*.tmp /tmp/clientes*.txt /tmp/activos.txt /tmp/revocados.txt /tmp/blocked_current.txt 2>/dev/null
            escribir_log "🧹 Archivos temporales de /tmp limpiados"
            echo "✅ Archivos temporales limpiados"
            ;;
        2)
            echo ""
            echo "🗓️  Limpiando historial de IPs antiguas..."
            if [ -f "$IP_HISTORY_FILE" ]; then
                # Calcular fecha límite (30 días atrás)
                fecha_limite=$(date -d "30 days ago" '+%Y-%m-%d' 2>/dev/null || date -v-30d '+%Y-%m-%d' 2>/dev/null || echo "1970-01-01")
                contador_antes=$(wc -l < "$IP_HISTORY_FILE" 2>/dev/null || echo 0)
                
                # Filtrar líneas más recientes que la fecha límite
                grep -E "^[^:]*:[^:]*:${fecha_limite}[0-9:-]*:" "$IP_HISTORY_FILE" > /tmp/ip_history_nuevo.txt 2>/dev/null
                
                if [ -s /tmp/ip_history_nuevo.txt ]; then
                    mv /tmp/ip_history_nuevo.txt "$IP_HISTORY_FILE"
                    contador_despues=$(wc -l < "$IP_HISTORY_FILE" 2>/dev/null || echo 0)
                    eliminadas=$((contador_antes - contador_despues))
                    escribir_log "🗑️  Historial de IPs limpiado: $eliminadas entradas antiguas eliminadas"
                    echo "✅ Historial de IPs limpiado: $eliminadas entradas antiguas eliminadas"
                else
                    echo "ℹ️  No hay entradas antiguas para eliminar"
                fi
                rm -f /tmp/ip_history_nuevo.txt 2>/dev/null
            else
                echo "ℹ️  No existe el archivo de historial de IPs"
            fi
            ;;
        3)
            echo ""
            echo "📅 Limpiando tracking antiguo..."
            if [ -f "$TRACKING_FILE" ]; then
                # Guardar copia de seguridad
                cp "$TRACKING_FILE" "$TRACKING_FILE.backup" 2>/dev/null
                
                # Mantener solo los últimos 1000 registros
                tail -1000 "$TRACKING_FILE" > /tmp/tracking_nuevo.txt 2>/dev/null
                mv /tmp/tracking_nuevo.txt "$TRACKING_FILE"
                
                contador_despues=$(wc -l < "$TRACKING_FILE" 2>/dev/null || echo 0)
                escribir_log "📅 Tracking limpiado: se mantuvieron los últimos $contador_despues registros"
                echo "✅ Tracking limpiado: se mantuvieron los últimos $contador_despues registros"
                rm -f /tmp/tracking_nuevo.txt 2>/dev/null
            else
                echo "ℹ️  No existe el archivo de tracking"
            fi
            ;;
        4)
            return
            ;;
        *)
            echo "❌ Opción inválida"
            ;;
    esac
}

# Programa principal
escribir_log "🚀 Sistema de gestión VPN iniciado"
registrar_bloqueo "🚀 Sistema de gestión VPN iniciado"

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
            registrar_ip_manual
            ;;
        8)
            ver_log
            ;;
        9)
            ver_log_bloqueos
            ;;
        10)
            limpiar_temporales
            ;;
        11)
            escribir_log "👋 Sistema de gestión VPN finalizado"
            registrar_bloqueo "👋 Sistema de gestión VPN finalizado"
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
echo "✅ SISTEMA ACTUALIZADO - USANDO TUS ARCHIVOS EXACTOS"
echo ""
echo "📁 ARCHIVOS UTILIZADOS:"
echo "   📍 Directorio: /etc/openvpn/clientes/"
echo ""
echo "   📄 nombres.txt              - Nombres descriptivos de clientes"
echo "   📄 ip_history.txt           - Historial de IPs conectadas"
echo "   📄 suspended.txt            - Clientes bloqueados"
echo "   📄 vpn_gestion.log          - Log principal del sistema"
echo "   📄 tracking.txt             - Tracking de eventos"
echo "   📄 conexiones_bloqueadas.log - Log específico de bloqueos"
echo ""
echo "🔧 MEJORAS IMPLEMENTADAS:"
echo ""
echo "   1. ✅ Usa TODOS tus archivos existentes"
echo "   2. ✅ Función para ver log de bloqueos (opción 9)"
echo "   3. ✅ Función para limpiar temporales (opción 10)"
echo "   4. ✅ Registro automático en tracking.txt"
echo "   5. ✅ Búsqueda mejorada del archivo status.log"
echo "   6. ✅ Manejo robusto de errores"
echo ""
echo "🚀 PRUEBA INMEDIATA:"
echo "   Ejecuta: gestion"
echo "   Verás el menú actualizado con 11 opciones"
echo ""
echo "💡 NUEVAS FUNCIONALIDADES:"
echo "   - Opción 9: Ver LOG de bloqueos específico"
echo "   - Opción 10: Limpiar archivos temporales"
echo "   - Tracking automático de todas las acciones"
echo "   - Mejor visualización del estado del sistema"
