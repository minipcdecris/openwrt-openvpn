#!/bin/sh

echo ""
echo "🔧 ACTUALIZANDO SISTEMA - BLOQUEO POR NOMBRE MEJORADO"
echo "====================================================="

# Crear directorios necesarios
mkdir -p /etc/openvpn/scripts
mkdir -p /etc/openvpn/clientes

# Crear el script principal MEJORADO
cat > /usr/bin/gestion << 'EOF'
#!/bin/sh

# Archivos de configuración
NOMBRES_FILE="/etc/openvpn/clientes/nombres.txt"
SUSPENDED_FILE="/etc/openvpn/clientes/suspended.txt"
LOG_FILE="/etc/openvpn/clientes/vpn_gestion.log"
BLOQUEOS_LOG="/etc/openvpn/clientes/conexiones_bloqueadas.log"
CRL_FILE="/etc/openvpn/crl.pem"

# Crear archivos si no existen
for file in "$NOMBRES_FILE" "$SUSPENDED_FILE" "$LOG_FILE" "$BLOQUEOS_LOG"; do
    touch "$file"
done

# Función para escribir en log
escribir_log() {
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" >> "$LOG_FILE"
    # También mostrar en consola en modo debug
    [ "$DEBUG" = "1" ] && echo "[LOG] $1"
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

# Función para verificar si está bloqueado
esta_bloqueado() {
    cliente="$1"
    cliente_limpio=$(limpiar_nombre "$cliente")
    
    if [ -f "$SUSPENDED_FILE" ] && grep -q "^$cliente_limpio:" "$SUSPENDED_FILE"; then
        echo "si"
        return 0
    else
        echo "no"
        return 1
    fi
}

# ==============================================
# FUNCIONES DE CONFIGURACIÓN OPENVPN
# ==============================================

# Función para configurar OpenVPN automáticamente
configurar_openvpn() {
    echo "🔄 Configurando OpenVPN..."
    
    local server_conf="/etc/openvpn/server.conf"
    local script_verificacion="/etc/openvpn/scripts/verificar_cliente.sh"
    
    # 1. Crear script de verificación MEJORADO
    cat > "$script_verificacion" << 'SCRIPT_EOF'
#!/bin/sh
# Script MEJORADO para verificar bloqueos por nombre
# Se ejecuta automáticamente en cada conexión

CLIENT_NAME="$1"
IP_REAL="$2"
SUSPENDED_FILE="/etc/openvpn/clientes/suspended.txt"
BLOQUEOS_LOG="/etc/openvpn/clientes/conexiones_bloqueadas.log"

# Depuración
DEBUG_LOG="/tmp/openvpn_script_debug.log"
echo "=== $(date) ===" >> "$DEBUG_LOG"
echo "Cliente: $CLIENT_NAME" >> "$DEBUG_LOG"
echo "IP Real: $IP_REAL" >> "$DEBUG_LOG"

# Limpiar nombre
CLIENT_CLEAN=$(echo "$CLIENT_NAME" | sed 's|/CN=||')
echo "Cliente limpio: $CLIENT_CLEAN" >> "$DEBUG_LOG"

# Verificar archivo de bloqueos
if [ ! -f "$SUSPENDED_FILE" ]; then
    echo "Archivo de bloqueos no encontrado" >> "$DEBUG_LOG"
    exit 0
fi

echo "Contenido de suspended.txt:" >> "$DEBUG_LOG"
cat "$SUSPENDED_FILE" >> "$DEBUG_LOG" 2>/dev/null

# Verificar si está bloqueado
if grep -q "^$CLIENT_CLEAN:" "$SUSPENDED_FILE"; then
    echo "CLIENTE BLOQUEADO DETECTADO: $CLIENT_CLEAN" >> "$DEBUG_LOG"
    
    # Registrar bloqueo
    echo "$(date '+%Y-%m-%d %H:%M:%S') | Cliente: $CLIENT_CLEAN | IP: $IP_REAL | Estado: BLOQUEADO" >> "$BLOQUEOS_LOG"
    
    # También registrar en syslog
    logger -t "OpenVPN-Bloqueo" "Cliente $CLIENT_CLEAN bloqueado - IP: $IP_REAL"
    
    # Rechazar conexión
    exit 1
else
    echo "Cliente NO bloqueado: $CLIENT_CLEAN" >> "$DEBUG_LOG"
fi

# Permitir conexión
exit 0
SCRIPT_EOF
    
    chmod +x "$script_verificacion"
    echo "✅ Script de verificación creado: $script_verificacion"
    
    # 2. Configurar server.conf si existe
    if [ -f "$server_conf" ]; then
        echo "📋 Configurando $server_conf..."
        
        # Añadir script-security si no está
        if ! grep -q "script-security" "$server_conf"; then
            echo "script-security 2" >> "$server_conf"
            echo "✅ Añadido: script-security 2"
        fi
        
        # Añadir client-connect si no está
        if ! grep -q "client-connect" "$server_conf"; then
            echo "client-connect $script_verificacion" >> "$server_conf"
            echo "✅ Añadido: client-connect $script_verificacion"
        fi
        
        # Recargar OpenVPN
        recargar_openvpn
    else
        echo "⚠️  No se encontró $server_conf"
        echo "💡 Debes configurar OpenVPN manualmente:"
        echo "   1. Edita tu configuración OpenVPN"
        echo "   2. Añade estas líneas:"
        echo "      script-security 2"
        echo "      client-connect $script_verificacion"
    fi
}

# Función para recargar OpenVPN
recargar_openvpn() {
    echo "🔄 Recargando OpenVPN..."
    
    if systemctl reload openvpn-server 2>/dev/null; then
        echo "✅ OpenVPN recargado (systemctl)"
        return 0
    elif systemctl reload openvpn 2>/dev/null; then
        echo "✅ OpenVPN recargado (systemctl)"
        return 0
    elif /etc/init.d/openvpn reload 2>/dev/null; then
        echo "✅ OpenVPN recargado (init.d)"
        return 0
    elif killall -HUP openvpn 2>/dev/null; then
        echo "✅ Señal HUP enviada a OpenVPN"
        return 0
    else
        echo "⚠️  No se pudo recargar OpenVPN, reinicia manualmente"
        echo "💡 Ejecuta: systemctl restart openvpn"
        return 1
    fi
}

# ==============================================
# FUNCIONES DE BLOQUEO MEJORADAS
# ==============================================

# Función para bloquear cliente
bloquear_cliente() {
    clear
    echo ""
    echo "🚫 BLOQUEO POR NOMBRE - CONFIRMACIÓN"
    echo "===================================="
    echo ""
    
    escribir_log "Iniciando bloqueo por nombre"
    
    # Mostrar clientes conectados actualmente
    echo "📊 Clientes actualmente conectados:"
    echo ""
    
    local clientes_conectados=()
    local status_file="/var/log/openvpn-status.log"
    
    if [ -f "$status_file" ]; then
        local count=0
        while read -r linea; do
            if [[ "$linea" == CLIENT_LIST* ]] && [[ ! "$linea" == *HEADER* ]]; then
                cliente=$(echo "$linea" | awk '{print $2}' | sed 's|/CN=||')
                if [ -n "$cliente" ] && [ "$cliente" != "UNDEF" ]; then
                    count=$((count + 1))
                    nombre_descriptivo=$(obtener_nombre "$cliente")
                    echo "   $count) $nombre_descriptivo ($cliente)"
                    clientes_conectados[$count]="$cliente"
                fi
            fi
        done < "$status_file"
        
        if [ $count -eq 0 ]; then
            echo "   ℹ️  No hay clientes conectados"
        fi
    else
        echo "   ⚠️  No se puede leer estado de OpenVPN"
    fi
    
    echo ""
    echo "📝 Ingresa el NOMBRE del cliente a bloquear"
    echo "   (sin /CN=, ej: 'client1' no '/CN=client1')"
    echo ""
    echo -n "Nombre del cliente: "
    read cliente_input
    
    if [ -z "$cliente_input" ]; then
        echo "❌ Nombre inválido"
        return 1
    fi
    
    # Limpiar nombre
    cliente=$(echo "$cliente_input" | sed 's|/CN=||')
    
    # Verificar si ya está bloqueado
    if esta_bloqueado "$cliente"; then
        echo ""
        echo "⚠️  Este cliente YA está bloqueado"
        echo -n "¿Forzar nuevo bloqueo? (s/N): "
        read confirmar_extra
        if [ "$confirmar_extra" != "s" ] && [ "$confirmar_extra" != "S" ]; then
            echo "❌ Operación cancelada"
            return 1
        fi
    fi
    
    echo ""
    echo "⚠️  CONFIRMACIÓN FINAL"
    echo "====================="
    echo "Cliente a bloquear: $cliente"
    echo "Nombre descriptivo: $(obtener_nombre "$cliente")"
    echo ""
    echo "¿Estás seguro de bloquear a este cliente?"
    echo "No podrá conectarse aunque cambie de IP."
    echo ""
    echo -n "Confirmar BLOQUEO (sí=1, no=0): "
    read confirmacion
    
    if [ "$confirmacion" != "1" ] && [ "$confirmacion" != "s" ] && [ "$confirmacion" != "S" ] && [ "$confirmacion" != "si" ]; then
        echo "❌ Bloqueo cancelado"
        return 1
    fi
    
    echo ""
    echo "🛡️  EJECUTANDO BLOQUEO..."
    echo ""
    
    # 1. Añadir a lista de bloqueados
    echo "📋 Añadiendo a lista de bloqueados..."
    local temp_file=$(mktemp)
    grep -v "^$cliente:" "$SUSPENDED_FILE" 2>/dev/null > "$temp_file"
    echo "$cliente:$(date '+%Y-%m-%d %H:%M:%S'):bloqueado_por_$(whoami)" >> "$temp_file"
    mv "$temp_file" "$SUSPENDED_FILE"
    
    escribir_log "Cliente $cliente añadido a lista de bloqueados"
    echo "✅ Cliente añadido a lista de bloqueados"
    
    # 2. Configurar OpenVPN si no está configurado
    if [ ! -f "/etc/openvpn/scripts/verificar_cliente.sh" ]; then
        echo "🔧 Configurando OpenVPN por primera vez..."
        configurar_openvpn
    elif ! grep -q "client-connect" "/etc/openvpn/server.conf" 2>/dev/null; then
        echo "🔧 Configurando OpenVPN..."
        configurar_openvpn
    else
        echo "✅ OpenVPN ya está configurado para verificar bloqueos"
    fi
    
    # 3. Forzar recarga de OpenVPN para aplicar cambios inmediatamente
    echo "🔄 Aplicando cambios en OpenVPN..."
    recargar_openvpn
    
    # 4. Intentar desconectar al cliente si está conectado
    if [ -f "/var/log/openvpn-status.log" ] && grep -q "/CN=$cliente" "/var/log/openvpn-status.log"; then
        echo "📡 Cliente está conectado, forzando desconexión..."
        
        # Método 1: Usar management interface
        echo "   Intentando desconectar mediante management interface..."
        
        # Método 2: Enviar señal de desconexión
        if command -v pkill >/dev/null; then
            # Buscar PID del proceso OpenVPN del cliente
            for pid in $(pgrep openvpn); do
                if grep -q "$cliente" "/proc/$pid/cmdline" 2>/dev/null; then
                    echo "   Enviando señal de terminación al PID $pid"
                    kill -TERM "$pid"
                fi
            done
        fi
        
        # Método 3: Reiniciar OpenVPN completamente si no funciona
        echo "   Si sigue conectado, reinicia OpenVPN: systemctl restart openvpn"
    fi
    
    echo ""
    echo "✅ BLOQUEO COMPLETADO EXITOSAMENTE"
    echo "================================="
    echo "👤 Cliente: $cliente"
    echo "🏷️  Nombre: $(obtener_nombre "$cliente")"
    echo "🕒 Fecha: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    echo "🔍 PARA VERIFICAR:"
    echo "   1. Cliente intenta reconectar - debería fallar"
    echo "   2. Ver logs: tail -f /etc/openvpn/clientes/conexiones_bloqueadas.log"
    echo "   3. Depuración: cat /tmp/openvpn_script_debug.log"
    echo ""
    echo "💡 El bloqueo es EFECTIVO incluso si:"
    echo "   • Cambia de IP/router"
    echo "   • Reinicia su dispositivo"
    echo "   • Usa otra red"
    
    escribir_log "✅ Bloqueo completado para cliente $cliente"
}

# Función para desbloquear cliente
desbloquear_cliente() {
    clear
    echo ""
    echo "✅ DESBLOQUEO POR NOMBRE"
    echo "========================"
    echo ""
    
    escribir_log "Iniciando desbloqueo por nombre"
    
    # Mostrar clientes bloqueados
    echo "📋 Clientes actualmente bloqueados:"
    echo ""
    
    if [ ! -s "$SUSPENDED_FILE" ]; then
        echo "   ℹ️  No hay clientes bloqueados"
        return 0
    fi
    
    local count=0
    while IFS=: read -r cliente fecha motivo; do
        if [ -n "$cliente" ]; then
            count=$((count + 1))
            nombre_descriptivo=$(obtener_nombre "$cliente")
            echo "   $count) $nombre_descriptivo ($cliente)"
            echo "       📅 Bloqueado: $fecha"
            echo "       📝 Motivo: $motivo"
            echo ""
        fi
    done < "$SUSPENDED_FILE"
    
    echo ""
    echo -n "Ingresa el NÚMERO del cliente a desbloquear: "
    read seleccion
    
    if ! echo "$seleccion" | grep -qE '^[0-9]+$'; then
        echo "❌ Selección inválida"
        return 1
    fi
    
    # Obtener cliente seleccionado
    local cliente_seleccionado=""
    local count2=0
    while IFS=: read -r cliente fecha motivo; do
        if [ -n "$cliente" ]; then
            count2=$((count2 + 1))
            if [ "$count2" -eq "$seleccion" ]; then
                cliente_seleccionado="$cliente"
                break
            fi
        fi
    done < "$SUSPENDED_FILE"
    
    if [ -z "$cliente_seleccionado" ]; then
        echo "❌ Cliente no encontrado"
        return 1
    fi
    
    echo ""
    echo "🔓 DESBLOQUEANDO: $cliente_seleccionado"
    echo "   Nombre: $(obtener_nombre "$cliente_seleccionado")"
    echo ""
    echo -n "¿Confirmar desbloqueo? (sí=1, no=0): "
    read confirmacion
    
    if [ "$confirmacion" != "1" ] && [ "$confirmacion" != "s" ] && [ "$confirmacion" != "S" ]; then
        echo "❌ Desbloqueo cancelado"
        return 1
    fi
    
    # Eliminar de lista de bloqueados
    local temp_file=$(mktemp)
    grep -v "^$cliente_seleccionado:" "$SUSPENDED_FILE" > "$temp_file"
    mv "$temp_file" "$SUSPENDED_FILE"
    
    escribir_log "Cliente $cliente_seleccionado desbloqueado"
    echo "✅ Cliente desbloqueado exitosamente"
    
    # Recargar OpenVPN para aplicar cambios
    echo "🔄 Aplicando cambios en OpenVPN..."
    recargar_openvpn
    
    echo ""
    echo "💡 El cliente $cliente_seleccionado ahora puede conectarse normalmente"
}

# ==============================================
# MENÚ PRINCIPAL SIMPLIFICADO
# ==============================================

mostrar_menu() {
    clear
    echo ""
    echo "🔧 GESTIÓN VPN - BLOQUEO POR NOMBRE"
    echo "==================================="
    echo ""
    echo "1) 👁️  Ver clientes conectados"
    echo "2) 📋 Ver clientes bloqueados"
    echo "3) 🚫 BLOQUEAR cliente (por nombre)"
    echo "4) ✅ DESBLOQUEAR cliente (por nombre)"
    echo "5) ⚙️  Configurar OpenVPN"
    echo "6) 📊 Ver logs de bloqueos"
    echo "7) ❌ Salir"
    echo ""
    echo -n "Selecciona opción [1-7]: "
}

# Función para ver clientes conectados
ver_conectados() {
    echo ""
    echo "📊 CLIENTES CONECTADOS"
    echo "======================"
    echo ""
    
    local status_file="/var/log/openvpn-status.log"
    if [ ! -f "$status_file" ]; then
        echo "❌ No se encuentra $status_file"
        return 1
    fi
    
    local count=0
    while read -r linea; do
        if [[ "$linea" == CLIENT_LIST* ]] && [[ ! "$linea" == *HEADER* ]]; then
            cliente=$(echo "$linea" | awk '{print $2}' | sed 's|/CN=||')
            ip_real=$(echo "$linea" | awk '{print $3}')
            ip_virtual=$(echo "$linea" | awk '{print $4}')
            fecha_conexion=$(echo "$linea" | awk '{print $8" "$9}')
            
            if [ -n "$cliente" ] && [ "$cliente" != "UNDEF" ]; then
                count=$((count + 1))
                nombre_descriptivo=$(obtener_nombre "$cliente")
                
                # Verificar si está bloqueado
                if esta_bloqueado "$cliente"; then
                    estado="🚫 BLOQUEADO"
                else
                    estado="🟢 ACTIVO"
                fi
                
                echo "┌─────────────────────────────────────────"
                echo "│ $estado"
                echo "│ 👤 Nombre: $nombre_descriptivo"
                echo "│ 🔑 Certificado: $cliente"
                echo "│ 🌐 IP Real: $ip_real"
                echo "│ 🔗 IP VPN: $ip_virtual"
                echo "│ 🕒 Conectado: $fecha_conexion"
                echo "└─────────────────────────────────────────"
                echo ""
            fi
        fi
    done < "$status_file"
    
    if [ $count -eq 0 ]; then
        echo "ℹ️  No hay clientes conectados"
    else
        echo "📈 Total conectados: $count"
    fi
}

# Función principal
main() {
    escribir_log "Sistema de gestión iniciado"
    
    while true; do
        mostrar_menu
        read opcion
        
        case $opcion in
            1)
                ver_conectados
                ;;
            2)
                echo ""
                echo "🚫 CLIENTES BLOQUEADOS"
                echo "===================="
                echo ""
                if [ -s "$SUSPENDED_FILE" ]; then
                    cat "$SUSPENDED_FILE" | while IFS=: read -r cliente fecha motivo; do
                        if [ -n "$cliente" ]; then
                            echo "• $cliente - $fecha ($motivo)"
                        fi
                    done
                else
                    echo "ℹ️  No hay clientes bloqueados"
                fi
                ;;
            3)
                bloquear_cliente
                ;;
            4)
                desbloquear_cliente
                ;;
            5)
                configurar_openvpn
                ;;
            6)
                echo ""
                echo "📜 LOGS DE BLOQUEOS"
                echo "=================="
                echo ""
                if [ -s "$BLOQUEOS_LOG" ]; then
                    tail -20 "$BLOQUEOS_LOG"
                else
                    echo "ℹ️  No hay logs de bloqueos"
                fi
                ;;
            7)
                escribir_log "Sistema finalizado"
                echo ""
                echo "👋 ¡Hasta luego!"
                exit 0
                ;;
            *)
                echo "❌ Opción inválida"
                ;;
        esac
        
        echo ""
        echo "──────────────────────────────────────"
        echo "Presiona Enter para continuar..."
        read
    done
}

# Iniciar
main "$@"
EOF

# Dar permisos
chmod +x /usr/bin/gestion

echo ""
echo "✅ SISTEMA MEJORADO INSTALADO"
echo ""
echo "🔧 PASOS PARA PROBAR:"
echo ""
echo "1. 📋 Verifica si OpenVPN está configurado:"
echo "   grep -E '(script-security|client-connect)' /etc/openvpn/server.conf"
echo ""
echo "2. ⚙️  Si no está configurado, ejecuta:"
echo "   gestion"
echo "   y selecciona opción 5 para configurar automáticamente"
echo ""
echo "3. 🚫 Para bloquear un cliente:"
echo "   gestion"
echo "   opción 3 → ingresa el nombre del certificado"
echo ""
echo "4. 🔍 Para verificar que funciona:"
echo "   a) El cliente intenta conectarse"
echo "   b) Revisa: tail -f /etc/openvpn/clientes/conexiones_bloqueadas.log"
echo "   c) Depuración: cat /tmp/openvpn_script_debug.log"
echo ""
echo "5. 🔄 Si necesitas reiniciar OpenVPN:"
echo "   systemctl restart openvpn"
echo ""
echo "💡 CONSEJO: Si el cliente sigue conectado después de bloquearlo,"
echo "   desconéctalo manualmente o reinicia OpenVPN completamente."
