#!/bin/sh

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Mostrar información
echo -e "${CYAN}=== CONFIGURACIÓN CLIENTE OPENVPN (MISMA RED SERVIDOR) ===${NC}"
echo -e "${CYAN}=== Los dispositivos estarán en MISMA red 192.168.1.x ===${NC}"

# Pedir el DDNS del servidor
echo -e "${YELLOW}- Introduce el DDNS o IP de tu servidor OpenVPN:${NC}"
echo -e "${YELLOW}- Ejemplo: campeon19.duckdns.org${NC}"
read -p "DDNS o IP del servidor: " DDNS_SERVER

if [ -z "$DDNS_SERVER" ]; then
    echo -e "${RED}- Error: Debes introducir un DDNS o IP${NC}"
    exit 1
fi

# Pedir el puerto (opcional, por defecto 1194)
echo -e "${YELLOW}- Introduce el puerto del servidor (Enter para 1194):${NC}"
read -p "Puerto: " VPN_PORT
VPN_PORT=${VPN_PORT:-1194}

echo -e "${GREEN}- Configurando conexión a: $DDNS_SERVER:$VPN_PORT${NC}"

# Actualizar la lista de paquetes
echo "- Actualizando lista de paquetes..."
opkg update

# Instalar OpenVPN
echo "- Instalando OpenVPN..."
opkg install openvpn-openssl

# Preguntar por el archivo .ovpn
echo -e "\n${YELLOW}=== CONFIGURACIÓN ARCHIVO .ovpn ===${NC}"
echo -e "${YELLOW}- Pega el contenido completo del archivo .ovpn:${NC}"
echo -e "${YELLOW}- (Termina con Ctrl+D en una línea vacía)${NC}"

# Leer el contenido .ovpn
echo "- Pegando contenido .ovpn (Ctrl+D cuando termines):"
USER_OVPN_CONTENT=$(cat)

if [ -z "$USER_OVPN_CONTENT" ]; then
    echo -e "${RED}- Error: No se recibió contenido .ovpn${NC}"
    exit 1
fi

# Crear el archivo .ovpn
echo "- Creando archivo de configuración OpenVPN..."
cat > /etc/openvpn/client.ovpn << EOF
# Configuración OpenVPN Cliente
# Servidor: $DDNS_SERVER:$VPN_PORT

$USER_OVPN_CONTENT

remote $DDNS_SERVER $VPN_PORT
persist-key
persist-tun
verb 3
mute 20

# Script que se ejecuta al conectar
script-security 2
up /etc/openvpn/up.sh
EOF

echo -e "${GREEN}- Archivo /etc/openvpn/client.ovpn creado${NC}"

# Crear script que se ejecuta cuando OpenVPN se conecta
echo "- Creando script de conexión..."
cat > /etc/openvpn/up.sh << 'EOF'
#!/bin/sh
# Script que se ejecuta cuando OpenVPN conecta

echo "=== OpenVPN Conectado ==="
echo "Configurando bridge..."

# Esperar a que tap0 esté lista
sleep 5

# Agregar tap0 al bridge br-lan
brctl addif br-lan tap0 2>/dev/null

# Configurar IP en la red del servidor
ifconfig br-lan 192.168.1.200 netmask 255.255.255.0 2>/dev/null

# Agregar rutas
route add default gw 192.168.1.1 2>/dev/null
route add -net 192.168.1.0 netmask 255.255.255.0 dev br-lan 2>/dev/null

echo "Bridge configurado:"
echo "- br-lan IP: 192.168.1.200"
echo "- tap0 agregada al bridge"
echo "- Rutas configuradas"
EOF

chmod +x /etc/openvpn/up.sh

# Configuración de red MUY SIMPLE
echo "- Configurando red básica..."

# Primero hacer backup
cp /etc/config/network /etc/config/network.backup.vpn

# Configuración mínima de red
cat > /etc/config/network << 'EOF'
config interface 'loopback'
    option ifname 'lo'
    option proto 'static'
    option ipaddr '127.0.0.1'
    option netmask '255.0.0.0'

config device 'br_lan_dev'
    option type 'bridge'
    option name 'br-lan'
    list ports 'eth1'

config interface 'lan'
    option device 'br-lan'
    option proto 'static'
    option ipaddr '192.168.1.200'
    option netmask '255.255.255.0'
    option ipv6 '0'

config interface 'wan'
    option ifname 'eth0'
    option proto 'dhcp'
    option ipv6 '0'
EOF

echo -e "${GREEN}- Configuración de red aplicada${NC}"

# Desactivar DHCP local de forma segura
echo "- Desactivando servicios locales..."
/etc/init.d/dnsmasq stop 2>/dev/null
/etc/init.d/dnsmasq disable 2>/dev/null

# Solo UNA regla de firewall básica
echo "- Configurando regla firewall básica..."
uci delete firewall.Allow_OpenVPN 2>/dev/null
uci add firewall rule
uci set firewall.@rule[-1].name='Allow-OpenVPN'
uci set firewall.@rule[-1].src='wan'
uci set firewall.@rule[-1].proto='udp'
uci set firewall.@rule[-1].dest_port="$VPN_PORT"
uci set firewall.@rule[-1].target='ACCEPT'
uci commit firewall 2>/dev/null

echo -e "${GREEN}- Firewall configurado${NC}"

# Iniciar OpenVPN
echo "- Iniciando OpenVPN..."
/etc/init.d/openvpn enable
/etc/init.d/openvpn start

# Reiniciar red
echo "- Reiniciando red..."
/etc/init.d/network restart

sleep 10

echo -e "\n${GREEN}=== CONFIGURACIÓN COMPLETADA ===${NC}"
echo -e "${GREEN}- OpenVPN cliente instalado${NC}"
echo -e "${GREEN}- Servidor: $DDNS_SERVER:$VPN_PORT${NC}"

echo -e "\n${YELLOW}=== VERIFICACIÓN ===${NC}"

# Verificar OpenVPN
if pgrep openvpn >/dev/null; then
    echo -e "${GREEN}- OpenVPN ejecutándose ✓${NC}"
else
    echo -e "${YELLOW}- OpenVPN no está ejecutándose${NC}"
fi

# Verificar interfaces
echo "- Interfaces de red:"
ifconfig | grep -E "(br-lan|tap0|eth1)" | while read line; do
    echo "  $line"
done

# Verificar conexión después de 30 segundos
echo -e "\n${YELLOW}- Esperando conexión VPN (30 segundos)...${NC}"
sleep 30

echo -e "\n${CYAN}=== ESTADO FINAL ===${NC}"

# Verificar si tap0 está en el bridge
if brctl show br-lan 2>/dev/null | grep -q tap0; then
    echo -e "${GREEN}- VPN integrada en bridge LAN ✓${NC}"
else
    echo -e "${YELLOW}- VPN no integrada en bridge${NC}"
    echo -e "${YELLOW}- Ejecuta manualmente: brctl addif br-lan tap0${NC}"
fi

# Verificar IP
CURRENT_IP=$(ifconfig br-lan 2>/dev/null | grep 'inet addr' | cut -d: -f2 | awk '{print $1}')
if [ -n "$CURRENT_IP" ]; then
    echo -e "${GREEN}- IP actual: $CURRENT_IP${NC}"
else
    echo -e "${YELLOW}- No se detectó IP en br-lan${NC}"
fi

echo -e "\n${GREEN}=== INSTRUCCIONES ===${NC}"
echo -e "${GREEN}1. Conecta el decodificador al router cliente${NC}"
echo -e "${GREEN}2. El decodificador debería recibir IP 192.168.1.x${NC}"
echo -e "${GREEN}3. Estará en la misma red que el servidor${NC}"

echo -e "\n${YELLOW}=== COMANDOS ÚTILES ===${NC}"
echo -e "${YELLOW}- Ver logs: logread | grep openvpn${NC}"
echo -e "${YELLOW}- Ver bridge: brctl show br-lan${NC}"
echo -e "${YELLOW}- Ver rutas: route -n${NC}"
echo -e "${YELLOW}- Reiniciar VPN: /etc/init.d/openvpn restart${NC}"

echo -e "\n${GREEN}¡Listo! El router cliente está configurado.${NC}"
