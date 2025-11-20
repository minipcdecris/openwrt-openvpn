#!/bin/sh

echo "================================================"
echo "    INSTALADOR SERVIDOR OPENVPN - COMPLETO"
echo "       BR-VPN + DUCKDNS EDITABLE"
echo "================================================"
echo ""

# INSTRUCCIONES PREVIAS DUCKDNS
echo "🦆 CONFIGURACIÓN PREVIA DUCKDNS"
echo "------------------------------"
echo "ANTES de ejecutar este script:"
echo ""
echo "1. 📍 Ve a LuCI: Services → Dynamic DNS"
echo "2. ➕ Crea un NUEVO servicio:"
echo "   - Service Name: DuckDNS"
echo "   - DDNS Service Provider: duckdns.org"
echo "3. 🔘 Haz click en 'Really switch service?'"
echo "4. 💾 Guarda (pero NO configures los demás campos)"
echo ""
echo "¿Ya has creado el servicio DuckDNS? (s/n): "
read DUCKDNS_CREADO

if [ "$DUCKDNS_CREADO" != "s" ]; then
    echo "❌ Crea primero el servicio DuckDNS y luego ejecuta el script"
    exit 1
fi

echo ""
echo "📋 CONFIGURACIÓN DUCKDNS"
echo "-----------------------"
read -p "🔹 Tu dominio DuckDNS (sin .duckdns.org): " DUCKDNS_DOMAIN
read -p "🔹 Token de DuckDNS: " DUCKDNS_TOKEN

DDNS_SERVER="${DUCKDNS_DOMAIN}.duckdns.org"

echo ""
echo "📍 DOMINIO DUCKDNS: $DDNS_SERVER"
echo ""

# CONFIGURACIÓN OPENVPN
echo "📋 CONFIGURACIÓN OPENVPN"
echo "-----------------------"
read -p "🔹 Puerto OpenVPN (1194): " VPN_PORT
VPN_PORT=${VPN_PORT:-1194}
read -p "🔹 Número de clientes (4): " NUM_CLIENTES
NUM_CLIENTES=${NUM_CLIENTES:-4}

echo ""
echo "📍 RESUMEN:"
echo "   DuckDNS: $DDNS_SERVER"
echo "   Servidor: $DDNS_SERVER:$VPN_PORT"
echo "   Clientes: $NUM_CLIENTES"
echo "   Interfaz: br-vpn"
echo ""

read -p "¿Continuar con la instalación? (s/n): " CONFIRMAR
[ "$CONFIRMAR" != "s" ] && echo "Instalación cancelada." && exit 0

echo ""
echo "🚀 INICIANDO INSTALACIÓN COMPLETA..."
echo ""

# 1. INSTALACIÓN DE PAQUETES
echo "📦 PASO 1: INSTALANDO PAQUETES..."
echo "--------------------------------"
opkg update
opkg install openvpn-easy-rsa openvpn-openssl luci-app-openvpn ddns-scripts ddns-scripts-duckdns luci-app-ddns
echo "✅ Paquetes instalados"
echo ""

# 2. CONFIGURAR DUCKDNS (EDITANDO SERVICIO EXISTENTE)
echo "🦆 PASO 2: CONFIGURANDO DUCKDNS..."
echo "---------------------------------"
# Buscar el servicio DuckDNS existente
DUCKDNS_SERVICE=$(uci show ddns | grep "service_name='duckdns.org'" | cut -d'.' -f2 | cut -d'=' -f1)

if [ -n "$DUCKDNS_SERVICE" ]; then
    echo "🔹 Editando servicio DuckDNS existente: $DUCKDNS_SERVICE"
    
    # Configurar los campos del servicio existente
    uci set ddns.$DUCKDNS_SERVICE.lookup_host="$DDNS_SERVER"
    uci set ddns.$DUCKDNS_SERVICE.domain="$DDNS_SERVER"
    uci set ddns.$DUCKDNS_SERVICE.username="$DUCKDNS_DOMAIN"
    uci set ddns.$DUCKDNS_SERVICE.password="$DUCKDNS_TOKEN"
    uci set ddns.$DUCKDNS_SERVICE.enabled='1'
    uci set ddns.$DUCKDNS_SERVICE.interface='wan'
    uci set ddns.$DUCKDNS_SERVICE.ip_source='web'
    uci set ddns.$DUCKDNS_SERVICE.ip_url='http://checkip.dyndns.com'
    uci set ddns.$DUCKDNS_SERVICE.check_interval='300'
    uci set ddns.$DUCKDNS_SERVICE.force_interval='5'
    uci set ddns.$DUCKDNS_SERVICE.force_unit='minutes'
    
    uci commit ddns
    /etc/init.d/ddns restart
    
    echo "✅ DuckDNS configurado automáticamente"
    echo "   🔸 Lookup Hostname: $DDNS_SERVER"
    echo "   🔸 Domain: $DDNS_SERVER"
    echo "   🔸 Username: $DUCKDNS_DOMAIN"
    echo "   🔸 IP Source: web"
    echo "   🔸 Check Interval: 300"
else
    echo "❌ No se encontró servicio DuckDNS existente"
    echo "⚠️  Configura DuckDNS manualmente en LuCI después"
fi
echo ""

# 3. GENERACIÓN DE CERTIFICADOS
echo "🔐 PASO 3: GENERANDO CERTIFICADOS..."
echo "-----------------------------------"
cd /etc/easy-rsa

echo "🔹 Inicializando PKI..."
echo -e "yes\nyes" | easyrsa init-pki

echo "🔹 Creando Autoridad Certificadora (CA)..."
echo -e "yes\nserver" | easyrsa build-ca nopass

echo "🔹 Creando certificado del servidor..."
echo -e "yes" | easyrsa build-server-full server nopass

echo "🔹 Creando certificados de clientes..."
for i in $(seq 1 $NUM_CLIENTES); do
    echo "   👤 Cliente $i..."
    echo -e "yes" | easyrsa build-client-full client$i nopass
done

echo "🔹 Generando parámetros Diffie-Hellman..."
easyrsa gen-dh
echo "✅ Certificados generados"
echo ""

# 4. COPIAR CERTIFICADOS
echo "📁 PASO 4: CONFIGURANDO OPENVPN..."
echo "---------------------------------"
cp /etc/easy-rsa/pki/ca.crt /etc/openvpn/
cp /etc/easy-rsa/pki/private/server.key /etc/openvpn/
cp /etc/easy-rsa/pki/issued/server.crt /etc/openvpn/
cp /etc/easy-rsa/pki/dh.pem /etc/openvpn/

# Configuración OpenVPN
cat > /etc/config/openvpn << CFG
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
CFG
echo "✅ OpenVPN configurado"
echo ""

# 5. CONFIGURAR FIREWALL
echo "🔥 PASO 5: CONFIGURANDO FIREWALL..."
echo "----------------------------------"
uci add firewall rule
uci set firewall.@rule[-1].name='Allow-OpenVPN'
uci set firewall.@rule[-1].src='wan'
uci set firewall.@rule[-1].proto='udp'
uci set firewall.@rule[-1].dest_port="$VPN_PORT"
uci set firewall.@rule[-1].target='ACCEPT'
uci commit firewall
/etc/init.d/firewall reload
echo "✅ Firewall configurado"
echo ""

# 6. CREAR BRIDGE BR-VPN
echo "🔧 PASO 6: CREANDO BRIDGE BR-VPN..."
echo "----------------------------------"
# Crear interfaz tap0 manualmente
ip tuntap add mode tap tap0
ifconfig tap0 up

# Crear bridge br-vpn manualmente
brctl addbr br-vpn
brctl addif br-vpn tap0
ifconfig br-vpn up

# Configurar UCI para persistencia
uci set network.br-vpn=device
uci set network.br-vpn.type='bridge'
uci set network.br-vpn.name='br-vpn'
uci add_list network.br-vpn.ports='tap0'
uci set network.br-vpn.igmp_snooping='1'

uci set network.vpn=interface
uci set network.vpn.proto='none'
uci set network.vpn.device='br-vpn'

uci commit network
echo "✅ Bridge br-vpn creado"
echo ""

# 7. GENERAR ARCHIVOS CLIENTE .OVPN
echo "📄 PASO 7: GENERANDO ARCHIVOS CLIENTE..."
echo "--------------------------------------"
for i in $(seq 1 $NUM_CLIENTES); do
    echo "🔹 Generando client$i.ovpn..."
    cat > /etc/openvpn/client$i.ovpn << OVPN
client
dev tap
proto udp
remote $DDNS_SERVER $VPN_PORT
resolv-retry infinite
nobind
float
cipher AES-256-GCM
keepalive 15 60
remote-cert-tls server
<ca>
$(cat /etc/openvpn/ca.crt)
</ca>
<cert>
$(cat /etc/easy-rsa/pki/issued/client$i.crt)
</cert>
<key>
$(cat /etc/easy-rsa/pki/private/client$i.key)
</key>
OVPN
    
    cp /etc/openvpn/client$i.ovpn /tmp/client$i.ovpn
    echo "   ✅ client$i.ovpn creado"
done
echo "✅ Todos los archivos .ovpn generados"
echo ""

# 8. INICIAR SERVICIOS
echo "🚀 PASO 8: INICIANDO SERVICIOS..."
echo "-------------------------------"
/etc/init.d/openvpn enable
/etc/init.d/openvpn start
/etc/init.d/ddns restart
sleep 3
echo "✅ Servicios iniciados"
echo ""

# 9. VERIFICACIÓN FINAL
echo "🔍 PASO 9: VERIFICACIÓN FINAL..."
echo "-------------------------------"
echo "🔹 Verificando OpenVPN..."
pgrep openvpn >/dev/null && echo "   ✅ OpenVPN corriendo" || echo "   ❌ OpenVPN no corre"

echo "🔹 Verificando DuckDNS..."
if [ -n "$DUCKDNS_SERVICE" ]; then
    uci get ddns.$DUCKDNS_SERVICE.enabled && echo "   ✅ DuckDNS configurado" || echo "   ❌ DuckDNS no configurado"
else
    echo "   ⚠️  DuckDNS requiere configuración manual"
fi

echo "🔹 Verificando interfaces..."
ifconfig tap0 >/dev/null 2>&1 && echo "   ✅ tap0 activa" || echo "   ❌ tap0 inactiva"
ifconfig br-vpn >/dev/null 2>&1 && echo "   ✅ br-vpn activo" || echo "   ❌ br-vpn inactivo"

echo "🔹 Verificando archivos cliente..."
for i in $(seq 1 $NUM_CLIENTES); do
    [ -f "/tmp/client$i.ovpn" ] && echo "   ✅ client$i.ovpn" || echo "   ❌ client$i.ovpn faltante"
done
echo ""

# RESUMEN FINAL
echo "🎉 INSTALACIÓN COMPLETADA EXITOSAMENTE!"
echo "========================================"
echo ""
echo "📍 SERVICIOS CONFIGURADOS:"
echo "   🔸 OpenVPN: ✅ $DDNS_SERVER:$VPN_PORT"
if [ -n "$DUCKDNS_SERVICE" ]; then
    echo "   🔸 DuckDNS: ✅ Configurado automáticamente"
else
    echo "   🔸 DuckDNS: ❌ Requiere configuración manual"
fi
echo "   🔸 Bridge: ✅ br-vpn con interfaz vpn"
echo ""
echo "📍 ARCHIVOS CLIENTE:"
echo "   🔸 /tmp/client1.ovpn ... client$NUM_CLIENTES.ovpn"
echo ""
echo "🔄 Reiniciando en 15 segundos..."
sleep 15
echo "Reiniciando..."
reboot
