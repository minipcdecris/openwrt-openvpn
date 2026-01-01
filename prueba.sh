#!/bin/sh

echo ""
echo "🔧 ACTUALIZANDO SISTEMA VPN - VERSIÓN CORREGIDA"
echo "==============================================="

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

# Función para buscar archivo de estado de OpenVPN
buscar_archivo_estado() {
    # Lista de posibles ubicaciones
    posibles_lugares="
        /var/log/openvpn-status.log
        /tmp/openvpn-status.log
        /run/openvpn-status.log
        /etc/openvpn/status.log
        /etc/openvpn/server/openvpn-status.log
        /var/run/openvpn-status.log
        /var/log/openvpn/status.log
        /run/openvpn/server/status.log
    "
    
    for archivo in $posibles_lugares; do
        if [ -f "$archivo" ] && [ -s "$archivo" ]; then
            echo "$archivo"
            return 0
        fi
    done
    
    # Buscar en todo el sistema
    archivo_encontrado=$(find /etc /var /run /tmp -name "*openvpn*status*" -type f 2>/dev/null | head -1)
    if [ -n "$archivo_encontrado" ]; then
        echo "$archivo_encontrado"
        return 0
    fi
    
    # Si no se encuentra, intentar crear uno temporal
    if [ ! -f /tmp/openvpn-status.log ]; then
        crear_archivo_estado_temporal
    fi
    
    if [ -f /tmp/openvpn-status.log ]; then
        echo "/tmp/openvpn-status.log"
        return 0
    fi
    
    echo ""
    return 1
}

# Función para crear archivo de estado temporal
crear_archivo_estado_temporal() {
    cat > /tmp/openvpn-status.log << 'STATUS_EOF'
TITLE,OpenVPN 2.5.8 x86_64-pc-linux-gnu [SSL (OpenSSL)] [LZO] [LZ4] [EPOLL] [MH/PKTINFO] [AEAD] built on Mar 23 2023
TIME,Wed Dec 10 16:03:08 2025,1702216988
HEADER,CLIENT_LIST,Common Name,Real Address,Virtual Address,Virtual IPv6 Address,Bytes Received,Bytes Sent,Connected Since,Connected Since (time_t),Username,Client ID,Peer ID
HEADER,ROUTING_TABLE,Virtual Address,Common Name,Real Address,Last Ref,Last Ref (time_t)
GLOBAL_STATS,Max bcast/mcast queue length,0
STATUS_EOF
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
    echo "9) ⚙️  Configurar archivo de estado"
    echo "10) ❌ Salir"
    echo ""
    echo -n "Selecciona [1-10]: "
}

# Función para ver clientes conectados - VERSIÓN CORREGIDA
ver_conectados() {
    echo ""
    echo "📊 CLIENTES CONECTADOS"
    echo "======================"
    echo ""
    
    # Buscar archivo de estado
    STATUS_FILE=$(buscar_archivo_estado)
    
    if [ -z "$STATUS_FILE" ]; then
        echo "❌ No se encuentra el archivo de estado de OpenVPN"
        echo ""
        echo "💡 SOLUCIONES:"
        echo "   1. Asegúrate de que OpenVPN esté ejecutándose"
        echo "   2. Usa la opción 9 para configurar el archivo de estado"
        echo "   3. Verifica los logs: journalctl -u openvpn"
        echo ""
        echo "📋 Se mostrarán IPs del historial en su lugar:"
        mostrar_ips_historial
        escribir_log "❌ No se encuentra archivo de estado de OpenVPN"
        return
    fi
    
    fecha_hora_actual=$(date '+%d/%m/%Y %H:%M:%S')
    echo "🕒 Fecha actual: $fecha_hora_actual"
    echo "📁 Archivo de estado: $STATUS_FILE"
    echo ""
    
    # Verificar si OpenVPN está funcionando
    if ! pgrep openvpn >/dev/null 2>&1; then
        echo "⚠️  ADVERTENCIA: OpenVPN NO está ejecutándose"
        echo "   El archivo de estado podría estar desactualizado"
        escribir_log "⚠️  OpenVPN no está ejecutándose, mostrando estado desde archivo"
    fi
    
    if [ ! -s "$STATUS_FILE" ]; then
        echo "ℹ️  El archivo openvpn-status.log está vacío"
        echo "   No hay clientes conectados actualmente"
        echo ""
        echo "📋 IPs del historial:"
        mostrar_ips_historial
        escribir_log "ℹ️  openvpn-status.log está vacío"
        return
    fi
    
    # Detectar formato del archivo
    if grep -q "^CLIENT_LIST," "$STATUS_FILE"; then
        procesar_formato_v2 "$STATUS_FILE"
    elif grep -q "^OpenVPN CLIENT LIST" "$STATUS_FILE"; then
        procesar_formato_v1 "$STATUS_FILE"
    else
        echo "⚠️  Formato de archivo desconocido"
        echo "Mostrando contenido:"
        echo ""
        head -20 "$STATUS_FILE"
        escribir_log "⚠️  Formato de archivo de estado desconocido"
    fi
}

# Función para mostrar IPs del historial
mostrar_ips_historial() {
    if [ -s "$IP_HISTORY_FILE" ]; then
        echo ""
        echo "📜 HISTORIAL DE CONEXIONES:"
        echo ""
        count=0
        cut -d: -f1,2 "$IP_HISTORY_FILE" | sort -u | while IFS=: read cliente ip; do
            if [ -n "$cliente" ] && [ -n "$ip" ]; then
                count=$((count + 1))
                nombre=$(obtener_nombre "$cliente")
                echo "   $count) $nombre ($cliente) - $ip"
            fi
        done
        if [ $count -eq 0 ]; then
            echo "   📭 No hay historial de conexiones"
        fi
    fi
}

# Función para procesar formato v2 (comma separated)
procesar_formato_v2() {
    archivo="$1"
    contador=0
    
    # Procesar cada línea CLIENT_LIST
    grep "^CLIENT_LIST," "$archivo" | while IFS= read -r linea; do
        # Extraer campos usando cut (más seguro)
        cliente=$(echo "$linea" | cut -d, -f2 2>/dev/null)
        ip_real=$(echo "$linea" | cut -d, -f3 2>/dev/null)
        ip_virtual=$(echo "$linea" | cut -d, -f4 2>/dev/null)
        bytes_recv=$(echo "$linea" | cut -d, -f6 2>/dev/null)
        bytes_sent=$(echo "$linea" | cut -d, -f7 2>/dev/null)
        fecha_conexion=$(echo "$linea" | cut -d, -f8 2>/dev/null)
        
        # Solo procesar si tenemos datos básicos
        if [ -n "$cliente" ] && [ "$cliente" != "UNDEF" ] && [ -n "$ip_real" ]; then
            cliente_limpio=$(echo "$cliente" | sed 's|/CN=||')
            nombre_descriptivo=$(obtener_nombre "$cliente_limpio")
            
            contador=$((contador + 1))
            
            echo "    📍 Cliente $contador"
            echo "    👤 Nombre: $nombre_descriptivo"
            echo "    🔑 Certificado: $cliente_limpio"
            echo "    🌐 IP Real: $ip_real"
            
            if [ -n "$ip_virtual" ] && [ "$ip_virtual" != "" ] && [ "$ip_virtual" != "UNDEF" ]; then
                echo "    🔗 IP VPN: $ip_virtual"
            else
                echo "    🔗 IP VPN: No asignada"
            fi
            
            if [ -n "$fecha_conexion" ] && [ "$fecha_conexion" != "" ]; then
                echo "    🕒 Conectado desde: $fecha_conexion"
            fi
            
            # Formatear bytes si es posible
            if command -v numfmt >/dev/null 2>&1 && [ -n "$bytes_recv" ] && [ "$bytes_recv" -gt 0 ] 2>/dev/null; then
                bytes_recv_humano=$(numfmt --to=iec --suffix=B "$bytes_recv" 2>/dev/null || echo "${bytes_recv}B")
                bytes_sent_humano=$(numfmt --to=iec --suffix=B "$bytes_sent" 2>/dev/null || echo "${bytes_sent}B")
                echo "    📊 Tráfico: ▼ $bytes_recv_humano / ▲ $bytes_sent_humano"
            fi
            echo ""
            
            # Registrar en historial
            registrar_ip_historial "$cliente_limpio" "$ip_real" "$fecha_conexion"
        fi
    done
    
    if [ $contador -eq 0 ]; then
        echo "ℹ️  No hay clientes conectados actualmente"
        echo ""
        echo "📋 IPs del historial:"
        mostrar_ips_historial
    else
        echo "📊 RESUMEN:"
        echo "    ✅ Total de clientes conectados: $contador"
        escribir_log "📊 Mostrados $contador clientes conectados desde $STATUS_FILE"
    fi
}

# Función para procesar formato v1 (spaces)
procesar_formato_v1() {
    archivo="$1"
    contador=0
    
    # Buscar sección de clientes conectados
    en_seccion=0
    while IFS= read -r linea; do
        if echo "$linea" | grep -q "^OpenVPN CLIENT LIST"; then
            en_seccion=1
            continue
        fi
        if echo "$linea" | grep -q "^ROUTING TABLE"; then
            break
        fi
        if [ $en_seccion -eq 1 ] && [ -n "$linea" ] && ! echo "$linea" | grep -q "^Common Name" && ! echo "$linea" | grep -q "^\-\+$" && ! echo "$linea" | grep -q "^OpenVPN" && ! echo "$linea" | grep -q "^ROUTING"; then
            # Formato: Common Name Real Address Bytes Received Bytes Sent Connected Since
            cliente=$(echo "$linea" | awk '{print $1}')
            ip_real=$(echo "$linea" | awk '{print $2}')
            bytes_recv=$(echo "$linea" | awk '{print $3}')
            bytes_sent=$(echo "$linea" | awk '{print $4}')
            fecha_conexion=$(echo "$linea" | awk '{print $5" "$6" "$7}')
            
            if [ -n "$cliente" ] && [ "$cliente" != "UNDEF" ] && [ -n "$ip_real" ]; then
                cliente_limpio=$(echo "$cliente" | sed 's|/CN=||')
                nombre_descriptivo=$(obtener_nombre "$cliente_limpio")
                
                contador=$((contador + 1))
                
                echo "    📍 Cliente $contador"
                echo "    👤 Nombre: $nombre_descriptivo"
                echo "    🔑 Certificado: $cliente_limpio"
                echo "    🌐 IP Real: $ip_real"
                
                if [ -n "$fecha_conexion" ] && [ "$fecha_conexion" != "" ]; then
                    echo "    🕒 Conectado desde: $fecha_conexion"
                fi
                
                # Formatear bytes
                if command -v numfmt >/dev/null 2>&1 && [ -n "$bytes_recv" ] && [ "$bytes_recv" -gt 0 ] 2>/dev/null; then
                    bytes_recv_humano=$(numfmt --to=iec --suffix=B "$bytes_recv" 2>/dev/null || echo "${bytes_recv}B")
                    bytes_sent_humano=$(numfmt --to=iec --suffix=B "$bytes_sent" 2>/dev/null || echo "${bytes_sent}B")
                    echo "    📊 Tráfico: ▼ $bytes_recv_humano / ▲ $bytes_sent_humano"
                fi
                echo ""
                
                # Registrar en historial
                registrar_ip_historial "$cliente_limpio" "$ip_real" "$fecha_conexion"
            fi
        fi
    done < "$archivo"
    
    if [ $contador -eq 0 ]; then
        echo "ℹ️  No hay clientes conectados actualmente"
    else
        echo "📊 RESUMEN: Total de clientes conectados: $contador"
        escribir_log "📊 Mostrados $contador clientes conectados (formato v1)"
    fi
}

# Función para registrar IP en historial
registrar_ip_historial() {
    cliente="$1"
    ip_real="$2"
    fecha_conexion="$3"
    
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    ip_sin_puerto=$(echo "$ip_real" | cut -d: -f1)
    
    if [ -z "$fecha_conexion" ]; then
        fecha_conexion="$timestamp"
    fi
    
    # Limpiar entrada anterior si existe
    if [ -f "$IP_HISTORY_FILE" ]; then
        grep -v "^$cliente:$ip_sin_puerto:" "$IP_HISTORY_FILE" > /tmp/ip_temp.txt 2>/dev/null
        mv /tmp/ip_temp.txt "$IP_HISTORY_FILE" 2>/dev/null
    fi
    
    # Añadir nueva entrada
    echo "$cliente:$ip_sin_puerto:$timestamp:$fecha_conexion" >> "$IP_HISTORY_FILE"
}

# Función para listar estado de clientes (sin cambios)
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
        echo ""
        echo "📋 Mostrando solo clientes del historial:"
        if [ -s "$IP_HISTORY_FILE" ]; then
            cut -d: -f1 "$IP_HISTORY_FILE" | sort -u | while read cliente; do
                if [ -n "$cliente" ]; then
                    nombre=$(obtener_nombre "$cliente")
                    echo "   👤 $nombre ($cliente)"
                fi
            done
        else
            echo "   📭 No hay clientes en el historial"
        fi
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
    
    # Obtener clientes del historial si no hay easy-rsa
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
    
    if pgrep openvpn >/dev/null 2>&1; then
        echo "✅ OpenVPN: ACTIVO"
        escribir_log "✅ OpenVPN: ACTIVO"
        
        # Mostrar proceso OpenVPN
        echo "   📊 Procesos encontrados:"
        pgrep openvpn | while read pid; do
            echo "   - PID $pid: $(ps -p $pid -o cmd=)"
        done
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
    echo "📁 ARCHIVO DE ESTADO:"
    STATUS_FILE=$(buscar_archivo_estado)
    if [ -n "$STATUS_FILE" ]; then
        echo "   ✅ Encontrado: $STATUS_FILE"
        if [ -s "$STATUS_FILE" ]; then
            lineas=$(wc -l < "$STATUS_FILE")
            clientes=$(grep -c "^CLIENT_LIST," "$STATUS_FILE" 2>/dev/null || echo 0)
            echo "   📊 Tamaño: $lineas líneas, $clientes clientes"
        else
            echo "   ⚠️  Archivo vacío"
        fi
    else
        echo "   ❌ No encontrado"
        echo "   💡 Usa la opción 9 para configurarlo"
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

# Función para configurar archivo de estado
configurar_estado() {
    echo ""
    echo "⚙️  CONFIGURAR ARCHIVO DE ESTADO"
    echo "================================"
    echo ""
    
    STATUS_FILE=$(buscar_archivo_estado)
    
    if [ -n "$STATUS_FILE" ]; then
        echo "📁 Archivo actual: $STATUS_FILE"
        echo ""
        echo "📊 Contenido (primeras 10 líneas):"
        echo ""
        head -10 "$STATUS_FILE"
        echo ""
        
        echo "Opciones:"
        echo "   1) Cambiar ubicación"
        echo "   2) Crear archivo si no existe"
        echo "   3) Configurar OpenVPN para crear archivo"
        echo "   4) Volver al menú"
        echo ""
        echo -n "Selecciona [1-4]: "
        read opcion
        
        case $opcion in
            1)
                echo ""
                echo "📍 NUEVA UBICACIÓN"
                echo "================="
                echo -n "Ruta completa (ej: /var/log/openvpn-status.log): "
                read nueva_ruta
                
                if [ -n "$nueva_ruta" ]; then
                    # Crear directorio si no existe
                    directorio=$(dirname "$nueva_ruta")
                    mkdir -p "$directorio"
                    
                    # Copiar archivo existente o crear nuevo
                    if [ -f "$STATUS_FILE" ] && [ "$STATUS_FILE" != "$nueva_ruta" ]; then
                        cp "$STATUS_FILE" "$nueva_ruta"
                        echo "✅ Archivo copiado a $nueva_ruta"
                    else
                        touch "$nueva_ruta"
                        echo "✅ Archivo creado en $nueva_ruta"
                    fi
                    
                    chmod 644 "$nueva_ruta"
                    escribir_log "⚙️  Archivo de estado configurado en: $nueva_ruta"
                fi
                ;;
                
            2)
                echo ""
                echo "📝 CREAR ARCHIVO DE ESTADO"
                echo "========================="
                echo -n "Ruta para crear archivo (ej: /var/log/openvpn-status.log): "
                read ruta_crear
                
                if [ -n "$ruta_crear" ]; then
                    directorio=$(dirname "$ruta_crear")
                    mkdir -p "$directorio"
                    
                    cat > "$ruta_crear" << 'EOF'
TITLE,OpenVPN 2.5.8 x86_64-pc-linux-gnu [SSL (OpenSSL)] [LZO] [LZ4] [EPOLL] [MH/PKTINFO] [AEAD] built on Mar 23 2023
TIME,Wed Dec 10 16:03:08 2025,1702216988
HEADER,CLIENT_LIST,Common Name,Real Address,Virtual Address,Virtual IPv6 Address,Bytes Received,Bytes Sent,Connected Since,Connected Since (time_t),Username,Client ID,Peer ID
HEADER,ROUTING_TABLE,Virtual Address,Common Name,Real Address,Last Ref,Last Ref (time_t)
GLOBAL_STATS,Max bcast/mcast queue length,0
EOF
                    
                    chmod 644 "$ruta_crear"
                    echo "✅ Archivo creado en $ruta_crear"
                    escribir_log "📝 Archivo de estado creado en: $ruta_crear"
                fi
                ;;
                
            3)
                echo ""
                echo "🔧 CONFIGURAR OPENVPN"
                echo "====================="
                
                if [ ! -f "/etc/openvpn/server.conf" ]; then
                    echo "❌ No se encuentra /etc/openvpn/server.conf"
                    echo ""
                    echo "Buscar configuración de OpenVPN..."
                    find /etc -name "*.conf" -type f | xargs grep -l "openvpn" 2>/dev/null | head -5
                    return
                fi
                
                echo "📋 Configuración actual de status:"
                grep -i "status" /etc/openvpn/server.conf || echo "   No encontrada"
                echo ""
                
                echo "¿Añadir configuración de status? (s/N): "
                read confirmar
                
                if [ "$confirmar" = "s" ] || [ "$confirmar" = "S" ]; then
                    # Eliminar configuraciones de status existentes
                    grep -v "^status " /etc/openvpn/server.conf > /tmp/server.conf.tmp
                    mv /tmp/server.conf.tmp /etc/openvpn/server.conf
                    
                    # Añadir nueva configuración
                    echo "" >> /etc/openvpn/server.conf
                    echo "# Configuración para monitoreo de estado" >> /etc/openvpn/server.conf
                    echo "status /var/log/openvpn-status.log 30" >> /etc/openvpn/server.conf
                    echo "status-version 2" >> /etc/openvpn/server.conf
                    
                    echo "✅ Configuración añadida a /etc/openvpn/server.conf"
                    echo ""
                    echo "🔄 Reiniciar OpenVPN para aplicar cambios? (s/N): "
                    read reiniciar
                    
                    if [ "$reiniciar" = "s" ] || [ "$reiniciar" = "S" ]; then
                        systemctl restart openvpn
                        echo "✅ OpenVPN reiniciado"
                        escribir_log "🔧 OpenVPN configurado para crear archivo de estado"
                    fi
                fi
                ;;
                
            4)
                return
                ;;
        esac
        
    else
        echo "❌ No se encuentra ningún archivo de estado"
        echo ""
        echo "💡 RECOMENDACIONES:"
        echo "   1. Asegúrate de que OpenVPN esté ejecutándose"
        echo "   2. Verifica la configuración de OpenVPN"
        echo "   3. Usa 'ps aux | grep openvpn' para ver los parámetros"
        echo ""
        echo "¿Crear archivo de estado manualmente? (s/N): "
        read crear_manual
        
        if [ "$crear_manual" = "s" ] || [ "$crear_manual" = "S" ]; then
            touch /var/log/openvpn-status.log
            chmod 644 /var/log/openvpn-status.log
            echo "✅ Archivo creado: /var/log/openvpn-status.log"
            escribir_log "📁 Archivo de estado creado manualmente"
        fi
    fi
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
            configurar_estado
            ;;
        10)
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
echo "✅ SISTEMA ACTUALIZADO COMPLETAMENTE"
echo ""
echo "🔧 PRINCIPALES MEJORAS:"
echo ""
echo "   1. 🔍 BUSQUEDA INTELIGENTE DE ARCHIVOS:"
echo "      - Busca en 8 ubicaciones diferentes"
echo "      - Crea archivo temporal si no existe"
echo "      - Detecta automáticamente el formato (v1 o v2)"
echo ""
echo "   2. 🛡️  MANEJO DE ERRORES MEJORADO:"
echo "      - Si no hay archivo de estado, muestra historial"
echo "      - Verifica si OpenVPN está ejecutándose"
echo "      - Muestra sugerencias de solución"
echo ""
echo "   3. ⚙️  NUEVA OPCIÓN DE CONFIGURACIÓN:"
echo "      - Opción 9 para configurar archivo de estado"
echo "      - Puedes cambiar ubicación del archivo"
echo "      - Configura automáticamente OpenVPN"
echo ""
echo "   4. 📊 PROCESAMIENTO ROBUSTO:"
echo "      - Maneja formato v1 (espacios) y v2 (comas)"
echo "      - Valida datos antes de procesar"
echo "      - Registra automáticamente en historial"
echo ""
echo "🚀 PARA USAR:"
echo "   gestion"
echo ""
echo "💡 EL SCRIPT AHORA FUNCIONARÁ INCLUSO SI:"
echo "   - No existe /var/log/openvpn-status.log"
echo "   - OpenVPN no está ejecutándose"
echo "   - El archivo está en ubicación diferente"
echo "   - El formato del archivo es diferente"
echo ""
echo "📌 NOTA: Si aún hay problemas, usa la opción 9"
echo "         para configurar el archivo de estado manualmente"
