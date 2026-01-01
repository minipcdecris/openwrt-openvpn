#!/bin/sh

echo ""
echo "🔧 INSTALANDO SISTEMA COMPLETO CON FILTROS"
echo "=========================================="

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
    echo "🔧 GESTIÓN VPN - SISTEMA COMPLETO"
    echo "================================="
    echo ""
    echo "1) 👁️  Ver clientes conectados (con fecha/hora)"
    echo "2) 📋 Listar estado de clientes"
    echo "3) 🚫 BLOQUEAR cliente (IP + certificado)"
    echo "4) ✅ DESBLOQUEAR cliente (IP + certificado)"
    echo "5) 🏷️  Gestionar nombres"
    echo "6) 🔍 Estado del sistema"
    echo "7) 📝 Registrar IP manualmente"
    echo "8) 📊 Ver LOG del sistema"
    echo "9) ❌ Salir"
    echo ""
    echo -n "Selecciona [1-9]: "
}

# FUNCIÓN VER_CONECTADOS CON FILTROS MEJORADOS
ver_conectados() {
    echo ""
    echo "📊 CLIENTES CONECTADOS (con fecha/hora):"
    echo ""
    
    escribir_log "Buscando clientes conectados"
    
    # Archivo de estado
    STATUS_FILE="/tmp/run/openvpn.VPN_Server.status"
    
    if [ ! -f "$STATUS_FILE" ] || [ ! -s "$STATUS_FILE" ]; then
        echo "❌ No se encuentra archivo de estado"
        escribir_log "No se encuentra archivo de estado: $STATUS_FILE"
        return
    fi
    
    fecha_hora_actual=$(date '+%d/%m/%Y %H:%M')
    echo "🕒 Fecha actual: $fecha_hora_actual"
    echo ""
    
    # Verificar formato CSV
    if head -1 "$STATUS_FILE" | grep -q "OpenVPN CLIENT LIST"; then
        echo "🔍 Buscando clientes conectados..."
        echo ""
        
        encontrados=0
        
        # Solo procesar líneas que sean clientes reales
        # Formato: client2,88.0.78.97:37861,42844,537034213,2026-01-02 00:10:47
        grep -E "^[a-zA-Z0-9_]+,[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+,[0-9]+,[0-9]+,20[0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9]$" "$STATUS_FILE" | while read linea; do
            
            cliente=$(echo "$linea" | cut -d',' -f1)
            ip_puerto=$(echo "$linea" | cut -d',' -f2)
            bytes_rx=$(echo "$linea" | cut -d',' -f3)
            bytes_tx=$(echo "$linea" | cut -d',' -f4)
            fecha_hora=$(echo "$linea" | cut -d',' -f5)
            
            cliente_limpio=$(limpiar_nombre "$cliente")
            nombre_descriptivo=$(obtener_nombre "$cliente")
            
            # Mostrar información
            if [ "$cliente_limpio" = "$nombre_descriptivo" ]; then
                echo "👤 $nombre_descriptivo"
            else
                echo "👤 $nombre_descriptivo ($cliente_limpio)"
            fi
            
            echo "   🔑 Certificado: $cliente_limpio"
            echo "   🌐 IP: $ip_puerto"
            
            # Formatear tráfico
            if echo "$bytes_rx" | grep -q '^[0-9]\+$'; then
                if [ "$bytes_rx" -lt 1024 ]; then
                    echo "   📥 Descargado: ${bytes_rx} B"
                elif [ "$bytes_rx" -lt 1048576 ]; then
                    kb_rx=$((bytes_rx / 1024))
                    echo "   📥 Descargado: ${kb_rx} KB"
                else
                    mb_rx=$((bytes_rx / 1024 / 1024))
                    echo "   📥 Descargado: ${mb_rx} MB"
                fi
            fi
            
            if echo "$bytes_tx" | grep -q '^[0-9]\+$'; then
                if [ "$bytes_tx" -lt 1024 ]; then
                    echo "   📤 Enviado: ${bytes_tx} B"
                elif [ "$bytes_tx" -lt 1048576 ]; then
                    kb_tx=$((bytes_tx / 1024))
                    echo "   📤 Enviado: ${kb_tx} KB"
                else
                    mb_tx=$((bytes_tx / 1024 / 1024))
                    echo "   📤 Enviado: ${mb_tx} MB"
                fi
            fi
            
            if [ -n "$fecha_hora" ]; then
                echo "   🕒 Conectado: $fecha_hora"
                
                # Registrar en historial
                timestamp_actual=$(date '+%Y-%m-%d %H:%M:%S')
                ip_externa=$(echo "$ip_puerto" | cut -d: -f1)
                
                # Eliminar entrada antigua si existe
                grep -v "^$cliente_limpio:$ip_externa:" "$IP_HISTORY_FILE" > /tmp/ip_temp.txt 2>/dev/null
                mv /tmp/ip_temp.txt "$IP_HISTORY_FILE" 2>/dev/null
                
                # Añadir nueva entrada
                echo "$cliente_limpio:$ip_externa:$timestamp_actual:$fecha_hora" >> "$IP_HISTORY_FILE"
                escribir_log "Cliente $nombre_descriptivo conectado desde $ip_puerto"
            fi
            
            echo ""
            encontrados=1
        done
        
        if [ $encontrados -eq 0 ]; then
            echo "ℹ️  No hay clientes conectados"
            escribir_log "No hay clientes conectados"
        else
            echo "✅ Información registrada en el historial"
        fi
        
    else
        echo "⚠️  Formato de archivo no compatible"
        escribir_log "Formato de archivo no compatible"
    fi
}

# Función para listar estado de clientes
listar_clientes() {
    echo ""
    echo "📋 ESTADO COMPLETO DE CLIENTES"
    echo "=============================="
    echo ""
    
    escribir_log "Mostrando estado completo de clientes"
    
    echo "🎯 CLIENTES CON IPs REGISTRADAS:"
    echo ""
    
    if [ -f "$IP_HISTORY_FILE" ] && [ -s "$IP_HISTORY_FILE" ]; then
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
                ultima_conexion=$(grep "^$cliente:" "$IP_HISTORY_FILE" | tail -1 | cut -d: -f4)
                
                echo "   $contador) $nombre ($cliente)"
                echo "      Estado: $estado"
                echo "      IPs registradas: $ips"
                if [ -n "$ultima_conexion" ]; then
                    echo "      Última conexión: $ultima_conexion"
                fi
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
        escribir_log "iptables no disponible para bloquear IP $ip"
        return 1
    fi
    
    # Extraer solo la IP si viene con puerto
    ip_sin_puerto=$(echo "$ip" | cut -d: -f1)
    
    # Verificar si ya está bloqueada
    if iptables -nL INPUT 2>/dev/null | grep -q "DROP.*$ip_sin_puerto"; then
        escribir_log "IP $ip_sin_puerto ya estaba bloqueada para $cliente"
        return 0
    fi
    
    # Bloquear IP
    if iptables -I INPUT -s "$ip_sin_puerto" -j DROP 2>/dev/null; then
        mkdir -p /etc/openvpn
        if ! grep -q "^$ip_sin_puerto:" /etc/openvpn/blocked_ips.txt 2>/dev/null; then
            echo "$ip_sin_puerto:$cliente:$(date '+%Y-%m-%d %H:%M:%S')" >> /etc/openvpn/blocked_ips.txt
        fi
        escribir_log "IP $ip_sin_puerto bloqueada para cliente $cliente"
        return 0
    else
        escribir_log "Error bloqueando IP $ip_sin_puerto para $cliente"
        return 1
    fi
}

# Función para desbloquear IP
desbloquear_ip() {
    ip="$1"
    
    # Extraer solo la IP si viene con puerto
    ip_sin_puerto=$(echo "$ip" | cut -d: -f1)
    
    if command -v iptables >/dev/null 2>&1; then
        iptables -D INPUT -s "$ip_sin_puerto" -j DROP 2>/dev/null
        escribir_log "IP $ip_sin_puerto desbloqueada"
    fi
    
    # Eliminar de persistencia
    if [ -f "/etc/openvpn/blocked_ips.txt" ]; then
        grep -v "^$ip_sin_puerto:" /etc/openvpn/blocked_ips.txt > /tmp/blocked.tmp
        mv /tmp/blocked.tmp /etc/openvpn/blocked_ips.txt 2>/dev/null
    fi
}

# Función para BLOQUEAR CLIENTE COMPLETAMENTE
bloquear_cliente() {
    echo ""
    echo "🚫 BLOQUEAR CLIENTE (IP + certificado)"
    echo "======================================"
    echo ""
    
    escribir_log "Iniciando proceso de bloqueo completo"
    
    if [ ! -f "$IP_HISTORY_FILE" ] || [ ! -s "$IP_HISTORY_FILE" ]; then
        echo "❌ No hay clientes registrados para bloquear"
        return
    fi
    
    echo "Clientes disponibles para BLOQUEAR:"
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
    echo "🔍 Buscando IPs de: $cliente_seleccionado"
    escribir_log "Buscando IPs para cliente $cliente_seleccionado"
    
    # Obtener IPs del cliente
    IPS=$(obtener_ips_cliente "$cliente_seleccionado")
    
    if [ -z "$IPS" ]; then
        echo "ℹ️  No hay IPs registradas para este cliente"
        echo -n "¿Continuar solo con bloqueo en lista? (s/N): "
        read continuar
        if [ "$continuar" != "s" ] && [ "$continuar" != "S" ]; then
            echo "❌ Operación cancelada"
            return
        fi
        IPS=""
    else
        echo "📋 IPs encontradas:"
        count=0
        for ip in $IPS; do
            count=$((count + 1))
            echo "      $count) $ip"
        done
    fi
    
    echo ""
    echo "⚠️  CONFIRMACIÓN FINAL"
    echo "Cliente: $cliente_seleccionado"
    if [ -n "$IPS" ]; then
        echo "IPs a bloquear: $count"
    fi
    echo ""
    echo -n "¿Confirmar BLOQUEO COMPLETO? (s/N): "
    read confirmar
    
    if [ "$confirmar" != "s" ] && [ "$confirmar" != "S" ]; then
        escribir_log "Bloqueo cancelado por usuario para $cliente_seleccionado"
        echo "❌ Operación cancelada"
        return
    fi
    
    echo ""
    echo "🛡️  EJECUTANDO BLOQUEO..."
    echo ""
    escribir_log "Iniciando bloqueo completo para $cliente_seleccionado"
    
    # 1. Bloquear IPs
    bloqueadas=0
    if [ -n "$IPS" ]; then
        echo "🔒 Bloqueando IPs en firewall..."
        for ip in $IPS; do
            if bloquear_ip "$ip" "$cliente_seleccionado"; then
                echo "   ✅ $ip - BLOQUEADA"
                bloqueadas=$((bloqueadas + 1))
            else
                echo "   ❌ $ip - Error"
            fi
        done
    fi
    
    # 2. Añadir a lista de bloqueados
    echo ""
    echo "📋 Añadiendo a lista de bloqueados..."
    grep -v "^$cliente_seleccionado:" "$SUSPENDED_FILE" > /tmp/suspended.tmp
    echo "$cliente_seleccionado:$(date '+%Y-%m-%d %H:%M:%S'):completo" >> /tmp/suspended.tmp
    mv /tmp/suspended.tmp "$SUSPENDED_FILE"
    
    echo ""
    echo "✅ BLOQUEO COMPLETO REALIZADO"
    echo "   👤 Cliente: $cliente_seleccionado"
    if [ -n "$IPS" ]; then
        echo "   🔒 IPs bloqueadas: $bloqueadas/$count"
    fi
    echo ""
    
    escribir_log "BLOQUEO COMPLETO REALIZADO para $cliente_seleccionado"
}

# Función para DESBLOQUEAR CLIENTE COMPLETAMENTE
desbloquear_cliente() {
    echo ""
    echo "✅ DESBLOQUEAR CLIENTE (IP + certificado)"
    echo "========================================="
    echo ""
    
    escribir_log "Iniciando proceso de desbloqueo completo"
    
    if [ ! -s "$SUSPENDED_FILE" ]; then
        echo "✅ No hay clientes bloqueados"
        return
    fi
    
    echo "Clientes BLOQUEADOS:"
    echo ""
    
    contador=0
    while IFS=: read -r cliente fecha tipo resto; do
        if [ -n "$cliente" ]; then
            contador=$((contador + 1))
            nombre=$(obtener_nombre "$cliente")
            echo "   $contador) $nombre ($cliente) - $fecha"
            echo "$contador:$cliente:$tipo" >> /tmp/bloqueados_ref.txt
        fi
    done < "$SUSPENDED_FILE"
    
    echo ""
    echo -n "Selecciona cliente (número): "
    read seleccion
    
    cliente_seleccionado=""
    tipo_bloqueo=""
    if [ -f /tmp/bloqueados_ref.txt ]; then
        while IFS=: read -r num cliente tipo; do
            if [ "$num" = "$seleccion" ]; then
                cliente_seleccionado="$cliente"
                tipo_bloqueo="$tipo"
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
    echo "🔓 DESBLOQUEANDO: $cliente_seleccionado"
    echo ""
    escribir_log "Iniciando desbloqueo para $cliente_seleccionado"
    
    # 1. Desbloquear IPs
    echo "🔓 Desbloqueando IPs..."
    IPS=$(obtener_ips_cliente "$cliente_seleccionado")
    if [ -n "$IPS" ]; then
        for ip in $IPS; do
            desbloquear_ip "$ip"
            echo "   ✅ $ip - DESBLOQUEADA"
        done
        escribir_log "IPs desbloqueadas para $cliente_seleccionado"
    else
        echo "   ℹ️  No hay IPs registradas para desbloquear"
    fi
    
    # 2. Eliminar de lista de bloqueados
    echo ""
    echo "📋 Eliminando de lista de bloqueados..."
    grep -v "^$cliente_seleccionado:" "$SUSPENDED_FILE" > /tmp/suspended.tmp
    mv /tmp/suspended.tmp "$SUSPENDED_FILE"
    
    echo ""
    echo "✅ CLIENTE DESBLOQUEADO COMPLETAMENTE"
    echo "   👤 Cliente: $cliente_seleccionado"
    echo ""
    
    escribir_log "CLIENTE $cliente_seleccionado DESBLOQUEADO COMPLETAMENTE"
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
                escribir_log "Mostrando nombres asignados"
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
                    grep -v "^$cliente:" "$NOMBRES_FILE" > /tmp/nombres.tmp
                    echo "$cliente:$nombre" >> /tmp/nombres.tmp
                    mv /tmp/nombres.tmp "$NOMBRES_FILE"
                    
                    echo ""
                    echo "✅ NOMBRE ASIGNADO:"
                    echo "   📋 Certificado: $cliente"
                    echo "   🏷️  Nombre: $nombre"
                    escribir_log "Nombre asignado: $nombre para $cliente"
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
                    grep -v "^$cliente_eliminar:" "$NOMBRES_FILE" > /tmp/nombres.tmp
                    mv /tmp/nombres.tmp "$NOMBRES_FILE"
                    escribir_log "Nombre eliminado para cliente $cliente_eliminar"
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
    
    escribir_log "Iniciando registro manual de IP"
    
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
    echo ""
    
    escribir_log "IP $ip registrada manualmente para $cliente"
}

# Función para estado del sistema
estado_servicio() {
    echo ""
    echo "🔍 ESTADO DEL SISTEMA"
    echo "===================="
    echo ""
    
    escribir_log "Mostrando estado del sistema"
    
    # OpenVPN
    if pgrep openvpn >/dev/null; then
        echo "✅ OpenVPN: ACTIVO"
        escribir_log "OpenVPN: ACTIVO"
    else
        echo "❌ OpenVPN: INACTIVO"
        escribir_log "OpenVPN: INACTIVO"
    fi
    
    # iptables
    echo ""
    echo "🛡️  IPTABLES:"
    if command -v iptables >/dev/null 2>&1; then
        echo "   ✅ Instalado"
        drops=$(iptables -nL INPUT 2>/dev/null | grep -c DROP)
        echo "   📊 Reglas DROP en INPUT: $drops"
        escribir_log "IPTABLES: Instalado, $drops reglas DROP"
    else
        echo "   ❌ No instalado"
        escribir_log "IPTABLES: No instalado"
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
    if [ -f "/tmp/run/openvpn.VPN_Server.status" ]; then
        lineas=$(wc -l < "/tmp/run/openvpn.VPN_Server.status")
        echo "   ✅ /tmp/run/openvpn.VPN_Server.status ($lineas líneas)"
        if grep -q "^Updated," "/tmp/run/openvpn.VPN_Server.status"; then
            updated=$(grep "^Updated," "/tmp/run/openvpn.VPN_Server.status" | cut -d',' -f2)
            echo "   📅 Última actualización: $updated"
        fi
    else
        echo "   ❌ No encontrado"
    fi
}

# Función para ver LOG del sistema
ver_log() {
    echo ""
    echo "📜 REGISTRO DEL SISTEMA (LOG)"
    echo "============================="
    echo ""
    
    if [ ! -f "$LOG_FILE" ] || [ ! -s "$LOG_FILE" ]; then
        echo "📭 El archivo de log está vacío"
        return
    fi
    
    echo "Mostrando las últimas 20 entradas:"
    echo ""
    tail -20 "$LOG_FILE" | while read linea; do
        echo "   $linea"
    done
    
    echo ""
    echo "📊 Estadísticas del log:"
    total_lineas=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)
    echo "   Total de entradas: $total_lineas"
}

# Programa principal
escribir_log "Sistema de gestión VPN iniciado"

while true; do
    mostrar_menu
    read opcion
    
    escribir_log "Opción seleccionada en menú: $opcion"
    
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
            escribir_log "Sistema de gestión VPN finalizado"
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
echo "✅ SISTEMA COMPLETO INSTALADO"
echo ""
echo "🔧 TODAS LAS FUNCIONES DISPONIBLES:"
echo ""
echo "   1) 👁️  Ver clientes conectados - FILTRADO (solo clientes reales)"
echo "   2) 📋 Listar estado de clientes"
echo "   3) 🚫 BLOQUEAR cliente (IP + certificado)"
echo "   4) ✅ DESBLOQUEAR cliente (IP + certificado)"
echo "   5) 🏷️  Gestionar nombres"
echo "   6) 🔍 Estado del sistema"
echo "   7) 📝 Registrar IP manualmente"
echo "   8) 📊 Ver LOG del sistema"
echo ""
echo "🚀 Ejecuta: gestion"
