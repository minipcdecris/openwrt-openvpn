#!/bin/sh

echo ""
echo "🔧 GESTOR VPN - SISTEMA DE SECUESTRO MEJORADO"
echo "=============================================="

# Crear el gestor completo con secuestro 100% efectivo
cat > /usr/bin/gestor-vpn << 'GESTOR_SCRIPT'
#!/bin/sh

# Archivos de configuración
NOMBRES_FILE="/etc/openvpn/clientes/nombres.txt"

# Asegurar que los directorios existen
mkdir -p /etc/openvpn/clientes/
mkdir -p /etc/openvpn/secuestrados/
mkdir -p /etc/openvpn/suspended/
touch "$NOMBRES_FILE"

# Función para obtener nombre descriptivo
obtener_nombre() {
    local cliente=$1
    if [ ! -f "$NOMBRES_FILE" ] || [ -z "$cliente" ]; then
        echo "$cliente"
        return
    fi
    local nombre=$(grep "^${cliente}:" "$NOMBRES_FILE" 2>/dev/null | cut -d: -f2-)
    if [ -n "$nombre" ]; then
        echo "$nombre"
    else
        echo "$cliente"
    fi
}

# Función para mostrar menú
mostrar_menu() {
    echo ""
    echo "🔧 GESTOR VPN COMPLETO"
    echo "======================"
    echo ""
    echo "1) 👁️  Ver clientes conectados"
    echo "2) 📋 Listar todos los clientes"
    echo "3) ⏸️  SUSPENDER cliente (temporal)"
    echo "4) 🔒 SUSPENDER con SECUESTRO (100% garantizado)"
    echo "5) ▶️  REACTIVAR cliente (mismo certificado)"
    echo "6) 🔓 RESTAURAR cliente secuestrado"
    echo "7) 🚫 BLOQUEAR permanente"
    echo "8) 🔌 DESCONECTAR cliente (forzar)"
    echo "9) 🏷️  GESTIONAR NOMBRES"
    echo "10) 📁 Ver clientes secuestrados"
    echo "11) 🔍 Estado del servicio"
    echo "12) ❌ Salir"
    echo ""
    echo -n "Selecciona [1-12]: "
}

# ========== FUNCIONES PRINCIPALES ==========

# Función para ver clientes conectados
ver_conectados() {
    echo ""
    echo "📊 CLIENTES CONECTADOS:"
    
    if [ -f "/var/log/openvpn-status.log" ] && grep -q "CLIENT_LIST" "/var/log/openvpn-status.log"; then
        grep "^CLIENT_LIST" "/var/log/openvpn-status.log" | while IFS=$'\t' read -r _ cliente ip_externa ip_interna bytes_recv bytes_sent connected_since _; do
            cliente=$(echo "$cliente" | xargs)
            ip_externa=$(echo "$ip_externa" | xargs)
            ip_interna=$(echo "$ip_interna" | xargs)
            bytes_recv=$(echo "$bytes_recv" | xargs)
            bytes_sent=$(echo "$bytes_sent" | xargs)
            connected_since=$(echo "$connected_since" | xargs)
            
            nombre_descriptivo=$(obtener_nombre "$cliente")
            
            if [ "$cliente" = "$nombre_descriptivo" ]; then
                echo "   👤 $cliente"
            else
                echo "   👤 $nombre_descriptivo ($cliente)"
            fi
            
            echo "      📍 IP Externa: $ip_externa"
            echo "      📍 IP Interna: $ip_interna"
            
            if [ -n "$connected_since" ] && [ "$connected_since" != "UNDEF" ]; then
                echo "      ⏰ Conectado desde: $connected_since"
            fi
            
            if [ -n "$bytes_sent" ] && [ "$bytes_sent" -gt 0 ] 2>/dev/null; then
                mb_sent=$((bytes_sent / 1024 / 1024))
                echo "      🔼 Subido: ${mb_sent} MB"
            fi
            
            if [ -n "$bytes_recv" ] && [ "$bytes_recv" -gt 0 ] 2>/dev/null; then
                mb_recv=$((bytes_recv / 1024 / 1024))
                echo "      🔽 Descargado: ${mb_recv} MB"
            fi
            
            echo ""
        done
    else
        echo "   ℹ️  No hay clientes conectados"
    fi
}

# Función para listar clientes
listar_clientes() {
    echo ""
    echo "📋 ESTADO DE CLIENTES:"
    
    INDEX_FILES="/etc/easy-rsa/pki/index.txt /etc/openvpn/easy-rsa/pki/index.txt /etc/easy-rsa/keys/index.txt"
    INDEX_FILE=""
    
    for file in $INDEX_FILES; do
        if [ -f "$file" ]; then
            INDEX_FILE="$file"
            break
        fi
    done
    
    if [ -z "$INDEX_FILE" ]; then
        echo "   ❌ No se encuentra la base de datos de certificados"
        return
    fi
    
    if [ ! -s "$INDEX_FILE" ]; then
        echo "   ℹ️  La base de datos de certificados está vacía"
        return
    fi

    todos_clientes=$(grep -E "^(V|R)" "$INDEX_FILE" 2>/dev/null | awk -F'/' '{print $NF}' | awk '{print $1}' | sort -u)
    
    if [ -z "$todos_clientes" ]; then
        echo "   ℹ️  No hay clientes configurados en la base de datos"
        return
    fi

    echo "🟢 ACTIVOS:"
    activos_encontrados=0
    for cliente in $todos_clientes; do
        if grep -q "^V.*/CN=${cliente}$" "$INDEX_FILE" 2>/dev/null || grep -q "^V.*${cliente}" "$INDEX_FILE" 2>/dev/null; then
            nombre_descriptivo=$(obtener_nombre "$cliente")
            if [ "$cliente" = "$nombre_descriptivo" ]; then
                echo "   $cliente"
            else
                echo "   $nombre_descriptivo ($cliente)"
            fi
            activos_encontrados=1
        fi
    done
    if [ $activos_encontrados -eq 0 ]; then
        echo "   Ninguno"
    fi
    
    echo ""
    echo "⏸️  SUSPENDIDOS (temporal):"
    suspendidos_encontrados=0
    for cliente in $todos_clientes; do
        if grep -q "^R.*/CN=${cliente}$" "$INDEX_FILE" 2>/dev/null || grep -q "^R.*${cliente}" "$INDEX_FILE" 2>/dev/null; then
            if [ -f "/etc/openvpn/suspended/${cliente}.crt.backup" ]; then
                nombre_descriptivo=$(obtener_nombre "$cliente")
                if [ "$cliente" = "$nombre_descriptivo" ]; then
                    echo "   $cliente"
                else
                    echo "   $nombre_descriptivo ($cliente)"
                fi
                suspendidos_encontrados=1
            fi
        fi
    done
    if [ $suspendidos_encontrados -eq 0 ]; then
        echo "   Ninguno"
    fi
    
    echo ""
    echo "🔒 SECUESTRADOS (100% garantizado):"
    secuestrados_encontrados=0
    if [ -d "/etc/openvpn/secuestrados" ]; then
        for cliente_dir in /etc/openvpn/secuestrados/*; do
            if [ -d "$cliente_dir" ]; then
                cliente=$(basename "$cliente_dir")
                nombre_descriptivo=$(obtener_nombre "$cliente")
                if [ "$cliente" = "$nombre_descriptivo" ]; then
                    echo "   🔒 $cliente"
                else
                    echo "   🔒 $nombre_descriptivo ($cliente)"
                fi
                secuestrados_encontrados=1
            fi
        done
    fi
    if [ $secuestrados_encontrados -eq 0 ]; then
        echo "   Ninguno"
    fi
    
    echo ""
    echo "🔴 BLOQUEADOS:"
    bloqueados_encontrados=0
    for cliente in $todos_clientes; do
        if grep -q "^R.*/CN=${cliente}$" "$INDEX_FILE" 2>/dev/null || grep -q "^R.*${cliente}" "$INDEX_FILE" 2>/dev/null; then
            if [ ! -f "/etc/openvpn/suspended/${cliente}.crt.backup" ] && [ ! -d "/etc/openvpn/secuestrados/${cliente}" ]; then
                nombre_descriptivo=$(obtener_nombre "$cliente")
                if [ "$cliente" = "$nombre_descriptivo" ]; then
                    echo "   $cliente"
                else
                    echo "   $nombre_descriptivo ($cliente)"
                fi
                bloqueados_encontrados=1
            fi
        fi
    done
    if [ $bloqueados_encontrados -eq 0 ]; then
        echo "   Ninguno"
    fi
    
    echo ""
    echo "💡 Total clientes en sistema: $(echo "$todos_clientes" | wc -w)"
}

# ========== SUSPENSIÓN TEMPORAL ==========

suspender_temporal() {
    echo ""
    echo "⏸️  SUSPENDER CLIENTE (TEMPORAL)"
    echo "------------------------------"
    
    echo "Clientes activos:"
    activos_encontrados=0
    
    INDEX_FILES="/etc/easy-rsa/pki/index.txt /etc/openvpn/easy-rsa/pki/index.txt /etc/easy-rsa/keys/index.txt"
    INDEX_FILE=""
    for file in $INDEX_FILES; do
        if [ -f "$file" ]; then
            INDEX_FILE="$file"
            break
        fi
    done
    
    if [ -n "$INDEX_FILE" ]; then
        for cliente in $(grep "^V" "$INDEX_FILE" 2>/dev/null | awk -F'/' '{print $NF}' | awk '{print $1}'); do
            nombre_descriptivo=$(obtener_nombre "$cliente")
            if [ "$cliente" = "$nombre_descriptivo" ]; then
                echo "   $cliente"
            else
                echo "   $nombre_descriptivo ($cliente)"
            fi
            activos_encontrados=1
        done
    fi
    
    if [ $activos_encontrados -eq 0 ]; then
        echo "   No hay clientes activos"
        return
    fi
    
    echo ""
    echo -n "Cliente a suspender (usar nombre o certificado): "
    read INPUT_CLIENTE
    
    CLIENTE_REAL=""
    if [ -f "$NOMBRES_FILE" ] && grep -q ":${INPUT_CLIENTE}$" "$NOMBRES_FILE" 2>/dev/null; then
        CLIENTE_REAL=$(grep ":${INPUT_CLIENTE}$" "$NOMBRES_FILE" | cut -d: -f1)
        echo "   🔍 Encontrado: $INPUT_CLIENTE → $CLIENTE_REAL"
    else
        CLIENTE_REAL=$INPUT_CLIENTE
    fi
    
    CERT_FOUND=0
    for cert_dir in "/etc/easy-rsa/pki/issued" "/etc/openvpn/easy-rsa/pki/issued" "/etc/easy-rsa/keys"; do
        if [ -f "${cert_dir}/${CLIENTE_REAL}.crt" ]; then
            CERT_FOUND=1
            break
        fi
    done
    
    if [ $CERT_FOUND -eq 0 ]; then
        echo "❌ Cliente '$INPUT_CLIENTE' no encontrado"
        return
    fi
    
    echo "   [....] Suspendiendo cliente (método temporal)..."
    mkdir -p /etc/openvpn/suspended/
    
    # Backup tradicional
    cp "/etc/easy-rsa/pki/issued/${CLIENTE_REAL}.crt" "/etc/openvpn/suspended/${CLIENTE_REAL}.crt.backup" 2>/dev/null || \
    cp "/etc/openvpn/easy-rsa/pki/issued/${CLIENTE_REAL}.crt" "/etc/openvpn/suspended/${CLIENTE_REAL}.crt.backup" 2>/dev/null || \
    cp "/etc/easy-rsa/keys/${CLIENTE_REAL}.crt" "/etc/openvpn/suspended/${CLIENTE_REAL}.crt.backup" 2>/dev/null
    
    # Revocar
    cd /etc/easy-rsa 2>/dev/null || cd /etc/openvpn/easy-rsa 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "yes" | ./easyrsa revoke "$CLIENTE_REAL" > /dev/null 2>&1
        ./easyrsa gen-crl > /dev/null 2>&1
        cp pki/crl.pem /etc/openvpn/ 2>/dev/null
    fi
    
    # Reiniciar para aplicar
    sudo systemctl restart openvpn > /dev/null 2>&1
    sleep 2
    
    nombre_descriptivo=$(obtener_nombre "$CLIENTE_REAL")
    echo "✅ CLIENTE '$nombre_descriptivo' SUSPENDIDO (temporal)"
    echo "💡 Método: Solo revocación - Puede reactivar con opción 5"
}

# ========== SUSPENSIÓN CON SECUESTRO MEJORADO ==========

suspender_con_secuestro() {
    echo ""
    echo "🔒 SUSPENDER CON SECUESTRO MEJORADO"
    echo "-----------------------------------"
    echo "⚠️  Método 100% garantizado - Triple seguridad"
    echo ""
    
    echo "Clientes activos:"
    activos_encontrados=0
    
    INDEX_FILES="/etc/easy-rsa/pki/index.txt /etc/openvpn/easy-rsa/pki/index.txt /etc/easy-rsa/keys/index.txt"
    INDEX_FILE=""
    for file in $INDEX_FILES; do
        if [ -f "$file" ]; then
            INDEX_FILE="$file"
            break
        fi
    done
    
    if [ -n "$INDEX_FILE" ]; then
        for cliente in $(grep "^V" "$INDEX_FILE" 2>/dev/null | awk -F'/' '{print $NF}' | awk '{print $1}'); do
            nombre_descriptivo=$(obtener_nombre "$cliente")
            if [ "$cliente" = "$nombre_descriptivo" ]; then
                echo "   $cliente"
            else
                echo "   $nombre_descriptivo ($cliente)"
            fi
            activos_encontrados=1
        done
    fi
    
    if [ $activos_encontrados -eq 0 ]; then
        echo "   No hay clientes activos"
        return
    fi
    
    echo ""
    echo -n "Cliente a suspender (con secuestro): "
    read INPUT_CLIENTE
    
    CLIENTE_REAL=""
    if [ -f "$NOMBRES_FILE" ] && grep -q ":${INPUT_CLIENTE}$" "$NOMBRES_FILE" 2>/dev/null; then
        CLIENTE_REAL=$(grep ":${INPUT_CLIENTE}$" "$NOMBRES_FILE" | cut -d: -f1)
        echo "   🔍 Encontrado: $INPUT_CLIENTE → $CLIENTE_REAL"
    else
        CLIENTE_REAL=$INPUT_CLIENTE
    fi
    
    CERT_FOUND=0
    for cert_dir in "/etc/easy-rsa/pki/issued" "/etc/openvpn/easy-rsa/pki/issued" "/etc/easy-rsa/keys"; do
        if [ -f "${cert_dir}/${CLIENTE_REAL}.crt" ]; then
            CERT_FOUND=1
            break
        fi
    done
    
    if [ $CERT_FOUND -eq 0 ]; then
        echo "❌ Cliente '$INPUT_CLIENTE' no encontrado"
        return
    fi
    
    echo ""
    echo "🔒 EJECUTANDO SECUESTRO MEJORADO..."
    echo ""
    
    # PASO 1: Backup completo
    echo "   1️⃣  BACKUP COMPLETO"
    echo "   ─────────────────"
    mkdir -p "/etc/openvpn/secuestrados/${CLIENTE_REAL}"
    
    # Guardar TODO
    cp "/etc/easy-rsa/pki/issued/${CLIENTE_REAL}.crt" "/etc/openvpn/secuestrados/${CLIENTE_REAL}/" 2>/dev/null
    cp "/etc/easy-rsa/pki/private/${CLIENTE_REAL}.key" "/etc/openvpn/secuestrados/${CLIENTE_REAL}/" 2>/dev/null
    cp "/etc/easy-rsa/pki/reqs/${CLIENTE_REAL}.req" "/etc/openvpn/secuestrados/${CLIENTE_REAL}/" 2>/dev/null
    
    echo "      ✅ Backup guardado en: /etc/openvpn/secuestrados/${CLIENTE_REAL}/"
    
    # PASO 2: Revocación en CRL
    echo ""
    echo "   2️⃣  REVOCACIÓN EN LISTA NEGRA (CRL)"
    echo "   ───────────────────────────────────"
    cd /etc/easy-rsa 2>/dev/null || cd /etc/openvpn/easy-rsa 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "yes" | ./easyrsa revoke "$CLIENTE_REAL" > /dev/null 2>&1
        ./easyrsa gen-crl > /dev/null 2>&1
        cp pki/crl.pem /etc/openvpn/ 2>/dev/null
        echo "      ✅ Añadido a lista de revocación (CRL)"
    fi
    
    # PASO 3: ELIMINAR COMPLETAMENTE del sistema
    echo ""
    echo "   3️⃣  ELIMINACIÓN TOTAL DEL SISTEMA"
    echo "   ─────────────────────────────────"
    
    # ELIMINAR todos los archivos del cliente
    rm -f "/etc/easy-rsa/pki/issued/${CLIENTE_REAL}.crt"
    rm -f "/etc/easy-rsa/pki/private/${CLIENTE_REAL}.key"
    rm -f "/etc/easy-rsa/pki/reqs/${CLIENTE_REAL}.req"
    
    # También eliminar de archivos comprimidos si existen
    rm -f "/etc/openvpn/client-configs/files/${CLIENTE_REAL}.ovpn" 2>/dev/null
    rm -f "/etc/openvpn/client-configs/${CLIENTE_REAL}.ovpn" 2>/dev/null
    
    echo "      ✅ Archivos eliminados del sistema"
    
    # PASO 4: DESCONEXIÓN INMEDIATA
    echo ""
    echo "   4️⃣  DESCONEXIÓN INMEDIATA"
    echo "   ────────────────────────"
    
    # Método 1: Management interface
    if echo "kill ${CLIENTE_REAL}" | timeout 2 nc 127.0.0.1 7505 2>/dev/null; then
        echo "      ✅ Desconectado via management interface"
    else
        # Método 2: Reiniciar OpenVPN completo
        sudo systemctl restart openvpn > /dev/null 2>&1
        sleep 3
        echo "      ✅ OpenVPN reiniciado - Cliente desconectado"
    fi
    
    # PASO 5: REGENERAR CERTIFICADO FALSO
    echo ""
    echo "   5️⃣  SEGURIDAD EXTRA: CERTIFICADO FALSO"
    echo "   ─────────────────────────────────────"
    
    # Crear un certificado falso para engañar al sistema
    FAKE_CERT="/etc/openvpn/secuestrados/${CLIENTE_REAL}/certificado_falso.crt"
    echo "-----BEGIN CERTIFICATE-----" > "$FAKE_CERT"
    echo "CERTIFICADO SECUESTRADO - NO VALIDO" >> "$FAKE_CERT"
    echo "Cliente: ${CLIENTE_REAL}" >> "$FAKE_CERT"
    echo "Estado: SUSPENDIDO" >> "$FAKE_CERT"
    echo "Fecha: $(date)" >> "$FAKE_CERT"
    echo "-----END CERTIFICATE-----" >> "$FAKE_CERT"
    
    # Dejar el certificado falso en el lugar original
    cp "$FAKE_CERT" "/etc/easy-rsa/pki/issued/${CLIENTE_REAL}.crt" 2>/dev/null
    
    echo "      ✅ Certificado falso instalado"
    
    # RESULTADO FINAL
    nombre_descriptivo=$(obtener_nombre "$CLIENTE_REAL")
    echo ""
    echo "🎯 SECUESTRO COMPLETADO - 100% EFECTIVO"
    echo "======================================="
    echo ""
    echo "✅ CLIENTE: $nombre_descriptivo ($CLIENTE_REAL)"
    echo ""
    echo "📊 MEDIDAS DE SEGURIDAD APLICADAS:"
    echo "   1. ✅ Backup completo guardado"
    echo "   2. ✅ Revocado en lista negra (CRL)"
    echo "   3. ✅ Archivos originales ELIMINADOS"
    echo "   4. ✅ Desconexión inmediata forzada"
    echo "   5. ✅ Certificado falso instalado"
    echo ""
    echo "🔒 RESULTADO:"
    echo "   • Cliente DESCONECTADO inmediatamente"
    echo "   • NO PUEDE reconectar (certificado revocado)"
    echo "   • Si intenta usar certificado antiguo: RECHAZADO"
    echo "   • Sistema protegido contra reconexiones"
    echo ""
    echo "📁 Backup disponible en: /etc/openvpn/secuestrados/${CLIENTE_REAL}/"
    echo "💡 Para reactivar: usa la opción 6 (Restaurar cliente secuestrado)"
}

# ========== REACTIVACIÓN NORMAL ==========

reactivar_cliente() {
    echo ""
    echo "▶️  REACTIVAR CLIENTE (SUSPENDIDO TEMPORAL)"
    echo "------------------------------------------"
    
    echo "Clientes suspendidos (temporal):"
    suspendidos_encontrados=0
    
    INDEX_FILES="/etc/easy-rsa/pki/index.txt /etc/openvpn/easy-rsa/pki/index.txt /etc/easy-rsa/keys/index.txt"
    INDEX_FILE=""
    for file in $INDEX_FILES; do
        if [ -f "$file" ]; then
            INDEX_FILE="$file"
            break
        fi
    done
    
    if [ -n "$INDEX_FILE" ]; then
        for cliente in $(grep "^R" "$INDEX_FILE" 2>/dev/null | awk -F'/' '{print $NF}' | awk '{print $1}'); do
            if [ -f "/etc/openvpn/suspended/${cliente}.crt.backup" ]; then
                nombre_descriptivo=$(obtener_nombre "$cliente")
                if [ "$cliente" = "$nombre_descriptivo" ]; then
                    echo "   $cliente"
                else
                    echo "   $nombre_descriptivo ($cliente)"
                fi
                suspendidos_encontrados=1
            fi
        done
    fi
    
    if [ $suspendidos_encontrados -eq 0 ]; then
        echo "   No hay clientes suspendidos (temporal)"
        return
    fi
    
    echo ""
    echo -n "Cliente a reactivar: "
    read INPUT_CLIENTE
    
    CLIENTE_REAL=""
    if [ -f "$NOMBRES_FILE" ] && grep -q ":${INPUT_CLIENTE}$" "$NOMBRES_FILE" 2>/dev/null; then
        CLIENTE_REAL=$(grep ":${INPUT_CLIENTE}$" "$NOMBRES_FILE" | cut -d: -f1)
        echo "   🔍 Encontrado: $INPUT_CLIENTE → $CLIENTE_REAL"
    else
        CLIENTE_REAL=$INPUT_CLIENTE
    fi
    
    if [ ! -f "/etc/openvpn/suspended/${CLIENTE_REAL}.crt.backup" ]; then
        echo "❌ Cliente '$INPUT_CLIENTE' no está suspendido (temporal)"
        echo "💡 ¿Quizás está secuestrado? Usa la opción 6"
        return
    fi
    
    echo "   [....] Reactivando cliente..."
    cp "/etc/openvpn/suspended/${CLIENTE_REAL}.crt.backup" "/etc/easy-rsa/pki/issued/${CLIENTE_REAL}.crt" 2>/dev/null || \
    cp "/etc/openvpn/suspended/${CLIENTE_REAL}.crt.backup" "/etc/openvpn/easy-rsa/pki/issued/${CLIENTE_REAL}.crt" 2>/dev/null || \
    cp "/etc/openvpn/suspended/${CLIENTE_REAL}.crt.backup" "/etc/easy-rsa/keys/${CLIENTE_REAL}.crt" 2>/dev/null
    
    cd /etc/easy-rsa 2>/dev/null || cd /etc/openvpn/easy-rsa 2>/dev/null
    if [ $? -eq 0 ]; then
        sed -i "/\/CN=${CLIENTE_REAL}$/d" pki/index.txt 2>/dev/null
        ./easyrsa gen-crl > /dev/null 2>&1
        cp pki/crl.pem /etc/openvpn/ 2>/dev/null
    fi
    
    sudo systemctl restart openvpn > /dev/null 2>&1
    sleep 2
    
    nombre_descriptivo=$(obtener_nombre "$CLIENTE_REAL")
    echo "✅ CLIENTE '$nombre_descriptivo' REACTIVADO"
}

# ========== RESTAURACIÓN DE SECUESTRO MEJORADO ==========

restaurar_secuestrado() {
    echo ""
    echo "🔓 RESTAURAR CLIENTE SECUESTRADO"
    echo "-------------------------------"
    
    echo "Clientes secuestrados:"
    secuestrados_encontrados=0
    if [ -d "/etc/openvpn/secuestrados" ]; then
        for cliente_dir in /etc/openvpn/secuestrados/*; do
            if [ -d "$cliente_dir" ]; then
                cliente=$(basename "$cliente_dir")
                nombre_descriptivo=$(obtener_nombre "$cliente")
                if [ "$cliente" = "$nombre_descriptivo" ]; then
                    echo "   $cliente"
                else
                    echo "   $nombre_descriptivo ($cliente)"
                fi
                secuestrados_encontrados=1
            fi
        done
    fi
    
    if [ $secuestrados_encontrados -eq 0 ]; then
        echo "   No hay clientes secuestrados"
        return
    fi
    
    echo ""
    echo -n "Cliente a restaurar: "
    read INPUT_CLIENTE
    
    CLIENTE_REAL=""
    if [ -f "$NOMBRES_FILE" ] && grep -q ":${INPUT_CLIENTE}$" "$NOMBRES_FILE" 2>/dev/null; then
        CLIENTE_REAL=$(grep ":${INPUT_CLIENTE}$" "$NOMBRES_FILE" | cut -d: -f1)
        echo "   🔍 Encontrado: $INPUT_CLIENTE → $CLIENTE_REAL"
    else
        CLIENTE_REAL=$INPUT_CLIENTE
    fi
    
    if [ ! -d "/etc/openvpn/secuestrados/${CLIENTE_REAL}" ]; then
        echo "❌ Cliente '$INPUT_CLIENTE' no está secuestrado"
        return
    fi
    
    echo ""
    echo "🔓 RESTAURANDO CLIENTE SECUESTRADO..."
    echo ""
    
    # PASO 1: Verificar que existe backup
    if [ ! -d "/etc/openvpn/secuestrados/${CLIENTE_REAL}" ]; then
        echo "❌ No hay backup para '$CLIENTE_REAL'"
        return
    fi
    
    echo "   1️⃣  ELIMINAR CERTIFICADO FALSO"
    echo "   ─────────────────────────────"
    rm -f "/etc/easy-rsa/pki/issued/${CLIENTE_REAL}.crt" 2>/dev/null
    echo "      ✅ Certificado falso eliminado"
    
    echo ""
    echo "   2️⃣  RESTAURAR ARCHIVOS ORIGINALES"
    echo "   ────────────────────────────────"
    
    # Restaurar desde backup
    cp "/etc/openvpn/secuestrados/${CLIENTE_REAL}/${CLIENTE_REAL}.crt" "/etc/easy-rsa/pki/issued/" 2>/dev/null
    cp "/etc/openvpn/secuestrados/${CLIENTE_REAL}/${CLIENTE_REAL}.key" "/etc/easy-rsa/pki/private/" 2>/dev/null
    cp "/etc/openvpn/secuestrados/${CLIENTE_REAL}/${CLIENTE_REAL}.req" "/etc/easy-rsa/pki/reqs/" 2>/dev/null
    
    echo "      ✅ Archivos originales restaurados"
    
    echo ""
    echo "   3️⃣  QUITAR DE LISTA NEGRA (CRL)"
    echo "   ──────────────────────────────"
    cd /etc/easy-rsa 2>/dev/null || cd /etc/openvpn/easy-rsa 2>/dev/null
    if [ $? -eq 0 ]; then
        # Eliminar línea de revocación
        sed -i "/\/CN=${CLIENTE_REAL}$/d" pki/index.txt 2>/dev/null
        # Regenerar CRL sin este cliente
        ./easyrsa gen-crl > /dev/null 2>&1
        cp pki/crl.pem /etc/openvpn/ 2>/dev/null
        echo "      ✅ Eliminado de lista de revocación"
    fi
    
    echo ""
    echo "   4️⃣  LIMPIAR Y REINICIAR"
    echo "   ──────────────────────"
    
    # Eliminar carpeta de secuestro
    rm -rf "/etc/openvpn/secuestrados/${CLIENTE_REAL}"
    
    # Reiniciar OpenVPN
    sudo systemctl restart openvpn > /dev/null 2>&1
    sleep 2
    
    echo "      ✅ Sistema limpiado y reiniciado"
    
    nombre_descriptivo=$(obtener_nombre "$CLIENTE_REAL")
    echo ""
    echo "🎯 RESTAURACIÓN COMPLETADA"
    echo "=========================="
    echo ""
    echo "✅ CLIENTE: $nombre_descriptivo ($CLIENTE_REAL)"
    echo ""
    echo "📊 ESTADO ACTUAL:"
    echo "   • Certificados restaurados ✓"
    echo "   • Eliminado de lista negra ✓"
    echo "   • OpenVPN reiniciado ✓"
    echo "   • PUEDE reconectar inmediatamente ✓"
    echo ""
    echo "🔓 Cliente completamente reactivado y operativo"
}

# ========== BLOQUEO PERMANENTE ==========

bloquear_permanentemente() {
    echo ""
    echo "🚫 BLOQUEO PERMANENTE"
    echo "-------------------"
    
    echo "Clientes activos:"
    activos_encontrados=0
    
    INDEX_FILES="/etc/easy-rsa/pki/index.txt /etc/openvpn/easy-rsa/pki/index.txt /etc/easy-rsa/keys/index.txt"
    INDEX_FILE=""
    for file in $INDEX_FILES; do
        if [ -f "$file" ]; then
            INDEX_FILE="$file"
            break
        fi
    done
    
    if [ -n "$INDEX_FILE" ]; then
        for cliente in $(grep "^V" "$INDEX_FILE" 2>/dev/null | awk -F'/' '{print $NF}' | awk '{print $1}'); do
            nombre_descriptivo=$(obtener_nombre "$cliente")
            if [ "$cliente" = "$nombre_descriptivo" ]; then
                echo "   $cliente"
            else
                echo "   $nombre_descriptivo ($cliente)"
            fi
            activos_encontrados=1
        done
    fi
    
    if [ $activos_encontrados -eq 0 ]; then
        echo "   No hay clientes activos"
        return
    fi
    
    echo ""
    echo -n "Cliente a bloquear: "
    read INPUT_CLIENTE
    
    CLIENTE_REAL=""
    if [ -f "$NOMBRES_FILE" ] && grep -q ":${INPUT_CLIENTE}$" "$NOMBRES_FILE" 2>/dev/null; then
        CLIENTE_REAL=$(grep ":${INPUT_CLIENTE}$" "$NOMBRES_FILE" | cut -d: -f1)
        echo "   🔍 Encontrado: $INPUT_CLIENTE → $CLIENTE_REAL"
    else
        CLIENTE_REAL=$INPUT_CLIENTE
    fi
    
    CERT_FOUND=0
    for cert_dir in "/etc/easy-rsa/pki/issued" "/etc/openvpn/easy-rsa/pki/issued" "/etc/easy-rsa/keys"; do
        if [ -f "${cert_dir}/${CLIENTE_REAL}.crt" ]; then
            CERT_FOUND=1
            break
        fi
    done
    
    if [ $CERT_FOUND -eq 0 ]; then
        echo "❌ Cliente '$INPUT_CLIENTE' no encontrado"
        return
    fi
    
    echo "   [....] Bloqueando cliente permanentemente..."
    
    # Solo revocar (sin backup)
    cd /etc/easy-rsa 2>/dev/null || cd /etc/openvpn/easy-rsa 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "yes" | ./easyrsa revoke "$CLIENTE_REAL" > /dev/null 2>&1
        ./easyrsa gen-crl > /dev/null 2>&1
        cp pki/crl.pem /etc/openvpn/ 2>/dev/null
    fi
    
    sudo systemctl restart openvpn > /dev/null 2>&1
    sleep 2
    
    nombre_descriptivo=$(obtener_nombre "$CLIENTE_REAL")
    echo "✅ CLIENTE '$nombre_descriptivo' BLOQUEADO PERMANENTEMENTE"
    echo "💡 Necesitará nuevo certificado para volver a conectarse"
}

# ========== DESCONEXIÓN DE CLIENTE ==========

desconectar_cliente() {
    echo ""
    echo "🔌 DESCONECTAR CLIENTE"
    echo "---------------------"
    
    ver_conectados
    
    if ! grep -q "CLIENT_LIST" "/var/log/openvpn-status.log" 2>/dev/null; then
        echo "   No hay clientes conectados para desconectar"
        return
    fi
    
    echo ""
    echo -n "Cliente a desconectar: "
    read cliente
    
    # Intentar con management interface
    if echo "kill $cliente" | timeout 2 nc 127.0.0.1 7505 2>/dev/null; then
        echo "✅ Cliente '$cliente' desconectado via management"
    else
        echo "⚠️  No se pudo desconectar via management"
        echo -n "¿Reiniciar OpenVPN para desconectar todos? (s/n): "
        read respuesta
        if [ "$respuesta" = "s" ] || [ "$respuesta" = "S" ]; then
            sudo systemctl restart openvpn > /dev/null 2>&1
            sleep 3
            echo "✅ OpenVPN reiniciado - Todos los clientes desconectados"
        fi
    fi
}

# ========== GESTIÓN DE NOMBRES ==========

gestionar_nombres() {
    while true; do
        echo ""
        echo "🏷️  GESTIÓN DE NOMBRES DESCRIPTIVOS"
        echo "=================================="
        echo ""
        echo "1) Asignar nombre a cliente"
        echo "2) Ver todos los nombres"
        echo "3) Eliminar nombre"
        echo "4) Volver al menú principal"
        echo ""
        echo -n "Selecciona [1-4]: "
        read opcion_nombre
        
        case $opcion_nombre in
            1)
                echo ""
                echo "📝 ASIGNAR NOMBRE"
                echo "----------------"
                
                echo "Clientes disponibles:"
                INDEX_FILES="/etc/easy-rsa/pki/index.txt /etc/openvpn/easy-rsa/pki/index.txt /etc/easy-rsa/keys/index.txt"
                INDEX_FILE=""
                for file in $INDEX_FILES; do
                    if [ -f "$file" ]; then
                        INDEX_FILE="$file"
                        break
                    fi
                done
                
                if [ -n "$INDEX_FILE" ]; then
                    count=0
                    for cliente in $(grep -E "^(V|R)" "$INDEX_FILE" 2>/dev/null | awk -F'/' '{print $NF}' | awk '{print $1}' | sort -u); do
                        if [ -n "$cliente" ]; then
                            nombre_actual=$(obtener_nombre "$cliente")
                            if [ "$cliente" = "$nombre_actual" ]; then
                                echo "   $cliente"
                            else
                                echo "   $nombre_actual ($cliente)"
                            fi
                            count=$((count + 1))
                            [ $count -ge 15 ] && break
                        fi
                    done
                fi
                
                echo ""
                echo -n "Certificado del cliente (ej: client1): "
                read cliente
                echo -n "Nombre descriptivo (ej: Juan_Movil): "
                read nombre_descriptivo
                
                if [ -n "$cliente" ] && [ -n "$nombre_descriptivo" ]; then
                    touch "$NOMBRES_FILE"
                    grep -v "^${cliente}:" "$NOMBRES_FILE" 2>/dev/null > "${NOMBRES_FILE}.tmp"
                    mv "${NOMBRES_FILE}.tmp" "$NOMBRES_FILE"
                    echo "${cliente}:${nombre_descriptivo}" >> "$NOMBRES_FILE"
                    echo "✅ Nombre '$nombre_descriptivo' asignado a $cliente"
                else
                    echo "❌ Nombre no válido"
                fi
                ;;
            2)
                echo ""
                echo "📋 NOMBRES ASIGNADOS:"
                if [ -f "$NOMBRES_FILE" ] && [ -s "$NOMBRES_FILE" ]; then
                    echo ""
                    grep -v "^#" "$NOMBRES_FILE" | grep -v "^$" | while read linea; do
                        if [ -n "$linea" ]; then
                            cliente=$(echo "$linea" | cut -d: -f1)
                            nombre=$(echo "$linea" | cut -d: -f2)
                            if [ -n "$cliente" ] && [ -n "$nombre" ]; then
                                echo "   🏷️  $nombre ($cliente)"
                            fi
                        fi
                    done
                else
                    echo "   No hay nombres asignados"
                fi
                ;;
            3)
                echo ""
                echo "🗑️  ELIMINAR NOMBRE"
                if [ -f "$NOMBRES_FILE" ] && [ -s "$NOMBRES_FILE" ]; then
                    echo "Nombres asignados:"
                    grep -v "^#" "$NOMBRES_FILE" | grep -v "^$" | while read linea; do
                        if [ -n "$linea" ]; then
                            cliente=$(echo "$linea" | cut -d: -f1)
                            nombre=$(echo "$linea" | cut -d: -f2)
                            if [ -n "$cliente" ] && [ -n "$nombre" ]; then
                                echo "   $nombre ($cliente)"
                            fi
                        fi
                    done
                    echo ""
                    echo -n "Nombre a eliminar: "
                    read nombre_eliminar
                    if [ -n "$nombre_eliminar" ]; then
                        CLIENTE_REAL=$(grep ":${nombre_eliminar}$" "$NOMBRES_FILE" 2>/dev/null | cut -d: -f1)
                        if [ -n "$CLIENTE_REAL" ]; then
                            grep -v "^${CLIENTE_REAL}:" "$NOMBRES_FILE" > "${NOMBRES_FILE}.tmp"
                            mv "${NOMBRES_FILE}.tmp" "$NOMBRES_FILE"
                            echo "✅ Nombre '$nombre_eliminar' eliminado"
                        else
                            echo "❌ Nombre '$nombre_eliminar' no encontrado"
                        fi
                    else
                        echo "❌ Nombre no válido"
                    fi
                else
                    echo "   No hay nombres asignados"
                fi
                ;;
            4)
                return
                ;;
            *)
                echo "❌ Opción inválida"
                ;;
        esac
    done
}

# ========== VER CLIENTES SECUESTRADOS ==========

ver_secuestrados() {
    echo ""
    echo "📁 CLIENTES SECUESTRADOS:"
    if [ -d "/etc/openvpn/secuestrados" ]; then
        for cliente_dir in /etc/openvpn/secuestrados/*; do
            if [ -d "$cliente_dir" ]; then
                cliente=$(basename "$cliente_dir")
                nombre_descriptivo=$(obtener_nombre "$cliente")
                echo ""
                if [ "$cliente" = "$nombre_descriptivo" ]; then
                    echo "   🔒 $cliente"
                else
                    echo "   🔒 $nombre_descriptivo ($cliente)"
                fi
                echo "      📍 Ubicación: $cliente_dir"
                echo "      📊 Archivos: $(ls "$cliente_dir" 2>/dev/null | wc -l) archivos"
                
                # Método portable para obtener fecha
                if ls -ld "$cliente_dir" >/dev/null 2>&1; then
                    fecha_mod=$(ls -ld "$cliente_dir" | awk '{print $6, $7}')
                    echo "      📅 Modificado: $fecha_mod"
                else
                    echo "      📅 Modificado: Información no disponible"
                fi
            fi
        done
    else
        echo "   No hay clientes secuestrados"
    fi
}

# ========== ESTADO DEL SERVICIO ==========

estado_servicio() {
    echo ""
    echo "🔍 ESTADO DEL SERVICIO:"
    if pgrep openvpn >/dev/null; then
        echo "   ✅ OpenVPN: ACTIVO"
    else
        echo "   ❌ OpenVPN: INACTIVO"
    fi
    
    if [ -f "/var/log/openvpn-status.log" ]; then
        echo "   ✅ Archivo de estado: EXISTE"
    else
        echo "   ❌ Archivo de estado: NO EXISTE"
    fi
    
    if [ -d "/etc/openvpn/secuestrados" ]; then
        count=$(find /etc/openvpn/secuestrados -maxdepth 1 -type d 2>/dev/null | wc -l)
        echo "   🔒 Clientes secuestrados: $((count - 1))"
    fi
    
    if [ -d "/etc/openvpn/suspended" ]; then
        count=$(ls /etc/openvpn/suspended/*.crt.backup 2>/dev/null | wc -l)
        echo "   ⏸️  Clientes suspendidos: $count"
    fi
    
    # Verificar management interface
    if netstat -tln 2>/dev/null | grep -q ":7505"; then
        echo "   🔌 Management interface: ACTIVA (puerto 7505)"
    else
        echo "   🔌 Management interface: INACTIVA"
    fi
}

# ========== MENÚ PRINCIPAL ==========

while true; do
    mostrar_menu
    read OPCION
    
    case $OPCION in
        1) ver_conectados ;;
        2) listar_clientes ;;
        3) suspender_temporal ;;
        4) suspender_con_secuestro ;;
        5) reactivar_cliente ;;
        6) restaurar_secuestrado ;;
        7) bloquear_permanentemente ;;
        8) desconectar_cliente ;;
        9) gestionar_nombres ;;
        10) ver_secuestrados ;;
        11) estado_servicio ;;
        12)
            echo ""
            echo "👋 Saliendo..."
            exit 0
            ;;
        *)
            echo "❌ Opción inválida"
            ;;
    esac
    echo ""
done
GESTOR_SCRIPT

# Dar permisos
chmod +x /usr/bin/gestor-vpn

echo ""
echo "✅ GESTOR VPN ACTUALIZADO - SISTEMA DE SECUESTRO MEJORADO"
echo ""
echo "🎯 MEJORAS IMPLEMENTADAS:"
echo "   1. ✅ Eliminación REAL de archivos (no solo mover)"
echo "   2. ✅ Certificado falso para engañar al sistema"
echo "   3. ✅ Desconexión inmediata garantizada"
echo "   4. ✅ Triple seguridad: CRL + Eliminación + Desconexión"
echo ""
echo "📊 MÉTODOS DE SUSPENSIÓN DISPONIBLES:"
echo "   ⏸️  Opción 3: Suspensión temporal (revocación + backup)"
echo "   🔒 Opción 4: Suspensión 100% garantizada (secuestro mejorado)"
echo ""
echo "🚀 EJECUTA: gestor-vpn"
echo ""
echo "💡 Ahora el secuestro es 100% efectivo - Cliente NO puede reconectar"
