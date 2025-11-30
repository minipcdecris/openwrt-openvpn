#!/bin/sh

echo ""
echo "🔧 CONFIGURANDO OPENVPN PARA LUCi"
echo "================================"

# 1. Verificar estado actual
echo ""
echo "🔍 ESTADO ACTUAL:"
echo "----------------"

if uci show openvpn | grep -q "VPN_Server"; then
    echo "✅ Configuración VPN_Server detectada"
    uci show openvpn.VPN_Server
else
    echo "❌ No hay configuración VPN_Server"
fi

# 2. Crear configuración compatible con LuCI
echo ""
echo "⚙️  CREANDO CONFIGURACIÓN LUCi:"
echo "------------------------------"

# Detectar valores actuales o usar valores por defecto
VPN_PORT=$(uci get openvpn.VPN_Server.port 2>/dev/null || echo "1194")
DDNS_DOMAIN=$(uci get ddns.@service[0].domain 2>/dev/null || echo "tudominio.duckdns.org")

echo "   Puerto detectado: $VPN_PORT"
echo "   Dominio detectado: $DDNS_DOMAIN"

# Crear configuración OpenVPN para LuCI
cat > /etc/config/openvpn << OVPN_CONFIG
config openvpn 'VPN_Server'
    option enabled '1'
    option mode 'server'
    option dev 'tap0'
    option proto 'udp'
    option port '$VPN_PORT'
    option tls_server '1'
    option ca '/etc/openvpn/ca.crt'
    option cert '/etc/openvpn/server.crt'
    option key '/etc/openvpn/server.key'
    option dh '/etc/openvpn/dh.pem'
    option server_bridge '10.8.0.1 255.255.255.0 10.8.0.2 10.8.0.254'
    option keepalive '10 120'
    option cipher 'AES-256-GCM'
    option user 'nobody'
    option group 'nogroup'
    option persist_key '1'
    option persist_tun '1'
    option verb '3'
    option duplicate_cn '1'
    option client_to_client '1'
    option status '/var/log/openvpn-status.log'
    option status_version '3'
    option log '/var/log/openvpn.log'
    option crl_verify '/etc/openvpn/crl.pem'

config openvpn 'client_template'
    option enabled '0'
    option dev 'tap'
    option proto 'udp'
    option resolv_retry 'infinite'
    option nobind '1'
    option remote "$DDNS_DOMAIN $VPN_PORT"
    option float '1'
    option cipher 'AES-256-GCM'
    option keepalive '15 60'
    option remote_cert_tls 'server'
OVPN_CONFIG

echo "✅ Configuración creada"

# 3. Asegurar que los archivos de certificados existan
echo ""
echo "🔐 VERIFICANDO CERTIFICADOS:"
echo "---------------------------"

echo "   [....] Verificando archivos de certificados..."

# Verificar cada archivo individualmente
if [ -f "/etc/openvpn/ca.crt" ]; then
    echo "✅ /etc/openvpn/ca.crt: EXISTE"
    chmod 644 /etc/openvpn/ca.crt
else
    echo "❌ /etc/openvpn/ca.crt: FALTANTE"
fi

if [ -f "/etc/openvpn/server.crt" ]; then
    echo "✅ /etc/openvpn/server.crt: EXISTE"
    chmod 644 /etc/openvpn/server.crt
else
    echo "❌ /etc/openvpn/server.crt: FALTANTE"
fi

if [ -f "/etc/openvpn/server.key" ]; then
    echo "✅ /etc/openvpn/server.key: EXISTE"
    chmod 600 /etc/openvpn/server.key
else
    echo "❌ /etc/openvpn/server.key: FALTANTE"
fi

if [ -f "/etc/openvpn/dh.pem" ]; then
    echo "✅ /etc/openvpn/dh.pem: EXISTE"
    chmod 644 /etc/openvpn/dh.pem
else
    echo "❌ /etc/openvpn/dh.pem: FALTANTE"
fi

if [ -f "/etc/openvpn/crl.pem" ]; then
    echo "✅ /etc/openvpn/crl.pem: EXISTE"
    chmod 644 /etc/openvpn/crl.pem
else
    echo "❌ /etc/openvpn/crl.pem: FALTANTE"
fi

# 4. Crear interfaz TAP si no existe
echo ""
echo "🔌 CONFIGURANDO INTERFAZ TAP:"
echo "----------------------------"

if ! grep -q "tap0" /etc/config/network 2>/dev/null; then
    echo "   [....] Agregando interfaz tap0 a network..."
    uci set network.tap0=interface
    uci set network.tap0.proto='none'
    uci set network.tap0.device='tap0'
    uci commit network
    echo "   ✅ Interfaz tap0 agregada"
else
    echo "   ✅ Interfaz tap0 ya existe"
fi

# Crear dispositivo TAP
if ! grep -q "name.*tap0" /etc/config/network 2>/dev/null; then
    echo "   [....] Agregando dispositivo tap0..."
    uci add network device
    uci set network.@device[-1].name='tap0'
    uci set network.@device[-1].type='tap'
    uci commit network
    echo "   ✅ Dispositivo tap0 agregado"
else
    echo "   ✅ Dispositivo tap0 ya existe"
fi

# 5. Configurar firewall para OpenVPN
echo ""
echo "🔥 CONFIGURANDO FIREWALL:"
echo "------------------------"

# Verificar si ya existe la regla
if ! uci show firewall | grep -q "Allow-OpenVPN"; then
    echo "   [....] Agregando regla de firewall..."
    uci add firewall rule
    uci set firewall.@rule[-1].name='Allow-OpenVPN'
    uci set firewall.@rule[-1].src='wan'
    uci set firewall.@rule[-1].proto='udp'
    uci set firewall.@rule[-1].dest_port="$VPN_PORT"
    uci set firewall.@rule[-1].target='ACCEPT'
    uci commit firewall
    echo "   ✅ Regla de firewall agregada"
else
    echo "   ✅ Regla de firewall ya existe"
fi

# 6. Reiniciar servicios
echo ""
echo "🔄 REINICIANDO SERVICIOS:"
echo "------------------------"

echo "   [....] Reiniciando firewall..."
/etc/init.d/firewall reload >/dev/null 2>&1
sleep 2

echo "   [....] Reiniciando red..."
/etc/init.d/network reload >/dev/null 2>&1
sleep 2

echo "   [....] Reiniciando OpenVPN..."
/etc/init.d/openvpn enable >/dev/null 2>&1
/etc/init.d/openvpn restart >/dev/null 2>&1
sleep 3

echo "   [....] Reiniciando LuCI..."
/etc/init.d/uhttpd restart >/dev/null 2>&1
sleep 2

# 7. Verificación final
echo ""
echo "✅ VERIFICACIÓN FINAL:"
echo "---------------------"

echo ""
echo "📊 ESTADO OPENVPN:"
if pgrep openvpn >/dev/null; then
    echo "   ✅ Servicio OpenVPN: ACTIVO"
    echo "   📍 PID: $(pgrep openvpn)"
else
    echo "   ❌ Servicio OpenVPN: INACTIVO"
fi

echo ""
echo "🌐 INTERFAZ TAP0:"
if ip link show tap0 >/dev/null 2>&1; then
    echo "   ✅ Interfaz tap0: ACTIVA"
else
    echo "   ❌ Interfaz tap0: INACTIVA"
fi

echo ""
echo "📁 CONFIGURACIÓN:"
if uci get openvpn.VPN_Server.enabled >/dev/null 2>&1; then
    echo "   ✅ Configuración VPN_Server: PRESENTE"
    echo "   🔧 Estado: $(uci get openvpn.VPN_Server.enabled)"
else
    echo "   ❌ Configuración VPN_Server: FALTANTE"
fi

echo ""
echo "🎯 INSTRUCCIONES DE ACCESO:"
ROUTER_IP=$(uci get network.lan.ipaddr 2>/dev/null || echo "192.168.1.1")
echo "   1. Ve a: http://$ROUTER_IP"
echo "   2. Navega a: VPN → OpenVPN"
echo "   3. Deberías ver:"
echo "      - Status (pestaña)"
echo "      - OpenVPN Instances (pestaña)" 
echo "      - Configuration (pestaña)"
echo ""
echo "💡 Si aún no aparece, limpia la cache del navegador o usa modo incógnito"

echo ""
echo "✨ CONFIGURACIÓN COMPLETADA"
