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

# Configurar bridge solo si no existe
echo -e "${YELLOW}- Configurando bridge para VPN...${NC}"

# Verificar si br-vpn ya existe en la configuración de red
if ! grep -q "br-vpn" /etc/config/network; then
    # Crear backup de la configuración de red
    cp /etc/config/network /etc/config/network.backup.$(date +%Y%m%d_%H%M%S)
    echo -e "${GREEN}- Backup de configuración de red creado: /etc/config/network.backup.$(date +%Y%m%d_%H%M%S)${NC}"
    
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
    
    echo -e "${GREEN}- Bridge br-vpn configurado en /etc/config/network${NC}"
else
    echo -e "${YELLOW}- El bridge br-vpn ya existe en la configuración${NC}"
fi

# Configurar IGMP snooping para br-lan si no existe
if grep -q "option name 'br-lan'" /etc/config/network && ! grep -q "igmp_snooping" /etc/config/network; then
    echo -e "${YELLOW}- Configurando IGMP snooping para br-lan...${NC}"
    sed -i "/option name 'br-lan'/a \    option igmp_snooping '1'" /etc/config/network
    echo -e "${GREEN}- IGMP snooping configurado para br-lan${NC}"
fi

# Mostrar resumen de la configuración
echo -e "\n${GREEN}=== RESUMEN DE CONFIGURACIÓN ==="
echo -e "✓ Paquetes instalados"
echo -e "✓ Archivo client.ovpn configurado en /etc/openvpn/"
echo -e "✓ Configuración de OpenVPN creada"
echo -e "✓ Bridge br-vpn configurado"
echo -e "✓ Interfaz VPN creada"
echo -e "✓ Backup de configuración de red creado"
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

# Mostrar los cambios pendientes en la configuración de red
echo -e "\n${YELLOW}=== CAMBIOS PENDIENTES EN CONFIGURACIÓN DE RED ==="
echo -e "Se han modificado los siguientes archivos:"
echo -e "  /etc/config/network (con bridge br-vpn)"
echo -e "  /etc/config/openvpn (con cliente VPN)"
echo -e "  /etc/openvpn/client.ovpn (configuración del cliente)"
echo -e ""
echo -e "Para aplicar estos cambios, necesita reiniciar el servicio de red o el dispositivo."
echo -e "===============================================${NC}\n"

echo -e "\n${YELLOW}PRÓXIMOS PASOS RECOMENDADOS:${NC}"
echo -e "1. Verifique la configuración de red: cat /etc/config/network"
echo -e "2. Verifique la configuración OpenVPN: cat /etc/openvpn/client.ovpn"
echo -e "3. Si necesita editar: nano /etc/openvpn/client.ovpn"
echo -e "4. REINICIE EL DISPOSITIVO para aplicar todos los cambios"

# Ofrecer opciones al usuario
echo -e "\n${YELLOW}¿Qué desea hacer ahora?${NC}"
echo -e "1) Reiniciar el dispositivo (RECOMENDADO)"
echo -e "2) Solo reiniciar el servicio de red (puede fallar)"
echo -e "3) No hacer nada, salir del script"
echo -e "${YELLOW}Seleccione una opción (1/2/3):${NC}"

read -r option
case "$option" in
    1)
        echo -e "${YELLOW}- Reiniciando dispositivo en 5 segundos...${NC}"
        echo -e "${YELLOW}- Presione Ctrl+C para cancelar${NC}"
        sleep 5
        reboot
        ;;
    2)
        echo -e "${YELLOW}- Intentando reiniciar servicio de red...${NC}"
        echo -e "${YELLOW}- ADVERTENCIA: Esto puede fallar o bloquearse${NC}"
        echo -e "${YELLOW}- Si se bloquea, puede reiniciar manualmente más tarde${NC}"
        /etc/init.d/network restart &
        echo -e "${GREEN}- Comando de reinicio de red ejecutado en segundo plano${NC}"
        echo -e "${YELLOW}- El script continúa...${NC}"
        ;;
    3)
        echo -e "${YELLOW}- Saliendo sin aplicar cambios de red${NC}"
        ;;
    *)
        echo -e "${RED}- Opción no válida. Saliendo.${NC}"
        ;;
esac

echo -e "\n${GREEN}¡Configuración de archivos completada!${NC}"
echo -e "${YELLOW}Recuerde:${NC}"
echo -e "- Los cambios de red requieren reinicio para aplicarse completamente"
echo -e "- Después del reinicio, inicie OpenVPN: /etc/init.d/openvpn start"
echo -e "- Habilite OpenVPN: /etc/init.d/openvpn enable"
echo -e "- Verifique el estado: /etc/init.d/openvpn status"
