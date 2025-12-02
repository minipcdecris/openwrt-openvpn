#!/bin/sh

echo ""
echo "🔧 IMPLEMENTANDO BLOQUEO POR IP/FIREWALL"
echo "========================================"

# Primero verificamos el sistema
if command -v update-rc.d >/dev/null 2>&1; then
    INIT_SYSTEM="sysv"
elif command -v systemctl >/dev/null 2>&1; then
    INIT_SYSTEM="systemd"
elif command -v rc-update >/dev/null 2>&1; then
    INIT_SYSTEM="openrc"
else
    INIT_SYSTEM="unknown"
fi

echo "📋 Sistema detectado: $INIT_SYSTEM"

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

# Función para bloquear IP en firewall
bloquear_ip_firewall() {
    local ip=$1
    local cliente=$2
    
    # Verificar si ya está bloqueada
    if iptables -nL INPUT 2>/dev/null | grep -q "$ip" && iptables -nL INPUT | grep -q "DROP.*$ip"; then
        return 0
    fi
    
    # Bloquear IP en iptables
    if iptables -I INPUT -s "$ip" -j DROP 2>/dev/null; then
        # Guardar regla para persistencia
        if ! grep -q "$ip" /etc/openvpn/blocked_ips.txt 2>/dev/null; then
            mkdir -p /etc/openvpn/
            echo "$ip:$cliente:$(date '+%Y-%m-%d %H:%M:%S')" >> /etc/openvpn/blocked_ips.txt
        fi
        return 0
    else
        return 1
    fi
}

# Función para desbloquear IP en firewall
desbloquear_ip_firewall() {
    local ip=$1
    
    # Eliminar regla de iptables
    iptables -D INPUT -s "$ip" -j DROP 2>/dev/null
    
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
    echo "🔧 GESTOR VPN - BLOQUEO POR IP/FIREWALL"
    echo "========================================"
    echo ""
    echo "1) 👁️  Ver clientes conectados (registrar IPs)"
    echo "2) 📋 Listar todos los clientes"
    echo "3) 🚫 BLOQUEAR cliente (bloquear IPs)"
    echo "4) ✅ DESBLOQUEAR cliente (desbloquear IPs)"
    echo "5) 🛡️  BLOQUEO PROFUNDO (todas las IPs históricas)"
    echo "6) 🏷️  GESTIONAR NOMBRES"
    echo "7) 🔍 Estado del servicio y bloqueos"
    echo "8) ❌ Salir"
    echo ""
    echo -n "Selecciona [1-8]: "
}

# Función para ver clientes conectados y registrar IPs
ver_conectados() {
    echo ""
    echo "📊 CLIENTES CONECTADOS:"
    
    if [ -f "/var/log/openvpn-status.log" ] && grep -q "CLIENT_LIST" "/var/log/openvpn-status.log"; then
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
        done < <(grep "^CLIENT_LIST" "/var/log/openvpn-status.log")
    else
        echo "   ℹ️  No hay clientes conectados"
        echo ""
        echo "💡 Puedes probar el sistema:"
        echo "   1. Conecta un cliente VPN"
        echo "   2. O añade una IP manualmente:"
        echo "      echo 'client1:192.168.1.100:\$(date)' >> $IP_HISTORY_FILE"
    fi
}

# Función para listar clientes
listar_clientes() {
    echo ""
    echo "📋 LISTADO DE CLIENTES"
    echo "======================"
    
    INDEX_FILES="/etc/easy-rsa/pki/index.txt /etc/openvpn/easy-rsa/pki/index.txt"
    INDEX_FILE=""
    for file in $INDEX_FILES; do
        if [ -f "$file" ]; then
            INDEX_FILE="$file"
            break
        fi
    done
    
    if [ -z "$INDEX_FILE" ]; then
        echo "❌ No se encuentra la base de datos de certificados"
        echo ""
        echo "💡 Ubicaciones probables:"
        echo "   /etc/easy-rsa/pki/index.txt"
        echo "   /etc/openvpn/easy-rsa/pki/index.txt"
        return
    fi
    
    echo "Clientes en sistema:"
    echo ""
    count=0
    for cliente in $(grep -E "^(V|R)" "$INDEX_FILE" 2>/dev/null | awk -F'/' '{print $NF}' | awk '{print $1}' | sort -u); do
        if [ -n "$cliente" ]; then
            count=$((count + 1))
            nombre_descriptivo=$(obtener_nombre "$cliente")
            
            # Verificar estado
            estado="🟢"
            if grep -q "^R.*/CN=${cliente}$" "$INDEX_FILE" 2>/dev/null; then
                estado="🔴"
            fi
            
            if [ "$cliente" = "$nombre_descriptivo" ]; then
                echo "   $estado $cliente"
            else
                echo "   $estado $nombre_descriptivo ($cliente)"
            fi
        fi
    done
    
    echo ""
    echo "📊 Total: $count clientes"
}

# Función para BLOQUEAR cliente
bloquear_cliente() {
    echo ""
    echo "🚫 BLOQUEAR CLIENTE (POR IP)"
    echo "============================"
    
    echo "Clientes disponibles para bloquear:"
    disponibles_encontrados=0
    
    INDEX_FILES="/etc/easy-rsa/pki/index.txt /etc/openvpn/easy-rsa/pki/index.txt"
    INDEX_FILE=""
    for file in $INDEX_FILES; do
        if [ -f "$file" ]; then
            INDEX_FILE="$file"
            break
        fi
    done
    
    if [ -n "$INDEX_FILE" ]; then
        for cliente in $(grep "^V" "$INDEX_FILE" 2>/dev/null | awk -F'/' '{print $NF}' | awk '{print $1}' | sort -u); do
            if [ -n "$cliente" ]; then
                nombre_descriptivo=$(obtener_nombre "$cliente")
                echo "   $nombre_descriptivo ($cliente)"
                disponibles_encontrados=1
            fi
        done
    fi
    
    if [ $disponibles_encontrados -eq 0 ]; then
        echo "   No hay clientes disponibles para bloquear"
        echo ""
        echo "💡 Primero asegúrate de tener clientes configurados en OpenVPN"
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
        echo "💡 CONSEJO: Primero usa la opción 1 para ver clientes conectados"
        echo "   Esto registrará las IPs actuales automáticamente"
        echo ""
        echo "💡 Alternativa: Añade IPs manualmente:"
        echo "   echo '$CLIENTE_REAL:192.168.1.100:\$(date)' >> $IP_HISTORY_FILE"
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
            
            # Bloquear cada IP
            bloqueadas=0
            for ip in $IPS_CLIENTE; do
                if bloquear_ip_firewall "$ip" "$CLIENTE_REAL"; then
                    echo "   🔒 IP $ip BLOQUEADA"
                    bloqueadas=$((bloqueadas + 1))
                else
                    echo "   ❌ Error bloqueando IP $ip"
                fi
            done
            
            # Marcar como bloqueado
            echo "$CLIENTE_REAL:$(date '+%Y-%m-%d %H:%M:%S'):normal" >> "$SUSPENDED_FILE"
            
            echo ""
            echo "✅ CLIENTE BLOQUEADO CORRECTAMENTE"
            echo "   👤 Cliente: $CLIENTE_REAL"
            echo "   🛡️  IPs bloqueadas: $bloqueadas de $contador"
            ;;
        2)
            echo ""
            echo "🛡️  APLICANDO BLOQUEO COMPLETO..."
            
            TOTAL_IPS=0
            BLOQUEADAS=0
            
            for ip in $IPS_CLIENTE; do
                TOTAL_IPS=$((TOTAL_IPS + 1))
                if bloquear_ip_firewall "$ip" "$CLIENTE_REAL"; then
                    echo "   🔒 IP $ip BLOQUEADA"
                    BLOQUEADAS=$((BLOQUEADAS + 1))
                else
                    echo "   ❌ Error bloqueando IP $ip"
                fi
            done
            
            # Marcar como bloqueado completo
            echo "$CLIENTE_REAL:$(date '+%Y-%m-%d %H:%M:%S'):completo" >> "$SUSPENDED_FILE"
            
            echo ""
            echo "✅ BLOQUEO COMPLETO APLICADO"
            echo "   👤 Cliente: $CLIENTE_REAL"
            echo "   📊 IPs encontradas: $TOTAL_IPS"
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
    echo "💡 INFORMACIÓN:"
    echo "   • El cliente NO podrá conectarse desde las IPs bloqueadas"
    echo "   • Si cambia de IP, la nueva también será bloqueada"
    echo "   • Para desbloquear, usa la opción 4 (DESBLOQUEAR CLIENTE)"
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
                tipo_texto=""
                case $tipo in
                    "normal") tipo_texto="[Bloqueo Normal]" ;;
                    "completo") tipo_texto="[Bloqueo Completo]" ;;
                    "profundo") tipo_texto="[Bloqueo Profundo]" ;;
                    *) tipo_texto="[Bloqueado]" ;;
                esac
                echo "   $nombre_descriptivo ($cliente) - $fecha $tipo_texto"
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
    echo "✅ CLIENTE DESBLOQUEADO CORRECTAMENTE"
    echo "   👤 Cliente: $CLIENTE_REAL"
    echo "   🔓 Todas las IPs han sido desbloqueadas"
}

# Función para bloqueo profundo (opción 5)
bloqueo_profundo() {
    echo ""
    echo "🛡️  BLOQUEO PROFUNDO"
    echo "==================="
    echo "Bloquea TODAS las IPs históricas de un cliente"
    echo "Incluso si cambia de router/ISP"
    echo ""
    
    echo "Todos los clientes con IPs registradas:"
    clientes_con_ips=$(cut -d: -f1 "$IP_HISTORY_FILE" 2>/dev/null | sort -u)
    
    if [ -z "$clientes_con_ips" ]; then
        echo "   No hay clientes con IPs registradas"
        echo ""
        echo "💡 Primero usa la opción 1 para ver clientes conectados"
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
    
    # Buscar cliente real
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
    echo "⚠️  ¿ESTÁS SEGURO DE APLICAR BLOQUEO PROFUNDO?"
    echo "   Cliente: $CLIENTE_REAL"
    echo "   IPs a bloquear: $(echo "$IPS_CLIENTE" | wc -w)"
    echo ""
    echo -n "ESCRIBE 'BLOQUEAR' para confirmar: "
    read confirmacion
    
    if [ "$confirmacion" != "BLOQUEAR" ]; then
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
    
    # Añadir a bloqueados con marca especial
    echo "$CLIENTE_REAL:$(date '+%Y-%m-%d %H:%M:%S'):profundo" >> "$SUSPENDED_FILE"
    
    echo ""
    echo "✅ BLOQUEO PROFUNDO APLICADO"
    echo "   👤 Cliente: $CLIENTE_REAL"
    echo "   🛡️  IPs bloqueadas: $TOTAL"
    echo "   ⚠️  Este bloqueo incluye TODAS las IPs históricas del cliente"
}

# Función para gestionar nombres
gestionar_nombres() {
    while true; do
        echo ""
        echo "🏷️  GESTIÓN DE NOMBRES DESCRIPTIVOS"
        echo "=================================="
        echo ""
        echo "1) 📝 Ver todos los nombres asignados"
        echo "2) ➕ Asignar nuevo nombre"
        echo "3) ✏️  Modificar nombre existente"
        echo "4) 🗑️  Eliminar nombre"
        echo "5) ↩️  Volver al menú principal"
        echo ""
        echo -n "Selecciona [1-5]: "
        read opcion_nombre
        
        case $opcion_nombre in
            1)
                echo ""
                echo "📋 NOMBRES ASIGNADOS:"
                echo "===================="
                if [ -f "$NOMBRES_FILE" ] && [ -s "$NOMBRES_FILE" ]; then
                    echo ""
                    printf "%-20s %-30s\n" "CERTIFICADO" "NOMBRE DESCRIPTIVO"
                    printf "%-20s %-30s\n" "===========" "=================="
                    
                    grep -v "^#" "$NOMBRES_FILE" | grep -v "^$" | while IFS=: read -r cliente nombre; do
                        if [ -n "$cliente" ] && [ -n "$nombre" ]; then
                            printf "%-20s %-30s\n" "$cliente" "$nombre"
                        fi
                    done
                    
                    echo ""
                    echo "📊 Total: $(grep -v "^#" "$NOMBRES_FILE" | grep -v "^$" | wc -l) nombres asignados"
                else
                    echo "   📭 No hay nombres asignados"
                fi
                ;;
            
            2)
                echo ""
                echo "➕ ASIGNAR NUEVO NOMBRE"
                echo "======================"
                
                echo -n "📝 Certificado del cliente (ej: client1): "
                read cliente
                echo -n "🏷️  Nombre descriptivo (ej: Juan_Movil): "
                read nombre_descriptivo
                
                if [ -n "$cliente" ] && [ -n "$nombre_descriptivo" ]; then
                    # Eliminar entrada existente si la hay
                    if grep -q "^${cliente}:" "$NOMBRES_FILE" 2>/dev/null; then
                        nombre_anterior=$(grep "^${cliente}:" "$NOMBRES_FILE" | cut -d: -f2)
                        echo "⚠️  Este cliente ya tenía el nombre: '$nombre_anterior'"
                        echo -n "¿Reemplazar? (s/N): "
                        read reemplazar
                        if [ "$reemplazar" != "s" ] && [ "$reemplazar" != "S" ]; then
                            echo "❌ Operación cancelada"
                            continue
                        fi
                        # Eliminar entrada antigua
                        grep -v "^${cliente}:" "$NOMBRES_FILE" 2>/dev/null > "${NOMBRES_FILE}.tmp"
                        mv "${NOMBRES_FILE}.tmp" "$NOMBRES_FILE"
                    fi
                    
                    # Añadir nueva entrada
                    echo "${cliente}:${nombre_descriptivo}" >> "$NOMBRES_FILE"
                    echo ""
                    echo "✅ NOMBRE ASIGNADO CORRECTAMENTE"
                    echo "   📋 Certificado: $cliente"
                    echo "   🏷️  Nombre: $nombre_descriptivo"
                    
                else
                    echo "❌ Error: Debes ingresar tanto el certificado como el nombre"
                fi
                ;;
            
            3)
                echo ""
                echo "✏️  MODIFICAR NOMBRE EXISTENTE"
                echo "============================"
                
                if [ ! -f "$NOMBRES_FILE" ] || [ ! -s "$NOMBRES_FILE" ]; then
                    echo "   📭 No hay nombres asignados para modificar"
                    continue
                fi
                
                echo "Nombres actualmente asignados:"
                echo ""
                count=1
                grep -v "^#" "$NOMBRES_FILE" | grep -v "^$" | while IFS=: read -r cliente nombre; do
                    if [ -n "$cliente" ] && [ -n "$nombre" ]; then
                        echo "   $count) $nombre ($cliente)"
                        count=$((count + 1))
                    fi
                done
                
                echo ""
                echo -n "Número del nombre a modificar: "
                read numero
                
                if ! echo "$numero" | grep -q '^[0-9]\+$'; then
                    echo "❌ Debes ingresar un número válido"
                    continue
                fi
                
                linea=$(grep -v "^#" "$NOMBRES_FILE" | grep -v "^$" | sed -n "${numero}p")
                if [ -z "$linea" ]; then
                    echo "❌ Número inválido"
                    continue
                fi
                
                cliente=$(echo "$linea" | cut -d: -f1)
                nombre_actual=$(echo "$linea" | cut -d: -f2)
                
                echo ""
                echo "📝 MODIFICANDO NOMBRE:"
                echo "   Certificado: $cliente"
                echo "   Nombre actual: $nombre_actual"
                echo ""
                echo -n "Nuevo nombre: "
                read nuevo_nombre
                
                if [ -z "$nuevo_nombre" ]; then
                    echo "❌ Modificación cancelada"
                    continue
                fi
                
                # Realizar la modificación
                grep -v "^${cliente}:" "$NOMBRES_FILE" 2>/dev/null > "${NOMBRES_FILE}.tmp"
                echo "${cliente}:${nuevo_nombre}" >> "${NOMBRES_FILE}.tmp"
                mv "${NOMBRES_FILE}.tmp" "$NOMBRES_FILE"
                
                echo "✅ Nombre modificado: $nombre_actual → $nuevo_nombre"
                ;;
            
            4)
                echo ""
                echo "🗑️  ELIMINAR NOMBRE"
                echo "=================="
                
                if [ ! -f "$NOMBRES_FILE" ] || [ ! -s "$NOMBRES_FILE" ]; then
                    echo "   📭 No hay nombres asignados"
                    continue
                fi
                
                echo "Selecciona el nombre a eliminar:"
                echo ""
                count=1
                grep -v "^#" "$NOMBRES_FILE" | grep -v "^$" | while IFS=: read -r cliente nombre; do
                    if [ -n "$cliente" ] && [ -n "$nombre" ]; then
                        echo "   $count) $nombre ($cliente)"
                        count=$((count + 1))
                    fi
                done
                
                echo ""
                echo -n "Número del nombre a eliminar: "
                read numero
                
                if ! echo "$numero" | grep -q '^[0-9]\+$'; then
                    echo "❌ Debes ingresar un número válido"
                    continue
                fi
                
                linea=$(grep -v "^#" "$NOMBRES_FILE" | grep -v "^$" | sed -n "${numero}p")
                if [ -z "$linea" ]; then
                    echo "❌ Número inválido"
                    continue
                fi
                
                cliente=$(echo "$linea" | cut -d: -f1)
                nombre=$(echo "$linea" | cut -d: -f2)
                
                echo ""
                echo -n "¿Estás seguro de eliminar '$nombre' de '$cliente'? (s/N): "
                read confirmar
                
                if [ "$confirmar" = "s" ] || [ "$confirmar" = "S" ]; then
                    grep -v "^${cliente}:" "$NOMBRES_FILE" > "${NOMBRES_FILE}.tmp"
                    mv "${NOMBRES_FILE}.tmp" "$NOMBRES_FILE"
                    echo "✅ Nombre '$nombre' eliminado"
                else
                    echo "❌ Eliminación cancelada"
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
        echo "Presiona Enter para continuar..."
        read
    done
}

# Función para estado del servicio
estado_servicio() {
    echo ""
    echo "🔍 ESTADO DEL SISTEMA"
    echo "===================="
    
    # Estado OpenVPN
    if pgrep openvpn >/dev/null; then
        echo "✅ OpenVPN: ACTIVO"
    else
        echo "❌ OpenVPN: INACTIVO"
    fi
    
    # IPs bloqueadas
    echo ""
    echo "🛡️  IPs BLOQUEADAS EN FIREWALL:"
    if command -v iptables >/dev/null 2>&1; then
        blocked_count=$(iptables -nL INPUT 2>/dev/null | grep DROP | grep -v "^Chain" | grep -v "^target" | wc -l)
        
        if [ $blocked_count -gt 0 ]; then
            iptables -nL INPUT | grep DROP | while read line; do
                ip=$(echo "$line" | awk '{print $4}')
                echo "   🔒 $ip"
            done
            echo "   📊 Total: $blocked_count IPs bloqueadas"
        else
            echo "   ℹ️  No hay IPs bloqueadas"
        fi
    else
        echo "   ⚠️  iptables no está instalado"
    fi
    
    # Estadísticas
    echo ""
    echo "📊 ESTADÍSTICAS:"
    echo "   👥 Clientes con nombres: $(wc -l < "$NOMBRES_FILE" 2>/dev/null || echo 0)"
    echo "   📍 IPs registradas: $(wc -l < "$IP_HISTORY_FILE" 2>/dev/null || echo 0)"
    echo "   🚫 Clientes bloqueados: $(wc -l < "$SUSPENDED_FILE" 2>/dev/null || echo 0)"
    
    # Verificar persistencia
    echo ""
    echo "💾 REGLAS PERSISTENTES:"
    if [ -f "/etc/openvpn/blocked_ips.txt" ]; then
        echo "   ✅ Archivo de persistencia: $(wc -l < /etc/openvpn/blocked_ips.txt) reglas"
    else
        echo "   ⚠️  Archivo de persistencia no creado aún"
    fi
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
    read -p "Presiona Enter para continuar..."
done
GESTOR_SCRIPT

# Hacer el script ejecutable
chmod +x /usr/bin/gestor-vpn

# Crear archivo de servicio según el sistema init detectado
echo ""
echo "🔧 Configurando persistencia para: $INIT_SYSTEM"

if [ "$INIT_SYSTEM" = "systemd" ]; then
    # Sistema con systemd
    cat > /etc/systemd/system/restaurar-bloqueos.service << 'SYSTEMD_SERVICE'
[Unit]
Description=Restaurar IPs bloqueadas de OpenVPN
After=network.target
Before=openvpn.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c 'if [ -f "/etc/openvpn/blocked_ips.txt" ]; then while IFS=: read -r ip cliente fecha; do iptables -I INPUT -s "$ip" -j DROP 2>/dev/null; done < /etc/openvpn/blocked_ips.txt; fi'
ExecStop=/bin/sh -c 'iptables -F INPUT 2>/dev/null'

[Install]
WantedBy=multi-user.target
SYSTEMD_SERVICE

    systemctl daemon-reload
    systemctl enable restaurar-bloqueos.service
    echo "✅ Servicio systemd creado: restaurar-bloqueos.service"
    
elif [ "$INIT_SYSTEM" = "openrc" ]; then
    # Sistema con OpenRC (Alpine Linux)
    cat > /etc/init.d/restaurar-bloqueos << 'OPENRC_SERVICE'
#!/sbin/openrc-run

name="restaurar-bloqueos"
description="Restaurar IPs bloqueadas de OpenVPN"
command="/bin/sh"
command_args="-c 'if [ -f \"/etc/openvpn/blocked_ips.txt\" ]; then while IFS=: read -r ip cliente fecha; do iptables -I INPUT -s \"\$ip\" -j DROP 2>/dev/null; done < /etc/openvpn/blocked_ips.txt; fi'"
pidfile="/var/run/${name}.pid"

depend() {
    need net
    before openvpn
}

start() {
    ebegin "Restaurando IPs bloqueadas"
    if [ -f "/etc/openvpn/blocked_ips.txt" ]; then
        while IFS=: read -r ip cliente fecha; do
            iptables -I INPUT -s "$ip" -j DROP 2>/dev/null
        done < /etc/openvpn/blocked_ips.txt
    fi
    eend $?
}
OPENRC_SERVICE

    chmod +x /etc/init.d/restaurar-bloqueos
    rc-update add restaurar-bloqueos default
    echo "✅ Servicio OpenRC creado: /etc/init.d/restaurar-bloqueos"
    
else
    # Sistema con SysV init o desconocido - usar rc.local
    echo "⚠️  Sistema init no reconocido, usando rc.local para persistencia"
    
    # Crear script de restauración
    cat > /usr/local/bin/restaurar-bloqueos.sh << 'RC_LOCAL_SCRIPT'
#!/bin/sh
if [ -f "/etc/openvpn/blocked_ips.txt" ]; then
    while IFS=: read -r ip cliente fecha; do
        iptables -I INPUT -s "$ip" -j DROP 2>/dev/null
    done < /etc/openvpn/blocked_ips.txt
fi
RC_LOCAL_SCRIPT
    
    chmod +x /usr/local/bin/restaurar-bloqueos.sh
    
    # Añadir a rc.local si existe
    if [ -f "/etc/rc.local" ]; then
        grep -q "restaurar-bloqueos" /etc/rc.local || echo "/usr/local/bin/restaurar-bloqueos.sh" >> /etc/rc.local
        chmod +x /etc/rc.local
    else
        # Crear rc.local si no existe
        cat > /etc/rc.local << 'RC_LOCAL'
#!/bin/sh
/usr/local/bin/restaurar-bloqueos.sh
exit 0
RC_LOCAL
        chmod +x /etc/rc.local
    fi
    
    echo "✅ Script de persistencia añadido a rc.local"
fi

# Verificar que iptables esté instalado
if ! command -v iptables >/dev/null 2>&1; then
    echo ""
    echo "⚠️  ADVERTENCIA: iptables no está instalado"
    echo "   El bloqueo por IP no funcionará sin iptables"
    echo ""
    echo "💡 Para instalar iptables:"
    echo "   • Debian/Ubuntu: apt-get install iptables -y"
    echo "   • Alpine Linux: apk add iptables"
    echo "   • CentOS/RHEL: yum install iptables -y"
fi

echo ""
echo "✅ INSTALACIÓN COMPLETADA"
echo ""
echo "🚀 PARA EJECUTAR EL GESTOR:"
echo "   gestor-vpn"
echo ""
echo "📋 MENÚ PRINCIPAL:"
echo "   1) 👁️  Ver clientes conectados"
echo "   2) 📋 Listar todos los clientes"
echo "   3) 🚫 BLOQUEAR cliente (bloquear IPs)"
echo "   4) ✅ DESBLOQUEAR cliente (desbloquear IPs)"
echo "   5) 🛡️  BLOQUEO PROFUNDO"
echo "   6) 🏷️  GESTIONAR NOMBRES"
echo "   7) 🔍 Estado del servicio"
echo "   8) ❌ Salir"
echo ""
echo "💡 PARA PROBAR RÁPIDAMENTE:"
echo "   1. Primero asigna un nombre: echo 'client1:Juan_Movil' >> /etc/openvpn/clientes/nombres.txt"
echo "   2. Añade una IP de prueba: echo 'client1:192.168.1.100:\$(date)' >> /etc/openvpn/clientes/ip_history.txt"
echo "   3. Ejecuta: gestor-vpn"
echo "   4. Prueba las opciones 3, 4, 5 y 7"
