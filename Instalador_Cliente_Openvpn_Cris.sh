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

# Función para crear el archivo client.ovpn
create_client_ovpn() {
    echo -e "${YELLOW}- Creando archivo client.ovpn...${NC}"
    
    echo -e "${GREEN}=== INSTRUCCIONES ==="
    echo -e "Por favor, pegue el contenido completo de su archivo client.ovpn"
    echo -e "Cuando termine, presione Ctrl+D para guardar"
    echo -e "========================${NC}"
    echo ""
    
    # Crear el archivo y permitir al usuario pegar el contenido
    cat > /etc/openvpn/client.ovpn << 'EOF'
# === CONFIGURACIÓN CLIENTE OPENVPN ===
# Pegue debajo de esta línea el contenido de su client.ovpn

EOF
    
    # Permitir al usuario pegar el contenido
    echo -e "${YELLOW}Pegue ahora el contenido de client.ovpn (Ctrl+D cuando termine):${NC}"
    cat >> /etc/openvpn/client.ovpn
    
    check_status
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

# Configurar bridge e interfaz VPN
echo -e "${YELLOW}- Configurando bridge e interfaz VPN...${NC}"

# Crear backup de la configuración de red
cp /etc/config/network /etc/config/network.backup.$(date +%Y%m%d_%H%M%S)
echo -e "${GREEN}- Backup de configuración de red creado${NC}"

# Verificar y configurar el bridge br-vpn
if ! uci show network.br-vpn > /dev/null 2>&1; then
    echo -e "${YELLOW}- Configurando bridge br-vpn...${NC}"
    uci set network.br-vpn=device
    uci set network.br-vpn.type='bridge'
    uci set network.br-vpn.name='br-vpn'
    uci add_list network.br-vpn.ports='tap0'
    uci set network.br-vpn.ipv6='0'
    uci set network.br-vpn.igmp_snooping='1'
    echo -e "${GREEN}- Bridge br-vpn configurado${NC}"
else
    echo -e "${YELLOW}- El bridge br-vpn ya existe${NC}"
fi

# Verificar y configurar la interfaz VPN
if ! uci show network.vpn > /dev/null 2>&1; then
    echo -e "${YELLOW}- Configurando interfaz VPN...${NC}"
    uci set network.vpn=interface
    uci set network.vpn.proto='none'
    uci set network.vpn.device='br-vpn'
    echo -e "${GREEN}- Interfaz VPN configurada${NC}"
else
    echo -e "${YELLOW}- La interfaz VPN ya existe${NC}"
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
echo -e "${GREEN}- Cambios de configuración aplicados${NC}"

# Mostrar la configuración aplicada
echo -e "${YELLOW}- Configuración de red aplicada:${NC}"
echo -e "Bridge VPN:"
uci show network.br-vpn
echo -e "Interfaz VPN:"
uci show network.vpn

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
echo -e "✓ Bridge br-vpn configurado"
echo -e "✓ Interfaz VPN creada"
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
ifconfig | grep -E "(br-vpn|tap0|vpn)" || echo -e "${YELLOW}- Interfaces VPN aún no visibles (pueden necesitar reinicio)${NC}"

echo -e "\n${YELLOW}PRÓXIMOS PASOS:${NC}"
echo -e "1. Verificar conexión VPN"
echo -e "2. Si la interfaz VPN no aparece, reiniciar el dispositivo"
echo -e "3. Verificar configuración: uci show network.vpn"
echo -e "4. Verificar estado OpenVPN: /etc/init.d/openvpn status"

# Preguntar si desea reiniciar para asegurar que la interfaz se cree
echo -e "\n${YELLOW}¿Desea reiniciar el dispositivo para crear la interfaz VPN? (s/n)${NC}"
echo -e "${YELLOW}(Recomendado si la interfaz VPN no se crea automáticamente)${NC}"
read -r response
case "$response" in
    [sS]|[sS][iI]|[yY]|[yY][eE][sS])
        echo -e "${YELLOW}- Reiniciando en 5 segundos...${NC}"
        sleep 5
        reboot
        ;;
    *)
        echo -e "${YELLOW}- Reinicio cancelado${NC}"
        echo -e "${YELLOW}- Si la interfaz VPN no aparece, ejecute 'reboot' manualmente${NC}"
        ;;
esac

echo -e "\n${GREEN}¡Configuración completada!${NC}"
