#!/bin/sh

echo ""
echo "🔧 ACTUALIZANDO GESTOR VPN CON LAS MODIFICACIONES"
echo "=================================================="

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

# Función para mostrar menú
mostrar_menu() {
    clear
    echo ""
    echo "🔧 GESTIÓN VPN - BLOQUEO POR IP"
    echo "================================"
    echo ""
    echo "1) 👁️  Ver clientes conectados (registra IPs)"
    echo "2) 📋 Listar todos los clientes"
    echo "3) 🚫 BLOQUEAR cliente"
    echo "4) ✅ DESBLOQUEAR cliente"
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
        echo ""
        echo "💡 Para crear el archivo, ejecuta:"
        echo "   killall openvpn"
        echo "   openvpn --config /etc/openvpn/server.conf --status /var/log/openvpn-status.log 10"
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
            nombre_descriptivo=$(obtener_nombre "$cliente")
            
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

# Función para listar clientes (FILTRANDO SERVER)
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
        echo "   ℹ️  No se encuentra base de datos"
        return
    fi
    
    echo "Clientes ACTIVOS (🟢):"
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
            activos=$((activos + 1))
            nombre_descriptivo=$(obtener_nombre "$cliente")
            echo "   $activos) 🟢 $nombre_descriptivo ($cliente)"
        fi
    done < /tmp/activos.txt
    
    rm -f /tmp/activos.txt
    
    if [ $activos -eq 0 ]; then
        echo "   Ninguno"
    fi
    
    echo ""
    echo "Clientes BLOQUEADOS (🔴):"
    echo ""
    bloqueados=0
    grep "^R" "$INDEX_FILE" > /tmp/bloqueados.txt 2>/dev/null
    
    while read linea; do
        # Extraer el CN (Common Name)
        if echo "$linea" | grep -q "/CN="; then
            cliente=$(echo "$linea" | sed 's/.*\/CN=//' | awk '{print $1}')
        else
            cliente=$(echo "$linea" | awk '{print $NF}')
        fi
        
        # FILTRAR: No mostrar "server"
        if [ -n "$cliente" ] && [ "$cliente" != "unknown" ] && [ "$cliente" != "server" ]; then
            bloqueados=$((bloqueados + 1))
            nombre_descriptivo=$(obtener_nombre "$cliente")
            echo "   $bloqueados) 🔴 $nombre_descriptivo ($cliente)"
        fi
    done < /tmp/bloqueados.txt
    
    rm -f /tmp/bloqueados.txt
    
    if [ $bloqueados -eq 0 ]; then
        echo "   Ninguno"
    fi
    
    echo ""
    echo "📊 Total clientes (excluyendo server): $((activos + bloqueados))"
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
        echo "   Ejecuta: opkg update && opkg install iptables-nft"
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

# Función para bloquear cliente (FILTRANDO SERVER)
bloquear_cliente() {
    echo ""
    echo "🚫 BLOQUEAR CLIENTE"
    echo "==================="
    
    if ! command -v iptables >/dev/null 2>&1; then
        echo "❌ ERROR: iptables no instalado"
        echo ""
        echo "💡 En OpenWRT:"
        echo "   opkg update && opkg install iptables-nft"
        echo ""
        echo "⚠️  Sin iptables no se pueden bloquear IPs"
        return
    fi
    
    # Listar clientes activos (EXCLUYENDO SERVER)
    echo "Clientes disponibles para BLOQUEAR:"
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
        echo "   ℹ️  No hay clientes"
        return
    fi
    
    # Crear lista de clientes activos (EXCLUYENDO SERVER)
    grep "^V" "$INDEX_FILE" 2>/dev/null | while read linea; do
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
    
    if [ ! -f /tmp/clientes_raw.txt ]; then
        echo "   ℹ️  No hay clientes disponibles para bloquear"
        return
    fi
    
    # Mostrar clientes numerados
    num=0
    while read cliente; do
        num=$((num + 1))
        nombre_descriptivo=$(obtener_nombre "$cliente")
        echo "   $num) $nombre_descriptivo ($cliente)"
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
    
    echo ""
    echo "🔍 Buscando IPs de: $cliente_seleccionado"
    
    # Obtener IPs
    IPS=$(obtener_ips_cliente "$cliente_seleccionado")
    
    if [ -z "$IPS" ]; then
        echo "   ℹ️  No hay IPs registradas para este cliente"
        echo ""
        echo "💡 PARA REGISTRAR IPs:"
        echo "   1. Conecta el cliente VPN primero"
        echo "   2. Usa la opción 1 del menú (ver conectados)"
        echo "   3. O añade IPs manualmente con opción 7"
        return
    fi
    
    echo "   📋 IPs encontradas:"
    count=0
    for ip in $IPS; do
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
    echo ""
    
    # Bloquear cada IP
    bloqueadas=0
    errores=0
    for ip in $IPS; do
        if bloquear_ip "$ip" "$cliente_seleccionado"; then
            echo "   ✅ $ip - BLOQUEADA"
            bloqueadas=$((bloqueadas + 1))
        else
            echo "   ❌ $ip - Error al bloquear"
            errores=$((errores + 1))
        fi
    done
    
    # Añadir a lista de bloqueados
    if [ $bloqueadas -gt 0 ]; then
        echo "$cliente_seleccionado:$(date '+%Y-%m-%d %H:%M:%S')" >> "$SUSPENDED_FILE"
    fi
    
    echo ""
    if [ $errores -eq 0 ]; then
        echo "✅ CLIENTE BLOQUEADO EXITOSAMENTE"
    else
        echo "⚠️  Cliente bloqueado con $errores errores"
    fi
    echo "   👤 Cliente: $cliente_seleccionado"
    echo "   🛡️  IPs bloqueadas: $bloqueadas"
    echo ""
    echo "💡 Para ver las reglas activas: iptables -nL INPUT | grep DROP"
}

# Función para desbloquear cliente
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
    num=0
    while IFS=: read -r cliente fecha resto; do
        if [ -n "$cliente" ]; then
            num=$((num + 1))
            nombre_descriptivo=$(obtener_nombre "$cliente")
            echo "   $num) $nombre_descriptivo ($cliente) - $fecha"
            echo "$num:$cliente" >> /tmp/bloqueados_index.txt
        fi
    done < "$SUSPENDED_FILE"
    
    echo ""
    echo -n "Selecciona cliente (número): "
    read seleccion
    
    # Obtener cliente seleccionado
    cliente_seleccionado=""
    if [ -f /tmp/bloqueados_index.txt ]; then
        while IFS=: read -r num cliente; do
            if [ "$num" = "$seleccion" ]; then
                cliente_seleccionado="$cliente"
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
    
    # Obtener y desbloquear IPs
    IPS=$(obtener_ips_cliente "$cliente_seleccionado")
    if [ -n "$IPS" ]; then
        echo ""
        for ip in $IPS; do
            desbloquear_ip "$ip"
            echo "   ✅ $ip - DESBLOQUEADA"
        done
    else
        echo "   ℹ️  No hay IPs registradas para desbloquear"
    fi
    
    # Eliminar de lista de bloqueados
    grep -v "^$cliente_seleccionado:" "$SUSPENDED_FILE" > /tmp/suspended.tmp
    mv /tmp/suspended.tmp "$SUSPENDED_FILE"
    
    echo ""
    echo "✅ CLIENTE DESBLOQUEADO: $cliente_seleccionado"
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

# Dar permisos al nuevo comando
chmod +x /usr/bin/gestion

# También mantener el anterior por compatibilidad (opcional)
if [ -f "/usr/bin/gestor-vpn" ]; then
    echo "⚠️  Manteniendo gestor-vpn por compatibilidad"
    echo "   El nuevo comando es: gestion"
else
    # Crear enlace simbólico para mantener compatibilidad
    ln -sf /usr/bin/gestion /usr/bin/gestor-vpn 2>/dev/null
fi

echo ""
echo "✅ ACTUALIZACIÓN COMPLETADA"
echo ""
echo "🔧 MODIFICACIONES APLICADAS:"
echo "   1. ✅ Nuevo comando: 'gestion' (en lugar de 'gestor-vpn')"
echo "   2. ✅ Se filtra 'server' de las listas (opción 2 y 3)"
echo "   3. ✅ Texto cambiado: 'Clientes BLOQUEADOS' en lugar de 'revocados'"
echo "   4. ✅ Compatibilidad mantenida: 'gestor-vpn' sigue funcionando"
echo ""
echo "🚀 PARA USAR EL NUEVO SISTEMA:"
echo "   gestion"
echo ""
echo "📋 EJEMPLO DE USO:"
echo "   1. gestion"
echo "   2. Opción 5 → Asigna nombres a clientes"
echo "   3. Opción 7 → Registra IPs manualmente"
echo "   4. Opción 3 → Bloquea un cliente"
echo "   5. Opción 6 → Verifica estado"
echo ""
echo "💡 NOTA: El servidor (server) ya no aparece en las listas"
echo "   para evitar bloquearlo accidentalmente."
