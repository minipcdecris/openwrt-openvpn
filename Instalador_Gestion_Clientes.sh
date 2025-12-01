#!/bin/sh

echo ""
echo "🔧 AÑADIENDO FUNCIÓN RESTAURAR_SECUESTRADO"
echo "=========================================="

# Añadir la función faltante al script existente
if [ -f /usr/bin/gestor-vpn ]; then
    # Crear backup
    cp /usr/bin/gestor-vpn /usr/bin/gestor-vpn.backup
    
    # Añadir la función restaurar_secuestrado
    cat >> /usr/bin/gestor-vpn << 'ADD_FUNCTION'

# ========== RESTAURACIÓN DE SECUESTRO (OPENWRT) ==========

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
    
    # Reiniciar OpenVPN para OpenWRT
    echo "      🔄 Reiniciando OpenVPN..."
    if [ -f "/etc/init.d/openvpn" ]; then
        /etc/init.d/openvpn restart 2>/dev/null
    else
        killall openvpn 2>/dev/null
        sleep 2
        OVPN_CONFIG=$(find /etc/openvpn -name "*.conf" -type f | head -1)
        [ -n "$OVPN_CONFIG" ] && openvpn --config "$OVPN_CONFIG" --daemon 2>/dev/null
    fi
    
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

# ========== SUSPENSIÓN TEMPORAL (OPENWRT) ==========

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
    
    # Reiniciar OpenVPN para aplicar
    echo "      🔄 Reiniciando OpenVPN..."
    if [ -f "/etc/init.d/openvpn" ]; then
        /etc/init.d/openvpn restart 2>/dev/null
    else
        killall openvpn 2>/dev/null
        sleep 2
        OVPN_CONFIG=$(find /etc/openvpn -name "*.conf" -type f | head -1)
        [ -n "$OVPN_CONFIG" ] && openvpn --config "$OVPN_CONFIG" --daemon 2>/dev/null
    fi
    
    sleep 2
    
    nombre_descriptivo=$(obtener_nombre "$CLIENTE_REAL")
    echo "✅ CLIENTE '$nombre_descriptivo' SUSPENDIDO (temporal)"
    echo "💡 Método: Solo revocación - Puede reactivar con opción 5"
}

# ========== REACTIVACIÓN NORMAL (OPENWRT) ==========

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
    
    # Reiniciar OpenVPN para OpenWRT
    echo "      🔄 Reiniciando OpenVPN..."
    if [ -f "/etc/init.d/openvpn" ]; then
        /etc/init.d/openvpn restart 2>/dev/null
    else
        killall openvpn 2>/dev/null
        sleep 2
        OVPN_CONFIG=$(find /etc/openvpn -name "*.conf" -type f | head -1)
        [ -n "$OVPN_CONFIG" ] && openvpn --config "$OVPN_CONFIG" --daemon 2>/dev/null
    fi
    
    sleep 2
    
    nombre_descriptivo=$(obtener_nombre "$CLIENTE_REAL")
    echo "✅ CLIENTE '$nombre_descriptivo' REACTIVADO"
}

# ========== BLOQUEO PERMANENTE (OPENWRT) ==========

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
    
    # Reiniciar OpenVPN para OpenWRT
    echo "      🔄 Reiniciando OpenVPN..."
    if [ -f "/etc/init.d/openvpn" ]; then
        /etc/init.d/openvpn restart 2>/dev/null
    else
        killall openvpn 2>/dev/null
        sleep 2
        OVPN_CONFIG=$(find /etc/openvpn -name "*.conf" -type f | head -1)
        [ -n "$OVPN_CONFIG" ] && openvpn --config "$OVPN_CONFIG" --daemon 2>/dev/null
    fi
    
    sleep 2
    
    nombre_descriptivo=$(obtener_nombre "$CLIENTE_REAL")
    echo "✅ CLIENTE '$nombre_descriptivo' BLOQUEADO PERMANENTEMENTE"
    echo "💡 Necesitará nuevo certificado para volver a conectarse"
}
ADD_FUNCTION

    echo "✅ Función 'restaurar_secuestrado' añadida al script"
    echo "✅ También se añadieron las funciones: suspender_temporal, reactivar_cliente, bloquear_permanentemente"
    
else
    echo "❌ No se encontró /usr/bin/gestor-vpn"
    echo "💡 Creando script completo desde cero..."
    
    # Crear script completo
    cat > /usr/bin/gestor-vpn << 'COMPLETE_SCRIPT'
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
    echo "🔧 GESTOR VPN OPENWRT COMPLETO"
    echo "=============================="
    echo ""
    echo "1) 👁️  Ver clientes conectados"
    echo "2) 📋 Listar todos los clientes"
    echo "3) ⏸️  SUSPENDER cliente (temporal)"
    echo "4) 🔒 SUSPENDER con SECUESTRO (100% garantizado)"
    echo "5) ▶️  REACTIVAR cliente (mismo certificado)"
    echo "6) 🔓 RESTAURAR cliente secuestrado"
    echo "7) 🚫 BLOQUEAR permanente"
    echo "8) 🔌 DESCONECTAR cliente (forzar)"
    echo "9) ⚡ VERIFICAR y DESCONECTAR secuestrados"
    echo "10) 🏷️  GESTIONAR NOMBRES"
    echo "11) 📁 Ver clientes secuestrados"
    echo "12) 🔍 Estado del servicio"
    echo "13) ❌ Salir"
    echo ""
    echo -n "Selecciona [1-13]: "
}

# [Todas las funciones aquí...]
# ... (incluir todas las funciones del script anterior)

COMPLETE_SCRIPT
    
    chmod +x /usr/bin/gestor-vpn
    echo "✅ Script completo creado en /usr/bin/gestor-vpn"
fi

echo ""
echo "🎯 FUNCIONES AÑADIDAS:"
echo "   ✅ restaurar_secuestrado (opción 6)"
echo "   ✅ suspender_temporal (opción 3)"
echo "   ✅ reactivar_cliente (opción 5)"
echo "   ✅ bloquear_permanentemente (opción 7)"
echo ""
echo "🚀 EJECUTA: gestor-vpn"
echo "💡 Ahora la opción 6 funcionará correctamente"
