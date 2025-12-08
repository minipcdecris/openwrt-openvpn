#!/bin/sh

echo ""
echo "🔧 SISTEMA DE BLOQUEO - INSTALACIÓN DEFINITIVA"
echo "=============================================="

# Instalar el sistema mejorado
cat > /usr/bin/gestion << 'EOF'
#!/bin/sh

# ==============================================
# CONFIGURACIÓN DETECTADA AUTOMÁTICAMENTE
# ==============================================

# Buscar archivo de bloqueos existente
find_suspended_file() {
    # Posibles ubicaciones
    for file in \
        "/etc/openvpn/clientes/suspended.txt" \
        "/etc/openvpn/suspended_clients.txt" \
        "/etc/openvpn/clientes/bloqueados.txt" \
        "/etc/openvpn/bloqueados.txt" \
        "/etc/openvpn/blocked_clients.txt"; do
        if [ -f "$file" ]; then
            echo "$file"
            return 0
        fi
    done
    
    # Si no existe, usar la predeterminada
    echo "/etc/openvpn/clientes/suspended.txt"
    return 1
}

# Buscar archivo de nombres
find_names_file() {
    for file in \
        "/etc/openvpn/clientes/nombres.txt" \
        "/etc/openvpn/nombres.txt"; do
        if [ -f "$file" ]; then
            echo "$file"
            return 0
        fi
    done
    echo "/etc/openvpn/clientes/nombres.txt"
}

# Buscar script de verificación
find_script_file() {
    for file in \
        "/etc/openvpn/scripts/verificar_cliente.sh" \
        "/etc/openvpn/check_client.sh" \
        "/etc/openvpn/client-connect.sh"; do
        if [ -f "$file" ]; then
            echo "$file"
            return 0
        fi
    done
    echo "/etc/openvpn/scripts/verificar_cliente.sh"
}

# Archivos detectados automáticamente
SUSPENDED_FILE=$(find_suspended_file)
NOMBRES_FILE=$(find_names_file)
SCRIPT_FILE=$(find_script_file)
LOG_FILE="/var/log/vpn_gestion.log"
OPENVPN_CONFIG="/etc/openvpn/server.conf"

# Crear directorios necesarios
mkdir -p /etc/openvpn/clientes
mkdir -p /etc/openvpn/scripts
touch "$SUSPENDED_FILE"
touch "$NOMBRES_FILE"
touch "$LOG_FILE"

# ==============================================
# FUNCIONES BÁSICAS
# ==============================================

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
    echo "$1"
}

esta_bloqueado() {
    cliente=$(echo "$1" | sed 's|/CN=||')
    if [ -f "$SUSPENDED_FILE" ] && grep -q "^$cliente:" "$SUSPENDED_FILE"; then
        return 0  # true
    else
        return 1  # false
    fi
}

obtener_nombre() {
    cliente=$(echo "$1" | sed 's|/CN=||')
    if [ -f "$NOMBRES_FILE" ]; then
        nombre=$(grep "^$cliente:" "$NOMBRES_FILE" 2>/dev/null | cut -d: -f2-)
        if [ -n "$nombre" ]; then
            echo "$nombre"
            return
        fi
    fi
    echo "$cliente"
}

# ==============================================
# CONFIGURACIÓN OPENVPN - MÉTODO GARANTIZADO
# ==============================================

configurar_openvpn() {
    echo ""
    echo "🔧 CONFIGURANDO OPENVPN PARA BLOQUEO..."
    echo ""
    
    # 1. Crear script de verificación SUPER SIMPLE
    cat > "$SCRIPT_FILE" << 'SCRIPT_EOF'
#!/bin/sh
# Script ULTRA SIMPLE para bloquear clientes

CLIENT="$1"
IP_REAL="$2"

# Limpiar nombre
CLIENT_CLEAN=$(echo "$CLIENT" | sed 's|/CN=||')

# Archivo de bloqueos (buscar automáticamente)
SUSPENDED=""
for file in /etc/openvpn/clientes/suspended.txt /etc/openvpn/suspended_clients.txt; do
    if [ -f "$file" ]; then
        SUSPENDED="$file"
        break
    fi
done

if [ -z "$SUSPENDED" ]; then
    # Si no existe, crear uno
    SUSPENDED="/etc/openvpn/clientes/suspended.txt"
    mkdir -p /etc/openvpn/clientes
    touch "$SUSPENDED"
fi

# DEBUG
echo "$(date) - Verificando: $CLIENT_CLEAN" >> /tmp/vpn_check.log

# Verificar bloqueo
if grep -q "^$CLIENT_CLEAN:" "$SUSPENDED"; then
    echo "$(date) - BLOQUEADO: $CLIENT_CLEAN desde $IP_REAL" >> /tmp/vpn_blocked.log
    exit 1
fi

exit 0
SCRIPT_EOF
    
    chmod +x "$SCRIPT_FILE"
    log "Script creado: $SCRIPT_FILE"
    
    # 2. Configurar OpenVPN server.conf
    if [ -f "$OPENVPN_CONFIG" ]; then
        echo "📝 Configurando $OPENVPN_CONFIG..."
        
        # Backup
        cp "$OPENVPN_CONFIG" "${OPENVPN_CONFIG}.backup.$(date +%s)"
        
        # Eliminar configuraciones anteriores de script
        sed -i '/^script-security/d' "$OPENVPN_CONFIG"
        sed -i '/^client-connect/d' "$OPENVPN_CONFIG"
        sed -i '/^auth-user-pass-verify/d' "$OPENVPN_CONFIG"
        
        # Añadir nuevas configuraciones
        echo "" >> "$OPENVPN_CONFIG"
        echo "# =========================================" >> "$OPENVPN_CONFIG"
        echo "# BLOQUEO DE CLIENTES (AUTOMÁTICO)" >> "$OPENVPN_CONFIG"
        echo "# =========================================" >> "$OPENVPN_CONFIG"
        echo "script-security 2" >> "$OPENVPN_CONFIG"
        echo "client-connect $SCRIPT_FILE" >> "$OPENVPN_CONFIG"
        
        log "OpenVPN configurado con client-connect"
        
        # 3. Recargar OpenVPN
        echo "🔄 Recargando OpenVPN..."
        if systemctl reload openvpn 2>/dev/null; then
            echo "✅ OpenVPN recargado"
        elif /etc/init.d/openvpn reload 2>/dev/null; then
            echo "✅ OpenVPN recargado"
        else
            echo "⚠️  No se pudo recargar, reinicia manualmente:"
            echo "   systemctl restart openvpn"
        fi
    else
        echo "❌ ERROR: No se encuentra $OPENVPN_CONFIG"
        echo ""
        echo "💡 SOLUCIÓN:"
        echo "1. Encuentra tu archivo de configuración:"
        echo "   find /etc -name '*.conf' | grep -i vpn"
        echo "2. Añade manualmente estas líneas:"
        echo "   script-security 2"
        echo "   client-connect $SCRIPT_FILE"
        echo "3. Reinicia OpenVPN"
    fi
    
    echo ""
    echo "✅ CONFIGURACIÓN COMPLETADA"
    echo "==========================="
}

# ==============================================
# BLOQUEO DE CLIENTES - MÉTODO EFECTIVO
# ==============================================

bloquear_cliente() {
    clear
    echo ""
    echo "🚫 BLOQUEO DE CLIENTE"
    echo "===================="
    echo ""
    
    # Mostrar clientes conectados
    if [ -f "/var/log/openvpn-status.log" ]; then
        echo "📊 Clientes conectados:"
        echo ""
        while read -r line; do
            if echo "$line" | grep -q "^CLIENT_LIST" && ! echo "$line" | grep -q "HEADER"; then
                cliente=$(echo "$line" | awk '{print $2}' | sed 's|/CN=||')
                if [ -n "$cliente" ] && [ "$cliente" != "UNDEF" ]; then
                    nombre=$(obtener_nombre "$cliente")
                    ip_real=$(echo "$line" | awk '{print $3}')
                    echo "  • $nombre ($cliente) - $ip_real"
                fi
            fi
        done < /var/log/openvpn-status.log
        echo ""
    fi
    
    echo "📝 Ingresa el nombre del cliente a bloquear:"
    echo "   (ej: 'client1', no '/CN=client1')"
    echo ""
    echo -n "Cliente: "
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
        echo -n "¿Actualizar fecha de bloqueo? (s/N): "
        read actualizar
        if [ "$actualizar" != "s" ] && [ "$actualizar" != "S" ]; then
            echo "❌ Operación cancelada"
            return 1
        fi
    fi
    
    echo ""
    echo "🔍 Cliente: $cliente"
    echo "📛 Nombre: $(obtener_nombre "$cliente")"
    echo ""
    echo -n "¿Confirmar BLOQUEO? (sí=s, no=n): "
    read confirmar
    
    if [ "$confirmar" != "s" ] && [ "$confirmar" != "S" ]; then
        echo "❌ Bloqueo cancelado"
        return 1
    fi
    
    echo ""
    echo "🛡️  APLICANDO BLOQUEO..."
    echo ""
    
    # 1. Añadir a lista de bloqueos
    echo "1. 📋 Añadiendo a lista de bloqueos..."
    temp_file="/tmp/suspended_$$.tmp"
    grep -v "^$cliente:" "$SUSPENDED_FILE" 2>/dev/null > "$temp_file"
    fecha=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$cliente:$fecha:bloqueado_por_$(whoami)" >> "$temp_file"
    mv "$temp_file" "$SUSPENDED_FILE"
    
    echo "   ✅ Guardado en: $SUSPENDED_FILE"
    log "Cliente $cliente bloqueado"
    
    # 2. Verificar configuración OpenVPN
    echo "2. ⚙️  Verificando configuración OpenVPN..."
    if [ ! -f "$SCRIPT_FILE" ]; then
        echo "   ⚠️  Script no encontrado, creando..."
        configurar_openvpn
    elif [ -f "$OPENVPN_CONFIG" ] && ! grep -q "client-connect.*$(basename "$SCRIPT_FILE")" "$OPENVPN_CONFIG"; then
        echo "   ⚠️  OpenVPN no configurado, configurando..."
        configurar_openvpn
    else
        echo "   ✅ OpenVPN ya está configurado"
    fi
    
    # 3. Desconectar cliente si está conectado
    echo "3. 🔌 Desconectando cliente..."
    if [ -f "/var/log/openvpn-status.log" ] && grep -q "/CN=$cliente" "/var/log/openvpn-status.log"; then
        echo "   📡 Cliente está conectado, forzando desconexión..."
        
        # Método simple: reiniciar OpenVPN
        echo "   🔄 Reiniciando OpenVPN para aplicar bloqueo inmediato..."
        if systemctl restart openvpn 2>/dev/null; then
            echo "   ✅ OpenVPN reiniciado"
        else
            echo "   ⚠️  Reinicia manualmente: systemctl restart openvpn"
        fi
    else
        echo "   ℹ️  Cliente no está conectado"
    fi
    
    echo ""
    echo "✅ BLOQUEO COMPLETADO"
    echo "===================="
    echo ""
    echo "📋 Cliente bloqueado: $cliente"
    echo "📅 Fecha: $fecha"
    echo ""
    echo "🔍 PARA VERIFICAR:"
    echo "   1. El cliente intentará reconectar y FALLARÁ"
    echo "   2. Ver logs: tail -f $LOG_FILE"
    echo "   3. Ver intentos bloqueados: tail -f /tmp/vpn_blocked.log"
    echo ""
    echo "💡 Si el cliente sigue conectado, REINICIA OPENVPN:"
    echo "   systemctl restart openvpn"
}

# ==============================================
# VERIFICACIÓN DEL SISTEMA
# ==============================================

verificar_sistema() {
    clear
    echo ""
    echo "🔍 ESTADO DEL SISTEMA"
    echo "===================="
    echo ""
    
    # 1. Archivos de configuración
    echo "📁 ARCHIVOS DE CONFIGURACIÓN:"
    echo "   • Bloqueos: $SUSPENDED_FILE"
    if [ -f "$SUSPENDED_FILE" ]; then
        echo "     ✅ Existe ($(wc -l < "$SUSPENDED_FILE") clientes bloqueados)"
    else
        echo "     ❌ NO EXISTE"
    fi
    
    echo "   • Script: $SCRIPT_FILE"
    if [ -f "$SCRIPT_FILE" ]; then
        echo "     ✅ Existe"
    else
        echo "     ❌ NO EXISTE"
    fi
    
    echo "   • Config OpenVPN: $OPENVPN_CONFIG"
    if [ -f "$OPENVPN_CONFIG" ]; then
        echo "     ✅ Existe"
    else
        echo "     ❌ NO EXISTE"
    fi
    echo ""
    
    # 2. Configuración OpenVPN
    echo "⚙️  CONFIGURACIÓN OPENVPN:"
    if [ -f "$OPENVPN_CONFIG" ]; then
        if grep -q "script-security" "$OPENVPN_CONFIG"; then
            echo "   ✅ script-security configurado"
        else
            echo "   ❌ script-security NO configurado"
        fi
        
        if grep -q "client-connect" "$OPENVPN_CONFIG"; then
            echo "   ✅ client-connect configurado"
            grep "client-connect" "$OPENVPN_CONFIG"
        else
            echo "   ❌ client-connect NO configurado"
        fi
    fi
    echo ""
    
    # 3. Clientes bloqueados
    echo "🚫 CLIENTES BLOQUEADOS:"
    if [ -s "$SUSPENDED_FILE" ]; then
        while IFS=: read -r cliente fecha motivo; do
            if [ -n "$cliente" ]; then
                echo "   • $cliente - $fecha"
            fi
        done < "$SUSPENDED_FILE"
    else
        echo "   ℹ️  No hay clientes bloqueados"
    fi
    echo ""
    
    # 4. Clientes conectados
    echo "📊 CLIENTES CONECTADOS:"
    if [ -f "/var/log/openvpn-status.log" ]; then
        count=0
        while read -r line; do
            if echo "$line" | grep -q "^CLIENT_LIST" && ! echo "$line" | grep -q "HEADER"; then
                cliente=$(echo "$line" | awk '{print $2}' | sed 's|/CN=||')
                if [ -n "$cliente" ] && [ "$cliente" != "UNDEF" ]; then
                    count=$((count + 1))
                    ip=$(echo "$line" | awk '{print $3}')
                    
                    if esta_bloqueado "$cliente"; then
                        estado="🚫 BLOQUEADO"
                    else
                        estado="🟢 ACTIVO"
                    fi
                    
                    echo "   $count) $cliente - $estado - $ip"
                fi
            fi
        done < /var/log/openvpn-status.log
        
        if [ $count -eq 0 ]; then
            echo "   ℹ️  No hay clientes conectados"
        fi
    else
        echo "   ⚠️  No se puede leer estado"
    fi
    echo ""
    
    # 5. Recomendaciones
    echo "💡 RECOMENDACIONES:"
    if [ ! -f "$SCRIPT_FILE" ]; then
        echo "   1. Ejecuta 'Configurar OpenVPN' (opción 4)"
    fi
    if [ -f "$OPENVPN_CONFIG" ] && ! grep -q "client-connect" "$OPENVPN_CONFIG"; then
        echo "   2. Ejecuta 'Configurar OpenVPN' (opción 4)"
    fi
    if [ -s "$SUSPENDED_FILE" ]; then
        echo "   3. Si un cliente bloqueado sigue conectado, reinicia OpenVPN"
    fi
}

# ==============================================
# MENÚ PRINCIPAL
# ==============================================

mostrar_menu() {
    clear
    echo ""
    echo "🔧 GESTIÓN VPN - SISTEMA DE BLOQUEO"
    echo "==================================="
    echo ""
    echo "📂 Archivo de bloqueos detectado:"
    echo "   $(basename "$SUSPENDED_FILE")"
    echo ""
    echo "1) 🚫 Bloquear cliente"
    echo "2) ✅ Desbloquear cliente"
    echo "3) 🔍 Verificar estado del sistema"
    echo "4) ⚙️  Configurar OpenVPN (IMPORTANTE)"
    echo "5) 📊 Ver logs"
    echo "6) 📋 Listar clientes bloqueados"
    echo "7) ❌ Salir"
    echo ""
    echo -n "Selecciona opción [1-7]: "
}

# Función principal
main() {
    log "=== Sistema iniciado ==="
    log "Archivo de bloqueos: $SUSPENDED_FILE"
    log "Script de verificación: $SCRIPT_FILE"
    
    while true; do
        mostrar_menu
        read opcion
        
        case $opcion in
            1)
                bloquear_cliente
                ;;
            2)
                echo ""
                echo "✅ DESBLOQUEAR CLIENTE"
                echo "====================="
                echo ""
                
                if [ ! -s "$SUSPENDED_FILE" ]; then
                    echo "ℹ️  No hay clientes bloqueados"
                else
                    echo "Clientes bloqueados:"
                    num=0
                    while IFS=: read -r cliente fecha motivo; do
                        if [ -n "$cliente" ]; then
                            num=$((num + 1))
                            echo "  $num) $cliente - $fecha"
                        fi
                    done < "$SUSPENDED_FILE"
                    
                    echo ""
                    echo -n "Número del cliente a desbloquear: "
                    read num
                    
                    if echo "$num" | grep -qE '^[0-9]+$'; then
                        cliente_desbloquear=""
                        counter=0
                        while IFS=: read -r cliente fecha motivo; do
                            if [ -n "$cliente" ]; then
                                counter=$((counter + 1))
                                if [ "$counter" -eq "$num" ]; then
                                    cliente_desbloquear="$cliente"
                                    break
                                fi
                            fi
                        done < "$SUSPENDED_FILE"
                        
                        if [ -n "$cliente_desbloquear" ]; then
                            echo ""
                            echo -n "¿Desbloquear a $cliente_desbloquear? (s/N): "
                            read confirmar
                            
                            if [ "$confirmar" = "s" ] || [ "$confirmar" = "S" ]; then
                                temp_file="/tmp/desbloqueo_$$.tmp"
                                grep -v "^$cliente_desbloquear:" "$SUSPENDED_FILE" > "$temp_file"
                                mv "$temp_file" "$SUSPENDED_FILE"
                                log "Cliente $cliente_desbloquear desbloqueado"
                                echo "✅ Cliente desbloqueado"
                                
                                # Recargar OpenVPN
                                systemctl reload openvpn 2>/dev/null
                            fi
                        fi
                    fi
                fi
                ;;
            3)
                verificar_sistema
                ;;
            4)
                configurar_openvpn
                ;;
            5)
                echo ""
                echo "📜 LOGS DEL SISTEMA"
                echo "=================="
                echo ""
                echo "Últimas 20 líneas:"
                tail -20 "$LOG_FILE"
                echo ""
                echo "Debug de bloqueos:"
                tail -10 /tmp/vpn_blocked.log 2>/dev/null || echo "No hay logs de bloqueos"
                ;;
            6)
                echo ""
                echo "📋 CLIENTES BLOQUEADOS"
                echo "====================="
                echo ""
                if [ -s "$SUSPENDED_FILE" ]; then
                    cat "$SUSPENDED_FILE" | while IFS=: read -r cliente fecha motivo; do
                        if [ -n "$cliente" ]; then
                            echo "• $cliente - $fecha"
                        fi
                    done
                else
                    echo "ℹ️  No hay clientes bloqueados"
                fi
                ;;
            7)
                echo ""
                echo "👋 ¡Hasta luego!"
                log "Sistema finalizado"
                exit 0
                ;;
            *)
                echo "❌ Opción inválida"
                ;;
        esac
        
        echo ""
        echo "──────────────────────────────────────"
        echo "Presiona Enter para continuar..."
        read dummy
    done
}

# Iniciar
main
EOF

# Dar permisos
chmod +x /usr/bin/gestion

echo ""
echo "✅ SISTEMA INSTALADO"
echo ""
echo "🚀 PASOS PARA CONFIGURAR:"
echo ""
echo "1. ${RED}CONFIGURA OPENVPN:${NC}"
echo "   Ejecuta: gestion"
echo "   Selecciona opción 4 (Configurar OpenVPN)"
echo "   Esto configurará automáticamente server.conf"
echo ""
echo "2. ${RED}SI EL PASO 1 FALLA, HAZLO MANUALMENTE:${NC}"
echo "   Edita /etc/openvpn/server.conf"
echo "   Añade al final:"
echo ""
echo "   script-security 2"
echo "   client-connect /etc/openvpn/scripts/verificar_cliente.sh"
echo ""
echo "3. ${RED}REINICIA OPENVPN:${NC}"
echo "   systemctl restart openvpn"
echo ""
echo "4. ${RED}PRUEBA EL BLOQUEO:${NC}"
echo "   gestion → opción 1 → bloquea un cliente"
echo ""
echo "📌 El sistema detectará automáticamente tu configuración existente."
