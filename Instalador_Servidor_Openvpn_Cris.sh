#!/bin/sh

echo "================================================"
echo "    INSTALADOR SERVIDOR OPENVPN - COMPLETO"
echo "       BR-VPN + INSTRUCCIONES DUCKDNS"
echo "================================================"
echo ""

# CONFIGURACIÓN DUCKDNS
echo "🦆 CONFIGURACIÓN DUCKDNS"
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

read -p "¿Continuar con la instalación OpenVPN? (s/n): " CONFIRMAR
[ "$CONFIRMAR" != "s" ] && echo "Instalación cancelada." && exit 0

echo ""
echo "🚀 INICIANDO INSTALACIÓN OPENVPN..."
echo ""

# 1. INSTALACIÓN DE PAQUETES
echo "📦 PASO 1: INSTALANDO PAQUETES..."
echo "--------------------------------"
opkg update
opkg install openvpn-easy-rsa openvpn-openssl luci-app-openvpn ddns-scripts ddns-scripts-duckdns luci-app-ddns
echo "✅ Paquetes instalados"
echo ""

# 2. GENERACIÓN DE CERTIFICADOS
echo "🔐 PASO 2: GENERANDO CERTIFICADOS..."
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

# 3. COPIAR CERTIFICADOS
echo "📁 PASO 3: CONFIGURANDO OPENVPN..."
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

# 4. CONFIGURAR FIREWALL
echo "🔥 PASO 4: CONFIGURANDO FIREWALL..."
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

# 5. CREAR BRIDGE BR-VPN
echo "🔧 PASO 5: CREANDO BRIDGE BR-VPN..."
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

# 6. GENERAR ARCHIVOS CLIENTE .OVPN
echo "📄 PASO 6: GENERANDO ARCHIVOS CLIENTE..."
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

# 7. INICIAR SERVICIOS
echo "🚀 PASO 7: INICIANDO SERVICIOS..."
echo "-------------------------------"
/etc/init.d/openvpn enable
/etc/init.d/openvpn start
sleep 3
echo "✅ Servicios OpenVPN iniciados"
echo ""

# 8. VERIFICACIÓN FINAL
echo "🔍 PASO 8: VERIFICACIÓN FINAL..."
echo "-------------------------------"
echo "🔹 Verificando OpenVPN..."
pgrep openvpn >/dev/null && echo "   ✅ OpenVPN corriendo" || echo "   ❌ OpenVPN no corre"

echo "🔹 Verificando interfaces..."
ifconfig tap0 >/dev/null 2>&1 && echo "   ✅ tap0 activa" || echo "   ❌ tap0 inactiva"
ifconfig br-vpn >/dev/null 2>&1 && echo "   ✅ br-vpn activo" || echo "   ❌ br-vpn inactivo"

echo "🔹 Verificando archivos cliente..."
for i in $(seq 1 $NUM_CLIENTES); do
    [ -f "/tmp/client$i.ovpn" ] && echo "   ✅ client$i.ovpn" || echo "   ❌ client$i.ovpn faltante"
done
echo ""

# 9. INSTRUCCIONES DUCKDNS DETALLADAS
echo "🦆 CONFIGURACIÓN MANUAL DUCKDNS"
echo "================================"
echo ""
echo "PARA CONFIGURAR DUCKDNS EN LUCI:"
echo ""
echo "1. 📍 Abre LuCI en tu navegador:"
echo "   http://$(uci get network.lan.ipaddr 2>/dev/null || echo '192.168.1.1')"
echo ""
echo "2. 🚀 Ve a: Services → Dynamic DNS"
echo ""
echo "3. 🗑️  ELIMINA los servicios existentes:"
echo "   - Haz click en cada servicio existente"
echo "   - Desplázate al final de la página"
echo "   - Haz click en 'Delete'"
echo ""
echo "4. ➕ CREA un NUEVO servicio:"
echo "   - Haz click en 'Add'"
echo "   - En 'Service Name' escribe: DuckDNS"
echo ""
echo "5. ⚙️  CONFIGURA los siguientes valores:"
echo ""
echo "   🔸 BASIC SETTINGS:"
echo "   - Lookup Hostname: $DDNS_SERVER"
echo "   - DDNS Service Provider: [Selecciona] duckdns.org"
echo "   - ⚠️  IMPORTANTE: Al seleccionar 'duckdns.org' aparecerá"
echo "     un mensaje 'Really switch service?' - Haz click en 'Switch'"
echo "   - Domain: $DDNS_SERVER"
echo "   - Username: $DUCKDNS_DOMAIN"
echo "   - Password: $DUCKDNS_TOKEN"
echo ""
echo "   🔸 ADVANCED SETTINGS (haz click en la pestaña):"
echo "   - IP address source: [Selecciona] URL"
echo "   - URL to detect: http://checkip.dyndns.com"
echo ""
echo "   🔸 TIMER SETTINGS:"
echo "   - Check Interval: 300"
echo "   - Force Interval: 5"
echo ""
echo "6. 💾 GUARDA la configuración:"
echo "   - Haz click en 'Save & Apply'"
echo ""
echo "7. ✅ VERIFICA que funciona:"
echo "   - El estado debería cambiar a 'enabled'"
echo "   - En unos minutos se actualizará tu IP"
echo ""

# RESUMEN FINAL
echo "🎉 INSTALACIÓN OPENVPN COMPLETADA!"
echo "==================================="
echo ""
echo "📍 SERVICIOS CONFIGURADOS:"
echo "   🔸 OpenVPN: ✅ $DDNS_SERVER:$VPN_PORT"
echo "   🔸 Bridge: ✅ br-vpn con interfaz vpn"
echo ""
echo "📍 ARCHIVOS CLIENTE:"
echo "   🔸 /tmp/client1.ovpn ... client$NUM_CLIENTES.ovpn"
echo ""
echo "📍 PRÓXIMOS PASOS:"
echo "   1. Configura DuckDNS siguiendo las instrucciones arriba"
echo "   2. Descarga los archivos .ovpn desde /tmp/"
echo "   3. Configura los routers clientes"
echo ""
echo "⚠️  RECUERDA:"
echo "   - Para DuckDNS: Debes hacer click en 'Really switch service?'"
echo "   - Para persistencia: Reinicia el router luego con 'reboot'"
echo ""
echo "¿Quieres reiniciar ahora? (s/n): "
read REINICIAR
if [ "$REINICIAR" = "s" ]; then
    echo "Reiniciando..."
    reboot
else
    echo "✅ Instalación completada. Reinicia luego con: reboot"
    echo "📁 Archivos cliente en: /tmp/client*.ovpn"
fi
