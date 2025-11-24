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

# Función alternativa más simple para reiniciar red
restart_network_simple() {
    echo -e "${YELLOW}- Aplicando cambios de configuración de red...${NC}"
    echo -e "${YELLOW}- Esto puede tomar unos segundos...${NC}"
    
    # Verificar si timeout está disponible
    if command -v timeout >/dev/null 2>&1; then
        # Ejecutar y esperar con timeout
        timeout 30 /etc/init.d/network restart
        local result=$?
        
        if [ $result -eq 0 ]; then
            echo -e "${GREEN}- Cambios de red aplicados correctamente${NC}"
            return 0
        elif [ $result -eq 124 ]; then
            echo -e "${YELLOW}- Timeout en reinicio de red, continuando...${NC}"
            return 1
        else
            echo -e "${RED}- Error en el reinicio de red (código: $result)${NC}"
            return 1
        fi
    else
        # Si timeout no está disponible, ejecutar normalmente
        echo -e "${YELLOW}- 'timeout' no disponible, ejecutando sin timeout...${NC}"
        /etc/init.d/network restart
        local result=$?
        
        if [ $result -eq 0 ]; then
            echo -e "${GREEN}- Cambios de red aplicados correctamente${NC}"
            return 0
        else
            echo -e "${RED}- Error en el reinicio de red (código: $result)${NC}"
            return 1
        fi
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

# Configurar bridge solo si no existe
echo -e "${YELLOW}- Configurando bridge para VPN...${NC}"

# Verificar si br-vpn ya existe en la configuración de red
if ! grep -q "br-vpn" /etc/config/network; then
    # Crear backup de la configuración de red
    cp /etc/config/network /etc/config/network.backup.$(date +%Y%m%d_%H%M%S)
    echo -e "${GREEN}- Backup de configuración de red creado${NC}"
    
    # Añadir configuración del bridge
    echo "" >> /etc/config/network
    echo "config device" >> /etc/config/network
    echo "    option type 'bridge'" >> /etc/config/network
    echo "    option name 'br-vpn'" >> /etc/config/network
    echo "    list ports 'tap0'" >> /etc/config/network
    echo "    option ipv6 '0'" >> /etc/config/network
    echo "    option igmp_snooping '1'" >> /etc/config/network
    echo "" >> /etc/config/network
    
    echo "config interface 'vpn'" >> /etc/config/network
    echo "    option proto 'none'" >> /etc/config/network
    echo "    option device 'br-vpn'" >> /etc/config/network
    echo "" >> /etc/config/network
    
    echo -e "${GREEN}- Bridge br-vpn configurado${NC}"
else
    echo -e "${YELLOW}- El bridge br-vpn ya existe en la configuración${NC}"
fi

# Configurar IGMP snooping para br-lan si no existe
if grep -q "option name 'br-lan'" /etc/config/network && ! grep -q "igmp_snooping" /etc/config/network; then
    echo -e "${YELLOW}- Configurando IGMP snooping para br-lan...${NC}"
    sed -i "/option name 'br-lan'/a \    option igmp_snooping '1'" /etc/config/network
    echo -e "${GREEN}- IGMP snooping configurado para br-lan${NC}"
fi

# Aplicar cambios de red con la función mejorada
restart_network_simple

# Mostrar resumen de la configuración
echo -e "\n${GREEN}=== RESUMEN DE CONFIGURACIÓN ==="
echo -e "✓ Paquetes instalados"
echo -e "✓ Archivo client.ovpn configurado en /etc/openvpn/"
echo -e "✓ Configuración de OpenVPN creada"
echo -e "✓ Bridge br-vpn configurado"
echo -e "✓ Interfaz VPN creada"
echo -e "✓ Cambios de red aplicados"
echo -e "==============================${NC}\n"

# Verificar el archivo client.ovpn
echo -e "${YELLOW}- Verificando archivo client.ovpn...${NC}"
if [ -s /etc/openvpn/client.ovpn ]; then
    file_size=$(wc -l < /etc/openvpn/client.ovpn)
    if [ "$file_size" -gt 5 ]; then
        echo -e "${GREEN}- El archivo client.ovpn tiene $file_size líneas (parece configurado)${NC}"
    else
        echo -e "${RED}- ADVERTENCIA: El archivo client.ovpn parece muy pequeño ($file_size líneas)${NC}"
        echo -e "${YELLOW}- Es posible que necesite editarlo manualmente: nano /etc/openvpn/client.ovpn${NC}"
    fi
else
    echo -e "${RED}- ERROR: El archivo client.ovpn está vacío${NC}"
    echo -e "${YELLOW}- Debe editarlo manualmente: nano /etc/openvpn/client.ovpn${NC}"
fi

# Mostrar estado de los servicios
echo -e "${YELLOW}- Estado de los servicios:${NC}"
/etc/init.d/openvpn status 2>/dev/null || echo "- Servicio OpenVPN no está corriendo (normal por ahora)"

echo -e "\n${YELLOW}PRÓXIMOS PASOS:${NC}"
echo -e "1. Verifique la configuración: cat /etc/openvpn/client.ovpn"
echo -e "2. Si necesita editar: nano /etc/openvpn/client.ovpn"
echo -e "3. Inicie OpenVPN: /etc/init.d/openvpn start"
echo -e "4. Habilite OpenVPN para que inicie automáticamente:"
echo -e "   /etc/init.d/openvpn enable"
echo -e "5. Verifique el estado: /etc/init.d/openvpn status"
echo -e "6. Verifique la conexión de red después del reinicio"

# Preguntar si desea reiniciar
echo -e "\n${YELLOW}¿Desea reiniciar el dispositivo para asegurar que todos los cambios se apliquen? (s/n)${NC}"
echo -e "${YELLOW}(Recomendado para aplicar completamente los cambios de red)${NC}"
read -r response
case "$response" in
    [sS]|[sS][iI]|[yY]|[yY][eE][sS])
        echo -e "${YELLOW}- Reiniciando en 5 segundos...${NC}"
        echo -e "${YELLOW}- Presione Ctrl+C para cancelar${NC}"
        sleep 5
        reboot
        ;;
    *)
        echo -e "${YELLOW}- Reinicio cancelado. Puede reiniciar manualmente más tarde con: reboot${NC}"
        echo -e "${YELLOW}- Recuerde iniciar OpenVPN manualmente: /etc/init.d/openvpn start${NC}"
        ;;
esac

echo -e "\n${GREEN}¡Configuración completada!${NC}"
