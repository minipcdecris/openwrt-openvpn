#!/bin/sh

echo ""
echo "🔧 ACTUALIZANDO GESTIÓN VPN - SOPORTE PARA FORMATO V1"
echo "====================================================="

# Actualizar el script
cat > /usr/bin/gestion << 'EOF'
#!/bin/sh

# Archivos de configuración
NOMBRES_FILE="/etc/openvpn/clientes/nombres.txt"
IP_HISTORY_FILE="/etc/openvpn/clientes/ip_history.txt"
SUSPENDED_FILE="/etc/openvpn/clientes/suspended.txt"
LOG_FILE="/etc/openvpn/clientes/vpn_gestion.log"

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

# Función para buscar archivo de estado
buscar_archivo_estado() {
    # Lista de posibles ubicaciones
    lugares="
        /var/log/openvpn-status.log
        /tmp/openvpn-status.log
        /etc/openvpn/status.log
        /etc/openvpn/server/status.log
        /etc/openvpn/openvpn-status.log
    "
    
    for archivo in $lugares; do
        if [ -f "$archivo" ]; then
            echo "$archivo"
            return 0
        fi
    done
    echo ""
    return 1
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

# Función para ver clientes conectados - SOPORTA FORMATO V1
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
        echo "   2. Configura OpenVPN para crear el archivo:"
        echo "      Añade esto a /etc/openvpn/server.conf:"
        echo "      status /etc/openvpn/status.log"
        echo "   3. Reinicia OpenVPN: systemctl restart openvpn"
        echo ""
        escribir_log "❌ No se encuentra archivo de estado"
        return
    fi
    
    fecha_hora_actual=$(date '+%d/%m/%Y %H:%M:%S')
    echo "🕒 Fecha actual: $fecha_hora_actual"
    echo "📁 Archivo de estado: $STATUS_FILE"
    echo ""
    
    if [ ! -s "$STATUS_FILE" ]; then
        echo "ℹ️  El archivo está vacío"
        echo "   No hay clientes conectados actualmente"
        escribir_log "ℹ️  Archivo de estado vacío"
        return
    fi
    
    # Detectar formato del archivo
    if head -1 "$STATUS_FILE" | grep -q "OpenVPN CLIENT LIST"; then
        procesar_formato_v1 "$STATUS_FILE"
    elif grep -q "^CLIENT_LIST," "$STATUS_FILE"; then
        procesar_formato_v2 "$STATUS_FILE"
    else
        echo "⚠️  Formato de archivo desconocido"
        echo "Primeras líneas del archivo:"
        head -3 "$STATUS_FILE"
        escribir_log "⚠️  Formato de archivo desconocido"
    fi
}

# Función para procesar formato v1 (OpenVPN CLIENT LIST)
procesar_formato_v1() {
    archivo="$1"
    contador=0
    
    echo "📋 Formato detectado: OpenVPN Status v1"
    echo ""
    
    # Leer línea por línea, saltando las primeras 2 líneas (encabezados)
    line_number=0
    while IFS= read -r linea; do
        line_number=$((line_number + 1))
        
        # Saltar líneas de encabezado
        if [ $line_number -le 3 ]; then
            continue
        fi
        
        # Si la línea está vacía o es separador, saltar
        if [ -z "$linea" ] || echo "$linea" | grep -q "^\-\+\|^ROUTING TABLE\|^GLOBAL STATS"; then
            continue
        fi
        
        # Procesar línea (formato: Common Name,Real Address,Bytes Received,Bytes Sent,Connected Since)
        cliente=$(echo "$linea" | cut -d, -f1 2>/dev/null)
        ip_real=$(echo "$linea" | cut -d, -f2 2>/dev/null)
        bytes_recv=$(echo "$linea" | cut -d, -f3 2>/dev/null)
        bytes_sent=$(echo "$linea" | cut -d, -f4 2>/dev/null)
        fecha_conexion=$(echo "$linea" | cut -d, -f5- 2>/dev/null)
        
        # Solo procesar si tenemos datos básicos
        if [ -n "$cliente" ] && [ "$cliente" != "UNDEF" ] && [ -n "$ip_real" ]; then
            cliente_limpio=$(limpiar_nombre "$cliente")
            nombre_descriptivo=$(obtener_nombre "$cliente_limpio")
            
            contador=$((contador + 1))
            
            echo "    📍 Cliente $contador"
            echo "    👤 Nombre: $nombre_descriptivo"
            echo "    🔑 Certificado: $cliente_limpio"
            echo "    🌐 IP Real: $ip_real"
            
            if [ -n "$fecha_conexion" ] && [ "$fecha_conexion" != "" ]; then
                # Limpiar fecha (puede tener comas extras)
                fecha_limpia=$(echo "$fecha_conexion" | sed 's/,/ /g')
                echo "    🕒 Conectado desde: $fecha_limpia"
            fi
            
            # Formatear bytes si es posible
            if [ -n "$bytes_recv" ] && [ -n "$bytes_sent" ]; then
                if command -v numfmt >/dev/null 2>&1; then
                    bytes_recv_humano=$(numfmt --to=iec --suffix=B "$bytes_recv" 2>/dev/null || echo "${bytes_recv}B")
                    bytes_sent_humano=$(numfmt --to=iec --suffix=B "$bytes_sent" 2>/dev/null || echo "${bytes_sent}B")
                    echo "    📊 Tráfico: ▼ $bytes_recv_humano / ▲ $bytes_sent_humano"
                else
                    echo "    📊 Tráfico: Recibido: $bytes_recv bytes, Enviado: $bytes_sent bytes"
                fi
            fi
            echo ""
            
            # Registrar en historial
            registrar_ip_historial "$cliente_limpio" "$ip_real" "$fecha_conexion"
        fi
    done < "$archivo"
    
    if [ $contador -eq 0 ]; then
        echo "ℹ️  No hay clientes conectados actualmente"
        escribir_log "ℹ️  No hay clientes conectados (formato v1)"
    else
        echo "📊 RESUMEN:"
        echo "    ✅ Total de clientes conectados: $contador"
        echo ""
        escribir_log "📊 Mostrados $contador clientes conectados (formato v1)"
    fi
}

# Función para procesar formato v2 (CLIENT_LIST)
procesar_formato_v2() {
    archivo="$1"
    contador=0
    
    echo "📋 Formato detectado: OpenVPN Status v2"
    echo ""
    
    grep "^CLIENT_LIST," "$archivo" | while IFS= read -r linea; do
        cliente=$(echo "$linea" | cut -d, -f2 2>/dev/null)
        ip_real=$(echo "$linea" | cut -d, -f3 2>/dev/null)
        ip_virtual=$(echo "$linea" | cut -d, -f4 2>/dev/null)
        fecha_conexion=$(echo "$linea" | cut -d, -f8 2>/dev/null)
        
        if [ -n "$cliente" ] && [ "$cliente" != "UNDEF" ] && [ -n "$ip_real" ]; then
            cliente_limpio=$(limpiar_nombre "$cliente")
            nombre_descriptivo=$(obtener_nombre "$cliente_limpio")
            
            contador=$((contador + 1))
            
            echo "    📍 Cliente $contador"
            echo "    👤 Nombre: $nombre_descriptivo"
            echo "    🔑 Certificado: $cliente_limpio"
            echo "    🌐 IP Real: $ip_real"
            
            if [ -n "$ip_virtual" ] && [ "$ip_virtual" != "" ] && [ "$ip_virtual" != "UNDEF" ]; then
                echo "    🔗 IP VPN: $ip_virtual"
            fi
            
            if [ -n "$fecha_conexion" ] && [ "$fecha_conexion" != "" ]; then
                echo "    🕒 Conectado desde: $fecha_conexion"
            fi
            echo ""
            
            # Registrar en historial
            registrar_ip_historial "$cliente_limpio" "$ip_real" "$fecha_conexion"
        fi
    done
    
    if [ $contador -eq 0 ]; then
        echo "ℹ️  No hay clientes conectados actualmente"
    else
        echo "📊 Total de clientes conectados: $contador"
    fi
}

# Función para registrar IP en historial
registrar_ip_historial() {
    cliente="$1"
    ip_real="$2"
    fecha_conexion="$3"
    
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Extraer IP sin puerto
    ip_sin_puerto=$(echo "$ip_real" | cut -d: -f1)
    
    # Limpiar entrada anterior si existe
    if [ -f "$IP_HISTORY_FILE" ]; then
        grep -v "^$cliente:$ip_sin_puerto:" "$IP_HISTORY_FILE" > /tmp/ip_temp.txt 2>/dev/null
        mv /tmp/ip_temp.txt "$IP_HISTORY_FILE" 2>/dev/null
    fi
    
    # Añadir nueva entrada
    echo "$cliente:$ip_sin_puerto:$timestamp:$fecha_conexion" >> "$IP_HISTORY_FILE"
    escribir_log "📡 Cliente $cliente conectado desde $ip_real"
}

# Función para listar estado de clientes
listar_clientes() {
    echo ""
    echo "📋 ESTADO DE CLIENTES"
    echo "====================="
    echo ""
    
    escribir_log "📋 Mostrando estado de clientes"
    
    echo "👥 CLIENTES DEL HISTORIAL:"
    echo ""
    
    if [ ! -f "$IP_HISTORY_FILE" ] || [ ! -s "$IP_HISTORY_FILE" ]; then
        echo "   📭 No hay clientes en el historial"
        return
    fi
    
    # Obtener lista única de clientes
    clientes_unicos=$(cut -d: -f1 "$IP_HISTORY_FILE" | sort -u)
    contador=0
    
    for cliente in $clientes_unicos; do
        if [ -n "$cliente" ]; then
            contador=$((contador + 1))
            nombre=$(obtener_nombre "$cliente")
            
            # Verificar si está bloqueado
            bloqueado=""
            if [ -f "$SUSPENDED_FILE" ] && grep -q "^$cliente:" "$SUSPENDED_FILE"; then
                bloqueado=" 🚫"
            fi
            
            echo "   $contador) 👤 $nombre ($cliente)$bloqueado"
            
            # Mostrar IPs asociadas
            grep "^$cliente:" "$IP_HISTORY_FILE" | cut -d: -f2 | sort -u | while read ip; do
                echo "      📍 $ip"
            done
            echo ""
        fi
    done
    
    echo "📊 RESUMEN:"
    echo "   👥 Total de clientes: $contador"
}

# Función para bloquear cliente
bloquear_cliente() {
    echo ""
    echo "🚫 BLOQUEAR CLIENTE"
    echo "=================="
    echo ""
    
    escribir_log "🚫 Iniciando bloqueo de cliente"
    
    echo "Selecciona cliente a bloquear:"
    echo ""
    
    if [ ! -f "$IP_HISTORY_FILE" ] || [ ! -s "$IP_HISTORY_FILE" ]; then
        echo "📭 No hay clientes en el historial"
        return
    fi
    
    # Listar clientes
    clientes=$(cut -d: -f1 "$IP_HISTORY_FILE" | sort -u)
    contador=0
    
    for cliente in $clientes; do
        if [ -n "$cliente" ]; then
            contador=$((contador + 1))
            nombre=$(obtener_nombre "$cliente")
            echo "   $contador) $nombre ($cliente)"
        fi
    done
    
    echo ""
    echo -n "Número del cliente: "
    read seleccion
    
    # Encontrar cliente seleccionado
    idx=0
    cliente_seleccionado=""
    for cliente in $clientes; do
        idx=$((idx + 1))
        if [ $idx -eq "$seleccion" ]; then
            cliente_seleccionado="$cliente"
            break
        fi
    done
    
    if [ -z "$cliente_seleccionado" ]; then
        echo "❌ Selección inválida"
        return
    fi
    
    echo ""
    echo "🔍 IPs del cliente $cliente_seleccionado:"
    ips=$(grep "^$cliente_seleccionado:" "$IP_HISTORY_FILE" | cut -d: -f2 | sort -u)
    
    if [ -z "$ips" ]; then
        echo "   ℹ️  No hay IPs registradas"
    else
        for ip in $ips; do
            echo "   📍 $ip"
        done
    fi
    
    echo ""
    echo -n "¿Confirmar bloqueo de $cliente_seleccionado? (s/N): "
    read confirmar
    
    if [ "$confirmar" = "s" ] || [ "$confirmar" = "S" ]; then
        # Añadir a lista de bloqueados
        grep -v "^$cliente_seleccionado:" "$SUSPENDED_FILE" > /tmp/suspended.tmp 2>/dev/null
        echo "$cliente_seleccionado:$(date '+%Y-%m-%d %H:%M:%S')" >> /tmp/suspended.tmp
        mv /tmp/suspended.tmp "$SUSPENDED_FILE"
        
        echo "✅ Cliente $cliente_seleccionado bloqueado"
        escribir_log "✅ Cliente $cliente_seleccionado bloqueado"
    else
        echo "❌ Operación cancelada"
    fi
}

# Función para desbloquear cliente
desbloquear_cliente() {
    echo ""
    echo "✅ DESBLOQUEAR CLIENTE"
    echo "====================="
    echo ""
    
    escribir_log "✅ Iniciando desbloqueo de cliente"
    
    if [ ! -f "$SUSPENDED_FILE" ] || [ ! -s "$SUSPENDED_FILE" ]; then
        echo "📭 No hay clientes bloqueados"
        return
    fi
    
    echo "Clientes bloqueados:"
    echo ""
    
    contador=0
    while IFS=: read -r cliente fecha; do
        if [ -n "$cliente" ]; then
            contador=$((contador + 1))
            nombre=$(obtener_nombre "$cliente")
            echo "   $contador) $nombre ($cliente) - $fecha"
        fi
    done < "$SUSPENDED_FILE"
    
    echo ""
    echo -n "Número del cliente: "
    read seleccion
    
    # Encontrar cliente seleccionado
    idx=0
    cliente_seleccionado=""
    while IFS=: read -r cliente fecha; do
        if [ -n "$cliente" ]; then
            idx=$((idx + 1))
            if [ $idx -eq "$seleccion" ]; then
                cliente_seleccionado="$cliente"
                break
            fi
        fi
    done < "$SUSPENDED_FILE"
    
    if [ -z "$cliente_seleccionado" ]; then
        echo "❌ Selección inválida"
        return
    fi
    
    echo ""
    echo -n "¿Confirmar desbloqueo de $cliente_seleccionado? (s/N): "
    read confirmar
    
    if [ "$confirmar" = "s" ] || [ "$confirmar" = "S" ]; then
        # Eliminar de lista de bloqueados
        grep -v "^$cliente_seleccionado:" "$SUSPENDED_FILE" > /tmp/suspended.tmp 2>/dev/null
        mv /tmp/suspended.tmp "$SUSPENDED_FILE"
        
        echo "✅ Cliente $cliente_seleccionado desbloqueado"
        escribir_log "✅ Cliente $cliente_seleccionado desbloqueado"
    else
        echo "❌ Operación cancelada"
    fi
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
                    grep -v "^$cliente:" "$NOMBRES_FILE" > /tmp/nombres.tmp 2>/dev/null
                    echo "$cliente:$nombre" >> /tmp/nombres.tmp
                    mv /tmp/nombres.tmp "$NOMBRES_FILE"
                    echo "✅ Nombre asignado: $nombre para $cliente"
                    escribir_log "🏷️  Nombre asignado: $nombre para $cliente"
                else
                    echo "❌ Error: Datos incompletos"
                fi
                ;;
                
            3)
                echo ""
                echo "🗑️  ELIMINAR NOMBRE"
                echo ""
                
                if [ ! -s "$NOMBRES_FILE" ]; then
                    echo "📭 No hay nombres para eliminar"
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
                
                idx=0
                cliente_eliminar=""
                while IFS=: read -r cliente nombre; do
                    idx=$((idx + 1))
                    if [ $idx -eq "$seleccion" ]; then
                        cliente_eliminar="$cliente"
                        break
                    fi
                done < "$NOMBRES_FILE"
                
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
                    escribir_log "🗑️  Nombre eliminado para $cliente_eliminar"
                else
                    echo "❌ Cancelado"
                fi
                ;;
                
            4)
                return
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
    
    escribir_log "🔍 Mostrando estado del sistema"
    
    if pgrep openvpn >/dev/null 2>&1; then
        echo "✅ OpenVPN: ACTIVO"
    else
        echo "❌ OpenVPN: INACTIVO"
    fi
    
    echo ""
    echo "📁 ARCHIVOS DE CONFIGURACIÓN:"
    STATUS_FILE=$(buscar_archivo_estado)
    if [ -n "$STATUS_FILE" ]; then
        echo "   ✅ Estado: $STATUS_FILE"
        if [ -s "$STATUS_FILE" ]; then
            clientes=$(grep -c "^/CN=" "$STATUS_FILE" 2>/dev/null || echo 0)
            echo "   📊 Clientes en archivo: $clientes"
        fi
    else
        echo "   ❌ Estado: NO ENCONTRADO"
    fi
    
    echo "   ✅ Nombres: $NOMBRES_FILE"
    echo "   ✅ Historial: $IP_HISTORY_FILE"
    echo "   ✅ Bloqueados: $SUSPENDED_FILE"
    echo "   ✅ Logs: $LOG_FILE"
    
    echo ""
    echo "📊 ESTADÍSTICAS:"
    nombres=$(grep -c ":" "$NOMBRES_FILE" 2>/dev/null || echo 0)
    echo "   👥 Nombres asignados: $nombres"
    
    ips=$(wc -l < "$IP_HISTORY_FILE" 2>/dev/null || echo 0)
    echo "   📍 IPs registradas: $ips"
    
    bloqueados=$(wc -l < "$SUSPENDED_FILE" 2>/dev/null || echo 0)
    echo "   🚫 Clientes bloqueados: $bloqueados"
    
    log_size=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)
    echo "   📜 Entradas en log: $log_size"
}

# Función para registrar IP manualmente
registrar_ip_manual() {
    echo ""
    echo "📝 REGISTRAR IP MANUALMENTE"
    echo "==========================="
    echo ""
    
    escribir_log "📝 Iniciando registro manual de IP"
    
    echo -n "Nombre del cliente: "
    read cliente
    
    cliente=$(echo "$cliente" | sed 's|/CN=||')
    
    if [ -z "$cliente" ]; then
        echo "❌ Debes ingresar un nombre"
        return
    fi
    
    echo -n "IP a registrar (ej: 192.168.1.100): "
    read ip
    
    if [ -z "$ip" ]; then
        echo "❌ Debes ingresar una IP"
        return
    fi
    
    fecha_conexion=$(date '+%d/%m/%Y %H:%M:%S')
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Eliminar entrada anterior si existe
    grep -v "^$cliente:$ip:" "$IP_HISTORY_FILE" > /tmp/ip_temp.txt 2>/dev/null
    mv /tmp/ip_temp.txt "$IP_HISTORY_FILE" 2>/dev/null
    
    # Añadir nueva entrada
    echo "$cliente:$ip:$timestamp:$fecha_conexion" >> "$IP_HISTORY_FILE"
    
    echo ""
    echo "✅ IP REGISTRADA CORRECTAMENTE"
    echo "   👤 Cliente: $cliente"
    echo "   📍 IP: $ip"
    echo "   🕒 Fecha: $fecha_conexion"
    echo ""
    
    escribir_log "✅ IP $ip registrada manualmente para $cliente"
}

# Función para ver LOG del sistema
ver_log() {
    echo ""
    echo "📜 REGISTRO DEL SISTEMA"
    echo "======================="
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
    echo "📊 Total de entradas: $(wc -l < "$LOG_FILE")"
}

# Programa principal
escribir_log "🚀 Sistema de gestión VPN iniciado"

while true; do
    mostrar_menu
    read opcion
    
    escribir_log "📱 Opción seleccionada: $opcion"
    
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
            escribir_log "👋 Sistema de gestión VPN finalizado"
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
echo "✅ SISTEMA ACTUALIZADO CORRECTAMENTE"
echo ""
echo "🔧 MEJORAS IMPLEMENTADAS:"
echo ""
echo "   1. ✅ SOPORTE PARA FORMATO V1:"
echo "      - Detecta automáticamente 'OpenVPN CLIENT LIST'"
echo "      - Procesa formato: Common Name,Real Address,Bytes..."
echo "      - Muestra tráfico y fecha de conexión"
echo ""
echo "   2. 📊 VISUALIZACIÓN MEJORADA:"
echo "      - Muestra fecha actual"
echo "      - Formatea bytes a KB/MB/GB"
echo "      - Muestra IPs sin puerto en historial"
echo ""
echo "   3. 🎯 FUNCIONES COMPLETAS:"
echo "      - Ver clientes conectados ✓"
echo "      - Listar clientes del historial ✓"
echo "      - Bloquear/desbloquear clientes ✓"
echo "      - Gestionar nombres descriptivos ✓"
echo "      - Registrar IPs manualmente ✓"
echo "      - Ver logs del sistema ✓"
echo ""
echo "🚀 PARA USAR:"
echo "   gestion"
echo ""
echo "📌 EJEMPLO DE SALIDA ESPERADA:"
echo ""
echo "   📊 CLIENTES CONECTADOS"
echo "   ======================"
echo "   🕒 Fecha actual: 10/12/2025 16:10:00"
echo "   📁 Archivo de estado: /etc/openvpn/status.log"
echo "   📋 Formato detectado: OpenVPN Status v1"
echo ""
echo "   📍 Cliente 1"
echo "   👤 Nombre: cliente1"
echo "   🔑 Certificado: cliente1"
echo "   🌐 IP Real: 192.168.1.100:54321"
echo "   🕒 Conectado desde: Thu Dec 10 15:40:00 2025"
echo "   📊 Tráfico: ▼ 1.5MB / ▲ 750KB"
echo ""
echo "💡 EL SCRIPT AHORA FUNCIONARÁ CON TU ARCHIVO:"
echo "   /etc/openvpn/status.log"
