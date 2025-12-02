#!/bin/sh

echo ""
echo "🔧 CREANDO GESTOR VPN COMPATIBLE CON OPENWRT"
echo "============================================"

# Crear directorios necesarios
mkdir -p /etc/openvpn/clientes/

# Crear script principal CORREGIDO
cat > /usr/bin/gestor-vpn << 'GESTOR_SCRIPT'
#!/bin/sh

# Archivos de configuración
NOMBRES_FILE="/etc/openvpn/clientes/nombres.txt"
IP_HISTORY_FILE="/etc/openvpn/clientes/ip_history.txt"
SUSPENDED_FILE="/etc/openvpn/clientes/suspended.txt"

# Crear archivos si no existen
for file in "$NOMBRES_FILE" "$IP_HISTORY_FILE" "$SUSPENDED_FILE"; do
    [ ! -f "$file" ] && touch "$file"
done

# Función para obtener nombre descriptivo
obtener_nombre() {
    local cliente="$1"
    if [ -f "$NOMBRES_FILE" ]; then
        local nombre=$(grep "^${cliente}:" "$NOMBRES_FILE" 2>/dev/null | cut -d: -f2-)
        if [ -n "$nombre" ]; then
            echo "$nombre"
        else
            echo "$cliente"
        fi
    else
        echo "$cliente"
    fi
}

# Función para registrar IP de cliente
registrar_ip() {
    local cliente="$1"
    local ip="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Validar IP simple
    if echo "$ip" | grep -q '^[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*$'; then
        # Crear archivo temporal
        grep -v "^${cliente}:${ip}:" "$IP_HISTORY_FILE" 2>/dev/null > /tmp/ip_history.tmp
        mv /tmp/ip_history.tmp "$IP_HISTORY_FILE" 2>/dev/null
        
        # Añadir nueva entrada
        echo "${cliente}:${ip}:${timestamp}" >> "$IP_HISTORY_FILE"
    fi
}

# Función para obtener todas las IPs de un cliente
obtener_ips_cliente() {
    local cliente="$1"
    if [ -f "$IP_HISTORY_FILE" ]; then
        grep "^${cliente}:" "$IP_HISTORY_FILE" 2>/dev/null | cut -d: -f2 | sort -u
    fi
}

# Función para bloquear IP en firewall
bloquear_ip_firewall() {
    local ip="$1"
    local cliente="$2"
    
    # Verificar iptables
    if ! command -v iptables >/dev/null 2>&1; then
        echo "❌ iptables no disponible"
        return 1
    fi
    
    # Verificar si ya está bloqueada
    if iptables -nL INPUT 2>/dev/null | grep -q "DROP.*$ip"; then
        return 0
    fi
    
    # Bloquear IP
    if iptables -I INPUT -s "$ip" -j DROP 2>/dev/null; then
        # Guardar para persistencia
        mkdir -p /etc/openvpn
        if [ -f "/etc/openvpn/blocked_ips.txt" ]; then
            if ! grep -q "^$ip:" /etc/openvpn/blocked_ips.txt; then
                echo "$ip:$cliente:$(date '+%Y-%m-%d %H:%M:%S')" >> /etc/openvpn/blocked_ips.txt
            fi
        else
            echo "$ip:$cliente:$(date '+%Y-%m-%d %H:%M:%S')" > /etc/openvpn/blocked_ips.txt
        fi
        return 0
    else
        return 1
    fi
}

# Función para desbloquear IP en firewall
desbloquear_ip_firewall() {
    local ip="$1"
    
    if command -v iptables >/dev/null 2>&1; then
        iptables -D INPUT -s "$ip" -j DROP 2>/dev/null
    fi
    
    # Eliminar de persistencia
    if [ -f "/etc/openvpn/blocked_ips.txt" ]; then
        grep -v "^$ip:" /etc/openvpn/blocked_ips.txt > /tmp/blocked.tmp
        mv /tmp/blocked.tmp /etc/openvpn/blocked_ips.txt 2>/dev/null
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
    echo "3) 🚫 BLOQUEAR cliente"
    echo "4) ✅ DESBLOQUEAR cliente"
    echo "5) 🏷️  Gestionar nombres"
    echo "6) 🔍 Estado del sistema"
    echo "7) ❌ Salir"
    echo ""
    echo -n "Selecciona [1-7]: "
}

# Función para ver clientes conectados (COMPATIBLE ASH)
ver_conectados() {
    echo ""
    echo "📊 CLIENTES CONECTADOS:"
    echo ""
    
    # Buscar archivo de estado
    STATUS_FILE=""
    if [ -f "/var/log/openvpn-status.log" ] && grep -q "CLIENT_LIST" "/var/log/openvpn-status.log"; then
        STATUS_FILE="/var/log/openvpn-status.log"
    elif [ -f "/tmp/openvpn-status.log" ] && grep -q "CLIENT_LIST" "/tmp/openvpn-status.log"; then
        STATUS_FILE="/tmp/openvpn-status.log"
    fi
    
    if [ -n "$STATUS_FILE" ]; then
        # Usar método compatible con ash
        grep "^CLIENT_LIST" "$STATUS_FILE" | {
            found=0
            while read line; do
                # Extraer datos usando awk
                cliente=$(echo "$line" | awk '{print $2}')
                ip_externa=$(echo "$line" | awk '{print $3}')
                ip_interna=$(echo "$line" | awk '{print $4}')
                
                if [ -n "$cliente" ] && [ "$ip_externa" != "UNDEF" ]; then
                    found=1
                    nombre_descriptivo=$(obtener_nombre "$cliente")
                    
                    # Registrar IP
                    registrar_ip "$cliente" "$ip_externa"
                    
                    if [ "$cliente" = "$nombre_descriptivo" ]; then
                        echo "   👤 $cliente"
                    else
                        echo "   👤 $nombre_descriptivo ($cliente)"
                    fi
                    echo "      📍 IP Externa: $ip_externa"
                    [ -n "$ip_interna" ] && echo "      📍 IP Interna: $ip_interna"
                    echo ""
                fi
            done
            if [ $found -eq 0 ]; then
                echo "   ℹ️  No hay clientes conectados en el log"
            fi
        }
    else
        echo "   ℹ️  Archivo de estado no encontrado"
        echo ""
        echo "💡 Para habilitar el log, añade a OpenVPN:"
        echo "   status /var/log/openvpn-status.log"
    fi
}

# Función para listar clientes (COMPATIBLE ASH)
listar_clientes() {
    echo ""
    echo "📋 LISTADO DE CLIENTES"
    echo "======================"
    echo ""
    
    # Buscar base de datos
    INDEX_FILE=""
    for dir in /etc/easy-rsa/pki /etc/openvpn/easy-rsa/pki /etc/openvpn /root/easy-rsa/pki; do
        if [ -f "$dir/index.txt" ]; then
            INDEX_FILE="$dir/index.txt"
            break
        fi
    done
    
    if [ -z "$INDEX_FILE" ]; then
        echo "   ℹ️  No se encuentra index.txt"
        echo ""
        echo "💡 Ubicaciones probables:"
        echo "   /etc/easy-rsa/pki/index.txt"
        echo "   /etc/openvpn/easy-rsa/pki/index.txt"
        return
    fi
    
    echo "Clientes ACTIVOS (🟢):"
    echo ""
    activos=0
    if [ -f "$INDEX_FILE" ]; then
        grep "^V" "$INDEX_FILE" | {
            while read line; do
                cliente=$(echo "$line" | awk '{print $NF}')
                if [ -n "$cliente" ] && [ "$cliente" != "unknown" ]; then
                    activos=$((activos + 1))
                    nombre_descriptivo=$(obtener_nombre "$cliente")
                    echo "   🟢 $nombre_descriptivo ($cliente)"
                fi
            done
        }
    fi
    [ $activos -eq 0 ] && echo "   Ninguno"
    
    echo ""
    echo "Clientes REVOCADOS (🔴):"
    echo ""
    revocados=0
    if [ -f "$INDEX_FILE" ]; then
        grep "^R" "$INDEX_FILE" | {
            while read line; do
                cliente=$(echo "$line" | awk '{print $NF}')
                if [ -n "$cliente" ] && [ "$cliente" != "unknown" ]; then
                    revocados=$((revocados + 1))
                    nombre_descriptivo=$(obtener_nombre "$cliente")
                    echo "   🔴 $nombre_descriptivo ($cliente)"
                fi
            done
        }
    fi
    [ $revocados -eq 0 ] && echo "   Ninguno"
    
    echo ""
    echo "📊 Total: $((activos + revocados)) clientes"
}

# Función para BLOQUEAR cliente
bloquear_cliente() {
    echo ""
    echo "🚫 BLOQUEAR CLIENTE"
    echo "==================="
    
    # Verificar iptables
    if ! command -v iptables >/dev/null 2>&1; then
        echo "❌ ERROR: iptables no instalado"
        echo ""
        echo "💡 En OpenWRT: opkg install iptables-nft"
        return
    fi
    
    echo "Clientes disponibles:"
    echo ""
    
    # Listar clientes activos
    activos=0
    INDEX_FILE=""
    for dir in /etc/easy-rsa/pki /etc/openvpn/easy-rsa/pki /etc/openvpn; do
        [ -f "$dir/index.txt" ] && INDEX_FILE="$dir/index.txt" && break
    done
    
    if [ -n "$INDEX_FILE" ]; then
        grep "^V" "$INDEX_FILE" 2>/dev/null | {
            while read line; do
                cliente=$(echo "$line" | awk '{print $NF}')
                if [ -n "$cliente" ] && [ "$cliente" != "unknown" ]; then
                    activos=$((activos + 1))
                    nombre_descriptivo=$(obtener_nombre "$cliente")
                    echo "   $activos) $nombre_descriptivo ($cliente)"
                fi
            done
        }
    fi
    
    if [ $activos -eq 0 ]; then
        echo "   ℹ️  No hay clientes disponibles"
        return
    fi
    
    echo ""
    echo -n "Número del cliente a BLOQUEAR: "
    read num_cliente
    
    # Obtener cliente seleccionado
    count=0
    cliente_seleccionado=""
    if [ -n "$INDEX_FILE" ]; then
        grep "^V" "$INDEX_FILE" 2>/dev/null | {
            while read line; do
                cliente=$(echo "$line" | awk '{print $NF}')
                if [ -n "$cliente" ] && [ "$cliente" != "unknown" ]; then
                    count=$((count + 1))
                    if [ $count -eq $num_cliente ]; then
                        cliente_seleccionado="$cliente"
                        echo "$cliente" > /tmp/cliente_seleccionado.txt
                    fi
                fi
            done
        }
    fi
    
    if [ -f "/tmp/cliente_seleccionado.txt" ]; then
        cliente_seleccionado=$(cat /tmp/cliente_seleccionado.txt)
        rm -f /tmp/cliente_seleccionado.txt
    fi
    
    if [ -z "$cliente_seleccionado" ]; then
        echo "❌ Selección inválida"
        return
    fi
    
    echo ""
    echo "🔍 BUSCANDO IPs DE: $cliente_seleccionado"
    IPS_CLIENTE=$(obtener_ips_cliente "$cliente_seleccionado")
    
    if [ -z "$IPS_CLIENTE" ]; then
        echo "   ℹ️  No hay IPs registradas"
        echo ""
        echo "💡 Para añadir IPs manualmente:"
        echo "   echo '$cliente_seleccionado:192.168.1.100:\$(date)' >> $IP_HISTORY_FILE"
        return
    fi
    
    echo "   📋 IPs encontradas:"
    count=0
    for ip in $IPS_CLIENTE; do
        count=$((count + 1))
        echo "      $count) $ip"
    done
    
    echo ""
    echo -n "¿Bloquear TODAS estas IPs? (s/N): "
    read confirmar
    
    if [ "$confirmar" != "s" ] && [ "$confirmar" != "S" ]; then
        echo "❌ Operación cancelada"
        return
    fi
    
    echo ""
    echo "🛡️  BLOQUEANDO IPs..."
    bloqueadas=0
    for ip in $IPS_CLIENTE; do
        if bloquear_ip_firewall "$ip" "$cliente_seleccionado"; then
            echo "   🔒 $ip - BLOQUEADA"
            bloqueadas=$((bloqueadas + 1))
        else
            echo "   ❌ $ip - Error"
        fi
    done
    
    # Añadir a lista de bloqueados
    echo "$cliente_seleccionado:$(date '+%Y-%m-%d %H:%M:%S')" >> "$SUSPENDED_FILE"
    
    echo ""
    echo "✅ CLIENTE BLOQUEADO"
    echo "   👤 $cliente_seleccionado"
    echo "   🛡️  $bloqueadas IPs bloqueadas"
}

# Función para DESBLOQUEAR cliente
desbloquear_cliente() {
    echo ""
    echo "✅ DESBLOQUEAR CLIENTE"
    echo "======================"
    
    echo "Clientes BLOQUEADOS:"
    echo ""
    
    if [ ! -s "$SUSPENDED_FILE" ]; then
        echo "   ℹ️  No hay clientes bloqueados"
        return
    fi
    
    # Mostrar clientes bloqueados
    count=0
    while IFS=: read -r cliente fecha resto; do
        count=$((count + 1))
        nombre_descriptivo=$(obtener_nombre "$cliente")
        echo "   $count) $nombre_descriptivo ($cliente) - $fecha"
    done < "$SUSPENDED_FILE"
    
    echo ""
    echo -n "Número del cliente a DESBLOQUEAR: "
    read num_cliente
    
    # Obtener cliente seleccionado
    count=0
    cliente_seleccionado=""
    while IFS=: read -r cliente fecha resto; do
        count=$((count + 1))
        if [ $count -eq $num_cliente ]; then
            cliente_seleccionado="$cliente"
            break
        fi
    done < "$SUSPENDED_FILE"
    
    if [ -z "$cliente_seleccionado" ]; then
        echo "❌ Selección inválida"
        return
    fi
    
    echo ""
    echo "🔓 DESBLOQUEANDO: $cliente_seleccionado"
    
    # Obtener y desbloquear IPs
    IPS_CLIENTE=$(obtener_ips_cliente "$cliente_seleccionado")
    if [ -n "$IPS_CLIENTE" ]; then
        for ip in $IPS_CLIENTE; do
            desbloquear_ip_firewall "$ip"
            echo "   ✅ $ip - DESBLOQUEADA"
        done
    fi
    
    # Eliminar de lista de bloqueados
    grep -v "^${cliente_seleccionado}:" "$SUSPENDED_FILE" > /tmp/suspended.tmp
    mv /tmp/suspended.tmp "$SUSPENDED_FILE"
    
    echo ""
    echo "✅ CLIENTE DESBLOQUEADO"
    echo "   👤 $cliente_seleccionado"
}

# Función para gestionar nombres
gestionar_nombres() {
    while true; do
        echo ""
        echo "🏷️  GESTIONAR NOMBRES"
        echo "===================="
        echo ""
        echo "1) Ver nombres"
        echo "2) Asignar nombre"
        echo "3) Modificar nombre"
        echo "4) Eliminar nombre"
        echo "5) Volver al menú"
        echo ""
        echo -n "Selecciona [1-5]: "
        read opcion
        
        case $opcion in
            1)
                echo ""
                echo "📋 NOMBRES ASIGNADOS:"
                echo ""
                if [ -s "$NOMBRES_FILE" ]; then
                    while IFS=: read -r cliente nombre; do
                        echo "   $nombre ($cliente)"
                    done < "$NOMBRES_FILE"
                else
                    echo "   📭 No hay nombres asignados"
                fi
                ;;
                
            2)
                echo ""
                echo "➕ ASIGNAR NOMBRE"
                echo ""
                echo -n "Certificado (ej: client1): "
                read cliente
                echo -n "Nombre (ej: Juan): "
                read nombre
                
                if [ -n "$cliente" ] && [ -n "$nombre" ]; then
                    # Eliminar si existe
                    grep -v "^${cliente}:" "$NOMBRES_FILE" > /tmp/nombres.tmp
                    # Añadir nuevo
                    echo "${cliente}:${nombre}" >> /tmp/nombres.tmp
                    mv /tmp/nombres.tmp "$NOMBRES_FILE"
                    echo "✅ Nombre asignado: $nombre ($cliente)"
                else
                    echo "❌ Datos incompletos"
                fi
                ;;
                
            3)
                echo ""
                if [ ! -s "$NOMBRES_FILE" ]; then
                    echo "📭 No hay nombres para modificar"
                    continue
                fi
                
                echo "✏️  MODIFICAR NOMBRE"
                echo ""
                echo "Selecciona:"
                echo ""
                count=1
                while IFS=: read -r cliente nombre; do
                    echo "   $count) $nombre ($cliente)"
                    count=$((count + 1))
                done < "$NOMBRES_FILE"
                
                echo ""
                echo -n "Número: "
                read num
                
                count=1
                cliente_mod=""
                nombre_actual=""
                while IFS=: read -r c n; do
                    if [ $count -eq $num ]; then
                        cliente_mod="$c"
                        nombre_actual="$n"
                        break
                    fi
                    count=$((count + 1))
                done < "$NOMBRES_FILE"
                
                if [ -z "$cliente_mod" ]; then
                    echo "❌ Número inválido"
                    continue
                fi
                
                echo ""
                echo "Modificando: $nombre_actual ($cliente_mod)"
                echo -n "Nuevo nombre: "
                read nuevo_nombre
                
                if [ -n "$nuevo_nombre" ]; then
                    grep -v "^${cliente_mod}:" "$NOMBRES_FILE" > /tmp/nombres.tmp
                    echo "${cliente_mod}:${nuevo_nombre}" >> /tmp/nombres.tmp
                    mv /tmp/nombres.tmp "$NOMBRES_FILE"
                    echo "✅ Nombre modificado"
                fi
                ;;
                
            4)
                echo ""
                if [ ! -s "$NOMBRES_FILE" ]; then
                    echo "📭 No hay nombres para eliminar"
                    continue
                fi
                
                echo "🗑️  ELIMINAR NOMBRE"
                echo ""
                echo "Selecciona:"
                echo ""
                count=1
                while IFS=: read -r cliente nombre; do
                    echo "   $count) $nombre ($cliente)"
                    count=$((count + 1))
                done < "$NOMBRES_FILE"
                
                echo ""
                echo -n "Número: "
                read num
                
                count=1
                cliente_del=""
                nombre_del=""
                while IFS=: read -r c n; do
                    if [ $count -eq $num ]; then
                        cliente_del="$c"
                        nombre_del="$n"
                        break
                    fi
                    count=$((count + 1))
                done < "$NOMBRES_FILE"
                
                if [ -z "$cliente_del" ]; then
                    echo "❌ Número inválido"
                    continue
                fi
                
                echo ""
                echo -n "¿Eliminar '$nombre_del'? (s/N): "
                read confirmar
                
                if [ "$confirmar" = "s" ] || [ "$confirmar" = "S" ]; then
                    grep -v "^${cliente_del}:" "$NOMBRES_FILE" > /tmp/nombres.tmp
                    mv /tmp/nombres.tmp "$NOMBRES_FILE"
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
        # Contar reglas DROP
        drops=$(iptables -nL INPUT 2>/dev/null | grep -c DROP)
        echo "   📊 Reglas DROP: $drops"
    else
        echo "   ❌ No instalado"
    fi
    
    # Estadísticas
    echo ""
    echo "📊 ESTADÍSTICAS:"
    nombres=$(grep -c ":" "$NOMBRES_FILE" 2>/dev/null || echo 0)
    echo "   👥 Nombres asignados: $nombres"
    
    ips=$(wc -l < "$IP_HISTORY_FILE" 2>/dev/null || echo 0)
    echo "   📍 IPs registradas: $ips"
    
    bloqueados=$(wc -l < "$SUSPENDED_FILE" 2>/dev/null || echo 0)
    echo "   🚫 Clientes bloqueados: $bloqueados"
    
    # IPs bloqueadas actuales
    echo ""
    echo "🔒 IPs BLOQUEADAS ACTUALES:"
    if command -v iptables >/dev/null 2>&1; then
        iptables -nL INPUT 2>/dev/null | grep DROP | {
            count=0
            while read line; do
                ip=$(echo "$line" | awk '{print $4}')
                if [ -n "$ip" ]; then
                    count=$((count + 1))
                    if [ $count -le 5 ]; then
                        echo "   $ip"
                    fi
                fi
            done
            if [ $count -gt 5 ]; then
                echo "   ... y $((count - 5)) más"
            fi
            if [ $count -eq 0 ]; then
                echo "   ℹ️  Ninguna"
            fi
        }
    else
        echo "   ℹ️  iptables no disponible"
    fi
}

# Bucle principal del menú
while true; do
    mostrar_menu
    read opcion
    
    case $opcion in
        1) ver_conectados ;;
        2) listar_clientes ;;
        3) bloquear_cliente ;;
        4) desbloquear_cliente ;;
        5) gestionar_nombres ;;
        6) estado_servicio ;;
        7)
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

# Dar permisos
chmod +x /usr/bin/gestor-vpn

echo ""
echo "✅ GESTOR VPN INSTALADO CORRECTAMENTE"
echo ""
echo "🔧 COMPATIBILIDAD:"
echo "   • 100% compatible con ash (OpenWRT)"
echo "   • Sin Process Substitution"
echo "   • Sintaxis simple y robusta"
echo ""
echo "🚀 PARA USAR:"
echo "   gestor-vpn"
echo ""
echo "💡 PRIMEROS PASOS:"
echo "   1. Asigna nombres: opción 5 → opción 2"
echo "   2. Añade IPs manualmente si es necesario:"
echo "      echo 'client1:192.168.1.100:\$(date)' >> /etc/openvpn/clientes/ip_history.txt"
echo "   3. Prueba bloqueo/desbloqueo"
echo ""
echo "⚠️  Si iptables no está instalado:"
echo "   opkg update && opkg install iptables-nft"
