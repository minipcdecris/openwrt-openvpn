#!/bin/sh

echo ""
echo "🔧 IMPLEMENTANDO BLOQUEO POR IP/FIREWALL EN OPENWRT"
echo "=================================================="

# Verificar que estamos en OpenWRT
if [ -f "/etc/openwrt_release" ] || [ -f "/etc/openwrt_version" ] || [ "$(cat /etc/os-release 2>/dev/null | grep OPENWRT)" ]; then
    echo "✅ Sistema detectado: OpenWRT"
    OPENWRT="yes"
else
    echo "⚠️  No parece ser OpenWRT, continuando igualmente..."
    OPENWRT="no"
fi

# En OpenWRT, iptables suele ser nftables-compat
if [ "$OPENWRT" = "yes" ]; then
    # Verificar si tenemos iptables (en OpenWRT suele ser iptables-nft)
    if ! command -v iptables >/dev/null 2>&1; then
        echo "📦 Instalando iptables en OpenWRT..."
        opkg update
        opkg install iptables-nft iptables-utils
        
        # También necesitamos algunos paquetes básicos
        opkg install coreutils-nohup procps-ng-pkill
    fi
    
    # En OpenWRT, /usr/local/bin no existe por defecto
    mkdir -p /usr/bin /etc/openvpn/clientes
fi

cat > /usr/bin/gestor-vpn << 'GESTOR_SCRIPT'
#!/bin/sh

# Archivos de configuración
NOMBRES_FILE="/etc/openvpn/clientes/nombres.txt"
IP_HISTORY_FILE="/etc/openvpn/clientes/ip_history.txt"
SUSPENDED_FILE="/etc/openvpn/clientes/suspended.txt"

# Asegurar que los archivos existen
mkdir -p /etc/openvpn/clientes/
touch "$NOMBRES_FILE"
touch "$IP_HISTORY_FILE"
touch "$SUSPENDED_FILE"

# Función para obtener nombre descriptivo
obtener_nombre() {
    local cliente=$1
    local nombre=$(grep "^${cliente}:" "$NOMBRES_FILE" 2>/dev/null | cut -d: -f2-)
    echo "${nombre:-$cliente}"
}

# Función para registrar IP de cliente
registrar_ip() {
    local cliente=$1
    local ip=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Solo registrar si es una IP válida
    if [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        # Eliminar entradas antiguas del mismo cliente+IP
        grep -v "^${cliente}:${ip}:" "$IP_HISTORY_FILE" 2>/dev/null > "${IP_HISTORY_FILE}.tmp"
        mv "${IP_HISTORY_FILE}.tmp" "$IP_HISTORY_FILE"
        
        # Añadir nueva entrada
        echo "${cliente}:${ip}:${timestamp}" >> "$IP_HISTORY_FILE"
    fi
}

# Función para obtener todas las IPs de un cliente
obtener_ips_cliente() {
    local cliente=$1
    grep "^${cliente}:" "$IP_HISTORY_FILE" 2>/dev/null | cut -d: -f2 | sort -u
}

# Función para bloquear IP en firewall (compatible con OpenWRT)
bloquear_ip_firewall() {
    local ip=$1
    local cliente=$2
    
    # Verificar si iptables existe
    if ! command -v iptables >/dev/null 2>&1; then
        echo "❌ ERROR: iptables no disponible"
        echo "   En OpenWRT: opkg install iptables-nft"
        return 1
    fi
    
    # Verificar si ya está bloqueada
    if iptables -nL INPUT 2>/dev/null | grep -q "$ip" && iptables -nL INPUT | grep -q "DROP.*$ip"; then
        return 0
    fi
    
    # Bloquear IP en iptables
    if iptables -I INPUT -s "$ip" -j DROP 2>/dev/null; then
        # Guardar regla para persistencia
        mkdir -p /etc/openvpn/
        if ! grep -q "$ip" /etc/openvpn/blocked_ips.txt 2>/dev/null; then
            echo "$ip:$cliente:$(date '+%Y-%m-%d %H:%M:%S')" >> /etc/openvpn/blocked_ips.txt
        fi
        return 0
    else
        # Intentar con ip6tables para IPv6
        if [[ $ip =~ : ]]; then
            ip6tables -I INPUT -s "$ip" -j DROP 2>/dev/null && return 0
        fi
        return 1
    fi
}

# Función para desbloquear IP en firewall
desbloquear_ip_firewall() {
    local ip=$1
    
    # Verificar si iptables existe
    if ! command -v iptables >/dev/null 2>&1; then
        return 1
    fi
    
    # Eliminar regla de iptables (IPv4)
    iptables -D INPUT -s "$ip" -j DROP 2>/dev/null
    
    # También eliminar de IPv6 si es una dirección IPv6
    if [[ $ip =~ : ]]; then
        ip6tables -D INPUT -s "$ip" -j DROP 2>/dev/null 2>&1
    fi
    
    # Eliminar de persistencia
    if [ -f "/etc/openvpn/blocked_ips.txt" ]; then
        grep -v "^$ip:" /etc/openvpn/blocked_ips.txt 2>/dev/null > /tmp/blocked_ips.tmp
        mv /tmp/blocked_ips.tmp /etc/openvpn/blocked_ips.txt 2>/dev/null
    fi
}

# Función para mostrar menú
mostrar_menu() {
    clear
    echo ""
    echo "🔧 GESTOR VPN - OPENWRT (BLOQUEO POR IP)"
    echo "========================================"
    echo ""
    echo "1) 👁️  Ver clientes conectados (registrar IPs)"
    echo "2) 📋 Listar todos los clientes"
    echo "3) 🚫 BLOQUEAR cliente (bloquear IPs)"
    echo "4) ✅ DESBLOQUEAR cliente (desbloquear IPs)"
    echo "5) 🛡️  BLOQUEO PROFUNDO"
    echo "6) 🏷️  GESTIONAR NOMBRES"
    echo "7) 🔍 Estado del sistema"
    echo "8) ⚙️  Configurar OpenWRT"
    echo "9) ❌ Salir"
    echo ""
    echo -n "Selecciona [1-9]: "
}

# Función para ver clientes conectados y registrar IPs
ver_conectados() {
    echo ""
    echo "📊 CLIENTES CONECTADOS:"
    
    # En OpenWRT, el archivo de log puede estar en otro lugar
    STATUS_FILES="/var/log/openvpn-status.log /tmp/openvpn-status.log /var/run/openvpn.status"
    STATUS_FILE=""
    for file in $STATUS_FILES; do
        if [ -f "$file" ] && grep -q "CLIENT_LIST" "$file"; then
            STATUS_FILE="$file"
            break
        fi
    done
    
    if [ -n "$STATUS_FILE" ]; then
        while IFS=$'\t' read -r _ cliente ip_externa ip_interna _ _ _ _; do
            cliente=$(echo "$cliente" | xargs)
            ip_externa=$(echo "$ip_externa" | xargs)
            
            if [ -n "$cliente" ] && [ -n "$ip_externa" ] && [ "$ip_externa" != "UNDEF" ]; then
                nombre_descriptivo=$(obtener_nombre "$cliente")
                
                # Registrar IP automáticamente
                registrar_ip "$cliente" "$ip_externa"
                
                if [ "$cliente" = "$nombre_descriptivo" ]; then
                    echo "   👤 $cliente"
                else
                    echo "   👤 $nombre_descriptivo ($cliente)"
                fi
                echo "      📍 IP Externa: $ip_externa"
                echo "      📍 IP Interna: $ip_interna"
                echo ""
            fi
        done < <(grep "^CLIENT_LIST" "$STATUS_FILE")
    else
        echo "   ℹ️  No hay clientes conectados o no se encuentra el log"
        echo ""
        echo "💡 En OpenWRT, OpenVPN puede no generar el log por defecto."
        echo "   Para habilitarlo, añade a /etc/config/openvpn:"
        echo "   option status '/var/log/openvpn-status.log'"
        echo ""
        echo "💡 Para probar manualmente:"
        echo "   echo 'client1:192.168.1.100:\$(date)' >> $IP_HISTORY_FILE"
    fi
}

# Función para listar clientes
listar_clientes() {
    echo ""
    echo "📋 LISTADO DE CLIENTES"
    echo "======================"
    
    # Buscar archivo index.txt en ubicaciones comunes de OpenWRT
    INDEX_FILE=""
    for dir in "/etc/easy-rsa/pki" "/etc/openvpn/easy-rsa/pki" "/etc/openvpn" "/root/easy-rsa/pki" "/tmp/easy-rsa/pki"; do
        if [ -f "$dir/index.txt" ]; then
            INDEX_FILE="$dir/index.txt"
            echo "   🔍 Usando: $INDEX_FILE"
            break
        fi
    done
    
    if [ -z "$INDEX_FILE" ]; then
        echo "ℹ️  No se encuentra la base de datos de certificados"
        echo ""
        echo "💡 En OpenWRT, los certificados pueden estar en:"
        echo "   • /etc/easy-rsa/pki/"
        echo "   • /etc/openvpn/"
        echo "   • /tmp/easy-rsa/"
        echo ""
        echo "💡 Puedes crear certificados con:"
        echo "   cd /etc/easy-rsa && ./easyrsa build-client-full client1 nopass"
        return
    fi
    
    echo "Clientes en sistema:"
    echo ""
    count=0
    
    # Extraer clientes
    clientes=$(grep -E "^(V|R)" "$INDEX_FILE" 2>/dev/null | awk '{print $NF}' | sort -u)
    
    for cliente in $clientes; do
        if [ -n "$cliente" ] && [ "$cliente" != "unknown" ]; then
            count=$((count + 1))
            nombre_descriptivo=$(obtener_nombre "$cliente")
            
            # Verificar estado
            estado="🟢"
            if grep -q "^R.*$cliente" "$INDEX_FILE"; then
                estado="🔴"
            fi
            
            if [ "$cliente" = "$nombre_descriptivo" ]; then
                echo "   $estado $cliente"
            else
                echo "   $estado $nombre_descriptivo ($cliente)"
            fi
        fi
    done
    
    if [ $count -eq 0 ]; then
        echo "   📭 No hay clientes configurados"
        echo ""
        echo "💡 Para crear un cliente:"
        echo "   cd /etc/easy-rsa"
        echo "   ./easyrsa build-client-full client1 nopass"
    else
        echo ""
        echo "📊 Total: $count clientes"
    fi
}

# Función para BLOQUEAR cliente (optimizada para OpenWRT)
bloquear_cliente() {
    echo ""
    echo "🚫 BLOQUEAR CLIENTE (POR IP)"
    echo "============================"
    
    # Verificar iptables
    if ! command -v iptables >/dev/null 2>&1; then
        echo "❌ ERROR: iptables no está instalado"
        echo ""
        echo "💡 En OpenWRT, instala con:"
        echo "   opkg update"
        echo "   opkg install iptables-nft"
        echo ""
        echo "⚠️  El bloqueo por IP no funcionará sin iptables"
        return
    fi
    
    echo "Clientes disponibles para bloquear:"
    disponibles_encontrados=0
    
    # Listar clientes activos
    for cliente_file in /etc/openvpn/client*.conf /etc/openvpn/ccd/* 2>/dev/null; do
        if [ -f "$cliente_file" ]; then
            cliente=$(basename "$cliente_file" .conf)
            if [ "$cliente" != "*" ]; then
                nombre_descriptivo=$(obtener_nombre "$cliente")
                echo "   $nombre_descriptivo ($cliente)"
                disponibles_encontrados=1
            fi
        fi
    done
    
    if [ $disponibles_encontrados -eq 0 ]; then
        echo "   No hay clientes detectados en /etc/openvpn/"
        echo ""
        echo "💡 Buscando en base de datos de certificados..."
        
        # Buscar en index.txt como alternativa
        INDEX_FILE=""
        for dir in "/etc/easy-rsa/pki" "/etc/openvpn/easy-rsa/pki" "/etc/openvpn"; do
            if [ -f "$dir/index.txt" ]; then
                INDEX_FILE="$dir/index.txt"
                break
            fi
        done
        
        if [ -n "$INDEX_FILE" ]; then
            clientes_activos=$(grep "^V" "$INDEX_FILE" 2>/dev/null | awk '{print $NF}' | sort -u)
            for cliente in $clientes_activos; do
                if [ -n "$cliente" ] && [ "$cliente" != "unknown" ]; then
                    nombre_descriptivo=$(obtener_nombre "$cliente")
                    echo "   $nombre_descriptivo ($cliente)"
                    disponibles_encontrados=1
                fi
            done
        fi
    fi
    
    if [ $disponibles_encontrados -eq 0 ]; then
        echo "   No hay clientes disponibles para bloquear"
        return
    fi
    
    echo ""
    echo -n "Cliente a BLOQUEAR: "
    read INPUT_CLIENTE
    
    # Buscar cliente real
    CLIENTE_REAL=""
    if grep -q ":${INPUT_CLIENTE}$" "$NOMBRES_FILE" 2>/dev/null; then
        CLIENTE_REAL=$(grep ":${INPUT_CLIENTE}$" "$NOMBRES_FILE" | cut -d: -f1)
    else
        CLIENTE_REAL=$INPUT_CLIENTE
    fi
    
    echo ""
    echo "🔍 BUSCANDO IPs HISTÓRICAS DE: $CLIENTE_REAL"
    IPS_CLIENTE=$(obtener_ips_cliente "$CLIENTE_REAL")
    
    if [ -z "$IPS_CLIENTE" ]; then
        echo "   ℹ️  No hay IPs registradas para este cliente"
        echo ""
        echo "💡 Opciones:"
        echo "   1. Usa la opción 1 para ver clientes conectados"
        echo "   2. Añade IPs manualmente:"
        echo "      echo '$CLIENTE_REAL:192.168.1.100:\$(date)' >> $IP_HISTORY_FILE"
        echo "   3. Si el cliente está conectado ahora, usa:"
        echo "      cat /tmp/openvpn-status.log | grep CLIENT_LIST | grep $CLIENTE_REAL"
        return
    fi
    
    echo "   📋 IPs encontradas:"
    contador=0
    for ip in $IPS_CLIENTE; do
        contador=$((contador + 1))
        echo "      $contador) $ip"
    done
    
    echo ""
    echo "⚠️  ¿Qué tipo de bloqueo deseas realizar?"
    echo "   1) Bloqueo NORMAL (solo IPs actuales)"
    echo "   2) Bloqueo COMPLETO (todas las IPs históricas)"
    echo "   3) Cancelar operación"
    echo ""
    echo -n "Selecciona [1-3]: "
    read opcion_bloqueo
    
    case $opcion_bloqueo in
        1)
            echo ""
            echo "🛡️  APLICANDO BLOQUEO NORMAL..."
            
            bloqueadas=0
            for ip in $IPS_CLIENTE; do
                if bloquear_ip_firewall "$ip" "$CLIENTE_REAL"; then
                    echo "   🔒 IP $ip BLOQUEADA"
                    bloqueadas=$((bloqueadas + 1))
                else
                    echo "   ❌ Error bloqueando IP $ip"
                fi
            done
            
            echo "$CLIENTE_REAL:$(date '+%Y-%m-%d %H:%M:%S'):normal" >> "$SUSPENDED_FILE"
            
            echo ""
            echo "✅ CLIENTE BLOQUEADO"
            echo "   👤 Cliente: $CLIENTE_REAL"
            echo "   🛡️  IPs bloqueadas: $bloqueadas"
            ;;
        2)
            echo ""
            echo "🛡️  APLICANDO BLOQUEO COMPLETO..."
            
            TOTAL=0
            BLOQUEADAS=0
            
            for ip in $IPS_CLIENTE; do
                TOTAL=$((TOTAL + 1))
                if bloquear_ip_firewall "$ip" "$CLIENTE_REAL"; then
                    echo "   🔒 IP $ip BLOQUEADA"
                    BLOQUEADAS=$((BLOQUEADAS + 1))
                fi
            done
            
            echo "$CLIENTE_REAL:$(date '+%Y-%m-%d %H:%M:%S'):completo" >> "$SUSPENDED_FILE"
            
            echo ""
            echo "✅ BLOQUEO COMPLETO APLICADO"
            echo "   👤 Cliente: $CLIENTE_REAL"
            echo "   📊 IPs encontradas: $TOTAL"
            echo "   🛡️  IPs bloqueadas: $BLOQUEADAS"
            ;;
        3)
            echo "❌ Operación cancelada"
            return
            ;;
        *)
            echo "❌ Opción inválida"
            return
            ;;
    esac
    
    echo ""
    echo "💡 En OpenWRT, las reglas iptables NO son persistentes por defecto."
    echo "   Para hacerlas persistentes, usa la opción 8 del menú principal."
}

# Función para DESBLOQUEAR cliente
desbloquear_cliente() {
    echo ""
    echo "✅ DESBLOQUEAR CLIENTE"
    echo "======================"
    
    echo "Clientes actualmente BLOQUEADOS:"
    bloqueados_encontrados=0
    
    if [ -f "$SUSPENDED_FILE" ] && [ -s "$SUSPENDED_FILE" ]; then
        while IFS=: read -r cliente fecha tipo; do
            if [ -n "$cliente" ]; then
                nombre_descriptivo=$(obtener_nombre "$cliente")
                echo "   $nombre_descriptivo ($cliente) - $fecha"
                bloqueados_encontrados=1
            fi
        done < "$SUSPENDED_FILE"
    fi
    
    if [ $bloqueados_encontrados -eq 0 ]; then
        echo "   No hay clientes bloqueados"
        return
    fi
    
    echo ""
    echo -n "Cliente a DESBLOQUEAR: "
    read INPUT_CLIENTE
    
    # Buscar cliente real
    CLIENTE_REAL=""
    if grep -q ":${INPUT_CLIENTE}$" "$NOMBRES_FILE" 2>/dev/null; then
        CLIENTE_REAL=$(grep ":${INPUT_CLIENTE}$" "$NOMBRES_FILE" | cut -d: -f1)
    else
        CLIENTE_REAL=$INPUT_CLIENTE
    fi
    
    if ! grep -q "^${CLIENTE_REAL}:" "$SUSPENDED_FILE" 2>/dev/null; then
        echo "❌ Cliente '$INPUT_CLIENTE' no está bloqueado"
        return
    fi
    
    echo ""
    echo "🔓 DESBLOQUEANDO IPs DE: $CLIENTE_REAL"
    IPS_CLIENTE=$(obtener_ips_cliente "$CLIENTE_REAL")
    
    if [ -z "$IPS_CLIENTE" ]; then
        echo "   ℹ️  No hay IPs registradas para desbloquear"
    else
        echo "   📋 IPs a desbloquear:"
        for ip in $IPS_CLIENTE; do
            desbloquear_ip_firewall "$ip"
            echo "   ✅ IP $ip DESBLOQUEADA"
        done
    fi
    
    # Eliminar de lista de bloqueados
    grep -v "^${CLIENTE_REAL}:" "$SUSPENDED_FILE" 2>/dev/null > "${SUSPENDED_FILE}.tmp"
    mv "${SUSPENDED_FILE}.tmp" "$SUSPENDED_FILE"
    
    echo ""
    echo "✅ CLIENTE DESBLOQUEADO"
    echo "   👤 Cliente: $CLIENTE_REAL"
}

# Función para bloqueo profundo
bloqueo_profundo() {
    echo ""
    echo "🛡️  BLOQUEO PROFUNDO"
    echo "==================="
    
    if ! command -v iptables >/dev/null 2>&1; then
        echo "❌ iptables no está instalado"
        return
    fi
    
    echo "Clientes con IPs registradas:"
    clientes_con_ips=$(cut -d: -f1 "$IP_HISTORY_FILE" 2>/dev/null | sort -u)
    
    if [ -z "$clientes_con_ips" ]; then
        echo "   No hay clientes con IPs registradas"
        return
    fi
    
    for cliente in $clientes_con_ips; do
        ips_count=$(grep -c "^${cliente}:" "$IP_HISTORY_FILE" 2>/dev/null)
        nombre_descriptivo=$(obtener_nombre "$cliente")
        echo "   $nombre_descriptivo ($cliente) - $ips_count IPs"
    done
    
    echo ""
    echo -n "Cliente a bloquear PROFUNDAMENTE: "
    read INPUT_CLIENTE
    
    CLIENTE_REAL=""
    if grep -q ":${INPUT_CLIENTE}$" "$NOMBRES_FILE" 2>/dev/null; then
        CLIENTE_REAL=$(grep ":${INPUT_CLIENTE}$" "$NOMBRES_FILE" | cut -d: -f1)
    else
        CLIENTE_REAL=$INPUT_CLIENTE
    fi
    
    IPS_CLIENTE=$(obtener_ips_cliente "$CLIENTE_REAL")
    
    if [ -z "$IPS_CLIENTE" ]; then
        echo "❌ No hay IPs registradas para '$INPUT_CLIENTE'"
        return
    fi
    
    echo ""
    echo -n "¿Estás seguro de bloquear profundamente? (s/N): "
    read confirmacion
    
    if [ "$confirmacion" != "s" ] && [ "$confirmacion" != "S" ]; then
        echo "❌ Operación cancelada"
        return
    fi
    
    echo ""
    echo "🛡️  APLICANDO BLOQUEO PROFUNDO..."
    
    TOTAL=0
    for ip in $IPS_CLIENTE; do
        if bloquear_ip_firewall "$ip" "$CLIENTE_REAL"; then
            echo "   🔒 IP $ip BLOQUEADA"
            TOTAL=$((TOTAL + 1))
        fi
    done
    
    echo "$CLIENTE_REAL:$(date '+%Y-%m-%d %H:%M:%S'):profundo" >> "$SUSPENDED_FILE"
    
    echo ""
    echo "✅ BLOQUEO PROFUNDO APLICADO"
    echo "   👤 Cliente: $CLIENTE_REAL"
    echo "   🛡️  IPs bloqueadas: $TOTAL"
}

# Función para gestión de nombres
gestionar_nombres() {
    while true; do
        echo ""
        echo "🏷️  GESTIÓN DE NOMBRES"
        echo "======================"
        echo ""
        echo "1) 📝 Ver todos los nombres"
        echo "2) ➕ Asignar nuevo nombre"
        echo "3) ✏️  Modificar nombre"
        echo "4) 🗑️  Eliminar nombre"
        echo "5) ↩️  Volver al menú principal"
        echo ""
        echo -n "Selecciona [1-5]: "
        read opcion_nombre
        
        case $opcion_nombre in
            1)
                echo ""
                if [ -s "$NOMBRES_FILE" ]; then
                    echo "Nombres asignados:"
                    echo ""
                    cat "$NOMBRES_FILE" | while IFS=: read -r cliente nombre; do
                        echo "   $nombre ($cliente)"
                    done
                else
                    echo "📭 No hay nombres asignados"
                fi
                ;;
            
            2)
                echo ""
                echo -n "Certificado del cliente: "
                read cliente
                echo -n "Nombre descriptivo: "
                read nombre
                
                if [ -n "$cliente" ] && [ -n "$nombre" ]; then
                    # Eliminar si ya existe
                    grep -v "^${cliente}:" "$NOMBRES_FILE" 2>/dev/null > "${NOMBRES_FILE}.tmp"
                    echo "${cliente}:${nombre}" >> "${NOMBRES_FILE}.tmp"
                    mv "${NOMBRES_FILE}.tmp" "$NOMBRES_FILE"
                    echo "✅ Nombre asignado: $nombre ($cliente)"
                else
                    echo "❌ Error: datos incompletos"
                fi
                ;;
            
            3)
                echo ""
                if [ ! -s "$NOMBRES_FILE" ]; then
                    echo "📭 No hay nombres para modificar"
                    continue
                fi
                
                echo "Selecciona nombre a modificar:"
                echo ""
                count=1
                while IFS=: read -r cliente nombre; do
                    echo "   $count) $nombre ($cliente)"
                    count=$((count + 1))
                done < "$NOMBRES_FILE"
                
                echo ""
                echo -n "Número: "
                read numero
                
                linea=$(sed -n "${numero}p" "$NOMBRES_FILE" 2>/dev/null)
                if [ -z "$linea" ]; then
                    echo "❌ Número inválido"
                    continue
                fi
                
                cliente=$(echo "$linea" | cut -d: -f1)
                nombre_actual=$(echo "$linea" | cut -d: -f2)
                
                echo ""
                echo "Modificando: $nombre_actual ($cliente)"
                echo -n "Nuevo nombre: "
                read nuevo_nombre
                
                if [ -n "$nuevo_nombre" ]; then
                    grep -v "^${cliente}:" "$NOMBRES_FILE" > "${NOMBRES_FILE}.tmp"
                    echo "${cliente}:${nuevo_nombre}" >> "${NOMBRES_FILE}.tmp"
                    mv "${NOMBRES_FILE}.tmp" "$NOMBRES_FILE"
                    echo "✅ Nombre modificado"
                fi
                ;;
            
            4)
                echo ""
                if [ ! -s "$NOMBRES_FILE" ]; then
                    echo "📭 No hay nombres para eliminar"
                    continue
                fi
                
                echo "Selecciona nombre a eliminar:"
                echo ""
                count=1
                while IFS=: read -r cliente nombre; do
                    echo "   $count) $nombre ($cliente)"
                    count=$((count + 1))
                done < "$NOMBRES_FILE"
                
                echo ""
                echo -n "Número: "
                read numero
                
                linea=$(sed -n "${numero}p" "$NOMBRES_FILE" 2>/dev/null)
                if [ -z "$linea" ]; then
                    echo "❌ Número inválido"
                    continue
                fi
                
                cliente=$(echo "$linea" | cut -d: -f1)
                nombre=$(echo "$linea" | cut -d: -f2)
                
                echo ""
                echo -n "¿Eliminar '$nombre' de '$cliente'? (s/N): "
                read confirmar
                
                if [ "$confirmar" = "s" ] || [ "$confirmar" = "S" ]; then
                    grep -v "^${cliente}:" "$NOMBRES_FILE" > "${NOMBRES_FILE}.tmp"
                    mv "${NOMBRES_FILE}.tmp" "$NOMBRES_FILE"
                    echo "✅ Nombre eliminado"
                fi
                ;;
            
            5)
                return
                ;;
            
            *)
                echo "❌ Opción inválida"
                ;;
        esac
        
        echo ""
        read -p "Presiona Enter para continuar..."
    done
}

# Función para estado del sistema (específica de OpenWRT)
estado_servicio() {
    echo ""
    echo "🔍 ESTADO DEL SISTEMA OPENWRT"
    echo "=============================="
    
    # Estado OpenVPN
    if pgrep openvpn >/dev/null; then
        echo "✅ OpenVPN: ACTIVO"
        # Mostrar interfaz tun
        ifconfig tun0 2>/dev/null | grep "inet addr" || echo "   ℹ️  Interfaz tun0 no configurada"
    else
        echo "❌ OpenVPN: INACTIVO"
    fi
    
    # Estado firewall
    echo ""
    echo "🛡️  ESTADO DEL FIREWALL:"
    if command -v iptables >/dev/null 2>&1; then
        # Reglas de bloqueo
        echo "   Reglas INPUT de bloqueo:"
        iptables -nL INPUT 2>/dev/null | grep DROP | head -5 | while read line; do
            echo "   🔒 $line"
        done
        
        # Contar reglas
        total_drop=$(iptables -nL INPUT 2>/dev/null | grep -c DROP)
        echo "   📊 Total reglas DROP: $total_drop"
    else
        echo "   ⚠️  iptables no instalado"
    fi
    
    # Uso de memoria
    echo ""
    echo "💾 USO DE MEMORIA:"
    free -h 2>/dev/null | grep Mem | awk '{print "   Memoria: "$3"/"$2" ("$4" libre)"}' || echo "   ℹ️  No se pudo obtener info de memoria"
    
    # Espacio en disco
    echo ""
    echo "💿 ESPACIO EN DISCO:"
    df -h / | tail -1 | awk '{print "   Root: "$3"/"$2" ("$5" usado)"}'
    
    # Estadísticas nuestro sistema
    echo ""
    echo "📊 ESTADÍSTICAS GESTOR VPN:"
    echo "   👥 Clientes con nombres: $(grep -c ":" "$NOMBRES_FILE" 2>/dev/null || echo 0)"
    echo "   📍 IPs registradas: $(wc -l < "$IP_HISTORY_FILE" 2>/dev/null || echo 0)"
    echo "   🚫 Clientes bloqueados: $(wc -l < "$SUSPENDED_FILE" 2>/dev/null || echo 0)"
}

# Función específica para configurar OpenWRT
configurar_openwrt() {
    echo ""
    echo "⚙️  CONFIGURACIÓN OPENWRT"
    echo "========================"
    echo ""
    echo "1) 🔧 Instalar iptables (si no está)"
    echo "2) 📝 Configurar log de OpenVPN"
    echo "3) 💾 Hacer reglas iptables persistentes"
    echo "4) 🔄 Reiniciar servicios"
    echo "5) ↩️  Volver al menú principal"
    echo ""
    echo -n "Selecciona [1-5]: "
    read opcion_config
    
    case $opcion_config in
        1)
            echo ""
            echo "📦 INSTALANDO IPTABLES..."
            opkg update
            opkg install iptables-nft iptables-utils
            echo "✅ iptables instalado"
            ;;
        
        2)
            echo ""
            echo "📝 CONFIGURANDO LOG DE OPENVPN..."
            echo ""
            echo "Para habilitar el log de estado de OpenVPN en OpenWRT:"
            echo ""
            echo "1. Edita /etc/config/openvpn"
            echo "2. Añade esta línea en cada sección de servidor:"
            echo "   option status '/var/log/openvpn-status.log'"
            echo "3. Reinicia OpenVPN:"
            echo "   /etc/init.d/openvpn restart"
            echo ""
            echo "💡 Alternativa temporal (solo esta sesión):"
            echo "   killall openvpn"
            echo "   openvpn --config /etc/openvpn/server.conf --status /var/log/openvpn-status.log 10"
            ;;
        
        3)
            echo ""
            echo "💾 HACIENDO REGLAS PERSISTENTES..."
            echo ""
            
            # Crear script de inicio
            cat > /etc/init.d/firewall-custom << 'FIREWALL_SCRIPT'
#!/bin/sh /etc/rc.common

START=99
STOP=10

start() {
    echo "Cargando reglas bloqueadas de OpenVPN..."
    if [ -f "/etc/openvpn/blocked_ips.txt" ]; then
        while IFS=: read -r ip cliente fecha; do
            iptables -I INPUT -s "$ip" -j DROP
        done < /etc/openvpn/blocked_ips.txt
        echo "Reglas cargadas"
    fi
}

stop() {
    echo "Eliminando reglas custom..."
    # No hacemos nada al parar
}
FIREWALL_SCRIPT
            
            chmod +x /etc/init.d/firewall-custom
            /etc/init.d/firewall-custom enable
            
            echo "✅ Script de persistencia creado"
            echo "   Las reglas se cargarán al reiniciar"
            ;;
        
        4)
            echo ""
            echo "🔄 REINICIANDO SERVICIOS..."
            /etc/init.d/openvpn restart
            /etc/init.d/network restart
            echo "✅ Servicios reiniciados"
            ;;
        
        5)
            return
            ;;
        
        *)
            echo "❌ Opción inválida"
            ;;
    esac
}

# Menú principal
while true; do
    mostrar_menu
    read OPCION
    
    case $OPCION in
        1) ver_conectados ;;
        2) listar_clientes ;;
        3) bloquear_cliente ;;
        4) desbloquear_cliente ;;
        5) bloqueo_profundo ;;
        6) gestionar_nombres ;;
        7) estado_servicio ;;
        8) configurar_openwrt ;;
        9)
            echo ""
            echo "👋 Saliendo..."
            exit 0
            ;;
        *)
            echo "❌ Opción inválida"
            ;;
    esac
    
    echo ""
    read -p "Presiona Enter para continuar..."
done
GESTOR_SCRIPT

# Hacer el script ejecutable
chmod +x /usr/bin/gestor-vpn

echo ""
echo "✅ INSTALACIÓN COMPLETADA PARA OPENWRT"
echo ""
echo "🔧 CARACTERÍSTICAS ESPECÍFICAS OPENWRT:"
echo "   • Compatibilidad con iptables-nft"
echo "   • Configuración automática de persistencia"
echo "   • Menú de configuración OpenWRT (opción 8)"
echo "   • Detección de rutas OpenWRT"
echo ""
echo "🚀 PARA EJECUTAR:"
echo "   gestor-vpn"
echo ""
echo "📋 PASOS INICIALES EN OPENWRT:"
echo "   1. Si no tienes iptables: opción 8 → opción 1"
echo "   2. Para habilitar logs OpenVPN: opción 8 → opción 2"
echo "   3. Para persistencia: opción 8 → opción 3"
echo ""
echo "💡 PRIMERA PRUEBA:"
echo "   gestor-vpn"
echo "   → Opción 6 (asignar nombres)"
echo "   → Opción 1 (ver conectados - puede estar vacío al inicio)"
echo "   → Opción 2 (listar clientes)"
echo ""
echo "⚠️  NOTA: En OpenWRT, el archivo de estado de OpenVPN"
echo "   (/var/log/openvpn-status.log) puede no existir por defecto."
echo "   Usa la opción 8 del menú para configurarlo."
