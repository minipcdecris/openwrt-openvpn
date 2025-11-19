#!/bin/sh

echo "=== OPENVPN - CONFIGURACIÓN CORREGIDA ==="

# Configuración
DDNS_SERVER="campeon19.duckdns.org"
VPN_PORT=1194
NUM_CLIENTES=4

echo "Servidor: $DDNS_SERVER:$VPN_PORT"

# Verificar si ya está instalado
if [ ! -f /etc/easy-rsa/pki/ca.crt ]; then
    echo "Generando certificados..."
    cd /etc/easy-rsa
    echo -e "yes\nyes" | easyrsa init-pki
    echo -e "yes\nserver" | easyrsa build-ca nopass
    echo -e "yes" | easyrsa build-server-full server nopass
    for i in 1 2 3 4; do
        echo "Cliente $i..."
        echo -e "yes" | easyrsa build-client-full client$i nopass
    done
    easyrsa gen-dh
    
    # Copiar archivos
    cp pki/ca.crt /etc/openvpn/
    cp pki/private/server.key /etc/openvpn/
    cp pki/issued/server.crt /etc/openvpn/
    cp pki/dh.pem /etc/openvpn/
fi

# CONFIGURACIÓN OPENVPN CORREGIDA
echo "Configurando OpenVPN..."
cat > /etc/config/openvpn << 'CFG'
config openvpn 'VPN_Server'
    option enabled '1'
    option mode 'server'
    option dev 'tap0'
    option proto 'udp'
    option port '1194'
    option tls_server '1'
    option ca '/etc/openvpn/ca.crt'
    option cert '/etc/openvpn/server.crt'
    option key '/etc/openvpn/server.key'
    option dh '/etc/openvpn/dh.pem'
CFG

# Firewall
echo "Configurando firewall..."
uci add firewall rule
uci set firewall.@rule[-1].name='OpenVPN'
uci set firewall.@rule[-1].src='wan'
uci set firewall.@rule[-1].proto='udp'
uci set firewall.@rule[-1].dest_port="1194"
uci set firewall.@rule[-1].target='ACCEPT'
uci commit firewall
/etc/init.d/firewall reload

# Archivos .ovpn
echo "Generando archivos cliente..."
for i in 1 2 3 4; do
    cat > /etc/openvpn/client$i.ovpn <<OVPN
client
dev tap
proto udp
remote $DDNS_SERVER 1194
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
    echo "✅ client$i.ovpn"
done

# Configurar red MANUALMENTE (sin network restart)
echo "Configurando red manualmente..."
ifconfig tap0 up
brctl addif br-lan tap0

# Iniciar OpenVPN
echo "Iniciando OpenVPN..."
/etc/init.d/openvpn enable
/etc/init.d/openvpn start

# Verificación
sleep 3
echo "🔍 Verificación final:"
pgrep openvpn && echo "✅ OpenVPN: ACTIVO" || echo "❌ OpenVPN: INACTIVO"
ifconfig tap0 >/dev/null 2>&1 && echo "✅ tap0: ACTIVA" || echo "❌ tap0: INACTIVA"

echo ""
echo "🎉 ¡CONFIGURACIÓN COMPLETADA!"
echo "📍 Servidor: $DDNS_SERVER:1194"
echo "📍 Clientes: /tmp/client1.ovpn ... client4.ovpn"
echo ""
echo "Reiniciar? (s/n): "
read respuesta
[ "$respuesta" = "s" ] && reboot || echo "OK, reinicia luego con: reboot"
