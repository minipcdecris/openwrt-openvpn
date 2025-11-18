#!/bin/sh

# Función para verificar si el comando se ejecutó correctamente
check_status() {
    if [ $? -ne 0 ]; then
        echo -e "\033[31m- Ha ocurrido un error\033[0m"
        exit 1
    fi
}

# Mostrar información
echo -e "\033[36m=== CONFIGURACIÓN CLIENTE OPENVPN (CRIS) ===\033[0m"

# Pedir el DDNS del servidor
echo -e "\033[33m- Introduce el DDNS o IP de tu servidor OpenVPN:\033[0m"
echo -e "\033[33m- Ejemplo: campeon19.duckdns.org\033[0m"
read -p "DDNS o IP del servidor: " DDNS_SERVER

if [ -z "$DDNS_SERVER" ]; then
    echo -e "\033[31m- Error: Debes introducir un DDNS o IP\033[0m"
    exit 1
fi

# Pedir el puerto (opcional, por defecto 1194)
echo -e "\033[33m- Introduce el puerto del servidor (Enter para 1194):\033[0m"
read -p "Puerto: " VPN_PORT
VPN_PORT=${VPN_PORT:-1194}

echo -e "\033[32m- Configurando conexión a: $DDNS_SERVER:$VPN_PORT\033[0m"

# Actualizar la lista de paquetes
echo "- Actualizando lista de paquetes..."
opkg update
check_status

# Instalar OpenVPN y herramientas
echo "- Instalando OpenVPN..."
opkg install openvpn-openssl luci-app-openvpn
check_status

# Preguntar por el archivo .ovpn
echo -e "\n\033[33m=== CONFIGURACIÓN ARCHIVO .ovpn ===\033[0m"
echo -e "\033[33m- Necesitas el archivo .ovpn correspondiente a este cliente\033[0m"
echo -e "\033[33m- (client1.ovpn, client2.ovpn, client3.ovpn o client4.ovpn)\033[0m"
echo -e "\033[33m- Pega el contenido completo a continuación:\033[0m"
echo -e "\033[33m- (Termina con Ctrl+D en una línea vacía)\033[0m"

# Crear archivo temporal para el contenido .ovpn
cat > /tmp/client_config.ovpn << 'EOF'
# Reemplaza esta línea con tu contenido .ovpn
# Pero mantén la línea 'remote' dinámica abajo
EOF

# Leer el contenido .ovpn pegado por el usuario
echo "- Pegando contenido .ovpn (Ctrl+D cuando termines):"
USER_OVPN_CONTENT=$(cat)

if [ -z "$USER_OVPN_CONTENT" ]; then
    echo -e "\033[31m- Error: No se recibió contenido .ovpn\033[0m"
    exit 1
fi

# Crear el archivo .ovpn final con el remote correcto
echo "- Creando archivo de configuración final..."
cat > /etc/openvpn/client.ovpn << EOF
# Configuración OpenVPN Cliente
# Servidor: $DDNS_SERVER:$VPN_PORT
# Generado automáticamente

$USER_OVPN_CONTENT

# Aseguramos que el remote sea correcto
remote $DDNS_SERVER $VPN_PORT
EOF

echo -e "\033[32m- Archivo /etc/openvpn/client.ovpn creado\033[0m"

# Configurar OpenVPN como cliente
echo "- Configurando OpenVPN cliente..."
cat > /etc/config/openvpn << 'EOF'
config openvpn 'VPN_Client'
    option enabled '1'
    option config '/etc/openvpn/client.ovpn'
EOF
check_status

# Configurar la interfaz de red para el bridge
echo "- Configurando red y DHCP..."

# Añadir bridge br-vpn y interfaz vpn
cat >> /etc/config/network << 'EOF'

config device
    option type 'bridge'
    option name 'br-vpn'
    list ports 'tap0'
    option ipv6 '0'
    option igmp_snooping '1'

config interface 'vpn'
    option proto 'none'
    option device 'br-vpn'
EOF
check_status

# Configurar DHCP para la interfaz LAN (br-lan)
echo "- Configurando DHCP en br-lan..."

# Verificar si ya existe configuración DHCP para lan
if ! grep -q "config dhcp 'lan'" /etc/config/dhcp; then
    cat >> /etc/config/dhcp << 'EOF'

config dhcp 'lan'
    option interface 'lan'
    option start '100'
    option limit '150'
    option leasetime '12h'
    option dhcpv4 'server'
    option dhcpv6 'server'
    option ra 'server'
EOF
else
    echo "- DHCP para LAN ya configurado"
fi

# Asegurar que br-lan tiene igmp_snooping
sed -i "/option name 'br-lan'/a \    option igmp_snooping '1'" /etc/config/network
check_status

# Habilitar y iniciar servicios
echo "- Iniciando servicios..."
/etc/init.d/openvpn enable
/etc/init.d/openvpn start
check_status

/etc/init.d/network restart
check_status

/etc/init.d/dnsmasq enable
/etc/init.d/dnsmasq restart
check_status

# Mostrar resumen
echo -e "\n\033[32m=== CONFIGURACIÓN COMPLETADA ===\033[0m"
echo -e "\033[32m- OpenVPN cliente instalado\033[0m"
echo -e "\033[32m- Servidor: $DDNS_SERVER:$VPN_PORT\033[0m"
echo -e "\033[32m- DHCP configurado en interfaz LAN\033[0m"
echo -e "\033[32m- Bridge br-vpn creado para VPN\033[0m"

echo -e "\n\033[33m=== INSTRUCCIONES ===\033[0m"
echo -e "\033[33m- Los dispositivos conectados a este router:\033[0m"
echo -e "\033[33m  • Recibirán IP por DHCP\033[0m"
echo -e "\033[33m  • Estarán en la red del servidor VPN\033[0m"
echo -e "\033[33m  • Tendrán acceso a todos los dispositivos locales del servidor\033[0m"

# Verificar conexión
echo "- Verificando conexión VPN..."
sleep 5
if ifconfig | grep -q "tap0"; then
    echo -e "\033[32m- Conexión VPN establecida correctamente ✓\033[0m"
else
    echo -e "\033[33m- La interfaz VPN aún no está activa\033[0m"
    echo -e "\033[33m- Puede tardar unos segundos en conectarse\033[0m"
fi

echo -e "\n\033[32m- Router cliente configurado correctamente ✓\033[0m"

# Preguntar por reinicio
echo -e "\n- ¿Reiniciar router? (s/n): "
read -r response
if [ "$response" = "s" ] || [ "$response" = "S" ]; then
    echo "- Reiniciando en 15 segundos..."
    sleep 15
    reboot
else
    echo "- Reinicia manualmente más tarde con: reboot"
fi
