#!/bin/sh

echo ""
echo "🛠️  REINSTALANDO GESTOR-OPENVPN FUNCIONAL"
echo "========================================"

# 1. Eliminar el gestor actual
echo ""
echo "🗑️  Eliminando gestor actual..."
rm -f /usr/bin/gestor-openvpn

# 2. Crear nuevo gestor funcional
echo ""
echo "📝 Creando nuevo gestor..."
cat > /usr/bin/gestor-openvpn << 'GESTOR_SCRIPT'
#!/bin/sh

# Función para mostrar menú
mostrar_menu() {
    echo ""
    echo "🔧 GESTOR DE CLIENTES OPENVPN - COMPLETO"
    echo "========================================"
    echo ""
    echo "1) Ver clientes conectados"
    echo "2) Ver todos los clientes (válidos y revocados)"
    echo "3) Bloquear cliente (revocar certificado)"
    echo "4) Desbloquear cliente (nuevo certificado)"
    echo "5) Ver solo clientes revocados"
    echo "6) Estado del servicio"
    echo "7) Salir"
    echo ""
    echo -n "Selecciona una opción [1-7]: "
}

# Función para ver clientes conectados
ver_conectados() {
    echo ""
    echo "📊 CLIENTES CONECTADOS:"
    if [ -f "/var/log/openvpn-status.log" ]; then
        if grep -q "CLIENT_LIST" "/var/log/openvpn-status.log"; then
            echo "📍 Por archivo de estado:"
            grep "^CLIENT_LIST" /var/log/openvpn-status.log | while read line; do
                client=$(echo "$line" | awk '{print $2}')
                ip=$(echo "$line" | awk '{print $3}')
                bytes_recv=$(echo "$line" | awk '{print $4}')
                bytes_sent=$(echo "$line" | awk '{print $5}')
                echo "   └─ $client (IP: $ip)"
                echo "      ├─ Descargado: $((${bytes_recv:-0}/1024/1024)) MB"
                echo "      ├─ Subido: $((${bytes_sent:-0}/1024/1024)) MB"
            done
        else
            echo "   ℹ️  No hay clientes conectados"
        fi
    else
        echo "   ❌ Archivo de estado no encontrado"
    fi
}

# Función para ver todos los clientes
ver_todos() {
    echo ""
    echo "👥 TODOS LOS CLIENTES:"
    if [ -f "/etc/easy-rsa/pki/index.txt" ]; then
        echo "✅ VÁLIDOS:"
        grep "^V" /etc/easy-rsa/pki/index.txt 2>/dev/null | awk '{print "   " $6}' || echo "   No hay clientes válidos"
        echo ""
        echo "❌ REVOCADOS:"
        grep "^R" /etc/easy-rsa/pki/index.txt 2>/dev/null | awk '{print "   " $6}' || echo "   No hay clientes revocados"
    else
        echo "   ❌ No se encontró la base de datos de certificados"
    fi
}

# Función para bloquear cliente
bloquear_cliente() {
    echo ""
    echo -n "🔒 Nombre del cliente a bloquear (ej: client1): "
    read CLIENTE
    
    if [ -f "/etc/easy-rsa/pki/issued/${CLIENTE}.crt" ]; then
        cd /etc/easy-rsa
        echo "yes" | easyrsa revoke "$CLIENTE" > /dev/null 2>&1
        easyrsa gen-crl > /dev/null 2>&1
        cp /etc/easy-rsa/pki/crl.pem /etc/openvpn/
        /etc/init.d/openvpn restart > /dev/null 2>&1
        echo "✅ Cliente $CLIENTE bloqueado"
    else
        echo "❌ Cliente $CLIENTE no encontrado"
    fi
}

# Función para desbloquear cliente
desbloquear_cliente() {
    echo ""
    echo -n "🔓 Nombre del cliente a desbloquear (ej: client1): "
    read CLIENTE
    
    cd /etc/easy-rsa
    echo -e "yes" | easyrsa build-client-full "$CLIENTE" nopass > /dev/null 2>&1
    easyrsa gen-crl > /dev/null 2>&1
    cp /etc/easy-rsa/pki/crl.pem /etc/openvpn/
    /etc/init.d/openvpn restart > /dev/null 2>&1
    echo "✅ Cliente $CLIENTE desbloqueado - NUEVO certificado generado"
}

# Función para ver revocados
ver_revocados() {
    echo ""
    echo "📋 CLIENTES REVOCADOS:"
    if [ -f "/etc/easy-rsa/pki/index.txt" ]; then
        revoked=$(grep "^R" /etc/easy-rsa/pki/index.txt 2>/dev/null | awk '{print $6}')
        if [ -n "$revoked" ]; then
            echo "$revoked" | while read client; do
                echo "   ❌ $client"
            done
        else
            echo "   ✅ No hay clientes revocados"
        fi
    else
        echo "   ❌ No se encontró la base de datos de certificados"
    fi
}

# Función para estado del servicio
estado_servicio() {
    echo ""
    echo "🔍 ESTADO DEL SERVICIO:"
    if pgrep openvpn > /dev/null; then
        echo "   ✅ OpenVPN: ACTIVO"
    else
        echo "   ❌ OpenVPN: INACTIVO"
    fi
    
    if [ -f "/var/log/openvpn-status.log" ]; then
        echo "   ✅ Archivo de estado: EXISTE"
    else
        echo "   ❌ Archivo de estado: NO EXISTE"
    fi
    
    if ip link show tap0 > /dev/null 2>&1; then
        echo "   ✅ Interfaz tap0: ACTIVA"
    else
        echo "   ❌ Interfaz tap0: INACTIVA"
    fi
}

# Menú principal
while true; do
    mostrar_menu
    read OPCION
    
    case $OPCION in
        1) ver_conectados ;;
        2) ver_todos ;;
        3) bloquear_cliente ;;
        4) desbloquear_cliente ;;
        5) ver_revocados ;;
        6) estado_servicio ;;
        7)
            echo ""
            echo "👋 Saliendo..."
            exit 0
            ;;
        *)
            echo "❌ Opción inválida. Usa números del 1 al 7."
            ;;
    esac
    
    echo ""
    echo "────────────────────────────────────"
done
GESTOR_SCRIPT

# 3. Dar permisos de ejecución
chmod +x /usr/bin/gestor-openvpn

echo ""
echo "✅ Gestor reinstalado correctamente"
echo ""
echo "🚀 Probando el gestor..."
echo "────────────────────────────────────"

# Probar que funcione
/usr/bin/gestor-openvpn
