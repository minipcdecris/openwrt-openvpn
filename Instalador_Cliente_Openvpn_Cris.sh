#!/bin/sh

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Función para verificar si el comando se ejecutó correctamente
check_status() {
    if [ $? -ne 0 ]; then
        echo -e "${RED}- Ha ocurrido un error en el paso anterior${NC}"
        exit 1
    fi
}

# Verificar que estamos en OpenWrt
if [ ! -f /etc/openwrt_release ]; then
    echo -e "${RED}- Error: Este script solo funciona en OpenWrt${NC}"
    exit 1
fi

echo -e "${YELLOW}- Iniciando configuración de OpenVPN Client...${NC}"

# Actualizar la lista de paquetes
echo -e "${YELLOW}- Actualizando lista de paquetes...${NC}"
opkg update
check_status
echo -e "${GREEN}- Lista de paquetes actualizada correctamente${NC}"

# Instalar OpenVPN, herramientas necesarias y nano
echo -e "${YELLOW}- Instalando paquetes necesarios...${NC}"
opkg install openvpn-easy-rsa openvpn-openssl luci-app-openvpn nano
check_status
echo -e "${GREEN}- Paquetes instalados correctamente${NC}"

# Función para crear el archivo client.ovpn sin esperar Enter después de Ctrl+D
create_client_ovpn() {
    echo -e "${YELLOW}- Creando archivo client.ovpn...${NC}"
    
    echo -e "${GREEN}=== INSTRUCCIONES ==="
    echo -e "Por favor, pegue el contenido completo de su archivo client.ovpn"
    echo -e "Cuando termine, presione Ctrl+D para guardar y continuar"
    echo -e "========================${NC}"
    echo ""
    
    # Crear el archivo base
    cat > /etc/openvpn/client.ovpn << 'EOF'
# === CONFIGURACIÓN CLIENTE OPENVPN ===
# Pegue debajo de esta línea el contenido de su client.ovpn

EOF
    
    # Permitir al usuario pegar el contenido sin esperar Enter
    echo -e "${YELLOW}Pegue ahora el contenido de client.ovpn (Ctrl+D cuando termine):${NC}"
    # Usar cat para leer la entrada y añadir al archivo
    cat >> /etc/openvpn/client.ovpn
    
    echo -e "${GREEN}- Archivo /etc/openvpn/client.ovpn creado correctamente${NC}"
    
    # Mostrar preview del archivo creado
    echo -e "${YELLOW}- Vista previa del archivo creado (primeras 10 líneas):${NC}"
    head -10 /etc/openvpn/client.ovpn
    echo -e "${YELLOW}...${NC}"
}

# Verificar si el archivo client.ovpn ya existe
if [ -f /etc/openvpn/client.ovpn ]; then
    echo -e "${YELLOW}- El archivo /etc/openvpn/client.ovpn ya existe${NC}"
    echo -e "${YELLOW}- Vista previa del archivo actual:${NC}"
    head -10 /etc/openvpn/client.ovpn
    echo ""
    
    echo -e "${YELLOW}¿Desea sobrescribirlo? (s/n)${NC}"
    # Leer sin esperar Enter
    read -r response
    case "$response" in
        [sS]|[sS][iI]|[yY]|[yY][eE][sS])
            create_client_ovpn
            ;;
        *)
            echo -e "${YELLOW}- Se mantiene el archivo existente${NC}"
            ;;
    esac
else
    create_client_ovpn
fi

# Configurar OpenVPN si no existe
if [ ! -f /etc/config/openvpn ]; then
    echo -e "${YELLOW}- Creando configuración de OpenVPN...${NC}"
    cat <<EOF > /etc/config/openvpn
config openvpn 'VPN_Tap_Client'
    option config '/etc/openvpn/client.ovpn'
    option enabled '1'
EOF
    check_status
    echo -e "${GREEN}- Configuración de OpenVPN creada${NC}"
else
    echo -e "${YELLOW}- La configuración de OpenVPN ya existe${NC}"
    
    # Verificar si ya existe la configuración del cliente VPN
    if ! uci show openvpn.VPN_Tap_Client > /dev/null 2>&1; then
        echo -e "${YELLOW}- Añadiendo configuración del cliente VPN...${NC}"
        uci set openvpn.VPN_Tap_Client=openvpn
        uci set openvpn.VPN_Tap_Client.config='/etc/openvpn/client.ovpn'
        uci set openvpn.VPN_Tap_Client.enabled='1'
        uci commit openvpn
        echo -e "${GREEN}- Configuración del cliente VPN añadida${NC}"
    else
        echo -e "${YELLOW}- La configuración del cliente VPN ya existe${NC}"
    fi
fi

# Desactivar WiFi de forma segura
echo -e "${YELLOW}- Verificando configuración WiFi...${NC}"
if [ -f /etc/config/wireless ]; then
    # Verificar si hay interfaces WiFi configuradas
    if uci show wireless > /dev/null 2>&1; then
        echo -e "${YELLOW}- Desactivando WiFi...${NC}"
        
        # Desactivar dispositivos WiFi
        wifi_devices=$(uci show wireless | grep "=wifi-device" | cut -d'.' -f2 | cut -d'=' -f1 | uniq)
        for device in $wifi_devices; do
            uci set wireless.$device.disabled='1'
            echo -e "${GREEN}- Dispositivo WiFi $device desactivado${NC}"
        done
        
        # Desactivar interfaces WiFi
        wifi_interfaces=$(uci show wireless | grep "=wifi-iface" | cut -d'.' -f2 | cut -d'=' -f1 | uniq)
        for interface in $wifi_interfaces; do
            uci set wireless.$interface.disabled='1'
            echo -e "${GREEN}- Interfaz WiFi $interface desactivada${NC}"
        done
        
        uci commit wireless
        echo -e "${GREEN}- WiFi desactivado correctamente${NC}"
    else
        echo -e "${YELLOW}- No hay configuración WiFi activa encontrada${NC}"
    fi
else
    echo -e "${YELLOW}- No existe archivo de configuración WiFi${NC}"
fi

# Configurar bridge e interfaz VPN con eth0 y tap0 (sin DHCP)
echo -e "${YELLOW}- Configurando bridge br-vpn con eth0 y tap0...${NC}"

# Crear backup de la configuración de red
cp /etc/config/network /etc/config/network.backup.$(date +%Y%m%d_%H%M%S)
echo -e "${GREEN}- Backup de configuración de red creado${NC}"

# Verificar y configurar el bridge br-vpn con eth0 y tap0
if ! uci show network.br-vpn > /dev/null 2>&1; then
    echo -e "${YELLOW}- Configurando bridge br-vpn con eth0 y tap0...${NC}"
    uci set network.br-vpn=device
    uci set network.br-vpn.type='bridge'
    uci set network.br-vpn.name='br-vpn'
    uci add_list network.br-vpn.ports='eth0'
    uci add_list network.br-vpn.ports='tap0'
    uci set network.br-vpn.ipv6='0'
    uci set network.br-vpn.igmp_snooping='1'
    echo -e "${GREEN}- Bridge br-vpn configurado con eth0 y tap0${NC}"
else
    echo -e "${YELLOW}- El bridge br-vpn ya existe, actualizando puertos...${NC}"
    # Limpiar puertos existentes y añadir eth0 y tap0
    uci delete network.br-vpn.ports
    uci add_list network.br-vpn.ports='eth0'
    uci add_list network.br-vpn.ports='tap0'
    uci set network.br-vpn.ipv6='0'
    uci set network.br-vpn.igmp_snooping='1'
    echo -e "${GREEN}- Puertos del bridge br-vpn actualizados a eth0 y tap0${NC}"
fi

# Verificar y configurar la interfaz VPN (sin DHCP)
if ! uci show network.vpn > /dev/null 2>&1; then
    echo -e "${YELLOW}- Configurando interfaz VPN (sin DHCP)...${NC}"
    uci set network.vpn=interface
    uci set network.vpn.proto='none'
    uci set network.vpn.device='br-vpn'
    echo -e "${GREEN}- Interfaz VPN configurada sin DHCP${NC}"
else
    echo -e "${YELLOW}- La interfaz VPN ya existe, actualizando...${NC}"
    uci set network.vpn.proto='none'
    uci set network.vpn.device='br-vpn'
    echo -e "${GREEN}- Interfaz VPN actualizada sin DHCP${NC}"
fi

# Configurar IGMP snooping para br-lan si no existe
if uci show network.@device[0] 2>/dev/null | grep -q "br-lan" && ! uci show network.@device[0] 2>/dev/null | grep -q "igmp_snooping"; then
    echo -e "${YELLOW}- Configurando IGMP snooping para br-lan...${NC}"
    uci set network.@device[0].igmp_snooping='1'
    echo -e "${GREEN}- IGMP snooping configurado para br-lan${NC}"
fi

# Aplicar cambios de configuración UCI
echo -e "${YELLOW}- Aplicando cambios de configuración...${NC}"
uci commit network
uci commit openvpn
if [ -f /etc/config/wireless ]; then
    uci commit wireless
fi
echo -e "${GREEN}- Cambios de configuración aplicados${NC}"

# Mostrar la configuración aplicada
echo -e "${YELLOW}- Configuración de red aplicada:${NC}"
echo -e "Bridge br-vpn:"
uci show network.br-vpn
echo -e "Interfaz VPN:"
uci show network.vpn

if [ -f /etc/config/wireless ]; then
    echo -e "WiFi:"
    uci show wireless | grep disabled || echo -e "${YELLOW}- No hay configuración WiFi para mostrar${NC}"
fi

# Iniciar y habilitar OpenVPN
echo -e "${YELLOW}- Iniciando servicio OpenVPN...${NC}"
/etc/init.d/openvpn enable
/etc/init.d/openvpn start
check_status
echo -e "${GREEN}- Servicio OpenVPN iniciado y habilitado${NC}"

# Mostrar resumen de la configuración
echo -e "\n${GREEN}=== RESUMEN DE CONFIGURACIÓN ==="
echo -e "✓ Paquetes instalados"
echo -e "✓ Archivo client.ovpn configurado"
echo -e "✓ Configuración de OpenVPN creada"
echo -e "✓ WiFi desactivado (si existía)"
echo -e "✓ Bridge br-vpn configurado con eth0 y tap0"
echo -e "✓ Interfaz VPN creada sin DHCP"
echo -e "✓ Servicio OpenVPN iniciado"
echo -e "==============================${NC}\n"

# Verificar el archivo client.ovpn
echo -e "${YELLOW}- Verificando archivo client.ovpn...${NC}"
if [ -s /etc/openvpn/client.ovpn ]; then
    file_size=$(wc -l < /etc/openvpn/client.ovpn)
    if [ "$file_size" -gt 5 ]; then
        echo -e "${GREEN}- El archivo client.ovpn tiene $file_size líneas${NC}"
    else
        echo -e "${RED}- ADVERTENCIA: El archivo client.ovpn parece muy pequeño${NC}"
    fi
else
    echo -e "${RED}- ERROR: El archivo client.ovpn está vacío${NC}"
fi

# Verificar servicios
echo -e "${YELLOW}- Verificando servicios...${NC}"
echo -e "OpenVPN status:"
/etc/init.d/openvpn status

# Verificar interfaces de red
echo -e "${YELLOW}- Verificando interfaces de red...${NC}"
ifconfig | grep -E "(br-vpn|eth0|tap0|vpn)" || echo -e "${YELLOW}- Interfaces VPN aún no visibles (pueden necesitar reinicio)${NC}"

# Mostrar configuración de bridges
echo -e "${YELLOW}- Bridges configurados:${NC}"
brctl show 2>/dev/null || echo -e "${YELLOW}- brctl no disponible${NC}"

echo -e "\n${YELLOW}PRÓXIMOS PASOS:${NC}"
echo -e "1. El bridge br-vpn combina eth0 (física) + tap0 (VPN)"
echo -e "2. La interfaz VPN está configurada sin DHCP"
echo -e "3. WiFi desactivado (si existía)"
echo -e "4. Verificar configuración: uci show network.br-vpn"
echo -e "5. Verificar estado OpenVPN: /etc/init.d/openvpn status"

# Preguntar si desea reiniciar para asegurar que la interfaz se cree
echo -e "\n${YELLOW}¿Desea reiniciar el dispositivo para aplicar todos los cambios? (s/n)${NC}"
echo -e "${YELLOW}(Recomendado para crear el bridge br-vpn correctamente)${NC}"
# Leer sin esperar Enter
read -r response
case "$response" in
    [sS]|[sS][iI]|[yY]|[yY][eE][sS])
        echo -e "${YELLOW}- Reiniciando en 5 segundos...${NC}"
        sleep 5
        reboot
        ;;
    *)
        echo -e "${YELLOW}- Reinicio cancelado${NC}"
        echo -e "${YELLOW}- Si el bridge no funciona, ejecute 'reboot' manualmente${NC}"
        ;;
esac

echo -e "\n${GREEN}¡Configuración completada!${NC}"
echo -e "${YELLOW}Resumen final:${NC}"
echo -e "  - Bridge br-vpn: eth0 + tap0"
echo -e "  - Interfaz VPN: sin DHCP"
echo -e "  - WiFi: desactivado (si existía)"
echo -e "  - OpenVPN: iniciado y habilitado"
