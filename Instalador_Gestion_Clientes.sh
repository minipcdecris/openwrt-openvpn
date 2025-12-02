#!/bin/sh

echo ""
echo "🔧 IMPLEMENTANDO BLOQUEO POR IP/FIREWALL EN OPENWRT"
echo "=================================================="

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
    if echo "$ip" | grep -q '^[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}$'; then
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
    
    # Eliminar regla de iptables
    iptables -D INPUT -s "$ip" -j DROP 2>/dev/null 2>&1
    
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
    echo "🔧 GESTOR VPN - BLOQUEO POR IP"
    echo "=============================="
    echo ""
    echo "1) 👁️  Ver clientes conectados"
    echo "2) 📋 Listar todos los clientes"
    echo "3) 🚫 BLOQUEAR cliente (bloquear IPs)"
    echo "4) ✅ DESBLOQUEAR cliente (desbloquear IPs)"
    echo "5) 🛡️  BLOQUEO PROFUNDO"
    echo "6) 🏷️  GESTIONAR NOMBRES"
    echo "7) 🔍 Estado del sistema"
    echo "8) ❌ Salir"
    echo ""
    echo -n "Selecciona [1-8]: "
}

# Función para ver clientes conectados y registrar IPs (COMPATIBLE CON ASH)
ver_conectados() {
    echo ""
    echo "📊 CLIENTES CONECTADOS:"
    
    # Buscar archivo de estado
    STATUS_FILE=""
    for file in "/var/log/openvpn-status.log" "/tmp/openvpn-status.log"; do
        if [ -f "$file" ] && grep -q "CLIENT_LIST" "$file"; then
            STATUS_FILE="$file"
            break
        fi
    done
    
    if [ -n "$STATUS_FILE" ]; then
        # Método compatible con ash (sin process substitution)
        grep "^CLIENT_LIST" "$STATUS_FILE" | while read line; do
            # Procesar línea manualmente
            cliente=$(echo "$line" | awk '{print $2}')
            ip_externa=$(echo "$line" | awk '{print $3}')
            ip_interna=$(echo "$line" | awk '{print $4}')
            
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
        done
    else
        echo "   ℹ️  No hay clientes conectados"
        echo ""
        echo "💡 El archivo de estado no se encuentra."
        echo "   Asegúrate de que OpenVPN esté configurado para generarlo."
    fi
}

# Función para listar clientes (COMPATIBLE CON ASH)
listar_clientes() {
    echo ""
    echo "📋 LISTADO DE CLIENTES"
    echo "======================"
    
    # Buscar archivo index.txt
    INDEX_FILE=""
    for dir in "/etc/easy-rsa/pki" "/etc/openvpn/easy-rsa/pki" "/etc/openvpn" "/root/easy-rsa/pki"; do
        if [ -f "$dir/index.txt" ]; then
            INDEX_FILE="$dir/index.txt"
            break
        fi
    done
    
    if [ -z "$INDEX_FILE" ]; then
        echo "ℹ️  No se encuentra la base de datos de certificados"
        return
    fi
    
    echo "Clientes en sistema:"
    echo ""
    count=0
    
    # Método compatible con ash
    grep -E "^(V|R)" "$INDEX_FILE" 2>/dev/null | while read line; do
        cliente=$(echo "$line" | awk '{print $NF}')
        if [ -n "$cliente" ] && [ "$cliente" != "unknown" ]; then
            count=$((count + 1))
            nombre_descriptivo=$(obtener_nombre "$cliente")
            
            # Verificar estado
            estado="🟢"
            if echo "$line" | grep -q "^R"; then
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
    
    # Verificar iptables
    if ! command -v iptables >/dev/null 2>&1; then
        echo "❌ ERROR: iptables no está instalado"
        echo ""
        echo "💡 Instala con: opkg update && opkg install iptables-nft"
        return
    fi
    
    echo "Clientes disponibles para bloquear:"
    disponibles_encontrados=0
    
    # Buscar clientes en archivos de configuración
    for cliente_file in /etc/openvpn/client*.conf 2>/dev/null; do
        if [ -f "$cliente_file" ]; then
            cliente=$(basename "$cliente_file" .conf)
            if [ "$cliente" != "*" ]; then
                nombre_descriptivo=$(obtener_nombre "$cliente")
                echo "   $nombre_descriptivo ($cliente)"
                disponibles_encontrados=1
            fi
        fi
    done
    
    # Si no hay archivos .conf, buscar en index.txt
    if [ $disponibles_encontrados -eq 0 ]; then
        INDEX_FILE=""
        for dir in "/etc/easy-rsa/pki" "/etc/openvpn/easy-rsa/pki" "/etc/openvpn"; do
            if [ -f "$dir/index.txt" ]; then
                INDEX_FILE="$dir/index.txt"
                break
            fi
        done
        
        if [ -n "$INDEX_FILE" ]; then
            grep "^V" "$INDEX_FILE" 2>/dev/null | while read line; do
                cliente=$(echo "$line" | awk '{print $NF}')
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
        echo "💡 Para añadir IPs manualmente:"
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
}

# Función para DESBLOQUEAR cliente
desbloquear_cliente() {
    echo ""
    echo "✅ DESBLOQUEAR CLIENTE"
    echo "======================"
    
    echo "Clientes actualmente BLOQUEADOS:"
    bloqueados_encontrados=0
    
    if [ -f "$SUSPENDED_FILE" ] && [ -s "$SUSPENDED_FILE" ]; then
        while IFS= read -r line; do
            cliente=$(echo "$line" | cut -d: -f1)
            if [ -n "$cliente" ]; then
                nombre_descriptivo=$(obtener_nombre "$cliente")
                echo "   $nombre_descriptivo ($cliente)"
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

# Función para gestión de nombres (COMPATIBLE CON ASH)
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
                    while IFS=: read -r cliente nombre; do
                        echo "   $nombre ($cliente)"
                    done < "$NOMBRES_FILE"
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
                
                count=1
                cliente=""
                nombre_actual=""
                while IFS=: read -r c n; do
                    if [ $count -eq $numero ]; then
                        cliente="$c"
                        nombre_actual="$n"
                        break
                    fi
                    count=$((count + 1))
                done < "$NOMBRES_FILE"
                
                if [ -z "$cliente" ]; then
                    echo "❌ Número inválido"
                    continue
                fi
                
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
                
                count=1
                cliente=""
                nombre=""
                while IFS=: read -r c n; do
                    if [ $count -eq $numero ]; then
                        cliente="$c"
                        nombre="$n"
                        break
                    fi
                    count=$((count + 1))
                done < "$NOMBRES_FILE"
                
                if [ -z "$cliente" ]; then
                    echo "❌ Número inválido"
                    continue
                fi
                
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
        echo "Presiona Enter para continuar..."
        read dummy
    done
}

# Función para estado del sistema
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
    
    # Estado firewall
    echo ""
    echo "🛡️  ESTADO DEL FIREWALL:"
    if command -v iptables >/dev/null 2>&1; then
        # Contar reglas
        total_drop=$(iptables -nL INPUT 2>/dev/null | grep -c DROP)
        echo "   📊 Reglas DROP en INPUT: $total_drop"
        
        # Mostrar algunas reglas
        if [ $total_drop -gt 0 ]; then
            echo "   📋 Primeras IPs bloqueadas:"
            iptables -nL INPUT 2>/dev/null | grep DROP | head -3 | while read line; do
                ip=$(echo "$line" | awk '{print $4}')
                if [ -n "$ip" ]; then
                    echo "   🔒 $ip"
                fi
            done
        fi
    else
        echo "   ⚠️  iptables no instalado"
    fi
    
    # Estadísticas nuestro sistema
    echo ""
    echo "📊 ESTADÍSTICAS GESTOR VPN:"
    nombres_count=$(grep -c ":" "$NOMBRES_FILE" 2>/dev/null || echo 0)
    echo "   👥 Clientes con nombres: $nombres_count"
    
    ips_count=$(wc -l < "$IP_HISTORY_FILE" 2>/dev/null || echo 0)
    echo "   📍 IPs registradas: $ips_count"
    
    bloqueados_count=$(wc -l < "$SUSPENDED_FILE" 2>/dev/null || echo 0)
    echo "   🚫 Clientes bloqueados: $bloqueados_count"
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
    echo "Presiona Enter para continuar..."
    read dummy
done
GESTOR_SCRIPT

# Hacer el script ejecutable
chmod +x /usr/bin/gestor-vpn

echo ""
echo "✅ SCRIPT CORREGIDO PARA OPENWRT/ASH"
echo ""
echo "🔧 CAMBIOS REALIZADOS:"
echo "   • Eliminado Process Substitution (< <(...))"
echo "   • Sintaxis compatible con ash (shell de OpenWRT)"
echo "   • Métodos alternativos para bucles"
echo "   • Validación de IP más simple"
echo ""
echo "🚀 PARA EJECUTAR:"
echo "   gestor-vpn"
echo ""
echo "💡 PRUEBA RÁPIDA:"
echo "   1. Asigna un nombre: echo 'client1:Juan' >> /etc/openvpn/clientes/nombres.txt"
echo "   2. Añade IPs: echo 'client1:192.168.1.100:\$(date)' >> /etc/openvpn/clientes/ip_history.txt"
echo "   3. Ejecuta: gestor-vpn"
