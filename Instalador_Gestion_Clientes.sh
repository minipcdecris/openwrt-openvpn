#!/bin/sh

echo ""
echo "🔧 AÑADIENDO DESCONEXIÓN DE CLIENTES"
echo "===================================="

# Crear el gestor con desconexión mejorada
cat > /usr/bin/gestor-vpn << 'GESTOR_SCRIPT'
#!/bin/sh

# Archivos de configuración
NOMBRES_FILE="/etc/openvpn/clientes/nombres.txt"
TRACKING_FILE="/etc/openvpn/clientes/tracking.txt"

# Asegurar que el archivo de nombres existe
mkdir -p /etc/openvpn/clientes/
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
    echo "🔧 GESTOR VPN - CON NOMBRES DESCRIPTIVOS"
    echo "========================================"
    echo ""
    echo "1) 👁️  Ver clientes conectados"
    echo "2) 📋 Listar todos los clientes"
    echo "3) ⏸️  SUSPENDER cliente (temporal)"
    echo "4) ▶️  REACTIVAR cliente (mismo certificado)"
    echo "5) 🚫 BLOQUEAR permanente (nuevo certificado)"
    echo "6) 🔌 DESCONECTAR cliente (forzar)"
    echo "7) 🏷️  GESTIONAR NOMBRES"
    echo "8) 🔍 Estado del servicio"
    echo "9) ❌ Salir"
    echo ""
    echo -n "Selecciona [1-9]: "
}

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

# Función para desconectar cliente (NUEVA)
desconectar_cliente() {
    echo ""
    echo "🔌 DESCONECTAR CLIENTE (FORZAR)"
    echo "------------------------------"
    
    # Mostrar clientes conectados
    ver_conectados
    
    echo -n "¿Quieres desconectar un cliente? (s/n): "
    read confirmar
    if [ "$confirmar" != "s" ] && [ "$confirmar" != "S" ]; then
        return
    fi
    
    echo ""
    echo -n "Cliente a desconectar (usar nombre o certificado): "
    read INPUT_CLIENTE
    
    CLIENTE_REAL=""
    if [ -f "$NOMBRES_FILE" ] && grep -q ":${INPUT_CLIENTE}$" "$NOMBRES_FILE" 2>/dev/null; then
        CLIENTE_REAL=$(grep ":${INPUT_CLIENTE}$" "$NOMBRES_FILE" | cut -d: -f1)
        echo "   🔍 Encontrado: $INPUT_CLIENTE → $CLIENTE_REAL"
    else
        CLIENTE_REAL=$INPUT_CLIENTE
    fi
    
    # Buscar el archivo de management interface
    MANAGEMENT_SOCKET=""
    if [ -S "/var/run/openvpn/server.sock" ]; then
        MANAGEMENT_SOCKET="/var/run/openvpn/server.sock"
    elif [ -S "/tmp/openvpn-management.sock" ]; then
        MANAGEMENT_SOCKET="/tmp/openvpn-management.sock"
    else
        # Intentar encontrar el proceso de OpenVPN
        OPENVPN_PID=$(pgrep openvpn | head -1)
        if [ -n "$OPENVPN_PID" ]; then
            echo "   ℹ️  OpenVPN ejecutándose (PID: $OPENVPN_PID)"
            echo "   💡 Para desconectar clientes, necesitas habilitar la management interface"
            echo "   📝 Añade esto en tu config: management 127.0.0.1 7505"
        fi
    fi
    
    if [ -n "$MANAGEMENT_SOCKET" ]; then
        echo "   [....] Desconectando cliente via management interface..."
        echo "kill ${CLIENTE_REAL}" | socat - UNIX-CONNECT:"$MANAGEMENT_SOCKET" 2>/dev/null
        echo "✅ Cliente '$CLIENTE_REAL' desconectado"
    else
        # Método alternativo: reiniciar OpenVPN (más agresivo)
        echo "   ℹ️  Management interface no disponible"
        echo -n "   ¿Reiniciar servicio OpenVPN para desconectar todos? (s/n): "
        read reiniciar
        if [ "$reiniciar" = "s" ] || [ "$reiniciar" = "S" ]; then
            echo "   [....] Reiniciando OpenVPN..."
            /etc/init.d/openvpn restart > /dev/null 2>&1
            sleep 3
            echo "✅ OpenVPN reiniciado - todos los clientes desconectados"
        else
            echo "💡 El cliente se desconectará automáticamente en unos minutos"
            echo "💡 Puede forzar desconexión manual en su dispositivo"
        fi
    fi
}

# Función para suspender cliente (MEJORADA)
suspender_cliente() {
    echo ""
    echo "⏸️  SUSPENDER CLIENTE (TEMPORAL)"
    echo "------------------------------"
    
    echo "Clientes activos:"
    activos_encontrados=0
    
    # Buscar base de datos
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
    
    # Buscar certificado en múltiples ubicaciones
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
    
    echo "   [....] Revocando certificado..."
    mkdir -p /etc/openvpn/suspended/
    
    # Backup del certificado
    cp "/etc/easy-rsa/pki/issued/${CLIENTE_REAL}.crt" "/etc/openvpn/suspended/${CLIENTE_REAL}.crt.backup" 2>/dev/null || \
    cp "/etc/openvpn/easy-rsa/pki/issued/${CLIENTE_REAL}.crt" "/etc/openvpn/suspended/${CLIENTE_REAL}.crt.backup" 2>/dev/null || \
    cp "/etc/easy-rsa/keys/${CLIENTE_REAL}.crt" "/etc/openvpn/suspended/${CLIENTE_REAL}.crt.backup" 2>/dev/null
    
    # Backup de la clave
    cp "/etc/easy-rsa/pki/private/${CLIENTE_REAL}.key" "/etc/openvpn/suspended/${CLIENTE_REAL}.key.backup" 2>/dev/null || \
    cp "/etc/openvpn/easy-rsa/pki/private/${CLIENTE_REAL}.key" "/etc/openvpn/suspended/${CLIENTE_REAL}.key.backup" 2>/dev/null || \
    cp "/etc/easy-rsa/keys/${CLIENTE_REAL}.key" "/etc/openvpn/suspended/${CLIENTE_REAL}.key.backup" 2>/dev/null
    
    # Revocar certificado
    cd /etc/easy-rsa 2>/dev/null || cd /etc/openvpn/easy-rsa 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "yes" | ./easyrsa revoke "$CLIENTE_REAL" > /dev/null 2>&1
        ./easyrsa gen-crl > /dev/null 2>&1
        cp pki/crl.pem /etc/openvpn/ 2>/dev/null
    fi
    
    # Preguntar si desconectar inmediatamente
    echo ""
    echo -n "¿Desconectar cliente inmediatamente? (s/n): "
    read desconectar_ahora
    
    if [ "$desconectar_ahora" = "s" ] || [ "$desconectar_ahora" = "S" ]; then
        desconectar_cliente
    else
        # Solo recargar OpenVPN
        /etc/init.d/openvpn reload > /dev/null 2>&1
        echo "   💡 El cliente se desconectará en unos minutos automáticamente"
        echo "   💡 Puede forzar desconexión manual en su dispositivo"
    fi
    
    nombre_descriptivo=$(obtener_nombre "$CLIENTE_REAL")
    echo "✅ CLIENTE '$nombre_descriptivo' SUSPENDIDO"
    echo ""
    echo "📝 INFORMACIÓN:"
    echo "   • Certificado revocado"
    echo "   • Backup guardado en /etc/openvpn/suspended/"
    echo "   • El cliente no podrá reconectar"
    echo "   • Para reactivar: usa la opción 4 del menú"
}

# [Las otras funciones (listar_clientes, reactivar_cliente, etc.) se mantienen igual...]
# Función para listar clientes
listar_clientes() {
    echo ""
    echo "📋 ESTADO DE CLIENTES:"
    
    INDEX_FILES="/etc/easy-rsa/pki/index.txt /etc/openvpn/easy-rsa/pki/index.txt /etc/easy-rsa/keys/index.txt"
    INDEX_FILE=""
    
    for file in $INDEX_FILES; do
        if [ -f "$file" ]; then
            INDEX_FILE="$file"
            echo "   🔍 Usando base de datos: $file"
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
    echo "⏸️  SUSPENDIDOS:"
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
    echo "🔴 BLOQUEADOS:"
    bloqueados_encontrados=0
    for cliente in $todos_clientes; do
        if grep -q "^R.*/CN=${cliente}$" "$INDEX_FILE" 2>/dev/null || grep -q "^R.*${cliente}" "$INDEX_FILE" 2>/dev/null; then
            if [ ! -f "/etc/openvpn/suspended/${cliente}.crt.backup" ]; then
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

# Función para reactivar cliente
reactivar_cliente() {
    echo ""
    echo "▶️  REACTIVAR CLIENTE"
    echo "-------------------"
    
    echo "Clientes suspendidos:"
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
        echo "   No hay clientes suspendidos"
        return
    fi
    
    echo ""
    echo -n "Cliente a reactivar (usar nombre o certificado): "
    read INPUT_CLIENTE
    
    CLIENTE_REAL=""
    if [ -f "$NOMBRES_FILE" ] && grep -q ":${INPUT_CLIENTE}$" "$NOMBRES_FILE" 2>/dev/null; then
        CLIENTE_REAL=$(grep ":${INPUT_CLIENTE}$" "$NOMBRES_FILE" | cut -d: -f1)
        echo "   🔍 Encontrado: $INPUT_CLIENTE → $CLIENTE_REAL"
    else
        CLIENTE_REAL=$INPUT_CLIENTE
    fi
    
    if [ ! -f "/etc/openvpn/suspended/${CLIENTE_REAL}.crt.backup" ]; then
        echo "❌ Cliente '$INPUT_CLIENTE' no está suspendido"
        return
    fi
    
    echo "   [....] Reactivando cliente..."
    cp "/etc/openvpn/suspended/${CLIENTE_REAL}.crt.backup" "/etc/easy-rsa/pki/issued/${CLIENTE_REAL}.crt" 2>/dev/null || \
    cp "/etc/openvpn/suspended/${CLIENTE_REAL}.crt.backup" "/etc/openvpn/easy-rsa/pki/issued/${CLIENTE_REAL}.crt" 2>/dev/null || \
    cp "/etc/openvpn/suspended/${CLIENTE_REAL}.crt.backup" "/etc/easy-rsa/keys/${CLIENTE_REAL}.crt" 2>/dev/null
    
    cp "/etc/openvpn/suspended/${CLIENTE_REAL}.key.backup" "/etc/easy-rsa/pki/private/${CLIENTE_REAL}.key" 2>/dev/null || \
    cp "/etc/openvpn/suspended/${CLIENTE_REAL}.key.backup" "/etc/openvpn/easy-rsa/pki/private/${CLIENTE_REAL}.key" 2>/dev/null || \
    cp "/etc/openvpn/suspended/${CLIENTE_REAL}.key.backup" "/etc/easy-rsa/keys/${CLIENTE_REAL}.key" 2>/dev/null
    
    cd /etc/easy-rsa 2>/dev/null || cd /etc/openvpn/easy-rsa 2>/dev/null
    if [ $? -eq 0 ]; then
        sed -i "/\/CN=${CLIENTE_REAL}$/d" pki/index.txt 2>/dev/null
        ./easyrsa gen-crl > /dev/null 2>&1
        cp pki/crl.pem /etc/openvpn/ 2>/dev/null
    fi
    
    /etc/init.d/openvpn restart > /dev/null 2>&1
    sleep 2
    
    nombre_descriptivo=$(obtener_nombre "$CLIENTE_REAL")
    echo "✅ CLIENTE '$nombre_descriptivo' REACTIVADO"
    echo "💡 El cliente puede reconectar inmediatamente"
}

# Función para bloquear permanente
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
    echo -n "Cliente a bloquear (usar nombre o certificado): "
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
    
    echo "   [....] Bloqueando cliente..."
    
    cd /etc/easy-rsa 2>/dev/null || cd /etc/openvpn/easy-rsa 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "yes" | ./easyrsa revoke "$CLIENTE_REAL" > /dev/null 2>&1
        ./easyrsa gen-crl > /dev/null 2>&1
        cp pki/crl.pem /etc/openvpn/ 2>/dev/null
    fi
    
    # Preguntar si desconectar inmediatamente
    echo ""
    echo -n "¿Desconectar cliente inmediatamente? (s/n): "
    read desconectar_ahora
    
    if [ "$desconectar_ahora" = "s" ] || [ "$desconectar_ahora" = "S" ]; then
        desconectar_cliente
    else
        /etc/init.d/openvpn reload > /dev/null 2>&1
    fi
    
    nombre_descriptivo=$(obtener_nombre "$CLIENTE_REAL")
    echo "✅ CLIENTE '$nombre_descriptivo' BLOQUEADO PERMANENTEMENTE"
    echo "💡 Necesitará un nuevo certificado para volver a conectarse"
}

# Función para gestionar nombres
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
                    for cliente in $(grep -E "^(V|R)" "$INDEX_FILE" 2>/dev/null | awk -F'/' '{print $NF}' | awk '{print $1}' | sort -u | head -10); do
                        if [ -n "$cliente" ]; then
                            nombre_actual=$(obtener_nombre "$cliente")
                            if [ "$cliente" = "$nombre_actual" ]; then
                                echo "   $cliente"
                            else
                                echo "   $nombre_actual ($cliente)"
                            fi
                        fi
                    done
                else
                    echo "   No se encontró base de datos de certificados"
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

# Función para estado del servicio
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
}

# Menú principal
while true; do
    mostrar_menu
    read OPCION
    
    case $OPCION in
        1) ver_conectados ;;
        2) listar_clientes ;;
        3) suspender_cliente ;;
        4) reactivar_cliente ;;
        5) bloquear_permanentemente ;;
        6) desconectar_cliente ;;
        7) gestionar_nombres ;;
        8) estado_servicio ;;
        9)
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
echo "✅ GESTOR MEJORADO - CON DESCONEXIÓN DE CLIENTES"
echo ""
echo "🎯 NUEVAS FUNCIONALIDADES:"
echo "   🔌 Opción 6: Desconectar cliente inmediatamente"
echo "   ⏸️  Suspensión mejorada: Pregunta si desconectar ahora"
echo "   🚫 Bloqueo mejorado: Pregunta si desconectar ahora"
echo ""
echo "💡 INFORMACIÓN IMPORTANTE:"
echo "   • Al suspender/bloquear: El certificado se revoca INMEDIATAMENTE"
echo "   • La desconexión puede ser: INMEDIATA o AUTOMÁTICA (en minutos)"
echo "   • Para desconexión inmediata necesita management interface"
echo ""
echo "🚀 EJECUTA: gestor-vpn"
