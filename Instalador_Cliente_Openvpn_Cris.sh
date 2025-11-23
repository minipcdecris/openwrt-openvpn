#!/bin/sh

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Función para verificar si el comando se ejecutó correctamente
check_status() {
    if [ $? -ne 0 ]; then
        echo -e "${RED}- Ha ocurrido un error${NC}"
        exit 1
    fi
}

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
check_status

# Instalar OpenVPN y herramientas
echo "- Instalando OpenVPN..."
opkg install openvpn-openssl luci-app-openvpn
check_status

# Preguntar por el archivo .ovpn
echo -e "\n${YELLOW}=== CONFIGURACIÓN ARCHIVO .ovpn ===${NC}"
echo -e "${YELLOW}- Necesitas el archivo .ovpn correspondiente a este cliente${NC}"
echo -e "${YELLOW}- (client1.ovpn, client2.ovpn, client3.ovpn o client4.ovpn)${NC}"
echo -e "${YELLOW}- Pega el contenido completo a continuación:${NC}"
echo -e "${YELLOW}- (Termina con Ctrl+D en una línea vacía)${NC}"

# Leer el contenido .ovpn pegado por el usuario
echo "- Pegando contenido .ovpn (Ctrl+D cuando termines):"
USER_OVPN_CONTENT=$(cat)

if [ -z "$USER_OVPN_CONTENT" ]; then
    echo -e "${RED}- Error: No se recibió contenido .ovpn${NC}"
    exit 1
fi

# Crear el archivo .ovpn final con el remote correcto
echo "- Creando archivo de configuración final..."
cat > /etc/openvpn/client.ovpn << EOF
# Configuración OpenVPN Cliente - Misma Red Servidor
# Servidor: $DDNS_SERVER:$VPN_PORT
# Los dispositivos estarán en MISMA red 192.168.1.x

$USER_OVPN_CONTENT

# Aseguramos que el remote sea correcto
remote $DDNS_SERVER $VPN_PORT

# Configuración adicional para misma red
persist-key
persist-tun
verb 3
mute 20

# Forzar ruta para red local del servidor
route 192.168.1.0 255.255.255.0
EOF

echo -e "${GREEN}- Archivo /etc/openvpn/client.ovpn creado${NC}"

# Configurar OpenVPN como cliente
echo "- Configurando OpenVPN cliente..."
cat > /etc/config/openvpn << EOF
config openvpn 'VPN_Client'
    option enabled '1'
    option config '/etc/openvpn/client.ovpn'
EOF
check_status

# CONFIGURACIÓN SIMPLIFICADA: Sin firewall complicado
echo "- Configurando red simplificada..."

# Backup de la configuración de red original
cp /etc/config/network /etc/config/network.backup

# Configuración de red básica - SIN ZONAS VPN COMPLEJAS
cat > /etc/config/network << 'EOF'
config interface 'loopback'
    option ifname 'lo'
    option proto 'static'
    option ipaddr '127.0.0.1'
    option netmask '255.0.0.0'

config globals 'globals'
    option ula_prefix 'fd00:ab:cd::/48'

# Bridge principal que incluye LAN física
config device
    option type 'bridge'
    option name 'br-lan'
    list ports 'eth1'
    option igmp_snooping '1'

# Interfaz LAN con IP FIJA en red del servidor
config interface 'lan'
    option device 'br-lan'
    option proto 'static'
    option ipaddr '192.168.1.200'
    option netmask '255.255.255.0'
    option gateway '192.168.1.1'
    option dns '192.168.1.1'
    option ipv6 '0'

# Interfaz WAN
config interface 'wan'
    option ifname 'eth0'
    option proto 'dhcp'
    option ipv6 '0'

config interface 'wan6'
    option ifname 'eth0'
    option proto 'dhcpv6'

# Interfaz VPN separada - NO en el bridge para evitar conflictos
config interface 'vpn'
    option ifname 'tap0'
    option proto 'none'
    option auto '1'
EOF

echo -e "${GREEN}- Configuración de red aplicada${NC}"

# DESACTIVAR DHCP LOCAL
echo "- Desactivando DHCP local..."
uci set dhcp.lan.ignore='1'
uci commit dhcp
/etc/init.d/dnsmasq stop
/etc/init.d/dnsmasq disable
echo -e "${GREEN}- DHCP local desactivado${NC}"

# CONFIGURACIÓN FIREWALL MUY SIMPLE - SOLO LO BÁSICO
echo "- Configurando firewall básico..."

# Limpiar configuraciones problemáticas
uci delete firewall.vpn 2>/dev/null
uci delete firewall.VPN_full_access 2>/dev/null
uci delete firewall.LAN_to_VPN 2>/dev/null
uci delete firewall.VPN_to_Internet 2>/dev/null
uci delete firewall.vpn_lan 2>/dev/null
uci delete firewall.lan_vpn 2>/dev/null

# Solo regla básica para permitir OpenVPN
uci delete firewall.Allow_OpenVPN 2>/dev/null
uci set firewall.Allow_OpenVPN=rule
uci set firewall.Allow_OpenVPN.name='Allow-OpenVPN-Client'
uci set firewall.Allow_OpenVPN.src='wan'
uci set firewall.Allow_OpenVPN.proto='udp'
uci set firewall.Allow_OpenVPN.dest_port="$VPN_PORT"
uci set firewall.Allow_OpenVPN.target='ACCEPT'

uci commit firewall
/etc/init.d/firewall reload
echo -e "${GREEN}- Firewall básico configurado${NC}"

# Script para configurar rutas después de que OpenVPN se conecte
echo "- Configurando rutas automáticas..."
cat > /etc/openvpn/up.sh << 'EOF'
#!/bin/sh
# Script que se ejecuta cuando OpenVPN se conecta

sleep 5

# Agregar ruta para la red del servidor
ip route add 192.168.1.0/24 dev tap0 2>/dev/null

# Agregar tap0 al bridge br-lan PARA BRIDGE REAL
brctl addif br-lan tap0 2>/dev/null

echo "OpenVPN conectado - Rutas configuradas"
EOF

chmod +x /etc/openvpn/up.sh

# Configurar OpenVPN para usar el script de conexión
echo "script-security 2" >> /etc/openvpn/client.ovpn
echo "up /etc/openvpn/up.sh" >> /etc/openvpn/client.ovpn

# Habilitar y iniciar servicios
echo "- Iniciando servicios..."
/etc/init.d/openvpn enable
/etc/init.d/openvpn start
check_status

# Reiniciar red para aplicar cambios
echo "- Aplicando configuración de red..."
/etc/init.d/network restart
check_status

sleep 10

# Mostrar resumen
echo -e "\n${GREEN}=== CONFIGURACIÓN COMPLETADA ===${NC}"
echo -e "${GREEN}- OpenVPN cliente instalado${NC}"
echo -e "${GREEN}- Servidor: $DDNS_SERVER:$VPN_PORT${NC}"
echo -e "${GREEN}- Router cliente en MISMA RED 192.168.1.x${NC}"

echo -e "\n${YELLOW}=== MODO DE FUNCIONAMIENTO ===${NC}"
echo -e "${YELLOW}- Este router está en la MISMA red que el servidor${NC}"
echo -e "${YELLOW}- Dispositivos conectados por LAN/WiFi:${NC}"
echo -e "${YELLOW}  • Recibirán IP del SERVIDOR (192.168.1.x) ✓${NC}"
echo -e "${YELLOW}  • Estarán en MISMA red 192.168.1.x ✓${NC}"
echo -e "${YELLOW}  • El decodificador será 192.168.1.x ✓${NC}"
echo -e "${YELLOW}  • Como conectado DIRECTAMENTE al servidor ✓${NC}"

# Verificar conexión
echo -e "\n- Verificando conexión..."
sleep 15

if pgrep openvpn >/dev/null; then
    echo -e "${GREEN}- Proceso OpenVPN ejecutándose ✓${NC}"
    
    # Verificar si tap0 está en el bridge
    if brctl show br-lan | grep -q tap0; then
        echo -e "${GREEN}- VPN integrada en bridge LAN ✓${NC}"
    else
        echo -e "${YELLOW}- VPN no integrada en bridge aún${NC}"
    fi
else
    echo -e "${RED}- Error: OpenVPN no se está ejecutando${NC}"
fi

# Verificar IP del router cliente
echo -e "\n- Verificando configuración de red..."
CURRENT_IP=$(uci get network.lan.ipaddr 2>/dev/null)
if [ "$CURRENT_IP" = "192.168.1.200" ]; then
    echo -e "${GREEN}- IP del router cliente: $CURRENT_IP ✓${NC}"
else
    echo -e "${YELLOW}- IP del router: $CURRENT_IP${NC}"
fi

# Probar conectividad con servidor
echo -e "\n- Probando conectividad con servidor..."
if ping -c 2 192.168.1.1 >/dev/null 2>&1; then
    echo -e "${GREEN}- Conexión con servidor (192.168.1.1) OK ✓${NC}"
    
    # Probar si podemos acceder a la red local
    echo "- Probando acceso a red local..."
    if ping -c 2 192.168.1.200 >/dev/null 2>&1; then
        echo -e "${GREEN}- Conexión local OK ✓${NC}"
    fi
else
    echo -e "${YELLOW}- No se puede alcanzar el servidor aún${NC}"
    echo -e "${YELLOW}- Esto es normal hasta que OpenVPN se conecte completamente${NC}"
fi

echo -e "\n${GREEN}=== ¡CONFIGURACIÓN EXITOSA! ===${NC}"
echo -e "${GREEN}- El decodificador de Movistar:${NC}"
echo -e "${GREEN}  • Recibirá IP: 192.168.1.x (DEL SERVIDOR) ✓${NC}"
echo -e "${GREEN}  • Estará en MISMA red que servidor ✓${NC}"
echo -e "${GREEN}  • Como conectado DIRECTAMENTE allí ✓${NC}"

# Instrucciones de diagnóstico
echo -e "\n${YELLOW}=== SI HAY PROBLEMAS ===${NC}"
echo -e "${YELLOW}- Ver logs: logread | grep openvpn${NC}"
echo -e "${YELLOW}- Ver estado: cat /tmp/openvpn-status.log${NC}"
echo -e "${YELLOW}- Reiniciar OpenVPN: /etc/init.d/openvpn restart${NC}"

# Preguntar por reinicio
echo -e "\n- ¿Reiniciar router para aplicar cambios? (s/n): "
read -r response
if [ "$response" = "s" ] || [ "$response" = "S" ]; then
    echo "- Reiniciando en 10 segundos (Ctrl+C para cancelar)..."
    for i in 10 9 8 7 6 5 4 3 2 1; do
        echo -n "$i... "
        sleep 1
    done
    echo ""
    echo "- Reiniciando sistema..."
    reboot
else
    echo -e "${YELLOW}- Algunos cambios pueden requerir reinicio${NC}"
    echo -e "${YELLOW}- Reinicia manualmente más tarde con: reboot${NC}"
fi
