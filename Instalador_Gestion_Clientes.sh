#!/bin/sh

echo ""
echo "🔧 CREANDO GESTOR VPN SUPER SIMPLE"
echo "================================="

# Crear directorios necesarios
mkdir -p /etc/openvpn/clientes/

# Crear script principal ULTRA SIMPLE
cat > /usr/bin/gestor-vpn << 'EOF'
#!/bin/sh

# Archivos de configuración
NOMBRES_FILE="/etc/openvpn/clientes/nombres.txt"
IP_HISTORY_FILE="/etc/openvpn/clientes/ip_history.txt"
SUSPENDED_FILE="/etc/openvpn/clientes/suspended.txt"

# Crear archivos si no existen
touch "$NOMBRES_FILE"
touch "$IP_HISTORY_FILE"
touch "$SUSPENDED_FILE"

# Función para obtener nombre descriptivo
obtener_nombre() {
    cliente="$1"
    if [ -f "$NOMBRES_FILE" ]; then
        nombre=$(grep "^$cliente:" "$NOMBRES_FILE" 2>/dev/null | cut -d: -f2-)
        if [ -n "$nombre" ]; then
            echo "$nombre"
            return
        fi
    fi
    echo "$cliente"
}

# Función para mostrar menú
mostrar_menu() {
    clear
    echo ""
    echo "🔧 GESTOR VPN SIMPLE"
    echo "==================="
    echo ""
    echo "1) Ver clientes conectados"
    echo "2) Listar clientes"
    echo "3) Bloquear cliente"
    echo "4) Desbloquear cliente"
    echo "5) Gestionar nombres"
    echo "6) Estado del sistema"
    echo "7) Salir"
    echo ""
    echo -n "Selecciona [1-7]: "
}

# Función para ver clientes conectados
ver_conectados() {
    echo ""
    echo "📊 CLIENTES CONECTADOS:"
    echo ""
    
    # Buscar archivo de estado
    if [ -f "/var/log/openvpn-status.log" ]; then
        STATUS_FILE="/var/log/openvpn-status.log"
    elif [ -f "/tmp/openvpn-status.log" ]; then
        STATUS_FILE="/tmp/openvpn-status.log"
    else
        echo "   No se encuentra archivo de estado"
        return
    fi
    
    # Leer clientes conectados
    grep "^CLIENT_LIST" "$STATUS_FILE" > /tmp/clientes_temp.txt
    
    if [ ! -s /tmp/clientes_temp.txt ]; then
        echo "   No hay clientes conectados"
        rm -f /tmp/clientes_temp.txt
        return
    fi
    
    # Procesar cada cliente
    while read linea; do
        # Extraer datos
        cliente=$(echo "$linea" | awk '{print $2}')
        ip_externa=$(echo "$linea" | awk '{print $3}')
        
        if [ -n "$cliente" ] && [ "$ip_externa" != "UNDEF" ]; then
            nombre_descriptivo=$(obtener_nombre "$cliente")
            
            # Registrar IP
            timestamp=$(date '+%Y-%m-%d %H:%M:%S')
            grep -v "^$cliente:$ip_externa:" "$IP_HISTORY_FILE" > /tmp/ip_temp.txt
            mv /tmp/ip_temp.txt "$IP_HISTORY_FILE"
            echo "$cliente:$ip_externa:$timestamp" >> "$IP_HISTORY_FILE"
            
            if [ "$cliente" = "$nombre_descriptivo" ]; then
                echo "   👤 $cliente"
            else
                echo "   👤 $nombre_descriptivo ($cliente)"
            fi
            echo "      📍 IP: $ip_externa"
            echo ""
        fi
    done < /tmp/clientes_temp.txt
    
    rm -f /tmp/clientes_temp.txt
}

# Función para listar clientes
listar_clientes() {
    echo ""
    echo "📋 LISTADO DE CLIENTES"
    echo "======================"
    echo ""
    
    # Buscar base de datos
    INDEX_FILE=""
    for dir in /etc/easy-rsa/pki /etc/openvpn/easy-rsa/pki /etc/openvpn; do
        if [ -f "$dir/index.txt" ]; then
            INDEX_FILE="$dir/index.txt"
            break
        fi
    done
    
    if [ -z "$INDEX_FILE" ]; then
        echo "   No se encuentra base de datos"
        return
    fi
    
    echo "Clientes ACTIVOS:"
    echo ""
    activos=0
    grep "^V" "$INDEX_FILE" > /tmp/activos.txt 2>/dev/null
    
    while read linea; do
        cliente=$(echo "$linea" | awk '{print $NF}')
        if [ -n "$cliente" ] && [ "$cliente" != "unknown" ]; then
            activos=$((activos + 1))
            nombre_descriptivo=$(obtener_nombre "$cliente")
            echo "   🟢 $nombre_descriptivo ($cliente)"
        fi
    done < /tmp/activos.txt
    
    rm -f /tmp/activos.txt
    
    if [ $activos -eq 0 ]; then
        echo "   Ninguno"
    fi
    
    echo ""
    echo "Clientes REVOCADOS:"
    echo ""
    revocados=0
    grep "^R" "$INDEX_FILE" > /tmp/revocados.txt 2>/dev/null
    
    while read linea; do
        cliente=$(echo "$linea" | awk '{print $NF}')
        if [ -n "$cliente" ] && [ "$cliente" != "unknown" ]; then
            revocados=$((revocados + 1))
            nombre_descriptivo=$(obtener_nombre "$cliente")
            echo "   🔴 $nombre_descriptivo ($cliente)"
        fi
    done < /tmp/revocados.txt
    
    rm -f /tmp/revocados.txt
    
    if [ $revocados -eq 0 ]; then
        echo "   Ninguno"
    fi
    
    echo ""
    echo "📊 Total: $((activos + revocados)) clientes"
}

# Función para obtener IPs de un cliente
obtener_ips_cliente() {
    cliente="$1"
    if [ -f "$IP_HISTORY_FILE" ]; then
        grep "^$cliente:" "$IP_HISTORY_FILE" | cut -d: -f2 | sort -u
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
    
    # Bloquear IP
    if iptables -I INPUT -s "$ip" -j DROP 2>/dev/null; then
        # Guardar para persistencia
        mkdir -p /etc/openvpn
        echo "$ip:$cliente:$(date '+%Y-%m-%d %H:%M:%S')" >> /etc/openvpn/blocked_ips.txt
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
        mv /tmp/blocked.tmp /etc/openvpn/blocked_ips.txt
    fi
}

# Función para bloquear cliente
bloquear_cliente() {
    echo ""
    echo "🚫 BLOQUEAR CLIENTE"
    echo "==================="
    
    if ! command -v iptables >/dev/null 2>&1; then
        echo "❌ iptables no instalado"
        echo ""
        echo "Instalar con: opkg update && opkg install iptables-nft"
        return
    fi
    
    # Listar clientes activos
    echo "Clientes disponibles:"
    echo ""
    
    # Buscar base de datos
    INDEX_FILE=""
    for dir in /etc/easy-rsa/pki /etc/openvpn/easy-rsa/pki /etc/openvpn; do
        if [ -f "$dir/index.txt" ]; then
            INDEX_FILE="$dir/index.txt"
            break
        fi
    done
    
    if [ -z "$INDEX_FILE" ]; then
        echo "   No hay clientes"
        return
    fi
    
    # Crear lista de clientes
    grep "^V" "$INDEX_FILE" 2>/dev/null | awk '{print $NF}' | grep -v "unknown" > /tmp/clientes_lista.txt
    
    if [ ! -s /tmp/clientes_lista.txt ]; then
        echo "   No hay clientes activos"
        rm -f /tmp/clientes_lista.txt
        return
    fi
    
    # Mostrar clientes
    num=0
    while read cliente; do
        if [ -n "$cliente" ]; then
            num=$((num + 1))
            nombre_descriptivo=$(obtener_nombre "$cliente")
            echo "   $num) $nombre_descriptivo ($cliente)"
        fi
    done < /tmp/clientes_lista.txt
    
    echo ""
    echo -n "Selecciona cliente (número): "
    read seleccion
    
    # Obtener cliente seleccionado
    count=0
    cliente_seleccionado=""
    while read cliente; do
        count=$((count + 1))
        if [ $count -eq $seleccion ]; then
            cliente_seleccionado="$cliente"
            break
        fi
    done < /tmp/clientes_lista.txt
    
    rm -f /tmp/clientes_lista.txt
    
    if [ -z "$cliente_seleccionado" ]; then
        echo "❌ Selección inválida"
        return
    fi
    
    echo ""
    echo "🔍 Buscando IPs de: $cliente_seleccionado"
    
    # Obtener IPs
    IPS=$(obtener_ips_cliente "$cliente_seleccionado")
    
    if [ -z "$IPS" ]; then
        echo "   No hay IPs registradas"
        echo ""
        echo "💡 Añade IPs manualmente:"
        echo "   echo '$cliente_seleccionado:192.168.1.100:\$(date)' >> $IP_HISTORY_FILE"
        return
    fi
    
    echo "   IPs encontradas:"
    for ip in $IPS; do
        echo "   - $ip"
    done
    
    echo ""
    echo -n "¿Bloquear estas IPs? (s/N): "
    read confirmar
    
    if [ "$confirmar" != "s" ] && [ "$confirmar" != "S" ]; then
        echo "❌ Cancelado"
        return
    fi
    
    echo ""
    echo "🛡️  Bloqueando IPs..."
    
    # Bloquear cada IP
    for ip in $IPS; do
        if bloquear_ip "$ip" "$cliente_seleccionado"; then
            echo "   ✅ $ip bloqueada"
        else
            echo "   ❌ Error con $ip"
        fi
    done
    
    # Añadir a lista de bloqueados
    echo "$cliente_seleccionado:$(date '+%Y-%m-%d %H:%M:%S')" >> "$SUSPENDED_FILE"
    
    echo ""
    echo "✅ Cliente bloqueado: $cliente_seleccionado"
}

# Función para desbloquear cliente
desbloquear_cliente() {
    echo ""
    echo "✅ DESBLOQUEAR CLIENTE"
    echo "======================"
    
    echo "Clientes bloqueados:"
    echo ""
    
    if [ ! -s "$SUSPENDED_FILE" ]; then
        echo "   No hay clientes bloqueados"
        return
    fi
    
    # Mostrar clientes bloqueados
    num=0
    while IFS=: read -r cliente fecha resto; do
        if [ -n "$cliente" ]; then
            num=$((num + 1))
            nombre_descriptivo=$(obtener_nombre "$cliente")
            echo "   $num) $nombre_descriptivo ($cliente)"
        fi
    done < "$SUSPENDED_FILE"
    
    echo ""
    echo -n "Selecciona cliente (número): "
    read seleccion
    
    # Obtener cliente seleccionado
    count=0
    cliente_seleccionado=""
    while IFS=: read -r cliente fecha resto; do
        count=$((count + 1))
        if [ $count -eq $seleccion ]; then
            cliente_seleccionado="$cliente"
            break
        fi
    done < "$SUSPENDED_FILE"
    
    if [ -z "$cliente_seleccionado" ]; then
        echo "❌ Selección inválida"
        return
    fi
    
    echo ""
    echo "🔓 Desbloqueando: $cliente_seleccionado"
    
    # Obtener y desbloquear IPs
    IPS=$(obtener_ips_cliente "$cliente_seleccionado")
    if [ -n "$IPS" ]; then
        for ip in $IPS; do
            desbloquear_ip "$ip"
            echo "   ✅ $ip desbloqueada"
        done
    fi
    
    # Eliminar de lista de bloqueados
    grep -v "^$cliente_seleccionado:" "$SUSPENDED_FILE" > /tmp/suspended.tmp
    mv /tmp/suspended.tmp "$SUSPENDED_FILE"
    
    echo ""
    echo "✅ Cliente desbloqueado: $cliente_seleccionado"
}

# Función para gestionar nombres
gestionar_nombres() {
    while true; do
        echo ""
        echo "🏷️  GESTIONAR NOMBRES"
        echo "===================="
        echo ""
        echo "1) Ver nombres"
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
                        echo "   $nombre ($cliente)"
                    done < "$NOMBRES_FILE"
                else
                    echo "   No hay nombres asignados"
                fi
                ;;
                
            2)
                echo ""
                echo "✏️  AÑADIR/MODIFICAR NOMBRE"
                echo ""
                echo -n "Certificado: "
                read cliente
                echo -n "Nombre: "
                read nombre
                
                if [ -n "$cliente" ] && [ -n "$nombre" ]; then
                    # Crear archivo temporal sin este cliente
                    grep -v "^$cliente:" "$NOMBRES_FILE" > /tmp/nombres.tmp
                    # Añadir nuevo
                    echo "$cliente:$nombre" >> /tmp/nombres.tmp
                    mv /tmp/nombres.tmp "$NOMBRES_FILE"
                    echo "✅ Nombre asignado: $nombre ($cliente)"
                else
                    echo "❌ Datos incompletos"
                fi
                ;;
                
            3)
                echo ""
                echo "🗑️  ELIMINAR NOMBRE"
                echo ""
                
                if [ ! -s "$NOMBRES_FILE" ]; then
                    echo "   No hay nombres para eliminar"
                    continue
                fi
                
                echo "Selecciona nombre a eliminar:"
                echo ""
                num=0
                while IFS=: read -r cliente nombre; do
                    num=$((num + 1))
                    echo "   $num) $nombre ($cliente)"
                done < "$NOMBRES_FILE"
                
                echo ""
                echo -n "Número: "
                read seleccion
                
                # Obtener cliente a eliminar
                count=0
                cliente_eliminar=""
                while IFS=: read -r cliente nombre; do
                    count=$((count + 1))
                    if [ $count -eq $seleccion ]; then
                        cliente_eliminar="$cliente"
                        break
                    fi
                done < "$NOMBRES_FILE"
                
                if [ -z "$cliente_eliminar" ]; then
                    echo "❌ Selección inválida"
                    continue
                fi
                
                echo ""
                echo -n "¿Eliminar nombre de $cliente_eliminar? (s/N): "
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
        echo "   📊 Reglas DROP: $drops"
    else
        echo "   ❌ No instalado"
    fi
    
    # Estadísticas
    echo ""
    echo "📊 ESTADÍSTICAS:"
    nombres=$(grep -c ":" "$NOMBRES_FILE" 2>/dev/null || echo 0)
    echo "   👥 Nombres: $nombres"
    
    ips=$(wc -l < "$IP_HISTORY_FILE" 2>/dev/null || echo 0)
    echo "   📍 IPs registradas: $ips"
    
    bloqueados=$(wc -l < "$SUSPENDED_FILE" 2>/dev/null || echo 0)
    echo "   🚫 Bloqueados: $bloqueados"
    
    # IPs bloqueadas
    echo ""
    echo "🔒 IPs BLOQUEADAS:"
    if command -v iptables >/dev/null 2>&1; then
        iptables -nL INPUT 2>/dev/null | grep DROP > /tmp/blocked_current.txt
        
        if [ -s /tmp/blocked_current.txt ]; then
            count=0
            while read linea; do
                ip=$(echo "$linea" | awk '{print $4}')
                if [ -n "$ip" ]; then
                    count=$((count + 1))
                    if [ $count -le 10 ]; then
                        echo "   $ip"
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
chmod +x /usr/bin/gestor-vpn

echo ""
echo "✅ GESTOR VPN INSTALADO"
echo ""
echo "🚀 PARA EJECUTAR:"
echo "   gestor-vpn"
echo ""
echo "💡 PRIMEROS PASOS:"
echo "   1. Usa opción 5 para asignar nombres"
echo "   2. Si no hay IPs, añade manualmente:"
echo "      echo 'client1:192.168.1.100:\$(date)' >> /etc/openvpn/clientes/ip_history.txt"
echo "   3. Prueba bloqueo/desbloqueo"
