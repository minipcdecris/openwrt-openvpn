#!/bin/sh

echo ""
echo "🔧 INSTALANDO SISTEMA DE GESTIÓN VPN CORREGIDO"
echo "=============================================="

# Crear directorio para archivos de configuración
mkdir -p /etc/openvpn/clientes

# Crear script principal corregido
cat > /usr/bin/gestion << 'EOF'
#!/bin/sh

# Archivos de configuración
NOMBRES_FILE="/etc/openvpn/clientes/nombres.txt"
IP_HISTORY_FILE="/etc/openvpn/clientes/ip_history.txt"
SUSPENDED_FILE="/etc/openvpn/clientes/suspended.txt"
LOG_FILE="/etc/openvpn/clientes/vpn_gestion.log"

# Crear archivos si no existen
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
    echo "🔧 GESTIÓN VPN - SISTEMA COMPLETO"
    echo "=================================="
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

# FUNCIÓN VER_CONECTADOS SIMPLIFICADA Y FUNCIONAL
ver_conectados() {
    echo ""
    echo "📊 CLIENTES CONECTADOS"
    echo "======================"
    echo ""
    
    escribir_log "Buscando clientes conectados"
    
    # Buscar archivo de estado en ubicaciones comunes
    STATUS_FILE=""
    
    # Lista de ubicaciones posibles (priorizando las tuyas)
    if [ -f "/etc/openvpn/openvpn-status.log" ]; then
        STATUS_FILE="/etc/openvpn/openvpn-status.log"
    elif [ -f "/tmp/run/openvpn.VPN_Server.status" ]; then
        STATUS_FILE="/tmp/run/openvpn.VPN_Server.status"
    elif [ -f "/var/log/openvpn-status.log" ]; then
        STATUS_FILE="/var/log/openvpn-status.log"
    elif [ -f "/tmp/openvpn-status.log" ]; then
        STATUS_FILE="/tmp/openvpn-status.log"
    else
        echo "❌ No se encuentra archivo de estado"
        echo ""
        echo "💡 Archivos encontrados en tu sistema:"
        echo "   /etc/openvpn/openvpn-status.log"
        echo "   /tmp/run/openvpn.VPN_Server.status"
        echo ""
        echo "⚠️  Verifica que OpenVPN esté configurado con:"
        echo "   status /etc/openvpn/openvpn-status.log"
        escribir_log "No se encuentra archivo de estado"
        return
    fi
    
    echo "✅ Usando archivo: $STATUS_FILE"
    
    # Verificar si el archivo tiene contenido
    if [ ! -s "$STATUS_FILE" ]; then
        echo "ℹ️  El archivo de estado está vacío"
        echo "   No hay clientes conectados o OpenVPN no ha generado datos"
        escribir_log "Archivo de estado vacío"
        return
    fi
    
    # Obtener fecha actual
    fecha_hora_actual=$(date '+%d/%m/%Y %H:%M')
    echo "🕒 Fecha actual: $fecha_hora_actual"
    echo ""
    
    # Buscar clientes en CLIENT_LIST (formato con espacios)
    if grep -q "^CLIENT_LIST" "$STATUS_FILE"; then
        echo "🔍 Buscando clientes conectados..."
        
        # Filtrar líneas con datos reales
        grep "^CLIENT_LIST" "$STATUS_FILE" | grep -v "UNDEF" > /tmp/clientes_temp.txt 2>/dev/null
        
        if [ ! -s /tmp/clientes_temp.txt ]; then
            echo "ℹ️  No hay clientes conectados"
            rm -f /tmp/clientes_temp.txt
            return
        fi
        
        # Procesar cada cliente
        while read linea; do
            # Formato: CLIENT_LIST client2 83.36.234.252:43295 10.8.0.2 2045818 47809865983 2025-12-03 10:41:58 1764754918 UNDEF 0 AES-256-GCM
            cliente=$(echo "$linea" | awk '{print $2}')
            ip_puerto=$(echo "$linea" | awk '{print $3}')
            ip_interna=$(echo "$linea" | awk '{print $4}')
            fecha_conexion=$(echo "$linea" | awk '{print $7}')
            hora_conexion=$(echo "$linea" | awk '{print $8}')
            
            if [ -n "$cliente" ] && [ "$cliente" != "UNDEF" ]; then
                cliente_limpio=$(limpiar_nombre "$cliente")
                nombre_descriptivo=$(obtener_nombre "$cliente")
                
                # Extraer IP (sin puerto)
                ip_externa=$(echo "$ip_puerto" | cut -d: -f1)
                puerto=$(echo "$ip_puerto" | cut -d: -f2)
                
                # Registrar en historial
                timestamp_actual=$(date '+%Y-%m-%d %H:%M:%S')
                
                # Eliminar entrada antigua si existe
                grep -v "^$cliente_limpio:$ip_externa:" "$IP_HISTORY_FILE" > /tmp/ip_temp.txt 2>/dev/null
                mv /tmp/ip_temp.txt "$IP_HISTORY_FILE" 2>/dev/null
                
                # Añadir nueva entrada
                echo "$cliente_limpio:$ip_externa:$timestamp_actual:$fecha_conexion $hora_conexion" >> "$IP_HISTORY_FILE"
                
                # Mostrar información
                echo "👤 $nombre_descriptivo"
                echo "   🔑 Certificado: $cliente_limpio"
                
                if [ -n "$puerto" ]; then
                    echo "   🌐 IP: $ip_externa:$puerto"
                else
                    echo "   🌐 IP: $ip_externa"
                fi
                
                if [ -n "$ip_interna" ] && [ "$ip_interna" != "UNDEF" ]; then
                    echo "   🏠 VPN: $ip_interna"
                fi
                
                if [ -n "$fecha_conexion" ] && [ -n "$hora_conexion" ]; then
                    echo "   🕒 Conectado: $fecha_conexion $hora_conexion"
                fi
                
                echo ""
            fi
        done < /tmp/clientes_temp.txt
        
        rm -f /tmp/clientes_temp.txt
        escribir_log "Clientes mostrados correctamente"
        
    else
        echo "⚠️  Formato de archivo no reconocido"
        echo ""
        echo "📄 Primeras líneas del archivo:"
        head -3 "$STATUS_FILE" | while read line; do
            echo "   $line"
        done
    fi
}

# Función para listar estado de clientes (simplificada)
listar_clientes() {
    echo ""
    echo "📋 ESTADO DE CLIENTES"
    echo "===================="
    echo ""
    
    echo "🎯 CLIENTES CON IPs REGISTRADAS:"
    echo ""
    
    if [ -f "$IP_HISTORY_FILE" ] && [ -s "$IP_HISTORY_FILE" ]; then
        # Obtener lista única de clientes
        cut -d: -f1 "$IP_HISTORY_FILE" | sort -u > /tmp/unicos.txt
        
        contador=0
        while read cliente; do
            if [ -n "$cliente" ]; then
                contador=$((contador + 1))
                nombre=$(obtener_nombre "$cliente")
                
                # Verificar si está bloqueado
                if grep -q "^$cliente:" "$SUSPENDED_FILE" 2>/dev/null; then
                    estado="🚫 BLOQUEADO"
                else
                    estado="🟢 ACTIVO"
                fi
                
                # Contar IPs registradas
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

# Función para bloquear cliente (simplificada)
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
    
    # Listar clientes únicos
    cut -d: -f1 "$IP_HISTORY_FILE" | sort -u > /tmp/lista_clientes.txt
    
    contador=0
    while read cliente; do
        if [ -n "$cliente" ]; then
            contador=$((contador + 1))
            nombre=$(obtener_nombre "$cliente")
            
            # Verificar si ya está bloqueado
            if grep -q "^$cliente:" "$SUSPENDED_FILE" 2>/dev/null; then
                echo "   $contador) $nombre ($cliente) [YA BLOQUEADO]"
            else
                echo "   $contador) $nombre ($cliente)"
            fi
            
            # Guardar referencia
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
    
    # Buscar cliente seleccionado
    cliente_seleccionado=""
    if [ -f /tmp/clientes_ref.txt ]; then
        while IFS=: read -r num cliente; do
            if [ "$num" = "$seleccion" ]; then
                cliente_seleccionado="$cliente"
                break
            fi
        done < /tmp/clientes_ref.txt
    fi
    
    # Limpiar archivos temporales
    rm -f /tmp/lista_clientes.txt /tmp/clientes_ref.txt
    
    if [ -z "$cliente_seleccionado" ]; then
        echo "❌ Selección inválida"
        return
    fi
    
    echo ""
    echo "🔍 Obteniendo IPs de: $cliente_seleccionado"
    
    # Obtener IPs del cliente
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
    
    # Añadir a lista de bloqueados
    if ! grep -q "^$cliente_seleccionado:" "$SUSPENDED_FILE" 2>/dev/null; then
        echo "$cliente_seleccionado:$(date '+%Y-%m-%d %H:%M:%S')" >> "$SUSPENDED_FILE"
        echo "✅ Cliente añadido a lista de bloqueados"
    else
        echo "ℹ️  Cliente ya estaba en lista de bloqueados"
    fi
    
    # Intentar bloquear IPs con iptables si está disponible
    if command -v iptables >/dev/null 2>&1; then
        echo "🔒 Configurando firewall..."
        for ip in $IPS; do
            # Extraer IP sin puerto
            ip_sin_puerto=$(echo "$ip" | cut -d: -f1)
            
            # Bloquear IP
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

# Función para desbloquear cliente (simplificada)
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
    
    # Buscar cliente seleccionado
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
    
    # Eliminar de lista de bloqueados
    grep -v "^$cliente_seleccionado:" "$SUSPENDED_FILE" > /tmp/suspended_temp.txt
    mv /tmp/suspended_temp.txt "$SUSPENDED_FILE"
    echo "✅ Cliente eliminado de lista de bloqueados"
    
    # Obtener IPs del cliente para desbloquear
    IPS=$(grep "^$cliente_seleccionado:" "$IP_HISTORY_FILE" | cut -d: -f2 | sort -u)
    
    # Intentar desbloquear IPs con iptables si está disponible
    if command -v iptables >/dev/null 2>&1 && [ -n "$IPS" ]; then
        echo "🔓 Desbloqueando IPs en firewall..."
        for ip in $IPS; do
            # Extraer IP sin puerto
            ip_sin_puerto=$(echo "$ip" | cut -d: -f1)
            
            # Desbloquear IP
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
                
                # Limpiar /CN= si lo pusieron
                cliente=$(echo "$cliente" | sed 's|/CN=||')
                
                if [ -n "$cliente" ] && [ -n "$nombre" ]; then
                    # Eliminar entrada existente
                    grep -v "^$cliente:" "$NOMBRES_FILE" > /tmp/nombres_temp.txt
                    # Añadir nueva
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
                
                # Buscar cliente a eliminar
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
    
    # Limpiar /CN= si lo pusieron
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
    
    # Eliminar entrada antigua si existe
    grep -v "^$cliente:$ip:" "$IP_HISTORY_FILE" > /tmp/ip_temp.txt 2>/dev/null
    mv /tmp/ip_temp.txt "$IP_HISTORY_FILE" 2>/dev/null
    
    # Añadir nueva entrada
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
    
    # Archivo de estado
    echo ""
    echo "📄 ARCHIVO DE ESTADO VPN:"
    if [ -f "/etc/openvpn/openvpn-status.log" ]; then
        lineas=$(wc -l < "/etc/openvpn/openvpn-status.log")
        echo "   ✅ /etc/openvpn/openvpn-status.log ($lineas líneas)"
    else
        echo "   ❌ No encontrado"
    fi
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

# Dar permisos
chmod +x /usr/bin/gestion

echo ""
echo "✅ SISTEMA INSTALADO CORRECTAMENTE"
echo ""
echo "🔧 CARACTERÍSTICAS:"
echo "   1. ✅ Ver clientes conectados"
echo "   2. ✅ Listar estado de clientes"
echo "   3. ✅ Bloquear clientes"
echo "   4. ✅ Desbloquear clientes"
echo "   5. ✅ Gestionar nombres"
echo "   6. ✅ Estado del sistema"
echo "   7. ✅ Registrar IPs manualmente"
echo "   8. ✅ Ver logs"
echo ""
echo "🚀 Ejecuta: gestion"
