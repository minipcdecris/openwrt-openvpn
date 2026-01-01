#!/bin/sh

echo ""
echo "🔧 REPARANDO PROCESAMIENTO DE ARCHIVO DE ESTADO"
echo "=============================================="

# Actualizar solo la función procesar_formato_v1
cat > /tmp/fix_status.sh << 'EOF'
#!/bin/sh

# Reemplazar la función procesar_formato_v1 en /usr/bin/gestion
sed -i '/procesar_formato_v1() {/,/^}/d' /usr/bin/gestion

# Encontrar dónde insertar la nueva función
linea=$(grep -n "procesar_formato_v1()" /usr/bin/gestion | head -1 | cut -d: -f1)

if [ -z "$linea" ]; then
    # Insertar después de procesar_formato_v2
    linea=$(grep -n "^procesar_formato_v2()" /usr/bin/gestion | head -1 | cut -d: -f1)
    linea=$((linea + 1))
fi

# Nueva función corregida
nueva_funcion='# Función para procesar formato v1 (OpenVPN CLIENT LIST)
procesar_formato_v1() {
    archivo="$1"
    contador=0
    
    echo "📋 Formato detectado: OpenVPN Status v1"
    echo ""
    
    # Buscar la sección de clientes conectados
    en_seccion_clientes=0
    while IFS= read -r linea; do
        # Detectar inicio de sección CLIENT LIST
        if echo "$linea" | grep -q "^OpenVPN CLIENT LIST"; then
            en_seccion_clientes=1
            continue
        fi
        
        # Detectar fin de sección CLIENT LIST
        if echo "$linea" | grep -q "^ROUTING TABLE\|^GLOBAL STATS\|^END"; then
            en_seccion_clientes=0
            continue
        fi
        
        # Si estamos en la sección correcta y no es línea de encabezado
        if [ $en_seccion_clientes -eq 1 ]; then
            # Saltar líneas de encabezado o separadores
            if echo "$linea" | grep -q "^Common Name\|^Updated,\|^-\+\|^$"; then
                continue
            fi
            
            # Procesar línea de cliente
            # Formato: /CN=nombre,ip:puerto,bytes_recibidos,bytes_enviados,fecha_conexion
            cliente=$(echo "$linea" | cut -d, -f1 2>/dev/null)
            ip_real=$(echo "$linea" | cut -d, -f2 2>/dev/null)
            bytes_recv=$(echo "$linea" | cut -d, -f3 2>/dev/null)
            bytes_sent=$(echo "$linea" | cut -d, -f4 2>/dev/null)
            fecha_conexion=$(echo "$linea" | cut -d, -f5- 2>/dev/null)
            
            # Validar que sea una línea de cliente real
            # Debe comenzar con /CN= y tener una IP
            if echo "$cliente" | grep -q "^/CN=" && [ -n "$ip_real" ] && echo "$ip_real" | grep -q ":"; then
                cliente_limpio=$(echo "$cliente" | sed "s|/CN=||")
                nombre_descriptivo=$(obtener_nombre "$cliente_limpio")
                
                contador=$((contador + 1))
                
                echo "    📍 Cliente $contador"
                echo "    👤 Nombre: $nombre_descriptivo"
                echo "    🔑 Certificado: $cliente_limpio"
                echo "    🌐 IP Real: $ip_real"
                
                if [ -n "$fecha_conexion" ] && [ "$fecha_conexion" != "" ]; then
                    echo "    🕒 Conectado desde: $fecha_conexion"
                fi
                
                # Formatear bytes
                if [ -n "$bytes_recv" ] && [ -n "$bytes_sent" ]; then
                    if command -v numfmt >/dev/null 2>&1; then
                        bytes_recv_humano=$(numfmt --to=iec --suffix=B "$bytes_recv" 2>/dev/null 2>/dev/null || echo "${bytes_recv}B")
                        bytes_sent_humano=$(numfmt --to=iec --suffix=B "$bytes_sent" 2>/dev/null 2>/dev/null || echo "${bytes_sent}B")
                        echo "    📊 Tráfico: ▼ $bytes_recv_humano / ▲ $bytes_sent_humano"
                    else
                        # Formato manual simple
                        if [ "$bytes_recv" -gt 1048576 ] 2>/dev/null; then
                            recv_mb=$((bytes_recv / 1048576))
                            echo "    📊 Tráfico: ▼ ${recv_mb}MB / "
                        elif [ "$bytes_recv" -gt 1024 ] 2>/dev/null; then
                            recv_kb=$((bytes_recv / 1024))
                            echo "    📊 Tráfico: ▼ ${recv_kb}KB / "
                        else
                            echo "    📊 Tráfico: ▼ ${bytes_recv}B / "
                        fi
                        
                        if [ "$bytes_sent" -gt 1048576 ] 2>/dev/null; then
                            sent_mb=$((bytes_sent / 1048576))
                            echo "    ▲ ${sent_mb}MB"
                        elif [ "$bytes_sent" -gt 1024 ] 2>/dev/null; then
                            sent_kb=$((bytes_sent / 1024))
                            echo "    ▲ ${sent_kb}KB"
                        else
                            echo "    ▲ ${bytes_sent}B"
                        fi
                    fi
                fi
                echo ""
                
                # Registrar en historial
                registrar_ip_historial "$cliente_limpio" "$ip_real" "$fecha_conexion"
            fi
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
}'

# Insertar la nueva función
sed -i "${linea}i\\
${nueva_funcion}" /usr/bin/gestion

echo "✅ Función de procesamiento actualizada"
EOF

chmod +x /tmp/fix_status.sh
/tmp/fix_status.sh

echo ""
echo "🎯 VERSIÓN MEJORADA SIMPLIFICADA"
echo "================================"

# Crear una versión simplificada y más robusta
cat > /usr/bin/gestion_simple << 'EOF'
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

# Función para mostrar menú
mostrar_menu() {
    clear
    echo ""
    echo "🔧 GESTIÓN VPN - VERSIÓN SIMPLIFICADA"
    echo "====================================="
    echo ""
    echo "1) 👁️  Ver clientes conectados (CORREGIDO)"
    echo "2) 📋 Listar estado de clientes"
    echo "3) 🏷️  Gestionar nombres"
    echo "4) 🔍 Estado del sistema"
    echo "5) ❌ Salir"
    echo ""
    echo -n "Selecciona [1-5]: "
}

# Función para ver clientes conectados - VERSIÓN CORREGIDA
ver_conectados() {
    echo ""
    echo "📊 CLIENTES CONECTADOS"
    echo "======================"
    echo ""
    
    # Archivo de estado
    STATUS_FILE="/etc/openvpn/status.log"
    
    if [ ! -f "$STATUS_FILE" ]; then
        echo "❌ No se encuentra $STATUS_FILE"
        return
    fi
    
    fecha_hora_actual=$(date '+%d/%m/%Y %H:%M:%S')
    echo "🕒 Fecha actual: $fecha_hora_actual"
    echo "📁 Archivo de estado: $STATUS_FILE"
    echo ""
    
    if [ ! -s "$STATUS_FILE" ]; then
        echo "ℹ️  El archivo está vacío"
        return
    fi
    
    # Procesar el archivo de manera más precisa
    echo "🔍 Buscando clientes conectados..."
    echo ""
    
    contador=0
    en_clientes=0
    
    while IFS= read -r linea; do
        # Inicio de sección CLIENT LIST
        if echo "$linea" | grep -q "^OpenVPN CLIENT LIST"; then
            en_clientes=1
            continue
        fi
        
        # Fin de sección CLIENT LIST
        if echo "$linea" | grep -q "^ROUTING TABLE\|^GLOBAL STATS\|^END"; then
            en_clientes=0
            continue
        fi
        
        # Procesar solo si estamos en sección CLIENT LIST
        if [ $en_clientes -eq 1 ]; then
            # Saltar encabezados y líneas vacías
            if echo "$linea" | grep -q "^Common Name\|^Updated,\|^-\+\|^$"; then
                continue
            fi
            
            # Extraer campos usando awk para mayor precisión
            cliente=$(echo "$linea" | awk -F, '{print $1}' | xargs)
            ip_real=$(echo "$linea" | awk -F, '{print $2}' | xargs)
            bytes_recv=$(echo "$linea" | awk -F, '{print $3}' | xargs)
            bytes_sent=$(echo "$linea" | awk -F, '{print $4}' | xargs)
            fecha_conexion=$(echo "$linea" | awk -F, '{for(i=5;i<=NF;i++) printf "%s%s", $i, (i<NF?", ":"")}' | xargs)
            
            # Validar que sea un cliente real (debe empezar con /CN=)
            if echo "$cliente" | grep -q "^/CN=" && [ -n "$ip_real" ]; then
                cliente_limpio=$(echo "$cliente" | sed 's|/CN=||')
                nombre_descriptivo=$(obtener_nombre "$cliente_limpio")
                
                contador=$((contador + 1))
                
                echo "    📍 Cliente $contador"
                echo "    👤 Nombre: $nombre_descriptivo"
                echo "    🔑 Certificado: $cliente_limpio"
                echo "    🌐 IP Real: $ip_real"
                
                if [ -n "$fecha_conexion" ] && [ "$fecha_conexion" != "" ]; then
                    echo "    🕒 Conectado desde: $fecha_conexion"
                fi
                
                # Formatear bytes
                if [ -n "$bytes_recv" ] && [ -n "$bytes_sent" ]; then
                    # Verificar si son números
                    if echo "$bytes_recv" | grep -q "^[0-9][0-9]*$" && echo "$bytes_sent" | grep -q "^[0-9][0-9]*$"; then
                        # Convertir a formato legible
                        if [ "$bytes_recv" -ge 1073741824 ] 2>/dev/null; then
                            recv_gb=$(echo "scale=2; $bytes_recv / 1073741824" | bc 2>/dev/null || echo "?")
                            echo "    📥 Recibido: ${recv_gb} GB"
                        elif [ "$bytes_recv" -ge 1048576 ] 2>/dev/null; then
                            recv_mb=$(echo "scale=2; $bytes_recv / 1048576" | bc 2>/dev/null || echo "?")
                            echo "    📥 Recibido: ${recv_mb} MB"
                        elif [ "$bytes_recv" -ge 1024 ] 2>/dev/null; then
                            recv_kb=$(echo "scale=2; $bytes_recv / 1024" | bc 2>/dev/null || echo "?")
                            echo "    📥 Recibido: ${recv_kb} KB"
                        else
                            echo "    📥 Recibido: ${bytes_recv} bytes"
                        fi
                        
                        if [ "$bytes_sent" -ge 1073741824 ] 2>/dev/null; then
                            sent_gb=$(echo "scale=2; $bytes_sent / 1073741824" | bc 2>/dev/null || echo "?")
                            echo "    📤 Enviado: ${sent_gb} GB"
                        elif [ "$bytes_sent" -ge 1048576 ] 2>/dev/null; then
                            sent_mb=$(echo "scale=2; $bytes_sent / 1048576" | bc 2>/dev/null || echo "?")
                            echo "    📤 Enviado: ${sent_mb} MB"
                        elif [ "$bytes_sent" -ge 1024 ] 2>/dev/null; then
                            sent_kb=$(echo "scale=2; $bytes_sent / 1024" | bc 2>/dev/null || echo "?")
                            echo "    📤 Enviado: ${sent_kb} KB"
                        else
                            echo "    📤 Enviado: ${bytes_sent} bytes"
                        fi
                    else
                        echo "    📊 Datos de tráfico no disponibles"
                    fi
                fi
                echo ""
                
                # Registrar en historial
                if [ -n "$cliente_limpio" ] && [ -n "$ip_real" ]; then
                    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
                    echo "$cliente_limpio:$ip_real:$timestamp:$fecha_conexion" >> "$IP_HISTORY_FILE"
                fi
            fi
        fi
    done < "$STATUS_FILE"
    
    if [ $contador -eq 0 ]; then
        echo "ℹ️  No hay clientes conectados actualmente"
    else
        echo "📊 RESUMEN: Total de clientes conectados: $contador"
    fi
    
    escribir_log "📊 Ver clientes conectados: $contador clientes"
}

# Función para listar estado de clientes
listar_clientes() {
    echo ""
    echo "📋 CLIENTES DEL HISTORIAL"
    echo "========================"
    echo ""
    
    if [ ! -f "$IP_HISTORY_FILE" ] || [ ! -s "$IP_HISTORY_FILE" ]; then
        echo "📭 No hay clientes en el historial"
        return
    fi
    
    echo "Clientes con IPs registradas:"
    echo ""
    cut -d: -f1 "$IP_HISTORY_FILE" | sort -u | while read cliente; do
        if [ -n "$cliente" ]; then
            nombre=$(obtener_nombre "$cliente")
            echo "   👤 $nombre ($cliente)"
        fi
    done
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
            echo ""
            echo "🏷️  GESTIONAR NOMBRES"
            echo "===================="
            echo "Función en desarrollo..."
            ;;
        4)
            echo ""
            echo "🔍 ESTADO DEL SISTEMA"
            echo "===================="
            echo ""
            echo "📁 Archivo de estado: /etc/openvpn/status.log"
            if [ -f "/etc/openvpn/status.log" ]; then
                echo "✅ Existe"
                lineas=$(wc -l < "/etc/openvpn/status.log")
                echo "📊 Líneas: $lineas"
            else
                echo "❌ No existe"
            fi
            ;;
        5)
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

chmod +x /usr/bin/gestion_simple

echo ""
echo "✅ SISTEMA REPARADO"
echo ""
echo "📋 SE HAN CREADO DOS VERSIONES:"
echo ""
echo "   1. 🔧 /usr/bin/gestion"
echo "      - Versión completa con la función corregida"
echo "      - Procesa correctamente todas las secciones"
echo ""
echo "   2. 🎯 /usr/bin/gestion_simple"
echo "      - Versión simplificada y más robusta"
echo "      - Solo funciones esenciales"
echo "      - Procesamiento más preciso"
echo ""
echo "🚀 PRUEBA LA VERSIÓN SIMPLIFICADA:"
echo "   gestion_simple"
echo ""
echo "💡 LA VERSIÓN SIMPLIFICADA DEBERÍA MOSTRAR SOLO:"
echo ""
echo "   📊 CLIENTES CONECTADOS"
echo "   ======================"
echo "   🕒 Fecha actual: 01/01/2026 22:54:46"
echo "   📁 Archivo de estado: /etc/openvpn/status.log"
echo ""
echo "   🔍 Buscando clientes conectados..."
echo ""
echo "   📍 Cliente 1"
echo "   👤 Nombre: cliente1"
echo "   🔑 Certificado: cliente1"
echo "   🌐 IP Real: 192.168.1.100:54321"
echo "   🕒 Conectado desde: Thu Dec 10 15:40:00 2025"
echo "   📥 Recibido: 1.43 MB"
echo "   📤 Enviado: 715.82 KB"
echo ""
echo "   📍 Cliente 2"
echo "   👤 Nombre: cliente2"
echo "   🔑 Certificado: cliente2"
echo "   🌐 IP Real: 10.0.0.50:12345"
echo "   🕒 Conectado desde: Thu Dec 10 15:10:00 2025"
echo "   📥 Recibido: 2.86 MB"
echo "   📤 Enviado: 1.43 MB"
echo ""
echo "   📊 RESUMEN: Total de clientes conectados: 2"
