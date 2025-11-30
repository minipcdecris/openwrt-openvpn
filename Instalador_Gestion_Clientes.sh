#!/bin/sh

echo ""
echo "🔧 REINSTALANDO GESTOR CORREGIDO"
echo "================================"

# Crear el gestor corregido
cat > /usr/bin/gestor-vpn << 'GESTOR_SCRIPT'
#!/bin/sh

# Archivos de configuración
NOMBRES_FILE="/etc/openvpn/clientes/nombres.txt"
TRACKING_FILE="/etc/openvpn/clientes/tracking.txt"

# Función para obtener nombre descriptivo
obtener_nombre() {
    local cliente=$1
    local nombre=$(grep "^${cliente}:" "$NOMBRES_FILE" 2>/dev/null | cut -d: -f2)
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
    echo "6) 🏷️  GESTIONAR NOMBRES"
    echo "7) 🔍 Estado del servicio"
    echo "8) ❌ Salir"
    echo ""
    echo -n "Selecciona [1-8]: "
}

# Función para ver clientes conectados (CORREGIDA)
ver_conectados() {
    echo ""
    echo "📊 CLIENTES CONECTADOS:"
    
    if [ -f "/var/log/openvpn-status.log" ] && grep -q "CLIENT_LIST" "/var/log/openvpn-status.log"; then
        # Usar while read sin operaciones aritméticas complejas
        while IFS= read -r line; do
            if echo "$line" | grep -q "^CLIENT_LIST"; then
                cliente=$(echo "$line" | awk '{print $2}')
                ip=$(echo "$line" | awk '{print $3}')
                bytes_recv=$(echo "$line" | awk '{print $4}')
                bytes_sent=$(echo "$line" | awk '{print $5}')
                nombre_descriptivo=$(obtener_nombre "$cliente")
                
                echo "   👤 $nombre_descriptivo"
                echo "      📍 IP: $ip"
                echo "      📋 Certificado: $cliente"
                
                # Mostrar tráfico de forma segura
                if [ -n "$bytes_recv" ] && [ "$bytes_recv" -gt 0 ] 2>/dev/null; then
                    echo "      🔽 Descargado: $bytes_recv bytes"
                fi
                
                if [ -n "$bytes_sent" ] && [ "$bytes_sent" -gt 0 ] 2>/dev/null; then
                    echo "      🔼 Subido: $bytes_sent bytes"
                fi
                echo ""
            fi
        done < "/var/log/openvpn-status.log"
    else
        echo "   ℹ️  No hay clientes conectados"
    fi
}

# Función para listar clientes (SIMPLIFICADA)
listar_clientes() {
    echo ""
    echo "📋 ESTADO DE CLIENTES:"
    
    if [ -f "/etc/easy-rsa/pki/index.txt" ]; then
        echo "🟢 ACTIVOS:"
        grep "^V" /etc/easy-rsa/pki/index.txt 2>/dev/null | awk '{print $6}' | while read cliente; do
            nombre_descriptivo=$(obtener_nombre "$cliente")
            if [ "$cliente" = "$nombre_descriptivo" ]; then
                echo "   $cliente"
            else
                echo "   $nombre_descriptivo ($cliente)"
            fi
        done
        
        echo ""
        echo "⏸️  SUSPENDIDOS:"
        for cliente in $(grep "^R" /etc/easy-rsa/pki/index.txt 2>/dev/null | awk '{print $6}'); do
            if [ -f "/etc/openvpn/suspended/${cliente}.crt.backup" ]; then
                nombre_descriptivo=$(obtener_nombre "$cliente")
                if [ "$cliente" = "$nombre_descriptivo" ]; then
                    echo "   $cliente"
                else
                    echo "   $nombre_descriptivo ($cliente)"
                fi
            fi
        done
        
        echo ""
        echo "🔴 BLOQUEADOS:"
        for cliente in $(grep "^R" /etc/easy-rsa/pki/index.txt 2>/dev/null | awk '{print $6}'); do
            if [ ! -f "/etc/openvpn/suspended/${cliente}.crt.backup" ]; then
                nombre_descriptivo=$(obtener_nombre "$cliente")
                if [ "$cliente" = "$nombre_descriptivo" ]; then
                    echo "   $cliente"
                else
                    echo "   $nombre_descriptivo ($cliente)"
                fi
            fi
        done
    else
        echo "   ❌ No hay base de datos de certificados"
    fi
}

# Función para suspender cliente (CORREGIDA)
suspender_cliente() {
    echo ""
    echo "⏸️  SUSPENDER CLIENTE (TEMPORAL)"
    echo "------------------------------"
    
    echo "Clientes activos:"
    clientes_activos=$(grep "^V" /etc/easy-rsa/pki/index.txt 2>/dev/null | awk '{print $6}' | head -10)
    
    if [ -z "$clientes_activos" ]; then
        echo "   No hay clientes activos"
        return
    fi
    
    for cliente in $clientes_activos; do
        nombre_descriptivo=$(obtener_nombre "$cliente")
        if [ "$cliente" = "$nombre_descriptivo" ]; then
            echo "   $cliente"
        else
            echo "   $nombre_descriptivo ($cliente)"
        fi
    done
    
    echo ""
    echo -n "Cliente a suspender: "
    read CLIENTE
    
    if [ ! -f "/etc/easy-rsa/pki/issued/${CLIENTE}.crt" ]; then
        echo "❌ Cliente '$CLIENTE' no encontrado"
        return
    fi
    
    echo "   [....] Suspendiendo cliente..."
    mkdir -p /etc/openvpn/suspended/
    cp "/etc/easy-rsa/pki/issued/${CLIENTE}.crt" "/etc/openvpn/suspended/${CLIENTE}.crt.backup"
    cp "/etc/easy-rsa/pki/private/${CLIENTE}.key" "/etc/openvpn/suspended/${CLIENTE}.key.backup"
    
    cd /etc/easy-rsa
    echo "yes" | easyrsa revoke "$CLIENTE" > /dev/null 2>&1
    easyrsa gen-crl > /dev/null 2>&1
    cp /etc/easy-rsa/pki/crl.pem /etc/openvpn/
    /etc/init.d/openvpn restart > /dev/null 2>&1
    sleep 2
    
    nombre_descriptivo=$(obtener_nombre "$CLIENTE")
    echo "✅ CLIENTE '$nombre_descriptivo' SUSPENDIDO"
}

# Función para reactivar cliente (CORREGIDA)
reactivar_cliente() {
    echo ""
    echo "▶️  REACTIVAR CLIENTE"
    echo "-------------------"
    
    echo "Clientes suspendidos:"
    suspendidos_encontrados=0
    for cliente in $(grep "^R" /etc/easy-rsa/pki/index.txt 2>/dev/null | awk '{print $6}'); do
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
    
    if [ $suspendidos_encontrados -eq 0 ]; then
        echo "   No hay clientes suspendidos"
        return
    fi
    
    echo ""
    echo -n "Cliente a reactivar: "
    read CLIENTE
    
    if [ ! -f "/etc/openvpn/suspended/${CLIENTE}.crt.backup" ]; then
        echo "❌ Cliente '$CLIENTE' no está suspendido"
        return
    fi
    
    echo "   [....] Reactivando cliente..."
    cp "/etc/openvpn/suspended/${CLIENTE}.crt.backup" "/etc/easy-rsa/pki/issued/${CLIENTE}.crt"
    cp "/etc/openvpn/suspended/${CLIENTE}.key.backup" "/etc/easy-rsa/pki/private/${CLIENTE}.key"
    
    cd /etc/easy-rsa
    sed -i "/\/CN=${CLIENTE}$/d" /etc/easy-rsa/pki/index.txt
    easyrsa gen-crl > /dev/null 2>&1
    cp /etc/easy-rsa/pki/crl.pem /etc/openvpn/
    /etc/init.d/openvpn restart > /dev/null 2>&1
    sleep 2
    
    nombre_descriptivo=$(obtener_nombre "$CLIENTE")
    echo "✅ CLIENTE '$nombre_descriptivo' REACTIVADO"
}

# Función para bloquear permanente (CORREGIDA)
bloquear_permanentemente() {
    echo ""
    echo "🚫 BLOQUEO PERMANENTE"
    echo "-------------------"
    
    echo "Clientes activos:"
    clientes_activos=$(grep "^V" /etc/easy-rsa/pki/index.txt 2>/dev/null | awk '{print $6}' | head -10)
    
    if [ -z "$clientes_activos" ]; then
        echo "   No hay clientes activos"
        return
    fi
    
    for cliente in $clientes_activos; do
        nombre_descriptivo=$(obtener_nombre "$cliente")
        if [ "$cliente" = "$nombre_descriptivo" ]; then
            echo "   $cliente"
        else
            echo "   $nombre_descriptivo ($cliente)"
        fi
    done
    
    echo ""
    echo -n "Cliente a bloquear permanentemente: "
    read CLIENTE
    
    if [ ! -f "/etc/easy-rsa/pki/issued/${CLIENTE}.crt" ]; then
        echo "❌ Cliente '$CLIENTE' no encontrado"
        return
    fi
    
    echo "   [....] Bloqueando cliente..."
    cd /etc/easy-rsa
    echo "yes" | easyrsa revoke "$CLIENTE" > /dev/null 2>&1
    easyrsa gen-crl > /dev/null 2>&1
    cp /etc/easy-rsa/pki/crl.pem /etc/openvpn/
    /etc/init.d/openvpn restart > /dev/null 2>&1
    sleep 2
    
    nombre_descriptivo=$(obtener_nombre "$CLIENTE")
    echo "✅ CLIENTE '$nombre_descriptivo' BLOQUEADO PERMANENTEMENTE"
}

# Función para gestionar nombres (CORREGIDA)
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
                if [ -f "/etc/easy-rsa/pki/index.txt" ]; then
                    grep -E "^(V|R)" /etc/easy-rsa/pki/index.txt 2>/dev/null | awk '{print $6}' | while read cliente; do
                        nombre_actual=$(obtener_nombre "$cliente")
                        if [ "$cliente" = "$nombre_actual" ]; then
                            echo "   $cliente"
                        else
                            echo "   $cliente → $nombre_actual"
                        fi
                    done | head -10
                fi
                echo ""
                echo -n "Certificado del cliente: "
                read cliente
                echo -n "Nombre descriptivo: "
                read nombre_descriptivo
                
                if [ -n "$cliente" ] && [ -n "$nombre_descriptivo" ]; then
                    # Eliminar entrada existente
                    grep -v "^${cliente}:" "$NOMBRES_FILE" 2>/dev/null > "${NOMBRES_FILE}.tmp"
                    mv "${NOMBRES_FILE}.tmp" "$NOMBRES_FILE"
                    
                    # Agregar nueva entrada
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
                    grep -v "^#" "$NOMBRES_FILE" | while read linea; do
                        cliente=$(echo "$linea" | cut -d: -f1)
                        nombre=$(echo "$linea" | cut -d: -f2)
                        echo "   $nombre → $cliente"
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
                    grep -v "^#" "$NOMBRES_FILE" | while read linea; do
                        cliente=$(echo "$linea" | cut -d: -f1)
                        nombre=$(echo "$linea" | cut -d: -f2)
                        echo "   $nombre ($cliente)"
                    done
                    echo ""
                    echo -n "Certificado del cliente a eliminar nombre: "
                    read cliente
                    if grep -q "^${cliente}:" "$NOMBRES_FILE"; then
                        grep -v "^${cliente}:" "$NOMBRES_FILE" > "${NOMBRES_FILE}.tmp"
                        mv "${NOMBRES_FILE}.tmp" "$NOMBRES_FILE"
                        echo "✅ Nombre eliminado para $cliente"
                    else
                        echo "❌ No hay nombre asignado para $cliente"
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

# Función para estado del servicio (CORREGIDA)
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

# Menú principal (CORREGIDO)
while true; do
    mostrar_menu
    read OPCION
    
    case $OPCION in
        1) ver_conectados ;;
        2) listar_clientes ;;
        3) suspender_cliente ;;
        4) reactivar_cliente ;;
        5) bloquear_permanentemente ;;
        6) gestionar_nombres ;;
        7) estado_servicio ;;
        8)
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
echo "✅ GESTOR CORREGIDO INSTALADO"
echo ""
echo "🔧 CORRECIONES APLICADAS:"
echo "   - Eliminados errores aritméticos en bucles"
echo "   - Simplificado el cálculo de bytes"
echo "   - Mejorado el manejo de variables"
echo ""
echo "🚀 EJECUTA: gestor-vpn"
