cat > /tmp/Instalador_Servidor_Openvpn_Cris.sh << 'EOF'
#!/bin/sh

# Función para verificar si el comando se ejecutó correctamente
check_status() {
    if [ $? -ne 0 ]; then
        echo -e "\033[31m- Ha ocurrido un error\033[0m"
        exit 1
    fi
}

# Configuración inicial
echo -e "\033[36m=== CONFIGURACIÓN SERVIDOR OPENVPN ===\033[0m"

# Pedir DDNS o IP
echo -e "\033[33m- Introduce tu DDNS o IP pública:\033[0m"
read -p "DDNS o IP: " DDNS_SERVER

if [ -z "$DDNS_SERVER" ]; then
    echo -e "\033[31m- Error: Debes introducir un DDNS o IP\033[0m"
    exit 1
fi

# Pedir puerto
echo -e "\033[33m- Introduce el puerto OpenVPN (Enter para 1194):\033[0m"
read -p "Puerto: " VPN_PORT
VPN_PORT=${VPN_PORT:-1194}

# Pedir número de clientes
echo -e "\033[33m- Número de clientes a crear (Enter para 4):\033[0m"
read -p "Clientes: " NUM_CLIENTES
NUM_CLIENTES=${NUM_CLIENTES:-4}

echo -e "\033[32m- Configurando servidor: $DDNS_SERVER:$VPN_PORT\033[0m"
echo -e "\033[32m- Creando $NUM_CLIENTES clientes\033[0m"

# Instalación de OpenVPN
echo "- Instalando OpenVPN y herramientas..."
opkg update
opkg install openvpn-easy-rsa openvpn-openssl luci-app-openvpn nano
check_status

echo -e "\033[32m- Instalación completada.\033[0m"

# Generación de certificados
cd /etc/easy-rsa
check_status

# Configurar easy-rsa
sed -i 's/#set_var EASYRSA_CA_EXPIRE.*/set_var EASYRSA_CA_EXPIRE      99999/' vars
sed -i 's/#set_var EASYRSA_CERT_EXPIRE.*/set_var EASYRSA_CERT_EXPIRE    99999/' vars
check_status

echo -e "yes\nyes" | easyrsa init-pki
check_status

# Crear CA y certificados
echo -e "yes\nserver" | easyrsa build-ca nopass
check_status

echo -e "yes" | easyrsa build-server-full server nopass
check_status

# Crear certificados clientes
echo -e "\033[32m- Generando certificados para $NUM_CLIENTES clientes...\033[0m"
for i in $(seq 1 $NUM_CLIENTES); do
    echo "- Generando certificado para client$i..."
    echo -e "yes" | easyrsa build-client-full client$i nopass
    check_status
    echo -e "\033[32m- Certificado para client$i generado con éxito.\033[0m"
done

# Generar DH
easyrsa gen-dh
check_status

# Copiar archivos
cp /etc/easy-rsa/pki/ca.crt /etc/openvpn/
cp /etc/easy-rsa/pki/private/server.key /etc/openvpn/
cp /etc/easy-rsa/pki/issued/server.crt /etc/openvpn/
cp /etc/easy-rsa/pki/dh.pem /etc/openvpn/
check_status

# Configuración OpenVPN servidor
cat > /etc/config/openvpn <<EOF
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
    option verb '5'
    option client_to_client '1'
    option remote_cert_tls 'client'
    option tls_server '1'
    option ca '/etc/openvpn/ca.crt'
    option cert '/etc/openvpn/server.crt'
    option key '/etc/openvpn/server.key'
    option dh '/etc/openvpn/dh.pem'
EOF
check_status

# Configurar firewall
echo "- Configurando firewall..."
uci add firewall rule
uci set firewall.@rule[-1].name='Allow-OpenVPN'
uci set firewall.@rule[-1].src='wan'
uci set firewall.@rule[-1].proto='udp'
uci set firewall.@rule[-1].dest_port="$VPN_PORT"
uci set firewall.@rule[-1].target='ACCEPT'
uci commit firewall
/etc/init.d/firewall restart
check_status
echo -e "\033[32m- Firewall configurado para puerto $VPN_PORT\033[0m"

# Generar archivos .ovpn
for i in $(seq 1 $NUM_CLIENTES); do
    echo "- Generando client$i.ovpn..."
    
    cat > /etc/openvpn/client$i.ovpn <<EOF
client
dev tap
proto udp
remote $DDNS_SERVER $VPN_PORT
resolv-retry infinite
nobind
float
data-ciphers AES-256-GCM
keepalive 15 60
remote-cert-tls server
route-nopull
route-noexec
mute-replay-warnings
<ca>
$(cat /etc/openvpn/ca.crt)
</ca>
<cert>
$(sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' /etc/easy-rsa/pki/issued/client$i.crt)
</cert>
<key>
$(cat /etc/easy-rsa/pki/private/client$i.key)
</key>
EOF
    check_status
    
    # Crear copia en /tmp/
    cp /etc/openvpn/client$i.ovpn /tmp/client$i.ovpn
    echo -e "\033[32m- Copia creada en: /tmp/client$i.ovpn\033[0m"
    
    echo -e "\033[32m- ✓ client$i.ovpn completado\033[0m"
done

# Crear bundle
tar -czf /etc/openvpn/clientes_openvpn.tar.gz -C /etc/openvpn/ *.ovpn
check_status
echo -e "\033[32m- Bundle creado: /etc/openvpn/clientes_openvpn.tar.gz\033[0m"

# Configurar red
sed -i "/option name 'br-lan'/a \    option igmp_snooping '1'" /etc/config/network
sed -i "/option igmp_snooping '1'/a \    list ports 'tap0'" /etc/config/network
check_status

# Reiniciar servicios
/etc/init.d/network restart
/etc/init.d/openvpn enable
/etc/init.d/openvpn start
check_status

# Verificación
echo "- Verificando servicios..."
sleep 5

if pgrep openvpn >/dev/null; then
    echo -e "\033[32m- OpenVPN funcionando ✓\033[0m"
else
    echo -e "\033[31m- OpenVPN no está corriendo\033[0m"
fi

if ifconfig tap0 >/dev/null 2>&1; then
    echo -e "\033[32m- Interfaz tap0 activa ✓\033[0m"
else
    echo -e "\033[31m- Interfaz tap0 no activa\033[0m"
fi

echo -e "\n\033[32m=== CONFIGURACIÓN COMPLETADA ===\033[0m"
echo -e "\033[32m- Servidor: $DDNS_SERVER:$VPN_PORT\033[0m"
echo -e "\033[32m- Clientes creados: $NUM_CLIENTES\033[0m"
echo -e "\033[32m- Archivos en /tmp/: client1.ovpn, client2.ovpn, etc.\033[0m"
echo -e "\033[32m- Bundle: /etc/openvpn/clientes_openvpn.tar.gz\033[0m"

echo -e "\n\033[33m- Reiniciando en 10 segundos...\033[0m"
sleep 10
reboot
EOF

chmod +x /tmp/Instalador_Servidor_Openvpn_Cris.sh
/tmp/Instalador_Servidor_Openvpn_Cris.sh
