#!/bin/sh

echo ""
echo "🔧 ACTUALIZANDO SISTEMA - CORRECCIÓN DE SINTAXIS"
echo "================================================"

# Actualizar el script
cat > /usr/bin/gestion << 'EOF'
#!/bin/sh

# Archivos de configuración
NOMBRES_FILE="/etc/openvpn/clientes/nombres.txt"
IP_HISTORY_FILE="/etc/openvpn/clientes/ip_history.txt"
SUSPENDED_FILE="/etc/openvpn/clientes/suspended.txt"
LOG_FILE="/etc/openvpn/clientes/vpn_gestion.log"

# Crear archivos si no existen
mkdir -p /etc/openvpn/clientes
touch "$NOMBRES_FILE"
touch "$IP_HISTORY_FILE"
touch "$SUSPENDED_FILE"
touch "$LOG_FILE"

# Función para convertir timestamp Unix a fecha legible
timestamp_a_fecha() {
    timestamp="$1"
    if [ -n "$timestamp" ] && [ "$timestamp" -gt 0 ] 2>/dev/null; then
        if command -v date >/dev/null 2>&1; then
            date -d "@$timestamp" '+%d/%m/%Y %H:%M:%S' 2>/dev/null || \
            date -r "$timestamp" '+%d/%m/%Y %H:%M:%S' 2>/dev/null || \
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
        escribir_log "⚠️  No se encuentra easy-rsa, no se puede revocar certificado para $cliente"
        echo "⚠️  No se encuentra easy-rsa, no se puede revocar certificado"
        echo "   Solo se bloqueará la IP en firewall"
        return 1
    fi
    
    echo "   📝 Revocando certificado de $cliente..."
    escribir_log "📝 Iniciando revocación de certificado para $cliente"
    
    cd "$EASYRSA_DIR" 2>/dev/null || return 1
    
    if [ ! -f "pki/issued/$cliente.crt" ]; then
        escribir_log "⚠️  Certificado $cliente.crt no encontrado"
        echo "   ⚠️  Certificado $cliente.crt no encontrado"
        return 1
    fi
    
    if [ ! -f "pki/issued/$cliente.crt.backup" ]; then
        cp "pki/issued/$cliente.crt" "pki/issued/$cliente.crt.backup" 2>/dev/null
        cp "pki/private/$cliente.key" "pki/private/$cliente.key.backup" 2>/dev/null
        escribir_log "✅ Backup de certificado $cliente creado"
    fi
    
    if [ -f "easyrsa" ]; then
        echo "yes" | ./easyrsa revoke "$cliente" > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            ./easyrsa gen-crl > /dev/null 2>&1
            cp pki/crl.pem /etc/openvpn/ 2>/dev/null
            escribir_log "✅ Certificado de $cliente revocado exitosamente"
            echo "   ✅ Certificado revocado"
            return 0
        fi
    fi
    
    escribir_log "❌ Error revocando certificado de $cliente"
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
        return 1
    fi
    
    echo "   📝 Restaurando certificado de $cliente..."
    escribir_log "📝 Iniciando restauración de certificado para $cliente"
    
    cd "$EASYRSA_DIR" 2>/dev/null || return 1
    
    if [ -f "pki/issued/$cliente.crt.backup" ]; then
        cp "pki/issued/$cliente.crt.backup" "pki/issued/$cliente.crt" 2>/dev/null
        cp "pki/private/$cliente.key.backup" "pki/private/$cliente.key" 2>/dev/null
        
        sed -i "/\/CN=$cliente$/d" pki/index.txt 2>/dev/null
        serial=$(openssl x509 -in "pki/issued/$cliente.crt" -serial -noout 2>/dev/null | cut -d= -f2)
        if [ -n "$serial" ]; then
            echo "V\t$(date +'%y%m%d%H%M%SZ')\t\t$serial\tunknown\t/CN=$cliente" >> pki/index.txt
        fi
        
        ./easyrsa gen-crl > /dev/null 2>&1
        cp pki/crl.pem /etc/openvpn/ 2>/dev/null
        escribir_log "✅ Certificado de $cliente restaurado exitosamente"
        echo "   ✅ Certificado restaurado"
        return 0
    else
        escribir_log "⚠️  No hay backup del certificado para $cliente"
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
    echo "9) ❌ Salir"
    echo ""
    echo -n "Selecciona [1-9]: "
}

# Función para ver clientes conectados - VERSIÓN SIMPLIFICADA Y CORREGIDA
ver_conectados() {
    echo ""
    echo "📊 CLIENTES CONECTADOS"
    echo "======================"
    echo ""
    
    if [ -f "/var/log/openvpn-status.log" ]; then
        STATUS_FILE="/var/log/openvpn-status.log"
    else
        echo "❌ No se encuentra /var/log/openvpn-status.log"
        escribir_log "❌ No se encuentra /var/log/openvpn-status.log"
        return
    fi
    
    fecha_hora_actual=$(date '+%d/%m/%Y %H:%M:%S')
    echo "🕒 Fecha actual: $fecha_hora_actual"
    echo ""
    
    if [ ! -s "$STATUS_FILE" ]; then
        echo "ℹ️  El archivo openvpn-status.log está vacío"
        escribir_log "ℹ️  openvpn-status.log está vacío"
        return
    fi
    
    if ! grep -q "^CLIENT_LIST," "$STATUS_FILE"; then
        echo "ℹ️  No hay clientes conectados en este momento"
        escribir_log "ℹ️  No hay clientes conectados"
        return
    fi
    
    contador=0
    
    # Procesar cada línea CLIENT_LIST - VERSIÓN SIMPLIFICADA
    grep "^CLIENT_LIST," "$STATUS_FILE" | while IFS= read -r linea; do
        # Extraer datos de forma simple
        cliente=$(echo "$linea" | cut -d, -f2)
        ip_real=$(echo "$linea" | cut -d, -f3)
        ip_virtual=$(echo "$linea" | cut -d, -f4)
        bytes_recv=$(echo "$linea" | cut -d, -f6)
        bytes_sent=$(echo "$linea" | cut -d, -f7)
        fecha_conexion=$(echo "$linea" | cut -d, -f8)
        cipher=$(echo "$linea" | cut -d, -f13)
        
        if [ -n "$cliente" ] && [ "$cliente" != "UNDEF" ] && [ -n "$ip_real" ]; then
            cliente_limpio=$(echo "$cliente" | sed 's|/CN=||')
            nombre_descriptivo=$(obtener_nombre "$cliente_limpio")
            
            contador=$((contador + 1))
            
            echo "    📍 Cliente $contador"
            echo "    👤 Nombre: $nombre_descriptivo"
            echo "    🔑 Certificado: $cliente_limpio"
            echo "    🌐 IP Real: $ip_real"
            
            if [ -n "$ip_virtual" ] && [ "$ip_virtual" != "" ]; then
                echo "    🔗 IP VPN: $ip_virtual"
            else
                echo "    🔗 IP VPN: No asignada"
            fi
            
            echo "    🕒 Conectado desde: $fecha_conexion"
            
            # Formatear bytes si es posible
            if command -v numfmt >/dev/null 2>&1 && [ -n "$bytes_recv" ] && [ -n "$bytes_sent" ]; then
                bytes_recv_humano=$(numfmt --to=iec --suffix=B "$bytes_recv" 2>/dev/null || echo "${bytes_recv}B")
                bytes_sent_humano=$(numfmt --to=iec --suffix=B "$bytes_sent" 2>/dev/null || echo "${bytes_sent}B")
                echo "    📊 Tráfico: ▼ $bytes_recv_humano / ▲ $bytes_sent_humano"
            fi
            
            if [ -n "$cipher" ] && [ "$cipher" != "" ]; then
                echo "    🔐 Cifrado: $cipher"
            fi
            echo ""
            
            # Registrar en historial
            timestamp=$(date '+%Y-%m-%d %H:%M:%S')
            ip_sin_puerto=$(echo "$ip_real" | cut -d: -f1)
            
            grep -v "^$cliente_limpio:$ip_sin_puerto:" "$IP_HISTORY_FILE" > /tmp/ip_temp.txt 2>/dev/null
            mv /tmp/ip_temp.txt "$IP_HISTORY_FILE" 2>/dev/null
            
            echo "$cliente_limpio:$ip_sin_puerto:$timestamp:$fecha_conexion" >> "$IP_HISTORY_FILE"
            
            escribir_log "📡 Cliente $nombre_descriptivo ($cliente_limpio) conectado desde $ip_real - $fecha_conexion"
        fi
    done
    
    if [ $contador -eq 0 ]; then
        echo "ℹ️  No hay clientes conectados en este momento"
        escribir_log "ℹ️  No hay clientes conectados"
    else
        echo "📊 RESUMEN:"
        echo "    ✅ Total de clientes conectados: $contador"
        echo "    📊 IPs registradas en historial: $contador"
        echo ""
        echo "💡 Las IPs se han registrado automáticamente en el historial"
        escribir_log "📊 Mostrados $contador clientes conectados, IPs registradas"
    fi
}

# Función para listar estado de clientes
listar_clientes() {
    echo ""
    echo "📋 ESTADO COMPLETO DE CLIENTES"
    echo "=============================="
    echo ""
    escribir_log "📋 Mostrando estado completo de clientes"
    
    INDEX_FILE=""
    EASYRSA_DIR=$(encontrar_easyrsa)
    if [ -n "$EASYRSA_DIR" ] && [ -f "$EASYRSA_DIR/pki/index.txt" ]; then
        INDEX_FILE="$EASYRSA_DIR/pki/index.txt"
    else
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
        if echo "$linea" | grep -q "/CN="; then
            cliente=$(echo "$linea" | sed 's/.*\/CN=//' | awk '{print $1}')
        else
            cliente=$(echo "$linea" | awk '{print $NF}')
        fi
        
        if [ -n "$cliente" ] && [ "$cliente" != "unknown" ] && [ "$cliente" != "server" ]; then
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
        if echo "$linea" | grep -q "/CN="; then
            cliente=$(echo "$linea" | sed 's/.*\/CN=//' | awk '{print $1}')
        else
            cliente=$(echo "$linea" | awk '{print $NF}')
        fi
        
        if [ -n "$cliente" ] && [ "$cliente" != "unknown" ] && [ "$cliente" != "server" ]; then
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
        grep "^$cliente_limpio:" "$IP_HISTORY_FILE" | cut -d: -f2,4 | sort -u
    fi
}

# Función para bloquear IP
bloquear_ip() {
    ip="$1"
    cliente="$2"
    
    if ! command -v iptables >/dev/null 2>&1; then
        escribir_log "❌ iptables no disponible para bloquear IP $ip"
        echo "❌ iptables no disponible"
        return 1
    fi
    
    if iptables -nL INPUT 2>/dev/null | grep -q "DROP.*$ip"; then
        escribir_log "ℹ️  IP $ip ya estaba bloqueada para $cliente"
        echo "   ℹ️  $ip ya estaba bloqueada"
        return 0
    fi
    
    if iptables -I INPUT -s "$ip" -j DROP 2>/dev/null; then
        mkdir -p /etc/openvpn
        if ! grep -q "^$ip:" /etc/openvpn/blocked_ips.txt 2>/dev/null; then
            echo "$ip:$cliente:$(date '+%Y-%m-%d %H:%M:%S')" >> /etc/openvpn/blocked_ips.txt
        fi
        escribir_log "🔒 IP $ip bloqueada para cliente $cliente"
        return 0
    else
        escribir_log "❌ Error bloqueando IP $ip para $cliente"
        return 1
    fi
}

# Función para desbloquear IP
desbloquear_ip() {
    ip="$1"
    
    if command -v iptables >/dev/null 2>&1; then
        iptables -D INPUT -s "$ip" -j DROP 2>/dev/null
        escribir_log "🔓 IP $ip desbloqueada"
    fi
    
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
    
    if ! command -v iptables >/dev/null 2>&1; then
        escribir_log "❌ ERROR: iptables no instalado"
        echo "❌ ERROR: iptables no instalado"
        echo ""
        echo "💡 En OpenWRT:"
        echo "   opkg update && opkg install iptables-nft"
        return
    fi
    
    echo "Clientes disponibles para BLOQUEAR:"
    echo ""
    
    EASYRSA_DIR=$(encontrar_easyrsa)
    if [ -z "$EASYRSA_DIR" ] || [ ! -f "$EASYRSA_DIR/pki/index.txt" ]; then
        escribir_log "ℹ️  No se encuentra easy-rsa, solo se bloquearán IPs"
        echo "   ℹ️  No se encuentra easy-rsa, solo se bloquearán IPs"
    fi
    
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
        cut -d: -f1 "$IP_HISTORY_FILE" 2>/dev/null | sort -u > /tmp/clientes_raw.txt
    fi
    
    if [ ! -f /tmp/clientes_raw.txt ] || [ ! -s /tmp/clientes_raw.txt ]; then
        escribir_log "ℹ️  No hay clientes disponibles para bloquear"
        echo "   ℹ️  No hay clientes disponibles para bloquear"
        return
    fi
    
    num=0
    while read cliente; do
        num=$((num + 1))
        nombre_descriptivo=$(obtener_nombre "$cliente")
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
    
    cliente_seleccionado=""
    if [ -f /tmp/clientes_index.txt ]; then
        while IFS=: read -r num cliente; do
            if [ "$num" = "$seleccion" ]; then
                cliente_seleccionado="$cliente"
                break
            fi
        done < /tmp/clientes_index.txt
    fi
    
    rm -f /tmp/clientes_raw.txt /tmp/clientes_index.txt 2>/dev/null
    
    if [ -z "$cliente_seleccionado" ]; then
        escribir_log "❌ Selección inválida en bloqueo"
        echo "❌ Selección inválida"
        return
    fi
    
    if grep -q "^$cliente_seleccionado:" "$SUSPENDED_FILE"; then
        echo ""
        echo "⚠️  Este cliente YA está bloqueado en nuestro sistema"
        echo -n "¿Bloquear de nuevo? (s/N): "
        read reconfirmar
        if [ "$reconfirmar" != "s" ] && [ "$reconfirmar" != "S" ]; then
            escribir_log "❌ Operación de bloqueo cancelada para $cliente_seleccionado"
            echo "❌ Operación cancelada"
            return
        fi
    fi
    
    echo ""
    echo "🔍 Buscando IPs de: $cliente_seleccionado"
    escribir_log "🔍 Buscando IPs para cliente $cliente_seleccionado"
    
    IPS_CON_FECHAS=$(obtener_ips_cliente "$cliente_seleccionado")
    
    if [ -z "$IPS_CON_FECHAS" ]; then
        escribir_log "ℹ️  No hay IPs registradas para $cliente_seleccionado"
        echo "   ℹ️  No hay IPs registradas para este cliente"
        echo ""
        echo -n "¿Continuar solo con revocación de certificado? (s/N): "
        read continuar
        if [ "$continuar" != "s" ] && [ "$continuar" != "S" ]; then
            escribir_log "❌ Bloqueo cancelado para $cliente_seleccionado (sin IPs)"
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
        echo "❌ Operación cancelada"
        return
    fi
    
    echo ""
    echo "🛡️  EJECUTANDO BLOQUEO COMPLETO..."
    echo ""
    escribir_log "🛡️  Iniciando bloqueo completo para $cliente_seleccionado"
    
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
    
    echo ""
    echo "📝 Revocando certificado..."
    revocar_certificado "$cliente_seleccionado"
    
    echo ""
    echo "📋 Actualizando lista de bloqueados..."
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
    
    escribir_log "✅ BLOQUEO COMPLETO REALIZADO para $cliente_seleccionado"
    escribir_log "   IPs bloqueadas: $bloqueadas/$count"
    
    echo "💡 El cliente NO podrá conectarse aunque cambie de IP"
}

# Función para DESBLOQUEAR CLIENTE COMPLETAMENTE
desbloquear_cliente() {
    echo ""
    echo "✅ DESBLOQUEAR CLIENTE (COMPLETO)"
    echo "================================"
    
    escribir_log "✅ Iniciando proceso de desbloqueo completo"
    
    echo "Clientes BLOQUEADOS en nuestro sistema:"
    echo ""
    
    if [ ! -s "$SUSPENDED_FILE" ]; then
        escribir_log "ℹ️  No hay clientes bloqueados"
        echo "   ℹ️  No hay clientes bloqueados"
        return
    fi
    
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
        echo "❌ Selección inválida"
        return
    fi
    
    echo ""
    echo "🔓 DESBLOQUEANDO: $cliente_seleccionado"
    echo ""
    escribir_log "🔓 Iniciando desbloqueo para $cliente_seleccionado"
    
    echo "🔓 Desbloqueando IPs..."
    IPS=$(obtener_ips_cliente "$cliente_seleccionado" | cut -d: -f1)
    if [ -n "$IPS" ]; then
        for ip in $IPS; do
            desbloquear_ip "$ip"
            echo "   ✅ $ip - DESBLOQUEADA"
        done
        escribir_log "🔓 IPs desbloqueadas para $cliente_seleccionado"
    else
        escribir_log "ℹ️  No hay IPs registradas para desbloquear para $cliente_seleccionado"
        echo "   ℹ️  No hay IPs registradas para desbloquear"
    fi
    
    if [ "$tipo_bloqueo" = "completo" ] || [ -z "$tipo_bloqueo" ]; then
        echo ""
        echo "📝 Restaurando certificado..."
        restaurar_certificado "$cliente_seleccionado"
    fi
    
    echo ""
    echo "📋 Eliminando de lista de bloqueados..."
    grep -v "^$cliente_seleccionado:" "$SUSPENDED_FILE" > /tmp/suspended.tmp
    mv /tmp/suspended.tmp "$SUSPENDED_FILE"
    
    echo ""
    echo "✅ CLIENTE DESBLOQUEADO COMPLETAMENTE"
    echo "   👤 Cliente: $cliente_seleccionado"
    echo "   🔓 IPs desbloqueadas"
    echo "   📝 Certificado: RESTAURADO (si era posible)"
    echo ""
    
    escribir_log "✅ CLIENTE $cliente_seleccionado DESBLOQUEADO COMPLETAMENTE"
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
    
    cliente=$(echo "$cliente" | sed 's|/CN=||')
    
    if [ -z "$cliente" ]; then
        escribir_log "❌ Registro manual fallido: sin nombre de cliente"
        echo "❌ Debes ingresar un nombre"
        return
    fi
    
    echo -n "IP a registrar (ej: 192.168.1.100): "
    read ip
    
    if echo "$ip" | grep -qv '^[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*$'; then
        escribir_log "❌ Registro manual fallido: IP $ip no válida"
        echo "❌ IP no válida"
        return
    fi
    
    fecha_conexion=$(date '+%d/%m/%Y %H:%M:%S')
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    grep -v "^$cliente:$ip:" "$IP_HISTORY_FILE" > /tmp/ip_temp.txt 2>/dev/null
    mv /tmp/ip_temp.txt "$IP_HISTORY_FILE" 2>/dev/null
    
    echo "$cliente:$ip:$timestamp:$fecha_conexion" >> "$IP_HISTORY_FILE"
    
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
    
    if pgrep openvpn >/dev/null; then
        echo "✅ OpenVPN: ACTIVO"
        escribir_log "✅ OpenVPN: ACTIVO"
    else
        echo "❌ OpenVPN: INACTIVO"
        escribir_log "❌ OpenVPN: INACTIVO"
    fi
    
    echo ""
    echo "🛡️  IPTABLES:"
    if command -v iptables >/dev/null 2>&1; then
        echo "   ✅ Instalado"
        drops=$(iptables -nL INPUT 2>/dev/null | grep -c DROP)
        echo "   📊 Reglas DROP en INPUT: $drops"
        escribir_log "🛡️  IPTABLES: Instalado, $drops reglas DROP"
    else
        echo "   ❌ No instalado"
        echo "   💡 Ejecuta: opkg update && opkg install iptables-nft"
        escribir_log "❌ IPTABLES: No instalado"
    fi
    
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
        echo "   ⚠️  No encontrado (no se pueden revocar certificados)"
        escribir_log "⚠️  EASY-RSA: No encontrado"
    fi
    
    echo ""
    echo "📊 ESTADÍSTICAS GESTOR:"
    nombres=$(grep -c ":" "$NOMBRES_FILE" 2>/dev/null || echo 0)
    echo "   👥 Nombres asignados: $nombres"
    
    ips=$(wc -l < "$IP_HISTORY_FILE" 2>/dev/null || echo 0)
    echo "   📍 IPs registradas: $ips"
    
    bloqueados=$(wc -l < "$SUSPENDED_FILE" 2>/dev/null || echo 0)
    echo "   🚫 Clientes bloqueados: $bloqueados"
    
    log_size=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)
    echo "   📜 Entradas en log: $log_size"
    
    escribir_log "📊 ESTADÍSTICAS: $nombres nombres, $ips IPs, $bloqueados bloqueados, $log_size logs"
    
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
    echo "Mostrando las últimas 50 entradas:"
    echo ""
    
    if [ ! -f "$LOG_FILE" ] || [ ! -s "$LOG_FILE" ]; then
        echo "   📭 El archivo de log está vacío o no existe"
        return
    fi
    
    tail -50 "$LOG_FILE" | while read linea; do
        echo "   $linea"
    done
    
    echo ""
    echo "📊 Estadísticas del log:"
    total_lineas=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)
    echo "   Total de entradas: $total_lineas"
    
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
            cat "$LOG_FILE" | while read linea; do
                echo "   $linea"
            done
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
                grep -i "$busqueda" "$LOG_FILE" | while read linea; do
                    echo "   $linea"
                done
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

# Programa principal
escribir_log "🚀 Sistema de gestión VPN iniciado"

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
echo "✅ SISTEMA ACTUALIZADO - ERROR DE SINTAXIS CORREGIDO"
echo ""
echo "🔧 CAMBIOS PRINCIPALES:"
echo ""
echo "   1. ✅ FUNCIÓN ver_conectados() SIMPLIFICADA:"
echo "      - Uso de 'cut -d, -fX' en lugar de IFS complejo"
echo "      - Eliminación de estructuras anidadas problemáticas"
echo "      - Código más limpio y menos propenso a errores"
echo ""
echo "   2. 🎯 PROCESAMIENTO DE DATOS:"
echo "      - cliente: cut -d, -f2"
echo "      - ip_real: cut -d, -f3"
echo "      - ip_virtual: cut -d, -f4"
echo "      - bytes_recv: cut -d, -f6"
echo "      - bytes_sent: cut -d, -f7"
echo "      - fecha_conexion: cut -d, -f8"
echo "      - cipher: cut -d, -f13"
echo ""
echo "   3. 📊 SALIDA ESPERADA:"
echo ""
echo "      📊 CLIENTES CONECTADOS"
echo "      ======================"
echo "      🕒 Fecha actual: 10/12/2025 16:10:00"
echo ""
echo "      📍 Cliente 1"
echo "      👤 Nombre: client1"
echo "      🔑 Certificado: client1"
echo "      🌐 IP Real: 83.60.168.35:41799"
echo "      🔗 IP VPN: 10.8.0.2"
echo "      🕒 Conectado desde: 2025-12-10 16:03:08"
echo "      📊 Tráfico: ▼ 17.84KB / ▲ 239.5MB"
echo "      🔐 Cifrado: AES-256-GCM"
echo ""
echo "🚀 EJECUTAR PRUEBA:"
echo "   gestion"
