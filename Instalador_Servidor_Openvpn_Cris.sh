#!/bin/sh

# Configuración inicial
echo "=== CONFIGURACIÓN SERVIDOR OPENVPN ==="

# Pedir DDNS o IP
read -p "Introduce tu DDNS o IP pública: " DDNS_SERVER
read -p "Puerto OpenVPN (1194): " VPN_PORT
VPN_PORT=${VPN_PORT:-1194}
read -p "Número de clientes (4): " NUM_CLIENTES
NUM_CLIENTES=${NUM_CLIENTES:-4}

echo "Configurando: $DDNS_SERVER:$VPN_PORT"
echo "Creando $NUM_CLIENTES clientes"

# Instalación
echo "Instalando OpenVPN..."
opkg update
opkg install openvpn-easy-rsa openvpn-openssl luci-app-openvpn

# Generar certificados
cd /etc/easy-rsa
sed -i 's/#set_var EASYRSA_CA_EXPIRE.*/set_var EASYRSA_CA_EXPIRE      99999/' vars
sed -i 's/#set_var EASYRSA_CERT_EXPIRE.*/set_var EASYRSA_CERT_EXPIRE    99999/' vars

echo -e "yes\nyes" | easyrsa init-pki
echo -e "yes\nserver" | easyrsa build-ca nopass
echo -e "yes" | easyrsa build-server-full server nopass

for i in $(seq 1 $NUM_CLIENTES); do
    echo "Generando client$i..."
    echo -e "yes" | easyrsa build-client-full client$i nopass
done

easyrsa gen-dh

# Copiar archivos
cp /etc/easy-rsa/pki/ca.crt /etc/openvpn/
cp /etc/easy-rsa/pki/private/server.key /etc/openvpn/
cp /etc/easy-rsa/pki/issued/server.crt /etc/openvpn/
cp /etc/easy-rsa/pki/dh.pem /etc/openvpn/

# Configurar OpenVPN
cat > /etc/config/openvpn <<CFG
config openvpn 'VPN_Tap_Server'
    option enabled '1'
    option mode 'server'
    option dev 'tap0'
    option proto 'udp'
    option port '$VPN_PORT'
    option float '1'
    option persist_key '1'
    option persist_tun '1'
    option keepalive '10 60'
    option cipher 'AES-256-GCM'
    option reneg_sec '0'
    option verb '3'
    option client_to_client '1'
    option remote_cert_tls 'client'
    option tls_server '1'
    option ca '/etc/openvpn/ca.crt'
    option cert '/etc/openvpn/server.crt'
    option key '/etc/openvpn/server.key'
    option dh '/etc/openvpn/dh.pem'
CFG

# Firewall
uci add firewall rule
uci set firewall.@rule[-1].name='Allow-OpenVPN'
uci set firewall.@rule[-1].src='wan'
uci set firewall.@rule[-1].proto='udp'
uci set firewall.@rule[-1].dest_port="$VPN_PORT"
uci set firewall.@rule[-1].target='ACCEPT'
uci commit firewall
/etc/init.d/firewall restart

# Generar archivos .ovpn
for i in $(seq 1 $NUM_CLIENTES); do
    echo "Creando client$i.ovpn..."
    cat > /etc/openvpn/client$i.ovpn <<OVPN
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
    
    # Copia a /tmp
    cp /etc/openvpn/client$i.ovpn /tmp/client$i.ovpn
    echo "Copia en /tmp/client$i.ovpn"
done

# Configurar red
uci set network.lan.igmp_snooping='1'
uci add_list network.lan.ports='tap0'
uci commit network

# Iniciar servicios
/etc/init.d/network restart
/etc/init.d/openvpn enable
/etc/init.d/openvpn start

echo "=== CONFIGURACIÓN COMPLETADA ==="
echo "Servidor: $DDNS_SERVER:$VPN_PORT"
echo "Clientes: $NUM_CLIENTES"
echo "Archivos en /tmp/: client1.ovpn, client2.ovpn, etc."

echo "Reiniciando en 10 segundos..."
sleep 10
reboot
