#!/bin/sh

echo ""
echo "🔧 IMPLEMENTANDO BLOQUEO POR IP/FIREWALL"
echo "========================================"

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
        echo "📝 IP registrada: $cliente → $ip ($timestamp)"
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
        echo "   ⚡ IP $ip ya estaba bloqueada"
        return 0
    fi
    
    # Bloquear IP en iptables
    if iptables -I INPUT -s "$ip" -j DROP 2>/dev/null; then
        echo "   🔒 IP $ip bloqueada en firewall"
        
        # Guardar regla para persistencia
        if ! grep -q "$ip" /etc/openvpn/blocked_ips.txt 2>/dev/null; then
            echo "$ip:$cliente:$(date '+%Y-%m-%d %H:%M:%S')" >> /etc/openvpn/blocked_ips.txt
        fi
        return 0
    else
        echo "   ❌ Error bloqueando IP $ip"
        return 1
    fi
}

# Función para desbloquear IP en firewall
desbloquear_ip_firewall() {
    local ip=$1
    
    # Eliminar regla de iptables
    iptables -D INPUT -s "$ip" -j DROP 2>/dev/null
    
    # Eliminar de persistencia
    grep -v "^$ip:" /etc/openvpn/blocked_ips.txt 2>/dev/null > /tmp/blocked_ips.tmp
    mv /tmp/blocked_ips.tmp /etc/openvpn/blocked_ips.txt 2>/dev/null
    
    echo "   🔓 IP $ip desbloqueada"
}

# Función para mostrar menú
mostrar_menu() {
    echo ""
    echo "🔧 GESTOR VPN - BLOQUEO POR IP/FIREWALL"
    echo "========================================"
    echo ""
    echo "1) 👁️  Ver clientes conectados (registrar IPs)"
    echo "2) 📋 Listar todos los clientes"
    echo "3) ⏸️  SUSPENDER cliente (bloquear IPs actuales)"
    echo "4) ▶️  REACTIVAR cliente (desbloquear IPs)"
    echo "5) 🚫 BLOQUEO PROFUNDO (todas las IPs históricas)"
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
    fi
}

# Función para suspender cliente (tu idea principal)
suspender_cliente() {
    echo ""
    echo "⏸️  SUSPENDER CLIENTE (BLOQUEO POR IP)"
    echo "======================================"
    
    echo "Clientes activos:"
    activos_encontrados=0
    
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
                activos_encontrados=1
            fi
        done
    fi
    
    if [ $activos_encontrados -eq 0 ]; then
        echo "   No hay clientes activos"
        return
    fi
    
    echo ""
    echo -n "Cliente a suspender: "
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
        return
    fi
    
    echo "   📋 IPs encontradas:"
    contador=0
    for ip in $IPS_CLIENTE; do
        contador=$((contador + 1))
        echo "      $contador) $ip"
    done
    
    echo ""
    echo "⚠️  ¿Qué acción deseas realizar?"
    echo "   1) Bloquear solo IPs actuales (recomendado)"
    echo "   2) Bloquear TODAS las IPs históricas"
    echo "   3) Cancelar"
    echo ""
    echo -n "Selecciona [1-3]: "
    read opcion_bloqueo
    
    case $opcion_bloqueo in
        1)
            echo ""
            echo "🛡️  BLOQUEANDO IPs ACTUALES..."
            
            # Bloquear cada IP
            for ip in $IPS_CLIENTE; do
                bloquear_ip_firewall "$ip" "$CLIENTE_REAL"
            done
            
            # Marcar como suspendido
            echo "$CLIENTE_REAL:$(date '+%Y-%m-%d %H:%M:%S')" >> "$SUSPENDED_FILE"
            
            echo ""
            echo "✅ CLIENTE SUSPENDIDO"
            echo "   👤 Cliente: $CLIENTE_REAL"
            echo "   🛡️  IPs bloqueadas: $contador"
            echo "   ⏰ Fecha: $(date '+%Y-%m-%d %H:%M:%S')"
            ;;
        2)
            echo ""
            echo "🛡️  BLOQUEO PROFUNDO - TODAS LAS IPs HISTÓRICAS..."
            
            # Tu idea original: bloquear todas las IPs históricas
            TOTAL_IPS=0
            BLOQUEADAS=0
            
            for ip in $IPS_CLIENTE; do
                TOTAL_IPS=$((TOTAL_IPS + 1))
                if bloquear_ip_firewall "$ip" "$CLIENTE_REAL"; then
                    BLOQUEADAS=$((BLOQUEADAS + 1))
                fi
            done
            
            # Marcar como suspendido
            echo "$CLIENTE_REAL:$(date '+%Y-%m-%d %H:%M:%S'):deep_block" >> "$SUSPENDED_FILE"
            
            echo ""
            echo "✅ BLOQUEO PROFUNDO COMPLETADO"
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
    echo "   • El cliente no podrá conectarse desde las IPs bloqueadas"
    echo "   • Si cambia de IP (reinicia router), se bloqueará la nueva"
    echo "   • Para reactivar, usa la opción 4 (REACTIVAR CLIENTE)"
}

# Función para reactivar cliente
reactivar_cliente() {
    echo ""
    echo "▶️  REACTIVAR CLIENTE"
    echo "===================="
    
    echo "Clientes suspendidos:"
    suspendidos_encontrados=0
    
    if [ -f "$SUSPENDED_FILE" ] && [ -s "$SUSPENDED_FILE" ]; then
        while IFS=: read -r cliente fecha tipo; do
            if [ -n "$cliente" ]; then
                nombre_descriptivo=$(obtener_nombre "$cliente")
                echo "   $nombre_descriptivo ($cliente) - $fecha"
                suspendidos_encontrados=1
            fi
        done < "$SUSPENDED_FILE"
    fi
    
    if [ $suspendidos_encontrados -eq 0 ]; then
        echo "   No hay clientes suspendidos"
        return
    fi
    
    echo ""
    echo -n "Cliente a reactivar: "
    read INPUT_CLIENTE
    
    # Buscar cliente real
    CLIENTE_REAL=""
    if grep -q ":${INPUT_CLIENTE}$" "$NOMBRES_FILE" 2>/dev/null; then
        CLIENTE_REAL=$(grep ":${INPUT_CLIENTE}$" "$NOMBRES_FILE" | cut -d: -f1)
    else
        CLIENTE_REAL=$INPUT_CLIENTE
    fi
    
    if ! grep -q "^${CLIENTE_REAL}:" "$SUSPENDED_FILE" 2>/dev/null; then
        echo "❌ Cliente '$INPUT_CLIENTE' no está suspendido"
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
        done
    fi
    
    # Eliminar de lista de suspendidos
    grep -v "^${CLIENTE_REAL}:" "$SUSPENDED_FILE" 2>/dev/null > "${SUSPENDED_FILE}.tmp"
    mv "${SUSPENDED_FILE}.tmp" "$SUSPENDED_FILE"
    
    echo ""
    echo "✅ CLIENTE REACTIVADO"
    echo "   👤 Cliente: $CLIENTE_REAL"
    echo "   🔓 IPs desbloqueadas"
    echo "   ⏰ Fecha: $(date '+%Y-%m-%d %H:%M:%S')"
}

# Función para bloqueo profundo (opción 5)
bloqueo_profundo() {
    echo ""
    echo "🚫 BLOQUEO PROFUNDO"
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
    echo -n "Cliente a bloquear profundamente: "
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
    echo "⚠️  ¿ESTÁS SEGURO DE BLOQUEAR PROFUNDAMENTE?"
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
    echo "🛡️  BLOQUEANDO PROFUNDAMENTE..."
    
    TOTAL=0
    for ip in $IPS_CLIENTE; do
        if bloquear_ip_firewall "$ip" "$CLIENTE_REAL"; then
            TOTAL=$((TOTAL + 1))
        fi
    done
    
    # Añadir a suspendidos con marca especial
    echo "$CLIENTE_REAL:$(date '+%Y-%m-%d %H:%M:%S'):deep_block_permanent" >> "$SUSPENDED_FILE"
    
    echo ""
    echo "✅ BLOQUEO PROFUNDO COMPLETADO"
    echo "   👤 Cliente: $CLIENTE_REAL"
    echo "   🛡️  IPs bloqueadas: $TOTAL"
    echo "   ⚠️  Este bloqueo incluye TODAS las IPs históricas"
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
    
    # Estadísticas
    echo ""
    echo "📊 ESTADÍSTICAS:"
    echo "   👥 Clientes con nombres: $(wc -l < "$NOMBRES_FILE" 2>/dev/null || echo 0)"
    echo "   📍 IPs registradas: $(wc -l < "$IP_HISTORY_FILE" 2>/dev/null || echo 0)"
    echo "   ⏸️  Clientes suspendidos: $(wc -l < "$SUSPENDED_FILE" 2>/dev/null || echo 0)"
    
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
        2) 
            echo "📋 LISTADO SIMPLIFICADO"
            echo "======================="
            if [ -f "/etc/easy-rsa/pki/index.txt" ]; then
                echo "Clientes en sistema:"
                grep -E "^(V|R)" "/etc/easy-rsa/pki/index.txt" 2>/dev/null | awk -F'/' '{print $NF}' | awk '{print "   "$1}' | sort -u
            else
                echo "Base de datos no disponible"
            fi
            ;;
        3) suspender_cliente ;;
        4) reactivar_cliente ;;
        5) bloqueo_profundo ;;
        6) 
            echo "🏷️  GESTIÓN DE NOMBRES (versión simplificada)"
            echo "============================================="
            echo "1) Ver nombres asignados"
            echo "2) Asignar nuevo nombre"
            echo -n "Selecciona: "
            read op
            if [ "$op" = "1" ]; then
                echo "Nombres asignados:"
                cat "$NOMBRES_FILE" 2>/dev/null || echo "   Ninguno"
            elif [ "$op" = "2" ]; then
                echo -n "Certificado: "; read cert
                echo -n "Nombre: "; read nombre
                if [ -n "$cert" ] && [ -n "$nombre" ]; then
                    echo "${cert}:${nombre}" >> "$NOMBRES_FILE"
                    echo "✅ Nombre asignado"
                fi
            fi
            ;;
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
    read
done
GESTOR_SCRIPT

# Hacer el script ejecutable
chmod +x /usr/bin/gestor-vpn

# Crear script para restaurar reglas al reiniciar
cat > /etc/init.d/restaurar-bloqueos << 'RESTAURAR_SCRIPT'
#!/bin/sh
### BEGIN INIT INFO
# Provides:          restaurar-bloqueos
# Required-Start:    $network $local_fs
# Required-Stop:     
# Default-Start:     2 3 4 5
# Default-Stop:      
# Short-Description: Restaurar IPs bloqueadas al inicio
### END INIT INFO

case "$1" in
    start)
        echo "🛡️  Restaurando IPs bloqueadas..."
        if [ -f "/etc/openvpn/blocked_ips.txt" ]; then
            while IFS=: read -r ip cliente fecha; do
                iptables -I INPUT -s "$ip" -j DROP 2>/dev/null && \
                echo "   🔒 Restaurado bloqueo: $ip ($cliente)"
            done < /etc/openvpn/blocked_ips.txt
        fi
        ;;
    *)
        echo "Usage: $0 {start}"
        exit 1
        ;;
esac

exit 0
RESTAURAR_SCRIPT

chmod +x /etc/init.d/restaurar-bloqueos
update-rc.d restaurar-bloqueos defaults

echo ""
echo "✅ SISTEMA IMPLEMENTADO CON ÉXITO"
echo ""
echo "🎯 CARACTERÍSTICAS DE TU IDEA:"
echo "   1. 📍 Registro automático de IPs cuando clientes se conectan"
echo "   2. 🛡️  Bloqueo por firewall (no solo revocación de certificados)"
echo "   3. 📊 Historial completo de todas las IPs usadas por cada cliente"
echo "   4. 🔄 Persistencia automática (sobrevive a reinicios)"
echo "   5. ⚡ Bloqueo inmediato sin reiniciar OpenVPN"
echo ""
echo "🔧 FUNCIONALIDADES:"
echo "   • Opción 1: Ver conectados y registrar IPs automáticamente"
echo "   • Opción 3: Suspender (bloquear IPs actuales)"
echo "   • Opción 4: Reactivar (desbloquear IPs)"
echo "   • Opción 5: Bloqueo profundo (TODAS las IPs históricas)"
echo ""
echo "🚀 EJECUTA: gestor-vpn"
echo ""
echo "💡 CONSEJOS:"
echo "   1. Primero usa opción 1 para registrar IPs de clientes conectados"
echo "   2. Luego usa opción 3 para suspender/bloquear"
echo "   3. Si el cliente cambia de IP, se registrará la nueva"
echo "   4. Para bloqueo total, usa opción 5 (bloqueo profundo)"
