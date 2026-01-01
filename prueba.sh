#!/bin/sh

echo ""
echo "🔧 CORRIGIENDO PARA FORMATO CSV"
echo "================================"

cat > /usr/bin/gestion << 'EOF'
#!/bin/sh

# Archivos de configuración
NOMBRES_FILE="/etc/openvpn/clientes/nombres.txt"
IP_HISTORY_FILE="/etc/openvpn/clientes/ip_history.txt"
SUSPENDED_FILE="/etc/openvpn/clientes/suspended.txt"
LOG_FILE="/etc/openvpn/clientes/vpn_gestion.log"

# Crear archivos si no existen
mkdir -p /etc/openvpn/clientes
touch "$NOMBRES_FILE" "$IP_HISTORY_FILE" "$SUSPENDED_FILE" "$LOG_FILE"

# Función para escribir en log
escribir_log() {
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" >> "$LOG_FILE"
}

# Función para limpiar nombre de certificado
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
    echo "🔧 GESTIÓN VPN"
    echo "=============="
    echo ""
    echo "1) 👁️  Ver clientes conectados"
    echo "2) 📋 Listar estado de clientes"
    echo "3) 🚫 BLOQUEAR cliente"
    echo "4) ✅ DESBLOQUEAR cliente"
    echo "5) 🏷️  Gestionar nombres"
    echo "6) 🔍 Estado del sistema"
    echo "7) 📝 Registrar IP manualmente"
    echo "8) 📊 Ver LOG del sistema"
    echo "9) ❌ Salir"
    echo ""
    echo -n "Selecciona [1-9]: "
}

# FUNCIÓN CORREGIDA - MANEJA FORMATO CSV
ver_conectados() {
    echo ""
    echo "📊 CLIENTES CONECTADOS"
    echo "======================"
    echo ""
    
    escribir_log "Buscando clientes conectados"
    
    fecha_hora_actual=$(date '+%d/%m/%Y %H:%M')
    echo "🕒 Fecha actual: $fecha_hora_actual"
    echo ""
    
    # PRIMERO: Usar el archivo principal que SÍ tiene datos
    STATUS_FILE="/tmp/run/openvpn.VPN_Server.status"
    
    if [ ! -f "$STATUS_FILE" ] || [ ! -s "$STATUS_FILE" ]; then
        echo "❌ Archivo de estado no encontrado o vacío: $STATUS_FILE"
        return
    fi
    
    echo "✅ Usando archivo: $STATUS_FILE"
    echo "📏 Tamaño: $(wc -l < "$STATUS_FILE") líneas"
    echo ""
    
    # Detectar formato del archivo
    primera_linea=$(head -1 "$STATUS_FILE")
    
    if echo "$primera_linea" | grep -q "OpenVPN CLIENT LIST"; then
        echo "📋 Formato detectado: OpenVPN CSV con comas"
        echo ""
        
        # Saltar las primeras 2 líneas de encabezado
        # Línea 1: "OpenVPN CLIENT LIST"
        # Línea 2: "Updated,fecha"
        # Línea 3: "Common Name,Real Address,Bytes Received,Bytes Sent,Connected Since"
        # Línea 4+: Datos reales
        
        # Buscar líneas con datos (después del encabezado)
        tail -n +4 "$STATUS_FILE" > /tmp/clientes_temp.txt 2>/dev/null
        
        if [ ! -s /tmp/clientes_temp.txt ]; then
            echo "ℹ️  No hay clientes conectados"
            rm -f /tmp/clientes_temp.txt
            
            # Mostrar si hay alguna sección ROUTING_TABLE
            if grep -q "ROUTING_TABLE" "$STATUS_FILE"; then
                echo ""
                echo "🔍 Buscando en ROUTING_TABLE..."
                sed -n '/^ROUTING_TABLE/,/^GLOBAL_STATS/p' "$STATUS_FILE" | grep -v "^ROUTING_TABLE\|^GLOBAL_STATS" > /tmp/routing_temp.txt
                
                if [ -s /tmp/routing_temp.txt ]; then
                    echo "✅ Clientes en enrutamiento:"
                    echo ""
                    cat /tmp/routing_temp.txt | while read linea; do
                        cliente=$(echo "$linea" | cut -d',' -f1)
                        ip=$(echo "$linea" | cut -d',' -f2)
                        if [ -n "$cliente" ] && [ "$cliente" != "Common Name" ]; then
                            nombre=$(obtener_nombre "$cliente")
                            echo "👤 $nombre ($cliente)"
                            echo "   📍 IP: $ip"
                            echo ""
                        fi
                    done
                fi
                rm -f /tmp/routing_temp.txt
            fi
            
            return
        fi
        
        echo "👥 CLIENTES ENCONTRADOS:"
        echo ""
        
        clientes_encontrados=0
        
        while IFS= read -r linea; do
            # Formato CSV: Common Name,Real Address,Bytes Received,Bytes Sent,Connected Since
            # Ejemplo: client2,83.36.234.252:43295,2045818,47809865983,2025-12-03 10:41:58
            
            # Separar por comas
            IFS=, read -r cliente ip_puerto bytes_rx bytes_tx fecha_hora <<< "$linea"
            
            if [ -n "$cliente" ] && [ "$cliente" != "Common Name" ]; then
                clientes_encontrados=$((clientes_encontrados + 1))
                cliente_limpio=$(limpiar_nombre "$cliente")
                nombre_descriptivo=$(obtener_nombre "$cliente")
                
                # Extraer IP (sin puerto si existe)
                ip_externa=$(echo "$ip_puerto" | cut -d: -f1)
                puerto=$(echo "$ip_puerto" | cut -d: -f2)
                
                echo "👤 $nombre_descriptivo"
                echo "   🔑 Certificado: $cliente_limpio"
                
                if [ -n "$puerto" ] && [ "$puerto" != "$ip_externa" ]; then
                    echo "   🌐 IP: $ip_externa:$puerto"
                else
                    echo "   🌐 IP: $ip_externa"
                fi
                
                if [ -n "$bytes_rx" ] && echo "$bytes_rx" | grep -q '^[0-9]\+$'; then
                    if [ "$bytes_rx" -gt 1048576 ]; then
                        echo "   📥 Descargado: $(echo "$bytes_rx" | awk '{printf "%.2f MB", $1/1024/1024}')"
                    else
                        echo "   📥 Descargado: $(echo "$bytes_rx" | awk '{printf "%.2f KB", $1/1024}')"
                    fi
                fi
                
                if [ -n "$bytes_tx" ] && echo "$bytes_tx" | grep -q '^[0-9]\+$'; then
                    if [ "$bytes_tx" -gt 1048576 ]; then
                        echo "   📤 Enviado: $(echo "$bytes_tx" | awk '{printf "%.2f MB", $1/1024/1024}')"
                    else
                        echo "   📤 Enviado: $(echo "$bytes_tx" | awk '{printf "%.2f KB", $1/1024}')"
                    fi
                fi
                
                if [ -n "$fecha_hora" ]; then
                    echo "   🕒 Conectado: $fecha_hora"
                fi
                
                # Registrar en historial
                timestamp_actual=$(date '+%Y-%m-%d %H:%M:%S')
                grep -v "^$cliente_limpio:$ip_externa:" "$IP_HISTORY_FILE" > /tmp/ip_temp.txt 2>/dev/null
                mv /tmp/ip_temp.txt "$IP_HISTORY_FILE" 2>/dev/null
                echo "$cliente_limpio:$ip_externa:$timestamp_actual:$fecha_hora" >> "$IP_HISTORY_FILE"
                
                echo ""
            fi
        done < /tmp/clientes_temp.txt
        
        rm -f /tmp/clientes_temp.txt
        
        if [ $clientes_encontrados -eq 0 ]; then
            echo "ℹ️  No hay clientes conectados en este momento"
        else
            echo "📊 RESUMEN: $clientes_encontrados cliente(s) conectado(s)"
            escribir_log "Encontrados $clientes_encontrados clientes conectados"
        fi
        
    elif echo "$primera_linea" | grep -q "^CLIENT_LIST"; then
        echo "📋 Formato detectado: CLIENT_LIST con espacios"
        echo ""
        
        # Tu código original para formato con espacios
        grep "^CLIENT_LIST" "$STATUS_FILE" | grep -v "UNDEF" > /tmp/clientes_temp.txt 2>/dev/null
        
        if [ ! -s /tmp/clientes_temp.txt ]; then
            echo "ℹ️  No hay clientes conectados"
            rm -f /tmp/clientes_temp.txt
            return
        fi
        
        echo "👥 CLIENTES ENCONTRADOS:"
        echo ""
        
        while read linea; do
            cliente=$(echo "$linea" | awk '{print $2}')
            ip_puerto=$(echo "$linea" | awk '{print $3}')
            fecha=$(echo "$linea" | awk '{print $7}')
            hora=$(echo "$linea" | awk '{print $8}')
            
            if [ -n "$cliente" ] && [ "$cliente" != "UNDEF" ]; then
                cliente_limpio=$(limpiar_nombre "$cliente")
                nombre_descriptivo=$(obtener_nombre "$cliente")
                
                echo "👤 $nombre_descriptivo"
                echo "   🔑 Certificado: $cliente_limpio"
                echo "   📍 IP: $ip_puerto"
                if [ -n "$fecha" ] && [ -n "$hora" ]; then
                    echo "   🕒 Conectado: $fecha $hora"
                fi
                echo ""
            fi
        done < /tmp/clientes_temp.txt
        
        rm -f /tmp/clientes_temp.txt
        
    else
        echo "⚠️  Formato de archivo no reconocido"
        echo ""
        echo "📄 Primeras líneas:"
        head -5 "$STATUS_FILE" | while read line; do
            echo "   $line"
        done
    fi
    
    # Mostrar información adicional
    echo ""
    echo "💡 INFORMACIÓN ADICIONAL:"
    echo "   📁 Archivo usado: $STATUS_FILE"
    echo "   📅 Última actualización: $(grep "^Updated," "$STATUS_FILE" 2>/dev/null | cut -d',' -f2 || echo "Desconocida")"
    
    # Verificar interfaz VPN
    if ip link show tap0 >/dev/null 2>&1; then
        echo "   🔗 Interfaz tap0: ACTIVA"
        echo "   🏠 IP local VPN: $(ip addr show tap0 2>/dev/null | grep 'inet ' | awk '{print $2}' || echo "No configurada")"
    fi
}

# Función para listar estado de clientes
listar_clientes() {
    echo ""
    echo "📋 ESTADO DE CLIENTES"
    echo "===================="
    echo ""
    
    echo "🎯 CLIENTES CON IPs REGISTRADAS:"
    echo ""
    
    if [ -f "$IP_HISTORY_FILE" ] && [ -s "$IP_HISTORY_FILE" ]; then
        cut -d: -f1 "$IP_HISTORY_FILE" | sort -u > /tmp/unicos.txt
        
        contador=0
        while read cliente; do
            if [ -n "$cliente" ]; then
                contador=$((contador + 1))
                nombre=$(obtener_nombre "$cliente")
                
                if grep -q "^$cliente:" "$SUSPENDED_FILE" 2>/dev/null; then
                    estado="🚫 BLOQUEADO"
                else
                    estado="🟢 ACTIVO"
                fi
                
                ips=$(grep -c "^$cliente:" "$IP_HISTORY_FILE")
                
                echo "   $contador) $nombre ($cliente)"
                echo "      Estado: $estado"
                echo "      IPs registradas: $ips"
                echo ""
            fi
        done < /tmp/unicos.txt
        
        rm -f /tmp/unicos.txt
        
        if [ $contador -eq 0 ]; then
            echo "   📭 No hay clientes registrados"
        fi
    else
        echo "   📭 No hay IPs registradas"
    fi
    
    echo ""
    echo "🚫 CLIENTES BLOQUEADOS:"
    echo ""
    
    if [ -s "$SUSPENDED_FILE" ]; then
        contador=0
        while IFS=: read -r cliente fecha resto; do
            if [ -n "$cliente" ]; then
                contador=$((contador + 1))
                nombre=$(obtener_nombre "$cliente")
                echo "   $contador) $nombre ($cliente) - $fecha"
            fi
        done < "$SUSPENDED_FILE"
    else
        echo "   ✅ No hay clientes bloqueados"
    fi
}

# Función para bloquear cliente
bloquear_cliente() {
    echo ""
    echo "🚫 BLOQUEAR CLIENTE"
    echo "==================="
    echo ""
    
    if [ ! -f "$IP_HISTORY_FILE" ] || [ ! -s "$IP_HISTORY_FILE" ]; then
        echo "❌ No hay clientes registrados para bloquear"
        return
    fi
    
    echo "Clientes disponibles:"
    echo ""
    
    cut -d: -f1 "$IP_HISTORY_FILE" | sort -u > /tmp/lista_clientes.txt
    
    contador=0
    while read cliente; do
        if [ -n "$cliente" ]; then
            contador=$((contador + 1))
            nombre=$(obtener_nombre "$cliente")
            
            if grep -q "^$cliente:" "$SUSPENDED_FILE" 2>/dev/null; then
                echo "   $contador) $nombre ($cliente) [YA BLOQUEADO]"
            else
                echo "   $contador) $nombre ($cliente)"
            fi
            
            echo "$contador:$cliente" >> /tmp/clientes_ref.txt
        fi
    done < /tmp/lista_clientes.txt
    
    if [ $contador -eq 0 ]; then
        echo "   📭 No hay clientes disponibles"
        rm -f /tmp/lista_clientes.txt /tmp/clientes_ref.txt
        return
    fi
    
    echo ""
    echo -n "Selecciona cliente (número): "
    read seleccion
    
    cliente_seleccionado=""
    if [ -f /tmp/clientes_ref.txt ]; then
        while IFS=: read -r num cliente; do
            if [ "$num" = "$seleccion" ]; then
                cliente_seleccionado="$cliente"
                break
            fi
        done < /tmp/clientes_ref.txt
    fi
    
    rm -f /tmp/lista_clientes.txt /tmp/clientes_ref.txt
    
    if [ -z "$cliente_seleccionado" ]; then
        echo "❌ Selección inválida"
        return
    fi
    
    echo ""
    echo "🔍 Obteniendo IPs de: $cliente_seleccionado"
    
    IPS=$(grep "^$cliente_seleccionado:" "$IP_HISTORY_FILE" | cut -d: -f2 | sort -u)
    
    if [ -z "$IPS" ]; then
        echo "ℹ️  No hay IPs registradas para este cliente"
        echo -n "¿Continuar con bloqueo básico? (s/N): "
        read confirmar
        if [ "$confirmar" != "s" ] && [ "$confirmar" != "S" ]; then
            echo "❌ Operación cancelada"
            return
        fi
    else
        echo "📋 IPs encontradas:"
        for ip in $IPS; do
            echo "   📍 $ip"
        done
    fi
    
    echo ""
    echo -n "¿Confirmar BLOQUEO? (s/N): "
    read confirmar
    
    if [ "$confirmar" != "s" ] && [ "$confirmar" != "S" ]; then
        echo "❌ Operación cancelada"
        return
    fi
    
    echo ""
    echo "🛡️  Ejecutando bloqueo..."
    
    if ! grep -q "^$cliente_seleccionado:" "$SUSPENDED_FILE" 2>/dev/null; then
        echo "$cliente_seleccionado:$(date '+%Y-%m-%d %H:%M:%S')" >> "$SUSPENDED_FILE"
        echo "✅ Cliente añadido a lista de bloqueados"
    else
        echo "ℹ️  Cliente ya estaba en lista de bloqueados"
    fi
    
    if command -v iptables >/dev/null 2>&1; then
        echo "🔒 Configurando firewall..."
        for ip in $IPS; do
            ip_sin_puerto=$(echo "$ip" | cut -d: -f1)
            
            if iptables -I INPUT -s "$ip_sin_puerto" -j DROP 2>/dev/null; then
                echo "   ✅ $ip_sin_puerto - BLOQUEADA"
            else
                echo "   ⚠️  $ip_sin_puerto - Error"
            fi
        done
    else
        echo "ℹ️  iptables no disponible, solo bloqueo en lista"
    fi
    
    echo ""
    echo "✅ BLOQUEO COMPLETADO"
    echo "   👤 Cliente: $cliente_seleccionado"
    if [ -n "$IPS" ]; then
        echo "   🔒 IPs bloqueadas: $(echo "$IPS" | wc -w)"
    fi
}

# Función para desbloquear cliente
desbloquear_cliente() {
    echo ""
    echo "✅ DESBLOQUEAR CLIENTE"
    echo "======================"
    echo ""
    
    if [ ! -s "$SUSPENDED_FILE" ]; then
        echo "✅ No hay clientes bloqueados"
        return
    fi
    
    echo "Clientes BLOQUEADOS:"
    echo ""
    
    contador=0
    while IFS=: read -r cliente fecha resto; do
        if [ -n "$cliente" ]; then
            contador=$((contador + 1))
            nombre=$(obtener_nombre "$cliente")
            echo "   $contador) $nombre ($cliente) - $fecha"
            echo "$contador:$cliente" >> /tmp/bloqueados_ref.txt
        fi
    done < "$SUSPENDED_FILE"
    
    echo ""
    echo -n "Selecciona cliente (número): "
    read seleccion
    
    cliente_seleccionado=""
    if [ -f /tmp/bloqueados_ref.txt ]; then
        while IFS=: read -r num cliente; do
            if [ "$num" = "$seleccion" ]; then
                cliente_seleccionado="$cliente"
                break
            fi
        done < /tmp/bloqueados_ref.txt
        rm -f /tmp/bloqueados_ref.txt
    fi
    
    if [ -z "$cliente_seleccionado" ]; then
        echo "❌ Selección inválida"
        return
    fi
    
    echo ""
    echo -n "¿Confirmar DESBLOQUEO de $cliente_seleccionado? (s/N): "
    read confirmar
    
    if [ "$confirmar" != "s" ] && [ "$confirmar" != "S" ]; then
        echo "❌ Operación cancelada"
        return
    fi
    
    echo ""
    echo "🔓 Ejecutando desbloqueo..."
    
    grep -v "^$cliente_seleccionado:" "$SUSPENDED_FILE" > /tmp/suspended_temp.txt
    mv /tmp/suspended_temp.txt "$SUSPENDED_FILE"
    echo "✅ Cliente eliminado de lista de bloqueados"
    
    IPS=$(grep "^$cliente_seleccionado:" "$IP_HISTORY_FILE" | cut -d: -f2 | sort -u)
    
    if command -v iptables >/dev/null 2>&1 && [ -n "$IPS" ]; then
        echo "🔓 Desbloqueando IPs en firewall..."
        for ip in $IPS; do
            ip_sin_puerto=$(echo "$ip" | cut -d: -f1)
            iptables -D INPUT -s "$ip_sin_puerto" -j DROP 2>/dev/null
            echo "   ✅ $ip_sin_puerto - DESBLOQUEADA"
        done
    fi
    
    echo ""
    echo "✅ CLIENTE DESBLOQUEADO"
    echo "   👤 Cliente: $cliente_seleccionado"
}

# Función para gestionar nombres
gestionar_nombres() {
    while true; do
        echo ""
        echo "🏷️  GESTIONAR NOMBRES"
        echo "===================="
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
                
                cliente=$(echo "$cliente" | sed 's|/CN=||')
                
                if [ -n "$cliente" ] && [ -n "$nombre" ]; then
                    grep -v "^$cliente:" "$NOMBRES_FILE" > /tmp/nombres_temp.txt
                    echo "$cliente:$nombre" >> /tmp/nombres_temp.txt
                    mv /tmp/nombres_temp.txt "$NOMBRES_FILE"
                    
                    echo ""
                    echo "✅ NOMBRE ASIGNADO:"
                    echo "   📋 Certificado: $cliente"
                    echo "   🏷️  Nombre: $nombre"
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
                contador=0
                while IFS=: read -r cliente nombre; do
                    contador=$((contador + 1))
                    echo "   $contador) $nombre ($cliente)"
                    echo "$contador:$cliente" >> /tmp/eliminar_ref.txt
                done < "$NOMBRES_FILE"
                
                echo ""
                echo -n "Número: "
                read seleccion
                
                cliente_eliminar=""
                if [ -f /tmp/eliminar_ref.txt ]; then
                    while IFS=: read -r num cliente; do
                        if [ "$num" = "$seleccion" ]; then
                            cliente_eliminar="$cliente"
                            break
                        fi
                    done < /tmp/eliminar_ref.txt
                    rm -f /tmp/eliminar_ref.txt
                fi
    
                if [ -z "$cliente_eliminar" ]; then
                    echo "❌ Selección inválida"
                    continue
                fi
    
                echo ""
                echo -n "¿Eliminar nombre de '$cliente_eliminar'? (s/N): "
                read confirmar
                
                if [ "$confirmar" = "s" ] || [ "$confirmar" = "S" ]; then
                    grep -v "^$cliente_eliminar:" "$NOMBRES_FILE" > /tmp/nombres_temp.txt
                    mv /tmp/nombres_temp.txt "$NOMBRES_FILE"
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
    
    echo -n "Nombre del cliente (SIN /CN=): "
    read cliente
    
    cliente=$(echo "$cliente" | sed 's|/CN=||')
    
    if [ -z "$cliente" ]; then
        echo "❌ Debes ingresar un nombre"
        return
    fi
    
    echo -n "IP a registrar: "
    read ip
    
    if [ -z "$ip" ]; then
        echo "❌ Debes ingresar una IP"
        return
    fi
    
    fecha_conexion=$(date '+%d/%m/%Y %H:%M')
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    grep -v "^$cliente:$ip:" "$IP_HISTORY_FILE" > /tmp/ip_temp.txt 2>/dev/null
    mv /tmp/ip_temp.txt "$IP_HISTORY_FILE" 2>/dev/null
    echo "$cliente:$ip:$timestamp:$fecha_conexion" >> "$IP_HISTORY_FILE"
    
    echo ""
    echo "✅ IP REGISTRADA"
    echo "   👤 Cliente: $cliente"
    echo "   📍 IP: $ip"
    echo "   🕒 Fecha: $fecha_conexion"
}

# Función para estado del sistema
estado_servicio() {
    echo ""
    echo "🔍 ESTADO DEL SISTEMA"
    echo "===================="
    echo ""
    
    if pgrep openvpn >/dev/null; then
        echo "✅ OpenVPN: ACTIVO"
    else
        echo "❌ OpenVPN: INACTIVO"
    fi
    
    echo ""
    echo "🛡️  IPTABLES:"
    if command -v iptables >/dev/null 2>&1; then
        echo "   ✅ Instalado"
    else
        echo "   ❌ No instalado"
    fi
    
    echo ""
    echo "📁 ARCHIVOS DEL SISTEMA:"
    
    if [ -f "/tmp/run/openvpn.VPN_Server.status" ]; then
        lineas=$(wc -l < "/tmp/run/openvpn.VPN_Server.status")
        echo "   ✅ /tmp/run/openvpn.VPN_Server.status ($lineas líneas)"
        
        # Mostrar última actualización
        updated=$(grep "^Updated," "/tmp/run/openvpn.VPN_Server.status" | cut -d',' -f2)
        if [ -n "$updated" ]; then
            echo "   📅 Última actualización: $updated"
        fi
    else
        echo "   ❌ Archivo de estado no encontrado"
    fi
    
    echo ""
    echo "📊 ESTADÍSTICAS:"
    
    nombres=$(grep -c ":" "$NOMBRES_FILE" 2>/dev/null || echo 0)
    echo "   👥 Nombres asignados: $nombres"
    
    ips=$(wc -l < "$IP_HISTORY_FILE" 2>/dev/null || echo 0)
    echo "   📍 IPs registradas: $ips"
    
    bloqueados=$(wc -l < "$SUSPENDED_FILE" 2>/dev/null || echo 0)
    echo "   🚫 Clientes bloqueados: $bloqueados"
}

# Función para ver LOG del sistema
ver_log() {
    echo ""
    echo "📜 REGISTRO DEL SISTEMA"
    echo "======================"
    echo ""
    
    if [ ! -f "$LOG_FILE" ] || [ ! -s "$LOG_FILE" ]; then
        echo "📭 El archivo de log está vacío"
        return
    fi
    
    echo "Últimas 20 entradas:"
    echo ""
    tail -20 "$LOG_FILE" | while read linea; do
        echo "   $linea"
    done
    
    echo ""
    echo "Total de entradas: $(wc -l < "$LOG_FILE")"
}

# Programa principal
escribir_log "Sistema de gestión VPN iniciado"

while true; do
    mostrar_menu
    read opcion
    
    escribir_log "Opción seleccionada: $opcion"
    
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
            escribir_log "Sistema finalizado"
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

chmod +x /usr/bin/gestion

echo ""
echo "✅ SISTEMA CORREGIDO"
echo ""
echo "🔧 CAMBIOS REALIZADOS:"
echo "   1. ✅ DETECTA FORMATO CSV:"
echo "      - Ahora maneja 'OpenVPN CLIENT LIST' con comas"
echo "      - Formato: Common Name,Real Address,Bytes Received,Bytes Sent,Connected Since"
echo ""
echo "   2. ✅ USA EL ARCHIVO CORRECTO:"
echo "      - Usa /tmp/run/openvpn.VPN_Server.status"
echo "      - Este archivo SÍ tiene datos en formato CSV"
echo ""
echo "   3. ✅ PROCESA CORRECTAMENTE:"
echo "      - Salta encabezados (líneas 1-3)"
echo "      - Lee datos reales desde línea 4"
echo "      - Muestra tráfico en KB/MB"
echo "      - Registra en historial"
echo ""
echo "📋 EJEMPLO DE SALIDA ESPERADA:"
echo ""
echo "📊 CLIENTES CONECTADOS"
echo "======================"
echo ""
echo "🕒 Fecha actual: 02/01/2026 00:10"
echo ""
echo "✅ Usando archivo: /tmp/run/openvpn.VPN_Server.status"
echo "📏 Tamaño: 8 líneas"
echo ""
echo "📋 Formato detectado: OpenVPN CSV con comas"
echo ""
echo "👥 CLIENTES ENCONTRADOS:"
echo ""
echo "👤 Cris"
echo "   🔑 Certificado: client2"
echo "   🌐 IP: 83.36.234.252:43295"
echo "   📥 Descargado: 1.95 MB"
echo "   📤 Enviado: 45598.76 MB"
echo "   🕒 Conectado: 2025-12-03 10:41:58"
echo ""
echo "📊 RESUMEN: 1 cliente(s) conectado(s)"
echo ""
echo "💡 INFORMACIÓN ADICIONAL:"
echo "   📁 Archivo usado: /tmp/run/openvpn.VPN_Server.status"
echo "   📅 Última actualización: 2026-01-02 00:09:48"
echo ""
echo "🚀 Ejecuta: gestion"
