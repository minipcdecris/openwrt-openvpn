#!/bin/sh

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Mostrar información
echo -e "${CYAN}=== CONFIGURACIÓN CLIENTE OPENVPN (SIN REINICIOS) ===${NC}"

# Pedir el DDNS del servidor
echo -e "${YELLOW}- Introduce el DDNS o IP de tu servidor OpenVPN:${NC}"
read -p "DDNS o IP del servidor: " DDNS_SERVER

if [ -z "$DDNS_SERVER" ]; then
    echo -e "${RED}- Error: Debes introducir un DDNS o IP${NC}"
    exit 1
fi

# Pedir el puerto
read -p "Puerto (Enter para 1194): " VPN_PORT
VPN_PORT=${VPN_PORT:-1194}

echo -e "${GREEN}- Configurando conexión a: $DDNS_SERVER:$VPN_PORT${NC}"

# Instalar OpenVPN sin reinicios
echo "- Instalando OpenVPN..."
opkg update
opkg install openvpn-openssl

# Preguntar por el archivo .ovpn
echo -e "\n${YELLOW}- Pega el contenido del archivo .ovpn (Ctrl+D cuando termines):${NC}"
USER_OVPN_CONTENT=$(cat)

if [ -z "$USER_OVPN_CONTENT" ]; then
    echo -e "${RED}- Error: No se recibió contenido .ovpn${NC}"
    exit 1
fi

# Crear archivo .ovpn
echo "- Creando configuración OpenVPN..."
cat > /etc/openvpn/client.ovpn << EOF
# Configuración OpenVPN Cliente
# Servidor: $DDNS_SERVER:$VPN_PORT

$USER_OVPN_CONTENT

remote $DDNS_SERVER $VPN_PORT
resolv-retry infinite
nobind
persist-key
persist-tun
verb 3
mute 20

# Script que configura el bridge automáticamente
script-security 2
up /etc/openvpn/up.sh
EOF

# Crear script de conexión MEJORADO
echo "- Creando script de configuración automática..."
cat > /etc/openvpn/up.sh << 'EOF'
#!/bin/sh
echo "=== OpenVPN Conectado - Configurando Bridge ==="

# Esperar a que la interfaz esté lista
sleep 3

# Crear bridge si no existe
brctl show br-lan >/dev/null 2>&1 || {
    echo "- Creando bridge br-lan..."
    brctl addbr br-lan
}

# Agregar interfaces al bridge
echo "- Agregando interfaces al bridge..."
brctl addif br-lan eth1 2>/dev/null
brctl addif br-lan tap0 2>/dev/null

# Configurar IP en la red del servidor
echo "- Configurando IP 192.168.1.200..."
ifconfig br-lan 192.168.1.200 netmask 255.255.255.0 up

# Configurar gateway
echo "- Configurando gateway 192.168.1.1..."
route add default gw 192.168.1.1 2>/dev/null

# Desactivar DHCP local
echo "- Desactivando servicios locales..."
/etc/init.d/dnsmasq stop 2>/dev/null
/etc/init.d/odhcpd stop 2>/dev/null

echo "- Bridge configurado correctamente"
echo "- IP: 192.168.1.200"
echo "- Gateway: 192.168.1.1"
echo "- Dispositivos recibirán IP del servidor"
EOF

chmod +x /etc/openvpn/up.sh

# Configurar OpenVPN sin reiniciar red
echo "- Configurando servicio OpenVPN..."
cat > /etc/config/openvpn << 'EOF'
config openvpn 'client'
    option enabled '1'
    option config '/etc/openvpn/client.ovpn'
EOF

# Configuración de red MÍNIMA (solo para persistencia)
echo "- Creando configuración de red persistente..."
cat > /etc/config/network << 'EOF'
config interface 'loopback'
    option ifname 'lo'
    option proto 'static'
    option ipaddr '127.0.0.1'
    option netmask '255.0.0.0'

config interface 'lan'
    option ifname 'br-lan'
    option proto 'static'
    option ipaddr '192.168.1.200'
    option netmask '255.255.255.0'
    option gateway '192.168.1.1'
    option dns '192.168.1.1'
    option ipv6 '0'

config interface 'wan'
    option ifname 'eth0'
    option proto 'dhcp'
    option ipv6 '0'
EOF

# Solo UNA regla de firewall simple
echo "- Configurando firewall básico..."
uci delete firewall.allow_openvpn 2>/dev/null
uci add firewall rule
uci set firewall.@rule[-1].name='allow_openvpn'
uci set firewall.@rule[-1].src='wan'
uci set firewall.@rule[-1].proto='udp'
uci set firewall.@rule[-1].dest_port="$VPN_PORT"
uci set firewall.@rule[-1].target='ACCEPT'
uci commit firewall

# Iniciar OpenVPN SIN REINICIAR RED
echo "- Iniciando OpenVPN..."
/etc/init.d/openvpn enable
/etc/init.d/openvpn start

echo -e "${GREEN}- OpenVPN iniciado${NC}"
echo -e "${YELLOW}- Esperando conexión...${NC}"

# Esperar y verificar
sleep 10

echo -e "\n${CYAN}=== VERIFICANDO CONEXIÓN ===${NC}"

# Verificar OpenVPN
if pgrep openvpn >/dev/null; then
    echo -e "${GREEN}- OpenVPN ejecutándose ✓${NC}"
else
    echo -e "${RED}- OpenVPN no está ejecutándose${NC}"
fi

# Verificar interfaces después de 20 segundos
echo "- Esperando configuración automática (20 segundos)..."
sleep 20

echo -e "\n${CYAN}=== ESTADO ACTUAL ===${NC}"

# Verificar bridge
if brctl show br-lan 2>/dev/null; then
    echo -e "${GREEN}- Bridge br-lan existe ✓${NC}"
    brctl show br-lan
else
    echo -e "${YELLOW}- Bridge br-lan no existe${NC}"
fi

# Verificar interfaces en el bridge
if brctl show br-lan 2>/dev/null | grep -q tap0; then
    echo -e "${GREEN}- tap0 en bridge ✓${NC}"
else
    echo -e "${YELLOW}- tap0 no está en el bridge${NC}"
fi

# Verificar IP
CURRENT_IP=$(ifconfig br-lan 2>/dev/null | grep 'inet addr' | cut -d: -f2 | awk '{print $1}')
if [ -n "$CURRENT_IP" ]; then
    echo -e "${GREEN}- IP br-lan: $CURRENT_IP ✓${NC}"
else
    echo -e "${YELLOW}- No hay IP en br-lan${NC}"
fi

# Probar conectividad
echo -e "\n${CYAN}=== PRUEBA DE CONECTIVIDAD ===${NC}"
if ping -c 2 -W 1 192.168.1.1 >/dev/null 2>&1; then
    echo -e "${GREEN}- Puede alcanzar 192.168.1.1 ✓${NC}"
else
    echo -e "${YELLOW}- No puede alcanzar 192.168.1.1${NC}"
fi

if ping -c 2 -W 1 192.168.1.200 >/dev/null 2>&1; then
    echo -e "${GREEN}- IP local responde ✓${NC}"
else
    echo -e "${YELLOW}- IP local no responde${NC}"
fi

echo -e "\n${GREEN}=== CONFIGURACIÓN COMPLETADA ===${NC}"
echo -e "${GREEN}- El script ha terminado${NC}"
echo -e "${GREEN}- OpenVPN se conectará automáticamente${NC}"
echo -e "${GREEN}- El bridge se configurará cuando se establezca la VPN${NC}"

echo -e "\n${YELLOW}=== INSTRUCCIONES ===${NC}"
echo -e "${YELLOW}1. Conecta dispositivos al router cliente${NC}"
echo -e "${YELLOW}2. Deberían recibir IP 192.168.1.x del servidor${NC}"
echo -e "${YELLOW}3. Estarán en la misma red que el servidor${NC}"

echo -e "\n${YELLOW}=== SI HAY PROBLEMAS ===${NC}"
echo -e "${YELLOW}- Ver logs: logread | grep openvpn${NC}"
echo -e "${YELLOW}- Reiniciar VPN: /etc/init.d/openvpn restart${NC}"
echo -e "${YELLOW}- Ver bridge: brctl show br-lan${NC}"
echo -e "${YELLOW}- Agregar tap0 manual: brctl addif br-lan tap0${NC}"

echo -e "\n${GREEN}¡Listo! No se requiere reinicio.${NC}"
