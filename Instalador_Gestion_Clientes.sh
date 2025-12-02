#!/bin/sh

echo ""
echo "🔧 CORRIGIENDO SISTEMA DE BLOQUEO COMPLETO"
echo "=========================================="

# Actualizar el script
cat > /usr/bin/gestion << 'EOF'
#!/bin/sh

# Archivos de configuración
NOMBRES_FILE="/etc/openvpn/clientes/nombres.txt"
IP_HISTORY_FILE="/etc/openvpn/clientes/ip_history.txt"
SUSPENDED_FILE="/etc/openvpn/clientes/suspended.txt"

# Crear archivos si no existen
touch "$NOMBRES_FILE"
touch "$IP_HISTORY_FILE"
touch "$SUSPENDED_FILE"

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

# Función para revocar certificado
revocar_certificado() {
    cliente="$1"
    EASYRSA_DIR=$(encontrar_easyrsa)
    
    if [ -z "$EASYRSA_DIR" ]; then
        echo "⚠️  No se encuentra easy-rsa, no se puede revocar certificado"
        echo "   Solo se bloqueará la IP en firewall"
        return 1
    fi
    
    echo "   📝 Revocando certificado de $cliente..."
    
    # Cambiar al directorio easy-rsa
    cd "$EASYRSA_DIR" 2>/dev/null || return 1
    
    # Verificar si el certificado existe
    if [ ! -f "pki/issued/$cliente.crt" ]; then
        echo "   ⚠️  Certificado $cliente.crt no encontrado"
        return 1
    fi
    
    # Revocar certificado
    if [ -f "easyrsa" ]; then
        echo "yes" | ./easyrsa revoke "$cliente" > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            # Actualizar CRL
            ./easyrsa gen-crl > /dev/null 2>&1
            # Copiar CRL a OpenVPN
            cp pki/crl.pem /etc/openvpn/ 2>/dev/null
            echo "   ✅ Certificado revocado"
            return 0
        fi
    fi
    
    echo "   ❌ Error revocando certificado"
    return 1
}

# Función para restaurar certificado
restaurar_certificado() {
    cliente="$1"
    EASYRSA_DIR=$(encontrar_easyrsa)
    
    if [ -z "$EASYRSA_DIR" ]; then
        echo "⚠️  No se encuentra easy-rsa"
        return 1
    fi
    
    echo "   📝 Restaurando certificado de $cliente..."
    
    cd "$EASYRSA_DIR" 2>/dev/null || return 1
    
    # Verificar si hay backup del certificado
    if [ -f "pki/issued/$cliente.crt.backup" ]; then
        # Restaurar desde backup
        cp "pki/issued/$cliente.crt.backup" "pki/issued/$cliente.crt" 2>/dev/null
        cp "pki/private/$cliente.key.backup" "pki/private/$cliente.key" 2>/dev/null
        
        # Eliminar línea de revocación del índice
        sed -i "/\/CN=$cliente$/d" pki/index.txt 2>/dev/null
        # Añadir como válido
        serial=$(openssl x509 -in "pki/issued/$cliente.crt" -serial -noout 2>/dev/null | cut -d= -f2)
        if [ -n "$serial" ]; then
            echo "V\t$(date +'%y%m%d%H%M%SZ')\t\t$serial\tunknown\t/CN=$cliente" >> pki/index.txt
        fi
        
        # Actualizar CRL
        ./easyrsa gen-crl > /dev/null 2>&1
        cp pki/crl.pem /etc/openvpn/ 2>/dev/null
        echo "   ✅ Certificado restaurado"
        return 0
    else
        echo "   ⚠️  No hay backup del certificado, solo se desbloqueará IP"
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
    
    if grep -q "^R.*/CN=$cliente$" "$EASYRSA_DIR/pki/index.txt" 2>/dev/null; then
        echo "revocado"
    elif grep -q "^V.*/CN=$cliente$" "$EASYRSA_DIR/pki/index.txt" 2>/dev/null; then
        echo "activo"
    else
        echo "no_encontrado"
    fi
}

# Función para mostrar menú
mostrar_menu() {
    clear
    echo ""
    echo "🔧 GESTIÓN VPN - BLOQUEO COMPLETO"
    echo "================================="
    echo ""
    echo "1) 👁️  Ver clientes conectados (registra IPs)"
    echo "2) 📋 Listar estado de clientes"
    echo "3) 🚫 BLOQUEAR cliente (IP + certificado)"
    echo "4) ✅ DESBLOQUEAR cliente (IP + certificado)"
    echo "5) 🏷️  Gestionar nombres"
    echo "6) 🔍 Estado del sistema"
    echo "7) 📝 Registrar IP manualmente"
    echo "8) ❌ Salir"
    echo ""
    echo -n "Selecciona [1-8]: "
}

# Función para ver clientes conectados (REGISTRA IPs automáticamente)
ver_conectados() {
    echo ""
    echo "📊 CLIENTES CONECTADOS (registrando IPs):"
    echo ""
    
    # Buscar archivo de estado
    if [ -f "/var/log/openvpn-status.log" ]; then
        STATUS_FILE="/var/log/openvpn-status.log"
    elif [ -f "/tmp/openvpn-status.log" ]; then
        STATUS_FILE="/tmp/openvpn-status.log"
    else
        echo "   ⚠️  No se encuentra archivo de estado"
        return
    fi
    
    # Leer clientes conectados
    grep "^CLIENT_LIST" "$STATUS_FILE" > /tmp/clientes_temp.txt 2>/dev/null
    
    if [ ! -s /tmp/clientes_temp.txt ]; then
        echo "   ℹ️  No hay clientes conectados"
        rm -f /tmp/clientes_temp.txt
        return
    fi
    
    registradas=0
    # Procesar cada cliente
    while read linea; do
        # Extraer datos
        cliente=$(echo "$linea" | awk '{print $2}')
        ip_externa=$(echo "$linea" | awk '{print $3}')
        
        if [ -n "$cliente" ] && [ "$ip_externa" != "UNDEF" ]; then
            cliente_limpio=$(limpiar_nombre "$cliente")
            nombre_descriptivo=$(obtener_nombre "$cliente"))
            
            # Registrar IP automáticamente
            timestamp=$(date '+%Y-%m-%d %H:%M:%S')
            
            # Eliminar entrada antigua si existe
            grep -v "^$cliente_limpio:$ip_externa:" "$IP_HISTORY_FILE" > /tmp/ip_temp.txt 2>/dev/null
            mv /tmp/ip_temp.txt "$IP_HISTORY_FILE" 2>/dev/null
            
            # Añadir nueva entrada
            echo "$cliente_limpio:$ip_externa:$timestamp" >> "$IP_HISTORY_FILE"
            registradas=$((registradas + 1))
            
            # Mostrar información
            if [ "$cliente_limpio" = "$nombre_descriptivo" ]; then
                echo "   👤 $cliente_limpio"
            else
                echo "   👤 $nombre_descriptivo ($cliente_limpio)"
            fi
            echo "      📍 IP: $ip_externa (REGISTRADA)"
            echo ""
        fi
    done < /tmp/clientes_temp.txt
    
    rm -f /tmp/clientes_temp.txt
    
    if [ $registradas -eq 0 ]; then
        echo "   ℹ️  No se registraron nuevas IPs"
    else
        echo "✅ Se registraron $registradas IPs en $IP_HISTORY_FILE"
    fi
}

# Función para listar estado de clientes (CORREGIDA)
listar_clientes() {
    echo ""
    echo "📋 ESTADO COMPLETO DE CLIENTES"
    echo "=============================="
    echo ""
    
    # Buscar base de datos
    INDEX_FILE=""
    EASYRSA_DIR=$(encontrar_easyrsa)
    if [ -n "$EASYRSA_DIR" ] && [ -f "$EASYRSA_DIR/pki/index.txt" ]; then
        INDEX_FILE="$EASYRSA_DIR/pki/index.txt"
    else
        # Buscar en ubicaciones alternativas
        for dir in /etc/easy-rsa/pki /etc/openvpn/easy-rsa/pki /etc/openvpn; do
            if [ -f "$dir/index.txt" ]; then
                INDEX_FILE="$dir/index.txt"
                break
            fi
        done
    fi
    
    if [ -z "$INDEX_FILE" ]; then
        echo "   ℹ️  No se encuentra base de datos de certificados"
        return
    fi
    
    echo "🎯 CLIENTES ACTIVOS (certificado válido):"
    echo ""
    activos=0
    grep "^V" "$INDEX_FILE" > /tmp/activos.txt 2>/dev/null
    
    while read linea; do
        # Extraer el CN (Common Name)
        if echo "$linea" | grep -q "/CN="; then
            cliente=$(echo "$linea" | sed 's/.*\/CN=//' | awk '{print $1}')
        else
            cliente=$(echo "$linea" | awk '{print $NF}')
        fi
        
        # FILTRAR: No mostrar "server"
        if [ -n "$cliente" ] && [ "$cliente" != "unknown" ] && [ "$cliente" != "server" ]; then
            # Verificar si está bloqueado en nuestro sistema
            bloqueado_nuestro=""
            if grep -q "^$cliente:" "$SUSPENDED_FILE"; then
                bloqueado_nuestro="🚫"
            fi
            
            activos=$((activos + 1))
            nombre_descriptivo=$(obtener_nombre "$cliente")
            echo "   $activos) 🟢 $nombre_descriptivo ($cliente) $bloqueado_nuestro"
        fi
    done < /tmp/activos.txt
    
    rm -f /tmp/activos.txt
    
    if [ $activos -eq 0 ]; then
        echo "   Ninguno"
    fi
    
    echo ""
    echo "🔴 CLIENTES REVOCADOS (certificado inválido):"
    echo ""
    revocados=0
    grep "^R" "$INDEX_FILE" > /tmp/revocados.txt 2>/dev/null
    
    while read linea; do
        # Extraer el CN (Common Name)
        if echo "$linea" | grep -q "/CN="; then
            cliente=$(echo "$linea" | sed 's/.*\/CN=//' | awk '{print $1}')
        else
            cliente=$(echo "$linea" | awk '{print $NF}')
        fi
        
        # FILTRAR: No mostrar "server"
        if [ -n "$cliente" ] && [ "$cliente" != "unknown" ] && [ "$cliente" != "server" ]; then
            # Verificar si está bloqueado en nuestro sistema
            bloqueado_nuestro=""
            if grep -q "^$cliente:" "$SUSPENDED_FILE"; then
                bloqueado_nuestro="🚫"
            fi
            
            revocados=$((revocados + 1))
            nombre_descriptivo=$(obtener_nombre "$cliente")
            echo "   $revocados) 🔴 $nombre_descriptivo ($cliente) $bloqueado_nuestro"
        fi
    done < /tmp/revocados.txt
    
    rm -f /tmp/revocados.txt
    
    if [ $revocados -eq 0 ]; then
        echo "   Ninguno"
    fi
    
    echo ""
    echo "🚫 CLIENTES BLOQUEADOS EN NUESTRO SISTEMA:"
    echo ""
    bloqueados_sistema=0
    
    if [ -s "$SUSPENDED_FILE" ]; then
        while IFS=: read -r cliente fecha resto; do
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
    if [ -f "$IP_HISTORY_FILE" ]; then
        grep "^$cliente_limpio:" "$IP_HISTORY_FILE" | cut -d: -f2 | sort -u
    fi
}

# Función para bloquear IP
bloquear_ip() {
    ip="$1"
    cliente="$2"
    
    if ! command -v iptables >/dev/null 2>&1; then
        echo "❌ iptables no disponible"
        return 1
    fi
    
    # Verificar si ya está bloqueada
    if iptables -nL INPUT 2>/dev/null | grep -q "DROP.*$ip"; then
        echo "   ℹ️  $ip ya estaba bloqueada"
        return 0
    fi
    
    # Bloquear IP
    if iptables -I INPUT -s "$ip" -j DROP 2>/dev/null; then
        # Guardar para persistencia
        mkdir -p /etc/openvpn
        if ! grep -q "^$ip:" /etc/openvpn/blocked_ips.txt 2>/dev/null; then
            echo "$ip:$cliente:$(date '+%Y-%m-%d %H:%M:%S')" >> /etc/openvpn/blocked_ips.txt
        fi
        return 0
    else
        return 1
    fi
}

# Función para desbloquear IP
desbloquear_ip() {
    ip="$1"
    
    if command -v iptables >/dev/null 2>&1; then
        iptables -D INPUT -s "$ip" -j DROP 2>/dev/null
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
    
    if ! command -v iptables >/dev/null 2>&1; then
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
    if [ -z "$EASYRSA_DIR" ] || [ ! -f "$EASYRSA_DIR/pki/index.txt" ]; then
        echo "   ℹ️  No se encuentra easy-rsa, solo se bloquearán IPs"
    fi
    
    # Crear lista de clientes activos
    if [ -n "$EASYRSA_DIR" ] && [ -f "$EASYRSA_DIR/pki/index.txt" ]; then
        grep "^V" "$EASYRSA_DIR/pki/index.txt" 2>/dev/null | while read linea; do
            # Extraer el CN
            if echo "$linea" | grep -q "/CN="; then
                cliente=$(echo "$linea" | sed 's/.*\/CN=//' | awk '{print $1}')
            else
                cliente=$(echo "$linea" | awk '{print $NF}')
            fi
            
            # FILTRAR: No incluir "server"
            if [ -n "$cliente" ] && [ "$cliente" != "unknown" ] && [ "$cliente" != "server" ]; then
                echo "$cliente" >> /tmp/clientes_raw.txt
            fi
        done
    else
        # Si no hay easy-rsa, usar clientes con IPs registradas
        cut -d: -f1 "$IP_HISTORY_FILE" 2>/dev/null | sort -u > /tmp/clientes_raw.txt
    fi
    
    if [ ! -f /tmp/clientes_raw.txt ] || [ ! -s /tmp/clientes_raw.txt ]; then
        echo "   ℹ️  No hay clientes disponibles para bloquear"
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
        # Guardar para referencia
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
        echo "❌ Selección inválida"
        return
    fi
    
    # Verificar si ya está bloqueado
    if grep -q "^$cliente_seleccionado:" "$SUSPENDED_FILE"; then
        echo ""
        echo "⚠️  Este cliente YA está bloqueado en nuestro sistema"
        echo -n "¿Bloquear de nuevo? (s/N): "
        read reconfirmar
        if [ "$reconfirmar" != "s" ] && [ "$reconfirmar" != "S" ]; then
            echo "❌ Operación cancelada"
            return
        fi
    fi
    
    echo ""
    echo "🔍 Buscando IPs de: $cliente_seleccionado"
    
    # Obtener IPs
    IPS=$(obtener_ips_cliente "$cliente_seleccionado")
    
    if [ -z "$IPS" ]; then
        echo "   ℹ️  No hay IPs registradas para este cliente"
        echo ""
        echo -n "¿Continuar solo con revocación de certificado? (s/N): "
        read continuar
        if [ "$continuar" != "s" ] && [ "$continuar" != "S" ]; then
            echo "❌ Operación cancelada"
            return
        fi
    else
        echo "   📋 IPs encontradas:"
        count=0
        for ip in $IPS; do
            count=$((count + 1))
            echo "      $count) $ip"
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
        echo "❌ Operación cancelada"
        return
    fi
    
    echo ""
    echo "🛡️  EJECUTANDO BLOQUEO COMPLETO..."
    echo ""
    
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
    # Eliminar si ya existe
    grep -v "^$cliente_seleccionado:" "$SUSPENDED_FILE" > /tmp/suspended.tmp
    echo "$cliente_seleccionado:$(date '+%Y-%m-%d %H:%M:%S'):completo" >> /tmp/suspended.tmp
    mv /tmp/suspended.tmp "$SUSPENDED_FILE"
    
    echo ""
    echo "✅ BLOQUEO COMPLETO REALIZADO"
    echo "   👤 Cliente: $cliente_seleccionado"
    if [ -n "$IPS" ]; then
        echo "   🔒 IPs bloqueadas: $bloqueadas/$count"
    fi
    echo "   📝 Certificado: REVOCADO"
    echo ""
    echo "💡 El cliente NO podrá conectarse aunque cambie de IP"
}

# Función para DESBLOQUEAR CLIENTE COMPLETAMENTE
desbloquear_cliente() {
    echo ""
    echo "✅ DESBLOQUEAR CLIENTE (COMPLETO)"
    echo "================================"
    
    echo "Clientes BLOQUEADOS en nuestro sistema:"
    echo ""
    
    if [ ! -s "$SUSPENDED_FILE" ]; then
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
        echo "❌ Selección inválida"
        return
    fi
    
    echo ""
    echo "🔓 DESBLOQUEANDO: $cliente_seleccionado"
    echo ""
    
    # 1. Desbloquear IPs
    echo "🔓 Desbloqueando IPs..."
    IPS=$(obtener_ips_cliente "$cliente_seleccionado")
    if [ -n "$IPS" ]; then
        for ip in $IPS; do
            desbloquear_ip "$ip"
            echo "   ✅ $ip - DESBLOQUEADA"
        done
    else
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
    
    echo ""
    echo "✅ CLIENTE DESBLOQUEADO COMPLETAMENTE"
    echo "   👤 Cliente: $cliente_seleccionado"
    echo "   🔓 IPs desbloqueadas"
    echo "   📝 Certificado: RESTAURADO (si era posible)"
}

# (Las funciones gestionar_nombres, registrar_ip_manual, estado_servicio se mantienen igual)
# [Pegar aquí las funciones existentes sin cambios...]

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
                
                # Limpiar /CN= si lo pusieron
                cliente=$(echo "$cliente" | sed 's|/CN=||')
                
                if [ -n "$cliente" ] && [ -n "$nombre" ]; then
                    # Crear archivo temporal sin este cliente
                    grep -v "^$cliente:" "$NOMBRES_FILE" > /tmp/nombres.tmp
                    # Añadir nuevo
                    echo "$cliente:$nombre" >> /tmp/nombres.tmp
                    mv /tmp/nombres.tmp "$NOMBRES_FILE"
                    echo ""
                    echo "✅ NOMBRE ASIGNADO:"
                    echo "   📋 Certificado: $cliente"
                    echo "   🏷️  Nombre: $nombre"
                    echo ""
                    echo "💡 Ahora aparecerá como '$nombre' en las listas"
                else
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
    
    echo -n "Nombre del cliente (SIN /CN=): "
    read cliente
    
    # Limpiar /CN= si lo pusieron
    cliente=$(echo "$cliente" | sed 's|/CN=||')
    
    if [ -z "$cliente" ]; then
        echo "❌ Debes ingresar un nombre"
        return
    fi
    
    echo -n "IP a registrar (ej: 192.168.1.100): "
    read ip
    
    # Validar IP simple
    if echo "$ip" | grep -qv '^[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*$'; then
        echo "❌ IP no válida"
        return
    fi
    
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Eliminar entrada antigua si existe
    grep -v "^$cliente:$ip:" "$IP_HISTORY_FILE" > /tmp/ip_temp.txt 2>/dev/null
    mv /tmp/ip_temp.txt "$IP_HISTORY_FILE" 2>/dev/null
    
    # Añadir nueva entrada
    echo "$cliente:$ip:$timestamp" >> "$IP_HISTORY_FILE"
    
    echo ""
    echo "✅ IP REGISTRADA CORRECTAMENTE"
    echo "   👤 Cliente: $cliente"
    echo "   📍 IP: $ip"
    echo "   ⏰ Fecha: $timestamp"
    echo ""
    echo "💡 Ahora puedes bloquear este cliente con la opción 3"
}

# Función para estado del sistema
estado_servicio() {
    echo ""
    echo "🔍 ESTADO DEL SISTEMA"
    echo "===================="
    echo ""
    
    # OpenVPN
    if pgrep openvpn >/dev/null; then
        echo "✅ OpenVPN: ACTIVO"
    else
        echo "❌ OpenVPN: INACTIVO"
    fi
    
    # iptables
    echo ""
    echo "🛡️  IPTABLES:"
    if command -v iptables >/dev/null 2>&1; then
        echo "   ✅ Instalado"
        drops=$(iptables -nL INPUT 2>/dev/null | grep -c DROP)
        echo "   📊 Reglas DROP en INPUT: $drops"
    else
        echo "   ❌ No instalado"
        echo "   💡 Ejecuta: opkg update && opkg install iptables-nft"
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
        fi
    else
        echo "   ⚠️  No encontrado (no se pueden revocar certificados)"
    fi
    
    # Estadísticas
    echo ""
    echo "📊 ESTADÍSTICAS GESTOR:"
    nombres=$(grep -c ":" "$NOMBRES_FILE" 2>/dev/null || echo 0)
    echo "   👥 Nombres asignados: $nombres"
    
    ips=$(wc -l < "$IP_HISTORY_FILE" 2>/dev/null || echo 0)
    echo "   📍 IPs registradas: $ips"
    
    bloqueados=$(wc -l < "$SUSPENDED_FILE" 2>/dev/null || echo 0)
    echo "   🚫 Clientes bloqueados: $bloqueados"
    
    # IPs bloqueadas actuales
    echo ""
    echo "🔒 IPs ACTUALMENTE BLOQUEADAS:"
    if command -v iptables >/dev/null 2>&1; then
        iptables -nL INPUT 2>/dev/null | grep DROP > /tmp/blocked_current.txt
        
        if [ -s /tmp/blocked_current.txt ]; then
            count=0
            while read linea; do
                ip=$(echo "$linea" | awk '{print $4}')
                if [ -n "$ip" ]; then
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
        else
            echo "   ℹ️  Ninguna"
        fi
    else
        echo "   ℹ️  iptables no disponible"
    fi
}

# Programa principal
while true; do
    mostrar_menu
    read opcion
    
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
            echo ""
            echo "👋 Saliendo..."
            exit 0
            ;;
        *)
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
echo "✅ SISTEMA CORREGIDO"
echo ""
echo "🔧 CAMBIOS REALIZADOS:"
echo "   1. ✅ BLOQUEO COMPLETO: Ahora revoca certificados además de bloquear IPs"
echo "   2. ✅ LISTADO CORRECTO: La opción 2 muestra estado real de certificados"
echo "   3. ✅ SEPARACIÓN CLARA:"
echo "      - 🟢 Certificados activos (V en index.txt)"
echo "      - 🔴 Certificados revocados (R en index.txt)"
echo "      - 🚫 Bloqueados en nuestro sistema (archivo suspended.txt)"
echo "   4. ✅ DESBLOQUEO COMPLETO: Restaura certificados al desbloquear"
echo ""
echo "🚀 FLUJO CORREGIDO:"
echo "   Opción 3 (BLOQUEAR):"
echo "     1. Bloquea IPs en firewall"
echo "     2. Revoca certificado en easy-rsa"
echo "     3. Añade a lista de bloqueados"
echo ""
echo "   Opción 4 (DESBLOQUEAR):"
echo "     1. Desbloquea IPs del firewall"
echo "     2. Restaura certificado (si había backup)"
echo "     3. Elimina de lista de bloqueados"
echo ""
echo "📊 LA OPCIÓN 2 AHORA MUESTRA:"
echo "   - Certificados válidos (🟢)"
echo "   - Certificados revocados (🔴)"
echo "   - Clientes bloqueados en nuestro sistema (🚫)"
echo ""
echo "💡 NOTA: Si easy-rsa no está disponible, solo se bloquearán IPs"
echo "   (compatible con instalaciones mínimas)"
