#!/bin/sh

echo ""
echo "🔧 INSTALANDO GESTIÓN VPN DEFINITIVA"
echo "===================================="

# Primero asegurarnos de que existe el archivo de estado
if [ ! -f "/etc/openvpn/status.log" ]; then
    echo "⚠️  Creando archivo de estado..."
    touch /etc/openvpn/status.log
    chmod 644 /etc/openvpn/status.log
fi

# Crear directorio de configuración
mkdir -p /etc/openvpn/clientes

# Crear archivos de configuración si no existen
touch /etc/openvpn/clientes/nombres.txt
touch /etc/openvpn/clientes/ip_history.txt
touch /etc/openvpn/clientes/suspended.txt
touch /etc/openvpn/clientes/vpn_gestion.log

# Crear el script definitivo
cat > /usr/bin/gestion << 'EOF'
#!/bin/sh

# ============================================
# GESTIÓN VPN - VERSIÓN DEFINITIVA
# Configurada para /etc/openvpn/status.log
# ============================================

# Archivos de configuración
NOMBRES_FILE="/etc/openvpn/clientes/nombres.txt"
IP_HISTORY_FILE="/etc/openvpn/clientes/ip_history.txt"
SUSPENDED_FILE="/etc/openvpn/clientes/suspended.txt"
LOG_FILE="/etc/openvpn/clientes/vpn_gestion.log"
STATUS_FILE="/etc/openvpn/status.log"  # TU ARCHIVO ESPECÍFICO

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
    echo "🔧 GESTIÓN VPN - SERVIDOR ABUELOS"
    echo "================================="
    echo ""
    echo "📁 Estado en: $STATUS_FILE"
    echo ""
    echo "1) 👁️  Ver clientes conectados"
    echo "2) 📋 Listar clientes del historial"
    echo "3) 🏷️  Gestionar nombres descriptivos"
    echo "4) 🚫 Bloquear cliente"
    echo "5) ✅ Desbloquear cliente"
    echo "6) 📝 Registrar IP manualmente"
    echo "7) 🔍 Estado del sistema"
    echo "8) 📊 Ver logs"
    echo "9) ❌ Salir"
    echo ""
    echo -n "Selecciona [1-9]: "
}

# ============================================
# FUNCIÓN PRINCIPAL: VER CLIENTES CONECTADOS
# ============================================
ver_conectados() {
    echo ""
    echo "📊 CLIENTES CONECTADOS"
    echo "======================"
    echo ""
    
    fecha_hora_actual=$(date '+%d/%m/%Y %H:%M:%S')
    echo "🕒 Fecha actual: $fecha_hora_actual"
    echo "📁 Archivo de estado: $STATUS_FILE"
    echo ""
    
    # Verificar si el archivo existe
    if [ ! -f "$STATUS_FILE" ]; then
        echo "❌ ERROR: No se encuentra $STATUS_FILE"
        echo ""
        echo "💡 SOLUCIONES:"
        echo "   1. Verifica que OpenVPN esté ejecutándose"
        echo "   2. Asegúrate de tener esta línea en server.conf:"
        echo "      status /etc/openvpn/status.log"
        echo "   3. Reinicia OpenVPN: systemctl restart openvpn"
        echo ""
        escribir_log "❌ No se encuentra $STATUS_FILE"
        return
    fi
    
    # Verificar si el archivo tiene contenido
    if [ ! -s "$STATUS_FILE" ]; then
        echo "ℹ️  El archivo está vacío"
        echo "   No hay clientes conectados actualmente"
        escribir_log "ℹ️  Archivo de estado vacío"
        return
    fi
    
    # Mostrar información básica del archivo
    tamano=$(wc -l < "$STATUS_FILE")
    echo "📊 Archivo: $tamano líneas"
    echo ""
    
    # Procesar el archivo de manera inteligente
    echo "🔍 Analizando conexiones..."
    echo ""
    
    contador=0
    en_seccion_clientes=0
    
    # Leer el archivo línea por línea
    while IFS= read -r linea; do
        # Detectar inicio de sección de clientes
        if echo "$linea" | grep -iq "OpenVPN CLIENT LIST"; then
            en_seccion_clientes=1
            continue
        fi
        
        # Detectar fin de sección de clientes
        if echo "$linea" | grep -iq "ROUTING TABLE\|GLOBAL STATS\|END"; then
            en_seccion_clientes=0
            continue
        fi
        
        # Solo procesar si estamos en la sección correcta
        if [ $en_seccion_clientes -eq 1 ]; then
            # Saltar encabezados, líneas vacías y separadores
            if echo "$linea" | grep -iq "Common Name\|Updated,\|^-\|^$"; then
                continue
            fi
            
            # Procesar línea de cliente
            # Formato: /CN=nombre,ip:puerto,bytes_recibidos,bytes_enviados,fecha
            cliente=$(echo "$linea" | cut -d, -f1 2>/dev/null | xargs)
            ip_real=$(echo "$linea" | cut -d, -f2 2>/dev/null | xargs)
            bytes_recv=$(echo "$linea" | cut -d, -f3 2>/dev/null | xargs)
            bytes_sent=$(echo "$linea" | cut -d, -f4 2>/dev/null | xargs)
            fecha_conexion=$(echo "$linea" | cut -d, -f5- 2>/dev/null | xargs)
            
            # Validar que sea un cliente real
            # Debe empezar con /CN= y tener una IP con puerto
            if echo "$cliente" | grep -q "^/CN=" && [ -n "$ip_real" ] && echo "$ip_real" | grep -q ":"; then
                cliente_limpio=$(echo "$cliente" | sed 's|/CN=||')
                nombre_descriptivo=$(obtener_nombre "$cliente_limpio")
                
                contador=$((contador + 1))
                
                # Mostrar información del cliente
                echo "    ┌─────────────────────────"
                echo "    │ 📍 CLIENTE $contador"
                echo "    ├─────────────────────────"
                echo "    │ 👤 Nombre: $nombre_descriptivo"
                echo "    │ 🔑 Certificado: $cliente_limpio"
                echo "    │ 🌐 IP Real: $ip_real"
                
                if [ -n "$fecha_conexion" ] && [ "$fecha_conexion" != "" ]; then
                    echo "    │ 🕒 Conectado desde: $fecha_conexion"
                fi
                
                # Mostrar tráfico en formato legible
                if [ -n "$bytes_recv" ] && [ -n "$bytes_sent" ]; then
                    # Verificar que sean números
                    if echo "$bytes_recv" | grep -q "^[0-9][0-9]*$" && echo "$bytes_sent" | grep -q "^[0-9][0-9]*$"; then
                        echo "    │ 📊 Tráfico:"
                        
                        # Recibido
                        if [ "$bytes_recv" -ge 1073741824 ] 2>/dev/null; then
                            recv_gb=$(echo "scale=1; $bytes_recv / 1073741824" | bc 2>/dev/null || echo "?")
                            echo "    │   📥 Recibido: ${recv_gb} GB"
                        elif [ "$bytes_recv" -ge 1048576 ] 2>/dev/null; then
                            recv_mb=$(echo "scale=1; $bytes_recv / 1048576" | bc 2>/dev/null || echo "?")
                            echo "    │   📥 Recibido: ${recv_mb} MB"
                        elif [ "$bytes_recv" -ge 1024 ] 2>/dev/null; then
                            recv_kb=$(echo "scale=1; $bytes_recv / 1024" | bc 2>/dev/null || echo "?")
                            echo "    │   📥 Recibido: ${recv_kb} KB"
                        else
                            echo "    │   📥 Recibido: ${bytes_recv} B"
                        fi
                        
                        # Enviado
                        if [ "$bytes_sent" -ge 1073741824 ] 2>/dev/null; then
                            sent_gb=$(echo "scale=1; $bytes_sent / 1073741824" | bc 2>/dev/null || echo "?")
                            echo "    │   📤 Enviado: ${sent_gb} GB"
                        elif [ "$bytes_sent" -ge 1048576 ] 2>/dev/null; then
                            sent_mb=$(echo "scale=1; $bytes_sent / 1048576" | bc 2>/dev/null || echo "?")
                            echo "    │   📤 Enviado: ${sent_mb} MB"
                        elif [ "$bytes_sent" -ge 1024 ] 2>/dev/null; then
                            sent_kb=$(echo "scale=1; $bytes_sent / 1024" | bc 2>/dev/null || echo "?")
                            echo "    │   📤 Enviado: ${sent_kb} KB"
                        else
                            echo "    │   📤 Enviado: ${bytes_sent} B"
                        fi
                    else
                        echo "    │ 📊 Tráfico: Datos no disponibles"
                    fi
                fi
                echo "    └─────────────────────────"
                echo ""
                
                # Registrar en historial (solo IP sin puerto)
                ip_sin_puerto=$(echo "$ip_real" | cut -d: -f1)
                timestamp=$(date '+%Y-%m-%d %H:%M:%S')
                
                # Eliminar entrada anterior si existe
                if [ -f "$IP_HISTORY_FILE" ]; then
                    grep -v "^$cliente_limpio:$ip_sin_puerto:" "$IP_HISTORY_FILE" > /tmp/vpn_temp.txt 2>/dev/null
                    mv /tmp/vpn_temp.txt "$IP_HISTORY_FILE" 2>/dev/null
                fi
                
                # Añadir nueva entrada
                echo "$cliente_limpio:$ip_sin_puerto:$timestamp:$fecha_conexion" >> "$IP_HISTORY_FILE"
                escribir_log "📡 Cliente $nombre_descriptivo conectado desde $ip_real"
            fi
        fi
    done < "$STATUS_FILE"
    
    if [ $contador -eq 0 ]; then
        echo "ℹ️  No hay clientes conectados actualmente"
        escribir_log "ℹ️  No hay clientes conectados"
    else
        echo "📊 RESUMEN:"
        echo "    ✅ Total de clientes conectados: $contador"
        echo "    💾 IPs registradas en historial: $contador"
        escribir_log "📊 Mostrados $contador clientes conectados"
    fi
}

# ============================================
# FUNCIÓN: LISTAR CLIENTES DEL HISTORIAL
# ============================================
listar_clientes() {
    echo ""
    echo "📋 CLIENTES DEL HISTORIAL"
    echo "========================"
    echo ""
    
    escribir_log "📋 Listando clientes del historial"
    
    if [ ! -f "$IP_HISTORY_FILE" ] || [ ! -s "$IP_HISTORY_FILE" ]; then
        echo "📭 No hay clientes en el historial"
        return
    fi
    
    # Contar clientes únicos
    clientes_unicos=$(cut -d: -f1 "$IP_HISTORY_FILE" | sort -u)
    total_clientes=$(echo "$clientes_unicos" | wc -l)
    
    echo "👥 Total de clientes únicos: $total_clientes"
    echo ""
    
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
            
            echo "   $contador) $nombre ($cliente)$bloqueado"
            
            # Mostrar todas las IPs de este cliente
            ips=$(grep "^$cliente:" "$IP_HISTORY_FILE" | cut -d: -f2 | sort -u)
            for ip in $ips; do
                # Obtener última conexión
                ultima=$(grep "^$cliente:$ip:" "$IP_HISTORY_FILE" | tail -1 | cut -d: -f3)
                echo "      📍 $ip (última: $ultima)"
            done
            echo ""
        fi
    done
}

# ============================================
# FUNCIÓN: GESTIONAR NOMBRES DESCRIPTIVOS
# ============================================
gestionar_nombres() {
    while true; do
        echo ""
        echo "🏷️  GESTIONAR NOMBRES DESCRIPTIVOS"
        echo "=================================="
        echo ""
        echo "1) Ver nombres asignados"
        echo "2) Añadir/Modificar nombre"
        echo "3) Eliminar nombre"
        echo "4) Volver al menú principal"
        echo ""
        echo -n "Selecciona [1-4]: "
        read opcion
        
        case $opcion in
            1)
                echo ""
                echo "📋 NOMBRES ASIGNADOS:"
                echo ""
                if [ -s "$NOMBRES_FILE" ]; then
                    num=0
                    while IFS=: read -r cliente nombre; do
                        num=$((num + 1))
                        echo "   $num) $nombre ← $cliente"
                    done < "$NOMBRES_FILE"
                else
                    echo "   📭 No hay nombres asignados"
                fi
                ;;
                
            2)
                echo ""
                echo "✏️  AÑADIR/MODIFICAR NOMBRE"
                echo ""
                echo -n "Nombre del certificado (ej: 'cliente1'): "
                read cliente
                echo -n "Nombre descriptivo (ej: 'Juan Pérez'): "
                read nombre
                
                # Limpiar /CN= si lo incluyeron
                cliente=$(echo "$cliente" | sed 's|/CN=||')
                
                if [ -n "$cliente" ] && [ -n "$nombre" ]; then
                    # Eliminar entrada anterior si existe
                    if [ -f "$NOMBRES_FILE" ]; then
                        grep -v "^$cliente:" "$NOMBRES_FILE" > /tmp/nombres_temp.txt 2>/dev/null
                        mv /tmp/nombres_temp.txt "$NOMBRES_FILE"
                    fi
                    
                    # Añadir nueva entrada
                    echo "$cliente:$nombre" >> "$NOMBRES_FILE"
                    
                    echo ""
                    echo "✅ NOMBRE ASIGNADO EXITOSAMENTE"
                    echo "   🔑 Certificado: $cliente"
                    echo "   🏷️  Nombre: $nombre"
                    escribir_log "🏷️  Nombre asignado: '$nombre' para $cliente"
                else
                    echo "❌ Error: Debes ingresar ambos valores"
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
                
                echo "Selecciona el número a eliminar:"
                echo ""
                num=0
                while IFS=: read -r cliente nombre; do
                    num=$((num + 1))
                    echo "   $num) $nombre ($cliente)"
                done < "$NOMBRES_FILE"
                
                echo ""
                echo -n "Número: "
                read seleccion
                
                # Buscar cliente correspondiente
                idx=0
                cliente_eliminar=""
                while IFS=: read -r cliente nombre; do
                    idx=$((idx + 1))
                    if [ $idx -eq "$seleccion" ]; then
                        cliente_eliminar="$cliente"
                        nombre_eliminar="$nombre"
                        break
                    fi
                done < "$NOMBRES_FILE"
                
                if [ -z "$cliente_eliminar" ]; then
                    echo "❌ Selección inválida"
                    continue
                fi
                
                echo ""
                echo -n "¿Eliminar '$nombre_eliminar' ($cliente_eliminar)? (s/N): "
                read confirmar
                
                if [ "$confirmar" = "s" ] || [ "$confirmar" = "S" ]; then
                    grep -v "^$cliente_eliminar:" "$NOMBRES_FILE" > /tmp/nombres_temp.txt
                    mv /tmp/nombres_temp.txt "$NOMBRES_FILE"
                    echo "✅ Nombre eliminado"
                    escribir_log "🗑️  Nombre eliminado: '$nombre_eliminar' para $cliente_eliminar"
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

# ============================================
# PROGRAMA PRINCIPAL
# ============================================
escribir_log "🚀 Sistema de gestión VPN iniciado"

echo ""
echo "🔧 GESTIÓN VPN INICIADA"
echo "📁 Estado: $STATUS_FILE"
echo ""

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
            gestionar_nombres
            ;;
        4)
            echo ""
            echo "🚫 BLOQUEAR CLIENTE"
            echo "=================="
            echo "Función disponible en la próxima versión"
            ;;
        5)
            echo ""
            echo "✅ DESBLOQUEAR CLIENTE"
            echo "====================="
            echo "Función disponible en la próxima versión"
            ;;
        6)
            echo ""
            echo "📝 REGISTRAR IP MANUALMENTE"
            echo "==========================="
            echo ""
            echo -n "Nombre del cliente: "
            read cliente
            echo -n "IP (ej: 192.168.1.100): "
            read ip
            
            if [ -n "$cliente" ] && [ -n "$ip" ]; then
                cliente=$(echo "$cliente" | sed 's|/CN=||')
                timestamp=$(date '+%Y-%m-%d %H:%M:%S')
                fecha_conexion=$(date '+%d/%m/%Y %H:%M:%S')
                
                echo "$cliente:$ip:$timestamp:$fecha_conexion" >> "$IP_HISTORY_FILE"
                echo "✅ IP registrada: $cliente - $ip"
                escribir_log "📝 IP registrada manualmente: $cliente - $ip"
            else
                echo "❌ Error: Datos incompletos"
            fi
            ;;
        7)
            echo ""
            echo "🔍 ESTADO DEL SISTEMA"
            echo "===================="
            echo ""
            
            # OpenVPN
            if pgrep openvpn >/dev/null 2>&1; then
                echo "✅ OpenVPN: ACTIVO"
            else
                echo "❌ OpenVPN: INACTIVO"
            fi
            
            # Archivo de estado
            echo "📁 $STATUS_FILE:"
            if [ -f "$STATUS_FILE" ]; then
                lineas=$(wc -l < "$STATUS_FILE" 2>/dev/null || echo 0)
                echo "   ✅ Existe ($lineas líneas)"
            else
                echo "   ❌ No existe"
            fi
            
            # Estadísticas
            echo ""
            echo "📊 ESTADÍSTICAS:"
            nombres=$(grep -c ":" "$NOMBRES_FILE" 2>/dev/null || echo 0)
            echo "   👥 Nombres asignados: $nombres"
            
            ips=$(wc -l < "$IP_HISTORY_FILE" 2>/dev/null || echo 0)
            echo "   📍 IPs en historial: $ips"
            
            logs=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)
            echo "   📜 Entradas en log: $logs"
            ;;
            
        8)
            echo ""
            echo "📊 REGISTROS DEL SISTEMA"
            echo "========================"
            echo ""
            
            if [ ! -f "$LOG_FILE" ] || [ ! -s "$LOG_FILE" ]; then
                echo "📭 No hay registros"
                continue
            fi
            
            echo "Últimas 20 entradas:"
            echo ""
            tail -20 "$LOG_FILE" | while read linea; do
                echo "   $linea"
            done
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

# Dar permisos de ejecución
chmod +x /usr/bin/gestion

echo ""
echo "✅ SISTEMA INSTALADO CORRECTAMENTE"
echo ""
echo "🎯 CONFIGURACIÓN ESPECÍFICA PARA TU SISTEMA:"
echo ""
echo "   📍 Archivo de estado: /etc/openvpn/status.log"
echo "   📁 Configuración: /etc/openvpn/clientes/"
echo "   🚀 Comando: gestion"
echo ""
echo "🔧 CARACTERÍSTICAS:"
echo ""
echo "   1. ✅ PROCESAMIENTO INTELIGENTE:"
echo "      - Lee específicamente /etc/openvpn/status.log"
echo "      - Filtra solo clientes reales (que empiezan con /CN=)"
echo "      - Ignora encabezados y otras secciones"
echo ""
echo "   2. 📊 VISUALIZACIÓN MEJORADA:"
echo "      - Formato de tabla limpio"
echo "      - Bytes convertidos a KB/MB/GB"
echo "      - Muestra fecha y hora actual"
echo ""
echo "   3. 💾 REGISTRO AUTOMÁTICO:"
echo "      - Guarda IPs en historial automáticamente"
echo "      - Registra todas las operaciones en log"
echo "      - Nombres descriptivos para clientes"
echo ""
echo "🚀 PARA USAR:"
echo "   gestion"
echo ""
echo "📌 EJEMPLO DE SALIDA CORRECTA:"
echo ""
echo "   🔧 GESTIÓN VPN - SERVIDOR ABUELOS"
echo "   ================================="
echo ""
echo "   📁 Estado en: /etc/openvpn/status.log"
echo ""
echo "   1) 👁️  Ver clientes conectados"
echo "   2) 📋 Listar clientes del historial"
echo "   ..."
echo ""
echo "💡 SI SIGUE SIN FUNCIONAR:"
echo "   1. Verifica que el archivo exista:"
echo "      ls -la /etc/openvpn/status.log"
echo "   2. Verifica que tenga contenido:"
echo "      head -10 /etc/openvpn/status.log"
echo "   3. Si está vacío, reinicia OpenVPN:"
echo "      systemctl restart openvpn"
