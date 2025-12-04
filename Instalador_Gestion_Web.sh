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
    local cliente="$1"
    if [ -f "$SUSPENDED_FILE" ] && grep -q "^$cliente:" "$SUSPENDED_FILE"; then
        return 0
    else
        return 1
    fi
}

obtener_nombre() {
    local cliente="$1"
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
    COLUMNAS=$(tput cols 2>/dev/null || echo 80)
    LINEAS=$(tput lines 2>/dev/null || echo 24)
}

# Limpiar pantalla adaptativa
limpiar_pantalla() {
    clear
    obtener_tamano
}

# Mostrar título según tamaño
mostrar_titulo() {
    obtener_tamano
    local titulo="$1"
    
    if [ "$COLUMNAS" -lt 60 ]; then
        # Móvil muy pequeño
        echo ""
        echo "🔧 $titulo"
        echo "══════════════"
    elif [ "$COLUMNAS" -lt 80 ]; then
        # Tablet
        echo ""
        echo "🔧 $titulo"
        echo "════════════════════════════"
    else
        # Desktop
        echo ""
        echo "🔧 $titulo"
        echo "══════════════════════════════════════"
    fi
    echo ""
}

# Mostrar menú responsive
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
        [ -f "$SUSPENDED_FILE" ] && bloqueados=$(wc -l < "$SUSPENDED_FILE" 2>/dev/null)
        conectados=0
        [ -f "/var/log/openvpn-status.log" ] && \
            conectados=$(grep -c "^CLIENT_LIST" /var/log/openvpn-status.log 2>/dev/null)
        
        echo "📊: 🚫$bloqueados 🟢$conectados"
        echo ""
        
        # 2 clientes máximo
        if [ "$conectados" -gt 0 ]; then
            echo "👤:"
            count=0
            while IFS=, read -r -a campos && [ $count -lt 2 ]; do
                if [[ "${campos[0]}" == "CLIENT_LIST" ]] && [[ "${campos[1]}" != "Common Name" ]]; then
                    count=$((count + 1))
                    cliente=$(echo "${campos[1]}" | sed 's|/CN=||')
                    nombre="$cliente"
                    [ ${#nombre} -gt 8 ] && nombre="${nombre:0:6}.."
                    
                    if esta_bloqueado "$cliente"; then
                        echo " $count) 🔴 $nombre"
                    else
                        echo " $count) 🟢 $nombre"
                    fi
                fi
            done < /var/log/openvpn-status.log 2>/dev/null
            
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
        [ -f "$SUSPENDED_FILE" ] && bloqueados=$(wc -l < "$SUSPENDED_FILE" 2>/dev/null)
        conectados=0
        [ -f "/var/log/openvpn-status.log" ] && \
            conectados=$(grep -c "^CLIENT_LIST" /var/log/openvpn-status.log 2>/dev/null)
        
        echo "📊 ESTADO:"
        echo "🚫 Bloqueados:  $bloqueados"
        echo "🟢 Conectados:  $conectados"
        echo ""
        
        # 3 clientes en tablet
        if [ "$conectados" -gt 0 ]; then
            echo "👥 CONECTADOS:"
            count=0
            while IFS=, read -r -a campos && [ $count -lt 3 ]; do
                if [[ "${campos[0]}" == "CLIENT_LIST" ]] && [[ "${campos[1]}" != "Common Name" ]]; then
                    count=$((count + 1))
                    cliente=$(echo "${campos[1]}" | sed 's|/CN=||')
                    ip=$(echo "${campos[2]}" | cut -d: -f1)
                    [ ${#cliente} -gt 12 ] && cliente="${cliente:0:10}.."
                    
                    if esta_bloqueado "$cliente"; then
                        echo "  $count) 🔴 $cliente"
                    else
                        echo "  $count) 🟢 $cliente"
                    fi
                    echo "      📍 $ip"
                fi
            done < /var/log/openvpn-status.log 2>/dev/null
            
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
        [ -f "$SUSPENDED_FILE" ] && bloqueados=$(wc -l < "$SUSPENDED_FILE" 2>/dev/null)
        conectados=0
        [ -f "/var/log/openvpn-status.log" ] && \
            conectados=$(grep -c "^CLIENT_LIST" /var/log/openvpn-status.log 2>/dev/null)
        
        echo "📊 ESTADO ACTUAL:"
        echo "────────────────"
        echo "🚫 Bloqueados:  $bloqueados cliente(s)"
        echo "🟢 Conectados:  $conectados cliente(s)"
        echo ""
        
        # 4 clientes en desktop
        if [ "$conectados" -gt 0 ]; then
            echo "👥 CLIENTES CONECTADOS:"
            echo ""
            count=0
            while IFS=, read -r -a campos && [ $count -lt 4 ]; do
                if [[ "${campos[0]}" == "CLIENT_LIST" ]] && [[ "${campos[1]}" != "Common Name" ]]; then
                    count=$((count + 1))
                    cliente=$(echo "${campos[1]}" | sed 's|/CN=||')
                    ip=$(echo "${campos[2]}" | cut -d: -f1)
                    nombre=$(obtener_nombre "$cliente")
                    
                    if esta_bloqueado "$cliente"; then
                        echo "  $count) 🔴 $nombre"
                    else
                        echo "  $count) 🟢 $nombre"
                    fi
                    echo "      📍 $ip"
                fi
            done < /var/log/openvpn-status.log 2>/dev/null
            
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
# MOSTRAR CLIENTES CONECTADOS (RESPONSIVE)
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
        grep "^CLIENT_LIST" /var/log/openvpn-status.log | grep -v "Common Name" | while read -r linea; do
            total=$((total + 1))
            cliente=$(echo "$linea" | cut -d, -f2 | sed 's|/CN=||')
            ip=$(echo "$linea" | cut -d, -f3 | cut -d: -f1)
            
            # Nombre corto
            nombre="$cliente"
            if [ -f "$NOMBRES_FILE" ]; then
                nom=$(grep "^$cliente:" "$NOMBRES_FILE" 2>/dev/null | cut -d: -f2)
                [ -n "$nom" ] && nombre="$nom"
            fi
            [ ${#nombre} -gt 10 ] && nombre="${nombre:0:8}.."
            
            # Estado
            if esta_bloqueado "$cliente"; then
                echo "🔴 $nombre"
            else
                echo "🟢 $nombre"
            fi
            echo "   $ip"
            echo ""
        done
        
        [ $total -gt 0 ] && echo "📊 Total: $total"
        echo ""
    
    # Para tablet
    elif [ "$COLUMNAS" -lt 80 ]; then
        echo ""
        echo "👥 CLIENTES CONECTADOS"
        echo "════════════════════════════"
        echo ""
        
        total=0
        grep "^CLIENT_LIST" /var/log/openvpn-status.log | grep -v "Common Name" | while read -r linea; do
            total=$((total + 1))
            cliente=$(echo "$linea" | cut -d, -f2 | sed 's|/CN=||')
            ip=$(echo "$linea" | cut -d, -f3 | cut -d: -f1)
            
            # Nombre
            nombre="$cliente"
            if [ -f "$NOMBRES_FILE" ]; then
                nom=$(grep "^$cliente:" "$NOMBRES_FILE" 2>/dev/null | cut -d: -f2)
                [ -n "$nom" ] && nombre="$nom"
            fi
            
            # Estado
            if esta_bloqueado "$cliente"; then
                echo "🔴 $nombre ($cliente)"
            else
                echo "🟢 $nombre ($cliente)"
            fi
            echo "   IP: $ip"
            echo ""
        done
        
        [ $total -gt 0 ] && echo "📊 Total: $total clientes"
        echo ""
    
    # Para desktop - VERSIÓN COMPLETA
    else
        echo ""
        echo "👥 CLIENTES CONECTADOS - DETALLE COMPLETO"
        echo "══════════════════════════════════════"
        echo ""
        
        total=0
        while IFS=, read -r -a campos; do
            [[ "${campos[0]}" != "CLIENT_LIST" ]] && continue
            [[ "${campos[1]}" == "Common Name" ]] && continue
            
            total=$((total + 1))
            
            cliente_raw="${campos[1]}"
            cliente=$(echo "$cliente_raw" | sed 's|/CN=||')
            ip_puerto="${campos[2]}"
            ip=$(echo "$ip_puerto" | cut -d: -f1)
            
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
            
            # Fecha y tiempo
            fecha_hora=""
            tiempo_desde=""
            
            if [ ${#campos[@]} -ge 7 ]; then
                fecha_raw="${campos[6]}"
                for ((i=7; i<${#campos[@]}; i++)); do
                    fecha_raw="$fecha_raw ${campos[i]}"
                done
                
                fecha_limpia=$(echo "$fecha_raw" | sed 's/Connected Since: //')
                fecha_hora=$(date -d "$fecha_limpia" '+%d/%m %H:%M:%S' 2>/dev/null || echo "$fecha_limpia")
                
                # Calcular tiempo
                fecha_epoch=$(date -d "$fecha_limpia" '+%s' 2>/dev/null)
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
            
            # Separador
            [ $total -lt $(grep -c "^CLIENT_LIST" /var/log/openvpn-status.log) ] && echo ""
            
        done < /var/log/openvpn-status.log
        
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
# BLOQUEO DE CLIENTES (RESPONSIVE)
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
        while IFS=, read -r -a campos; do
            if [[ "${campos[0]}" == "CLIENT_LIST" ]] && [[ "${campos[1]}" != "Common Name" ]]; then
                count=$((count + 1))
                cliente=$(echo "${campos[1]}" | sed 's|/CN=||')
                ip_real=$(echo "${campos[2]}" | cut -d: -f1)
                nombre=$(obtener_nombre "$cliente")
                
                if [ "$COLUMNAS" -lt 60 ]; then
                    echo " $count) $cliente"
                else
                    echo "  $count) $nombre ($cliente) - $ip_real"
                fi
            fi
        done < /var/log/openvpn-status.log
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
    grep -v "^$cliente:" "$SUSPENDED_FILE" 2>/dev/null > "$temp_file"
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
        systemctl restart openvpn 2>/dev/null && echo "✅ Reiniciado" || echo "⚠️  Reinicia manualmente"
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
[ -f "$SUSPENDED" ] && grep -q "^$CLIENT_CLEAN:" "$SUSPENDED" && exit 1
exit 0
SCRIPT_EOF
    
    chmod +x "$SCRIPT_FILE"
    echo "✅ Script creado"
    
    # Configurar OpenVPN
    if [ -f "$OPENVPN_CONFIG" ]; then
        sed -i '/^script-security/d' "$OPENVPN_CONFIG"
        sed -i '/^client-connect/d' "$OPENVPN_CONFIG"
        echo "" >> "$OPENVPN_CONFIG"
        echo "script-security 2" >> "$OPENVPN_CONFIG"
        echo "client-connect $SCRIPT_FILE" >> "$OPENVPN_CONFIG"
        echo "✅ Configurado $OPENVPN_CONFIG"
        
        # Recargar
        systemctl reload openvpn 2>/dev/null && echo "✅ OpenVPN recargado" || \
        systemctl restart openvpn 2>/dev/null && echo "✅ OpenVPN reiniciado" || \
        echo "⚠️  Reinicia manualmente"
    else
        echo "❌ No se encuentra $OPENVPN_CONFIG"
        echo ""
        echo "💡 Añade manualmente:"
        echo "script-security 2"
        echo "client-connect $SCRIPT_FILE"
    fi
    
    echo ""
    echo "✅ CONFIGURACIÓN COMPLETADA"
    echo ""
}

# ==============================================
# FUNCIONES RESTANTES (SIMPLIFICADAS)
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
    [ -f "$SUSPENDED_FILE" ] && \
        echo "✅ Bloqueos: $(basename "$SUSPENDED_FILE") ($(wc -l < "$SUSPENDED_FILE"))" || \
        echo "❌ Bloqueos: NO EXISTE"
    [ -f "$SCRIPT_FILE" ] && echo "✅ Script: $(basename "$SCRIPT_FILE")" || echo "❌ Script: NO EXISTE"
    [ -f "$OPENVPN_CONFIG" ] && echo "✅ Config: $(basename "$OPENVPN_CONFIG")" || echo "❌ Config: NO EXISTE"
    echo ""
    
    if [ "$COLUMNAS" -ge 60 ]; then
        echo "⚙️  OPENVPN:"
        [ -f "$OPENVPN_CONFIG" ] && grep -q "script-security" "$OPENVPN_CONFIG" && \
            echo "✅ script-security" || echo "❌ script-security"
        [ -f "$OPENVPN_CONFIG" ] && grep -q "client-connect" "$OPENVPN_CONFIG" && \
            echo "✅ client-connect" || echo "❌ client-connect"
        echo ""
    fi
    
    echo "🚫 BLOQUEADOS:"
    if [ -s "$SUSPENDED_FILE" ]; then
        count=0
        while IFS=: read -r cliente fecha _; do
            [ -n "$cliente" ] && count=$((count + 1)) && echo " $count) $cliente"
        done < "$SUSPENDED_FILE"
    else
        echo " ℹ️  No hay bloqueados"
    fi
    echo ""
}

# ==============================================
# MENÚ PRINCIPAL
# ==============================================

main() {
    log "=== Sistema iniciado ==="
    
    while true; do
        mostrar_menu
        read opcion
        
        case $opcion in
            1)
                bloquear_cliente
                ;;
            2)
                limpiar_pantalla
                echo ""
                echo "✅ DESBLOQUEAR CLIENTE"
                echo "══════════════════════════════════════"
                echo ""
                
                if [ ! -s "$SUSPENDED_FILE" ]; then
                    echo "ℹ️  No hay clientes bloqueados"
                else
                    echo "Bloqueados:"
                    num=0
                    while IFS=: read -r cliente fecha _; do
                        [ -n "$cliente" ] && num=$((num + 1)) && echo "  $num) $cliente"
                    done < "$SUSPENDED_FILE"
                    
                    echo ""
                    echo -n "Número a desbloquear: "
                    read num
                    
                    if echo "$num" | grep -qE '^[0-9]+$'; then
                        counter=0
                        while IFS=: read -r cliente fecha _; do
                            [ -n "$cliente" ] && counter=$((counter + 1))
                            [ "$counter" -eq "$num" ] && break
                        done < "$SUSPENDED_FILE"
                        
                        if [ -n "$cliente" ]; then
                            echo ""
                            echo -n "¿Desbloquear $cliente? (s/N): "
                            read confirmar
                            
                            if [ "$confirmar" = "s" ] || [ "$confirmar" = "S" ]; then
                                temp_file="/tmp/desbloqueo_$$.tmp"
                                grep -v "^$cliente:" "$SUSPENDED_FILE" > "$temp_file"
                                mv "$temp_file" "$SUSPENDED_FILE"
                                log "Cliente $cliente desbloqueado"
                                echo "✅ Desbloqueado"
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
                tail -10 "$LOG_FILE"
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
                        [ -n "$cliente" ] && echo "• $cliente - $fecha"
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
                log "Sistema finalizado"
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
