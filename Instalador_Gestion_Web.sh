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
}

esta_bloqueado() {
    cliente="$1"
    if [ -f "$SUSPENDED_FILE" ] && grep -q "^$cliente:" "$SUSPENDED_FILE"; then
        return 0
    else
        return 1
    fi
}

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

# ==============================================
# FUNCIONES RESPONSIVE
# ==============================================

# Detectar tamaño de terminal
obtener_tamano() {
    if command -v tput >/dev/null 2>&1; then
        COLUMNAS=$(tput cols 2>/dev/null || echo 80)
        LINEAS=$(tput lines 2>/dev/null || echo 24)
    else
        COLUMNAS=80
        LINEAS=24
    fi
}

# Limpiar pantalla adaptativa
limpiar_pantalla() {
    clear
    obtener_tamano
}

# ==============================================
# MOSTRAR MENÚ (COMPATIBLE CON SH)
# ==============================================

mostrar_menu() {
    limpiar_pantalla
    obtener_tamano
    
    # Móvil muy pequeño (< 60 columnas)
    if [ "$COLUMNAS" -lt 60 ]; then
        echo ""
        echo "🔧 VPN - $(date '+%H:%M')"
        echo "══════════════"
        echo ""
        
        # Estado rápido
        bloqueados=0
        if [ -f "$SUSPENDED_FILE" ]; then
            bloqueados=$(wc -l < "$SUSPENDED_FILE" 2>/dev/null || echo 0)
        fi
        
        conectados=0
        if [ -f "/var/log/openvpn-status.log" ]; then
            conectados=$(grep -c "^CLIENT_LIST" "/var/log/openvpn-status.log" 2>/dev/null || echo 0)
        fi
        
        echo "📊: 🚫$bloqueados 🟢$conectados"
        echo ""
        
        # 2 clientes máximo
        if [ "$conectados" -gt 0 ] && [ -f "/var/log/openvpn-status.log" ]; then
            echo "👤:"
            count=0
            while read -r linea; do
                if echo "$linea" | grep -q "^CLIENT_LIST" && ! echo "$linea" | grep -q "Common Name"; then
                    count=$((count + 1))
                    [ $count -gt 2 ] && break
                    
                    cliente=$(echo "$linea" | cut -d, -f2 | sed 's|/CN=||')
                    
                    # Acortar nombre
                    if [ ${#cliente} -gt 8 ]; then
                        nombre_display=$(echo "$cliente" | cut -c1-6)..
                    else
                        nombre_display="$cliente"
                    fi
                    
                    if esta_bloqueado "$cliente"; then
                        echo " $count) 🔴 $nombre_display"
                    else
                        echo " $count) 🟢 $nombre_display"
                    fi
                fi
            done < "/var/log/openvpn-status.log"
            
            [ "$conectados" -gt 2 ] && echo " ..."
            echo ""
        fi
        
        echo "══════════════"
        echo "1)🚫 2)✅"
        echo "3)🔍 4)⚙️"
        echo "5)📊 6)📋"
        echo "7)👥 8)❌"
        echo ""
        echo -n "> "
    
    # Tablet (60-79 columnas)
    elif [ "$COLUMNAS" -lt 80 ]; then
        echo ""
        echo "🔧 VPN GESTIÓN - $(date '+%H:%M')"
        echo "════════════════════════════"
        echo ""
        
        # Estado
        bloqueados=0
        if [ -f "$SUSPENDED_FILE" ]; then
            bloqueados=$(wc -l < "$SUSPENDED_FILE" 2>/dev/null || echo 0)
        fi
        
        conectados=0
        if [ -f "/var/log/openvpn-status.log" ]; then
            conectados=$(grep -c "^CLIENT_LIST" "/var/log/openvpn-status.log" 2>/dev/null || echo 0)
        fi
        
        echo "📊 ESTADO:"
        echo "🚫 Bloqueados:  $bloqueados"
        echo "🟢 Conectados:  $conectados"
        echo ""
        
        # 3 clientes en tablet
        if [ "$conectados" -gt 0 ] && [ -f "/var/log/openvpn-status.log" ]; then
            echo "👥 CONECTADOS:"
            count=0
            while read -r linea; do
                if echo "$linea" | grep -q "^CLIENT_LIST" && ! echo "$linea" | grep -q "Common Name"; then
                    count=$((count + 1))
                    [ $count -gt 3 ] && break
                    
                    cliente=$(echo "$linea" | cut -d, -f2 | sed 's|/CN=||')
                    ip=$(echo "$linea" | cut -d, -f3 | cut -d: -f1)
                    
                    # Acortar nombre
                    if [ ${#cliente} -gt 12 ]; then
                        cliente_display=$(echo "$cliente" | cut -c1-10)..
                    else
                        cliente_display="$cliente"
                    fi
                    
                    if esta_bloqueado "$cliente"; then
                        echo "  $count) 🔴 $cliente_display"
                    else
                        echo "  $count) 🟢 $cliente_display"
                    fi
                    echo "      📍 $ip"
                fi
            done < "/var/log/openvpn-status.log"
            
            [ "$conectados" -gt 3 ] && echo "  ... y $((conectados - 3)) más"
            echo ""
        fi
        
        echo "════════════════════════════"
        echo "📋 MENÚ:"
        echo ""
        echo "1) 🚫 Bloquear"
        echo "2) ✅ Desbloquear"
        echo "3) 🔍 Sistema"
        echo "4) ⚙️  Configurar"
        echo "5) 📊 Logs"
        echo "6) 📋 Bloqueados"
        echo "7) 👥 Conectados"
        echo "8) ❌ Salir"
        echo ""
        echo -n "Opción [1-8]: "
    
    # Desktop (80+ columnas)
    else
        echo ""
        echo "🔧 GESTIÓN VPN - SISTEMA DE BLOQUEO"
        echo "══════════════════════════════════════"
        echo ""
        echo "📂 Archivo de bloqueos: $(basename "$SUSPENDED_FILE")"
        echo ""
        
        # Estado completo
        bloqueados=0
        if [ -f "$SUSPENDED_FILE" ]; then
            bloqueados=$(wc -l < "$SUSPENDED_FILE" 2>/dev/null || echo 0)
        fi
        
        conectados=0
        if [ -f "/var/log/openvpn-status.log" ]; then
            conectados=$(grep -c "^CLIENT_LIST" "/var/log/openvpn-status.log" 2>/dev/null || echo 0)
        fi
        
        echo "📊 ESTADO ACTUAL:"
        echo "────────────────"
        echo "🚫 Bloqueados:  $bloqueados cliente(s)"
        echo "🟢 Conectados:  $conectados cliente(s)"
        echo ""
        
        # 4 clientes en desktop
        if [ "$conectados" -gt 0 ] && [ -f "/var/log/openvpn-status.log" ]; then
            echo "👥 CLIENTES CONECTADOS:"
            echo ""
            count=0
            while read -r linea; do
                if echo "$linea" | grep -q "^CLIENT_LIST" && ! echo "$linea" | grep -q "Common Name"; then
                    count=$((count + 1))
                    [ $count -gt 4 ] && break
                    
                    cliente=$(echo "$linea" | cut -d, -f2 | sed 's|/CN=||')
                    ip=$(echo "$linea" | cut -d, -f3 | cut -d: -f1)
                    nombre=$(obtener_nombre "$cliente")
                    
                    if esta_bloqueado "$cliente"; then
                        echo "  $count) 🔴 $nombre"
                    else
                        echo "  $count) 🟢 $nombre"
                    fi
                    echo "      📍 $ip"
                fi
            done < "/var/log/openvpn-status.log"
            
            [ "$conectados" -gt 4 ] && echo "  ... y $((conectados - 4)) más"
            echo ""
        fi
        
        echo "══════════════════════════════════════"
        echo "📋 MENÚ PRINCIPAL:"
        echo ""
        echo "1) 🚫 Bloquear cliente"
        echo "2) ✅ Desbloquear cliente"
        echo "3) 🔍 Verificar sistema"
        echo "4) ⚙️  Configurar OpenVPN"
        echo "5) 📊 Ver logs"
        echo "6) 📋 Listar bloqueados"
        echo "7) 👥 Ver conectados (detalle)"
        echo "8) ❌ Salir"
        echo ""
        echo -n "Selecciona opción [1-8]: "
    fi
}

# ==============================================
# MOSTRAR CLIENTES CONECTADOS (COMPATIBLE CON SH)
# ==============================================

mostrar_conectados() {
    limpiar_pantalla
    obtener_tamano
    
    # Verificar si existe el archivo
    if [ ! -f "/var/log/openvpn-status.log" ]; then
        echo ""
        echo "❌ No hay clientes conectados"
        echo ""
        return 1
    fi
    
    # Para móvil muy pequeño
    if [ "$COLUMNAS" -lt 60 ]; then
        echo ""
        echo "👥 CONECTADOS"
        echo ""
        
        total=0
        while read -r linea; do
            if echo "$linea" | grep -q "^CLIENT_LIST" && ! echo "$linea" | grep -q "Common Name"; then
                total=$((total + 1))
                cliente=$(echo "$linea" | cut -d, -f2 | sed 's|/CN=||')
                ip=$(echo "$linea" | cut -d, -f3 | cut -d: -f1)
                
                # Nombre corto
                nombre="$cliente"
                if [ -f "$NOMBRES_FILE" ]; then
                    nom=$(grep "^$cliente:" "$NOMBRES_FILE" 2>/dev/null | cut -d: -f2)
                    if [ -n "$nom" ]; then
                        nombre="$nom"
                    fi
                fi
                
                if [ ${#nombre} -gt 10 ]; then
                    nombre_display=$(echo "$nombre" | cut -c1-8)..
                else
                    nombre_display="$nombre"
                fi
                
                # Estado
                if esta_bloqueado "$cliente"; then
                    echo "🔴 $nombre_display"
                else
                    echo "🟢 $nombre_display"
                fi
                echo "   $ip"
                echo ""
            fi
        done < "/var/log/openvpn-status.log"
        
        [ $total -gt 0 ] && echo "📊 Total: $total"
        echo ""
    
    # Para tablet
    elif [ "$COLUMNAS" -lt 80 ]; then
        echo ""
        echo "👥 CLIENTES CONECTADOS"
        echo "════════════════════════════"
        echo ""
        
        total=0
        while read -r linea; do
            if echo "$linea" | grep -q "^CLIENT_LIST" && ! echo "$linea" | grep -q "Common Name"; then
                total=$((total + 1))
                cliente=$(echo "$linea" | cut -d, -f2 | sed 's|/CN=||')
                ip=$(echo "$linea" | cut -d, -f3 | cut -d: -f1)
                
                # Nombre
                nombre="$cliente"
                if [ -f "$NOMBRES_FILE" ]; then
                    nom=$(grep "^$cliente:" "$NOMBRES_FILE" 2>/dev/null | cut -d: -f2)
                    if [ -n "$nom" ]; then
                        nombre="$nom"
                    fi
                fi
                
                # Estado
                if esta_bloqueado "$cliente"; then
                    echo "🔴 $nombre ($cliente)"
                else
                    echo "🟢 $nombre ($cliente)"
                fi
                echo "   IP: $ip"
                echo ""
            fi
        done < "/var/log/openvpn-status.log"
        
        [ $total -gt 0 ] && echo "📊 Total: $total clientes"
        echo ""
    
    # Para desktop - VERSIÓN COMPLETA
    else
        echo ""
        echo "👥 CLIENTES CONECTADOS - DETALLE COMPLETO"
        echo "══════════════════════════════════════"
        echo ""
        
        total=0
        while read -r linea; do
            if echo "$linea" | grep -q "^CLIENT_LIST" && ! echo "$linea" | grep -q "Common Name"; then
                total=$((total + 1))
                
                cliente=$(echo "$linea" | cut -d, -f2 | sed 's|/CN=||')
                ip=$(echo "$linea" | cut -d, -f3 | cut -d: -f1)
                
                # Obtener nombre real
                nombre="$cliente"
                if [ -f "$NOMBRES_FILE" ] && [ -s "$NOMBRES_FILE" ]; then
                    nombre_linea=$(grep "^$cliente:" "$NOMBRES_FILE" 2>/dev/null)
                    if [ -n "$nombre_linea" ]; then
                        nombre=$(echo "$nombre_linea" | cut -d: -f2-)
                    fi
                fi
                
                # Estado
                if esta_bloqueado "$cliente"; then
                    circulo="🔴"
                else
                    circulo="🟢"
                fi
                
                # Extraer fecha y tiempo
                fecha_hora=""
                tiempo_desde=""
                
                # Intentar extraer fecha de conexión
                if echo "$linea" | grep -q "Connected Since:"; then
                    # Extraer todo después de "Connected Since: "
                    fecha_raw=$(echo "$linea" | sed 's/.*Connected Since: //')
                    
                    # Formatear fecha (dd/mm HH:MM:SS)
                    fecha_hora=$(date -d "$fecha_raw" '+%d/%m %H:%M:%S' 2>/dev/null || echo "$fecha_raw")
                    
                    # Calcular tiempo transcurrido
                    fecha_epoch=$(date -d "$fecha_raw" '+%s' 2>/dev/null)
                    ahora=$(date '+%s')
                    
                    if [ -n "$fecha_epoch" ] && [ "$fecha_epoch" -gt 0 ]; then
                        segundos=$((ahora - fecha_epoch))
                        
                        if [ $segundos -lt 60 ]; then
                            tiempo_desde="${segundos}s"
                        elif [ $segundos -lt 3600 ]; then
                            tiempo_desde="$((segundos / 60))m"
                        elif [ $segundos -lt 86400 ]; then
                            tiempo_desde="$((segundos / 3600))h"
                        else
                            tiempo_desde="$((segundos / 86400))d"
                        fi
                    fi
                else
                    fecha_hora="--/-- --:--:--"
                    tiempo_desde="?"
                fi
                
                # Mostrar
                echo "$circulo $nombre ($cliente)"
                echo "   IP: $ip"
                echo "   Conectado: $fecha_hora ($tiempo_desde)"
                
                # Separador (excepto último)
                if [ $total -lt $(grep -c "^CLIENT_LIST" "/var/log/openvpn-status.log" 2>/dev/null) ]; then
                    echo ""
                fi
            fi
        done < "/var/log/openvpn-status.log"
        
        if [ $total -eq 0 ]; then
            echo "ℹ️  No hay clientes conectados"
        else
            echo ""
            echo "📊 Total: $total clientes"
        fi
        echo ""
    fi
}

# ==============================================
# BLOQUEO DE CLIENTES (COMPATIBLE CON SH)
# ==============================================

bloquear_cliente() {
    limpiar_pantalla
    obtener_tamano
    
    if [ "$COLUMNAS" -lt 60 ]; then
        # Móvil pequeño
        echo ""
        echo "🚫 BLOQUEAR"
        echo "══════════"
    elif [ "$COLUMNAS" -lt 80 ]; then
        # Tablet
        echo ""
        echo "🚫 BLOQUEAR CLIENTE"
        echo "════════════════════════"
    else
        # Desktop
        echo ""
        echo "🚫 BLOQUEO DE CLIENTE"
        echo "══════════════════════════════════════"
    fi
    echo ""
    
    # Mostrar clientes conectados según tamaño
    if [ -f "/var/log/openvpn-status.log" ]; then
        if [ "$COLUMNAS" -lt 60 ]; then
            echo "📊 Conectados:"
        else
            echo "📊 Clientes conectados:"
        fi
        echo ""
        
        count=0
        while read -r linea; do
            if echo "$linea" | grep -q "^CLIENT_LIST" && ! echo "$linea" | grep -q "Common Name"; then
                count=$((count + 1))
                cliente=$(echo "$linea" | cut -d, -f2 | sed 's|/CN=||')
                ip_real=$(echo "$linea" | cut -d, -f3 | cut -d: -f1)
                nombre=$(obtener_nombre "$cliente")
                
                if [ "$COLUMNAS" -lt 60 ]; then
                    echo " $count) $cliente"
                else
                    echo "  $count) $nombre ($cliente) - $ip_real"
                fi
            fi
        done < "/var/log/openvpn-status.log"
        echo ""
    fi
    
    if [ "$COLUMNAS" -lt 60 ]; then
        echo "📝 Cliente a bloquear:"
    else
        echo "📝 Ingresa el nombre del cliente a bloquear:"
        echo "   (ej: 'client1', no '/CN=client1')"
    fi
    echo ""
    echo -n "Cliente: "
    read cliente_input
    
    if [ -z "$cliente_input" ]; then
        echo "❌ Nombre inválido"
        return 1
    fi
    
    cliente=$(echo "$cliente_input" | sed 's|/CN=||')
    
    # Verificar si ya está bloqueado
    if esta_bloqueado "$cliente"; then
        echo ""
        echo "⚠️  Ya está bloqueado"
        echo -n "¿Actualizar? (s/N): "
        read actualizar
        if [ "$actualizar" != "s" ] && [ "$actualizar" != "S" ]; then
            echo "❌ Cancelado"
            return 1
        fi
    fi
    
    echo ""
    if [ "$COLUMNAS" -ge 60 ]; then
        echo "🔍 Cliente: $cliente"
        echo "📛 Nombre: $(obtener_nombre "$cliente")"
        echo ""
    fi
    
    echo -n "¿Confirmar BLOQUEO? (s/n): "
    read confirmar
    
    if [ "$confirmar" != "s" ] && [ "$confirmar" != "S" ]; then
        echo "❌ Cancelado"
        return 1
    fi
    
    echo ""
    echo "🛡️  APLICANDO BLOQUEO..."
    echo ""
    
    # Añadir a lista de bloqueos
    temp_file="/tmp/suspended_$$.tmp"
    if [ -f "$SUSPENDED_FILE" ]; then
        grep -v "^$cliente:" "$SUSPENDED_FILE" > "$temp_file" 2>/dev/null
    else
        > "$temp_file"
    fi
    
    fecha=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$cliente:$fecha:bloqueado_por_$(whoami)" >> "$temp_file"
    mv "$temp_file" "$SUSPENDED_FILE"
    
    echo "✅ Guardado en: $(basename "$SUSPENDED_FILE")"
    log "Cliente $cliente bloqueado"
    
    # Verificar configuración
    echo "⚙️  Verificando configuración..."
    if [ ! -f "$SCRIPT_FILE" ]; then
        echo "⚠️  Configurando OpenVPN..."
        configurar_openvpn
    elif [ -f "$OPENVPN_CONFIG" ] && ! grep -q "client-connect.*$(basename "$SCRIPT_FILE")" "$OPENVPN_CONFIG"; then
        echo "⚠️  Configurando OpenVPN..."
        configurar_openvpn
    else
        echo "✅ OpenVPN configurado"
    fi
    
    # Desconectar si está conectado
    echo "🔌 Desconectando cliente..."
    if [ -f "/var/log/openvpn-status.log" ] && grep -q "/CN=$cliente" "/var/log/openvpn-status.log"; then
        echo "📡 Cliente conectado, reiniciando OpenVPN..."
        if systemctl restart openvpn 2>/dev/null; then
            echo "✅ Reiniciado"
        else
            echo "⚠️  Reinicia manualmente: systemctl restart openvpn"
        fi
    else
        echo "ℹ️  Cliente no conectado"
    fi
    
    echo ""
    echo "✅ BLOQUEO COMPLETADO"
    echo ""
    if [ "$COLUMNAS" -ge 60 ]; then
        echo "📋 Cliente: $cliente"
        echo "📅 Fecha: $fecha"
        echo ""
    fi
}

# ==============================================
# CONFIGURACIÓN OPENVPN (SIMPLIFICADA)
# ==============================================

configurar_openvpn() {
    limpiar_pantalla
    obtener_tamano
    
    if [ "$COLUMNAS" -lt 60 ]; then
        echo ""
        echo "⚙️  CONFIGURAR"
        echo "════════════"
    else
        echo ""
        echo "🔧 CONFIGURANDO OPENVPN"
        echo "══════════════════════════════════════"
    fi
    echo ""
    
    # Crear script
    cat > "$SCRIPT_FILE" << 'SCRIPT_EOF'
#!/bin/sh
CLIENT="$1"
CLIENT_CLEAN=$(echo "$CLIENT" | sed 's|/CN=||')
SUSPENDED="/etc/openvpn/clientes/suspended.txt"
if [ -f "$SUSPENDED" ] && grep -q "^$CLIENT_CLEAN:" "$SUSPENDED"; then
    exit 1
fi
exit 0
SCRIPT_EOF
    
    chmod +x "$SCRIPT_FILE"
    echo "✅ Script creado"
    
    # Configurar OpenVPN
    if [ -f "$OPENVPN_CONFIG" ]; then
        # Hacer backup
        cp "$OPENVPN_CONFIG" "${OPENVPN_CONFIG}.backup.$(date +%s)" 2>/dev/null
        
        # Eliminar configuraciones anteriores
        sed -i '/^script-security/d' "$OPENVPN_CONFIG"
        sed -i '/^client-connect/d' "$OPENVPN_CONFIG"
        
        # Añadir nuevas configuraciones
        echo "" >> "$OPENVPN_CONFIG"
        echo "# =========================================" >> "$OPENVPN_CONFIG"
        echo "# BLOQUEO DE CLIENTES (AUTOMÁTICO)" >> "$OPENVPN_CONFIG"
        echo "# =========================================" >> "$OPENVPN_CONFIG"
        echo "script-security 2" >> "$OPENVPN_CONFIG"
        echo "client-connect $SCRIPT_FILE" >> "$OPENVPN_CONFIG"
        
        echo "✅ Configurado $OPENVPN_CONFIG"
        
        # Recargar OpenVPN
        echo "🔄 Recargando OpenVPN..."
        if systemctl reload openvpn 2>/dev/null; then
            echo "✅ OpenVPN recargado"
        elif systemctl restart openvpn 2>/dev/null; then
            echo "✅ OpenVPN reiniciado"
        else
            echo "⚠️  Reinicia manualmente: systemctl restart openvpn"
        fi
    else
        echo "❌ No se encuentra $OPENVPN_CONFIG"
        echo ""
        if [ "$COLUMNAS" -ge 60 ]; then
            echo "💡 Añade manualmente:"
            echo "script-security 2"
            echo "client-connect $SCRIPT_FILE"
        fi
    fi
    
    echo ""
    echo "✅ CONFIGURACIÓN COMPLETADA"
    echo ""
}

# ==============================================
# VERIFICACIÓN DEL SISTEMA
# ==============================================

verificar_sistema() {
    limpiar_pantalla
    obtener_tamano
    
    if [ "$COLUMNAS" -lt 60 ]; then
        echo ""
        echo "🔍 SISTEMA"
        echo "═════════"
    else
        echo ""
        echo "🔍 ESTADO DEL SISTEMA"
        echo "══════════════════════════════════════"
    fi
    echo ""
    
    echo "📁 ARCHIVOS:"
    if [ -f "$SUSPENDED_FILE" ]; then
        bloqueados_count=$(wc -l < "$SUSPENDED_FILE" 2>/dev/null || echo 0)
        echo "✅ Bloqueos: $(basename "$SUSPENDED_FILE") ($bloqueados_count)"
    else
        echo "❌ Bloqueos: NO EXISTE"
    fi
    
    if [ -f "$SCRIPT_FILE" ]; then
        echo "✅ Script: $(basename "$SCRIPT_FILE")"
    else
        echo "❌ Script: NO EXISTE"
    fi
    
    if [ -f "$OPENVPN_CONFIG" ]; then
        echo "✅ Config: $(basename "$OPENVPN_CONFIG")"
    else
        echo "❌ Config: NO EXISTE"
    fi
    echo ""
    
    if [ "$COLUMNAS" -ge 60 ]; then
        echo "⚙️  OPENVPN:"
        if [ -f "$OPENVPN_CONFIG" ] && grep -q "script-security" "$OPENVPN_CONFIG"; then
            echo "✅ script-security"
        else
            echo "❌ script-security"
        fi
        
        if [ -f "$OPENVPN_CONFIG" ] && grep -q "client-connect" "$OPENVPN_CONFIG"; then
            echo "✅ client-connect"
        else
            echo "❌ client-connect"
        fi
        echo ""
    fi
    
    echo "🚫 BLOQUEADOS:"
    if [ -s "$SUSPENDED_FILE" ]; then
        count=0
        while IFS=: read -r cliente fecha _; do
            if [ -n "$cliente" ]; then
                count=$((count + 1))
                echo " $count) $cliente"
            fi
        done < "$SUSPENDED_FILE"
    else
        echo " ℹ️  No hay bloqueados"
    fi
    echo ""
}

# ==============================================
# FUNCIÓN PRINCIPAL
# ==============================================

main() {
    # Iniciar log
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Sistema iniciado" >> "$LOG_FILE"
    
    while true; do
        mostrar_menu
        read opcion
        
        case $opcion in
            1)
                bloquear_cliente
                ;;
            2)
                limpiar_pantalla
                obtener_tamano
                
                if [ "$COLUMNAS" -lt 60 ]; then
                    echo ""
                    echo "✅ DESBLOQUEAR"
                    echo "═════════════"
                else
                    echo ""
                    echo "✅ DESBLOQUEAR CLIENTE"
                    echo "══════════════════════════════════════"
                fi
                echo ""
                
                if [ ! -s "$SUSPENDED_FILE" ]; then
                    echo "ℹ️  No hay clientes bloqueados"
                else
                    echo "Bloqueados:"
                    num=0
                    while IFS=: read -r cliente fecha _; do
                        if [ -n "$cliente" ]; then
                            num=$((num + 1))
                            echo "  $num) $cliente"
                        fi
                    done < "$SUSPENDED_FILE"
                    
                    echo ""
                    echo -n "Número a desbloquear: "
                    read num
                    
                    if echo "$num" | grep -qE '^[0-9]+$'; then
                        counter=0
                        cliente_desbloquear=""
                        while IFS=: read -r cliente fecha _; do
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
                            echo -n "¿Desbloquear $cliente_desbloquear? (s/N): "
                            read confirmar
                            
                            if [ "$confirmar" = "s" ] || [ "$confirmar" = "S" ]; then
                                temp_file="/tmp/desbloqueo_$$.tmp"
                                grep -v "^$cliente_desbloquear:" "$SUSPENDED_FILE" > "$temp_file"
                                mv "$temp_file" "$SUSPENDED_FILE"
                                echo "$(date '+%Y-%m-%d %H:%M:%S') - Cliente $cliente_desbloquear desbloqueado" >> "$LOG_FILE"
                                echo "✅ Desbloqueado"
                                
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
                limpiar_pantalla
                echo ""
                echo "📊 LOGS DEL SISTEMA"
                echo "══════════════════════════════════════"
                echo ""
                echo "Últimas 10 líneas:"
                tail -10 "$LOG_FILE" 2>/dev/null || echo "No hay logs"
                echo ""
                ;;
            6)
                limpiar_pantalla
                echo ""
                echo "📋 CLIENTES BLOQUEADOS"
                echo "══════════════════════════════════════"
                echo ""
                if [ -s "$SUSPENDED_FILE" ]; then
                    while IFS=: read -r cliente fecha _; do
                        if [ -n "$cliente" ]; then
                            echo "• $cliente - $fecha"
                        fi
                    done < "$SUSPENDED_FILE"
                else
                    echo "ℹ️  No hay clientes bloqueados"
                fi
                echo ""
                ;;
            7)
                mostrar_conectados
                ;;
            8)
                echo ""
                echo "👋 ¡Hasta luego!"
                echo "$(date '+%Y-%m-%d %H:%M:%S') - Sistema finalizado" >> "$LOG_FILE"
                exit 0
                ;;
            *)
                echo "❌ Opción inválida"
                ;;
        esac
        
        echo ""
        if [ "$COLUMNAS" -lt 60 ]; then
            echo "───"
        else
            echo "──────────────────────────────────────"
        fi
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
echo "🚀 EJECUTA: sudo gestion"
echo ""
