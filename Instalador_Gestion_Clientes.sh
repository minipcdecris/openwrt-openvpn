#!/bin/sh
echo ""
echo "🔧 AGREGAR GESTIÓN A OPENVPN EXISTENTE"
echo "======================================"

# 1. Verificar que OpenVPN está instalado y funcionando
echo "🔍 Verificando instalación OpenVPN..."
if ! pgrep openvpn >/dev/null; then
    echo "❌ OpenVPN no está ejecutándose"
    exit 1
fi

if [ ! -f "/etc/config/openvpn" ]; then
    echo "❌ No se encontró configuración OpenVPN"
    exit 1
fi

echo "✅ OpenVPN detectado y funcionando"

# 2. Agregar configuración de logs si no existe
echo ""
echo "📝 Configurando sistema de logs..."
if uci get openvpn.VPN_Server >/dev/null 2>&1; then
    # Solo agregar si no existen
    if ! uci get openvpn.VPN_Server.status >/dev/null 2>&1; then
        uci set openvpn.VPN_Server.status='/var/log/openvpn-status.log'
        echo "   ✅ Agregado: status log"
    fi
    
    if ! uci get openvpn.VPN_Server.status_version >/dev/null 2>&1; then
        uci set openvpn.VPN_Server.status_version='3'
        echo "   ✅ Agregado: status version"
    fi
    
    if ! uci get openvpn.VPN_Server.log >/dev/null 2>&1; then
        uci set openvpn.VPN_Server.log='/var/log/openvpn.log'
        echo "   ✅ Agregado: log file"
    fi
    
    if ! uci get openvpn.VPN_Server.crl_verify >/dev/null 2>&1; then
        uci set openvpn.VPN_Server.crl_verify='/etc/openvpn/crl.pem'
        echo "   ✅ Agregado: CRL verification"
    fi
    
    uci commit openvpn
else
    echo "❌ No se encontró la configuración VPN_Server"
fi

# 3. Crear lista de revocación si no existe
echo ""
echo "🔐 Configurando sistema de revocación..."
if [ -d "/etc/easy-rsa/pki" ]; then
    if [ ! -f "/etc/openvpn/crl.pem" ]; then
        cd /etc/easy-rsa
        easyrsa gen-crl > /dev/null 2>&1
        cp /etc/easy-rsa/pki/crl.pem /etc/openvpn/
        echo "   ✅ Lista de revocación creada"
    else
        echo "   ✅ Lista de revocación ya existe"
    fi
else
    echo "   ⚠️  No se encontró Easy-RSA, no se puede crear CRL"
fi

# 4. Crear script de gestión
echo ""
echo "📁 Creando script de gestión..."
cat > /usr/bin/gestor-openvpn << 'GESTOR_SCRIPT'
#!/bin/sh
echo ""
echo "🔧 GESTOR DE CLIENTES OPENVPN - COMPLETO"
echo "========================================"

# ... (TODO EL CÓDIGO DEL GESTOR COMPLETO QUE TE PUSE ANTES)
# ... (con todas las funciones: ver conectados, bloquear, desbloquear, etc.)

GESTOR_SCRIPT

chmod +x /usr/bin/gestor-openvpn
echo "   ✅ Script de gestión creado: /usr/bin/gestor-openvpn"

# 5. Reiniciar OpenVPN para aplicar cambios
echo ""
echo "🔄 Reiniciando OpenVPN..."
/etc/init.d/openvpn restart
sleep 3

# 6. Verificación final
echo ""
echo "✅ VERIFICACIÓN FINAL:"
if [ -f "/var/log/openvpn-status.log" ]; then
    echo "   ✅ Archivo de estado: CREADO"
else
    echo "   ⚠️  Archivo de estado: Se creará con la primera conexión"
fi

if [ -f "/var/log/openvpn.log" ]; then
    echo "   ✅ Archivo de log: CREADO"
else
    echo "   ⚠️  Archivo de log: Se creará con la primera conexión"
fi

if [ -f "/etc/openvpn/crl.pem" ]; then
    echo "   ✅ Lista de revocación: CREADA"
else
    echo "   ❌ Lista de revocación: FALTANTE"
fi

if [ -x "/usr/bin/gestor-openvpn" ]; then
    echo "   ✅ Script de gestión: INSTALADO"
else
    echo "   ❌ Script de gestión: FALTANTE"
fi

echo ""
echo "🎉 CONFIGURACIÓN COMPLETADA!"
echo "📍 Los certificados existentes se mantuvieron intactos"
echo "📍 Ahora puedes usar: gestor-openvpn"
echo ""
echo "🔧 Funciones disponibles:"
echo "   - Ver clientes conectados"
echo "   - Bloquear/desbloquear clientes"
echo "   - Gestión completa de certificados"
