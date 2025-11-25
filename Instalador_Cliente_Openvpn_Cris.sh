#!/bin/sh

echo ""
echo "================================================"
echo "     INSTALADOR CLIENTE OPENVPN - COMPLETO"
echo "  BR-VPN - GL AX3000 - GL MT300 - CUDY TR3000"
echo "================================================"
echo ""

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

check_status() {
    if [ $? -ne 0 ]; then
        echo -e "${RED}- Ha ocurrido un error${NC}"
        exit 1
    fi
}

# Detectar dispositivo y configurar accordingly
detect_device() {
    echo -e "${YELLOW}- Detectando dispositivo...${NC}"
    
    # Obtener modelo del dispositivo
    if [ -f /tmp/sysinfo/model ]; then
        MODEL=$(cat /tmp/sysinfo/model)
        echo -e "${YELLOW}- Modelo: $MODEL${NC}"
    else
        MODEL=$(cat /proc/cpuinfo | grep -i machine | cut -d: -f2 | tr -d ' ')
        echo -e "${YELLOW}- Modelo (CPU): $MODEL${NC}"
    fi
    
    # Detectar fabricante y modelo específico
    if echo "$MODEL" | grep -i -q "tr3000"; then
        DEVICE_BRAND="Cudy"
        DEVICE_MODEL="TR3000"
        DEVICE_TYPE="Cudy_TR3000"
    elif echo "$MODEL" | grep -i -q "mango\|mt300"; then
        DEVICE_BRAND="GL.iNet"
        DEVICE_MODEL="MT300"
        DEVICE_TYPE="GL_MT300"  
    elif echo "$MODEL" | grep -i -q "ax3000"; then
        DEVICE_BRAND="GL.iNet"
        DEVICE_MODEL="AX3000"
        DEVICE_TYPE="GL_AX3000"
    else
        DEVICE_BRAND="Unknown"
        DEVICE_MODEL="Generic"
        DEVICE_TYPE="Generic"
    fi
    
    echo -e "${GREEN}- Fabricante: $DEVICE_BRAND${NC}"
    echo -e "${GREEN}- Modelo: $DEVICE_MODEL${NC}"
    
    # Detectar interfaz WAN correcta
    detect_wan_interface
}

detect_wan_interface() {
    echo -e "${YELLOW}- Detectando interfaz WAN...${NC}"
    
    # Método 1: Ver configuración UCI actual
    if uci get network.wan.ifname >/dev/null 2>&1; then
        WAN_INTERFACE=$(uci get network.wan.ifname)
        echo -e "${GREEN}- Interfaz WAN configurada: $WAN_INTERFACE${NC}"
        return
    fi
    
    # Método 2: Detección por modelo específico
    case "$DEVICE_TYPE" in
        "GL_MT300")
            WAN_INTERFACE="eth0.2"
            ;;
        "GL_AX3000")
            WAN_INTERFACE="eth0"
            ;;
        "Cudy_TR3000")
            # Cudy TR3000 usa DSA - interfaces pueden ser diferentes
            # Intentar detectar la interfaz WAN real
            if ip link show | grep -q "wan"; then
                WAN_INTERFACE=$(ip link show | grep "wan" | head -1 | cut -d: -f2 | tr -d ' ')
            elif uci show network | grep "wan" | grep "ifname" | head -1; then
                WAN_INTERFACE=$(uci show network | grep "wan" | grep "ifname" | head -1 | cut -d= -f2 | tr -d "'" | tr -d ' ')
            else
                # Fallback para TR3000 - usualmente eth1 o br-lan_wan
                WAN_INTERFACE="eth1"
            fi
            ;;
        *)
            # Método 3: Escanear interfaces disponibles
            WAN_INTERFACE=$(ip link show | grep -E "eth[0-9]" | grep "state UP" | head -1 | cut -d: -f2 | tr -d ' ')
            if [ -z "$WAN_INTERFACE" ]; then
                WAN_INTERFACE="eth0"
            fi
            ;;
    esac
    
    echo -e "${GREEN}- Interfaz WAN detectada: $WAN_INTERFACE${NC}"
}

# Verificar compatibilidad del dispositivo
check_compatibility() {
    echo -e "${YELLOW}- Verificando compatibilidad...${NC}"
    
    # Verificar si es OpenWrt
    if [ ! -f /etc/openwrt_release ]; then
        echo -e "${RED}- Error: No se detecta OpenWrt${NC}"
        exit 1
    fi
    
    # Verificar almacenamiento disponible
    if df /overlay >/dev/null 2>&1; then
        STORAGE_AVAILABLE=$(df /overlay | awk 'NR==2 {print $4}')
        if [ "$STORAGE_AVAILABLE" -lt 5000 ]; then
            echo -e "${YELLOW}- Advertencia: Almacenamiento limitado ($STORAGE_AVAILABLE KB)${NC}"
        else
            echo -e "${GREEN}- Almacenamiento adecuado: $STORAGE_AVAILABLE KB${NC}"
        fi
    fi
    
    # Verificar RAM disponible
    RAM_AVAILABLE=$(free | grep Mem | awk '{print $4}')
    if [ "$RAM_AVAILABLE" -lt 20000 ]; then
        echo -e "${YELLOW}- Advertencia: RAM limitada ($RAM_AVAILABLE KB)${NC}"
    else
        echo -e "${GREEN}- RAM adecuada: $RAM_AVAILABLE KB${NC}"
    fi
    
    echo -e "${GREEN}- Dispositivo compatible${NC}"
}

# Función específica para configuración DSA (TR3000)
configure_dsa_network() {
    echo -e "${YELLOW}- Configurando red DSA para TR3000...${NC}"
    
    # Para dispositivos con DSA, necesitamos un enfoque diferente
    # No eliminar interfaces WAN, en su caso reconfigurar
    
    # Verificar si usa DSA
    if uci show network | grep -q "dsa"; then
        echo -e "${YELLOW}- Detectada configuración DSA${NC}"
        
        # En DSA, las interfaces pueden ser diferentes
        # Mantener la configuración WAN existente pero añadir nuestro bridge
        echo -e "${YELLOW}- Manteniendo configuración WAN existente${NC}"
        
        # Para TR3000, el bridge debe incluir la interfaz física correcta
        # Normalmente eth1 o una interfaz específica para WAN
        if [ "$WAN_INTERFACE" = "eth1" ]; then
            echo -e "${GREEN}- Usando eth1 como interfaz WAN para TR3000${NC}"
        fi
    else
        echo -e "${YELLOW}- Configuración de red tradicional${NC}"
    fi
}

echo -e "${YELLOW}- Iniciando configuración OpenVPN universal...${NC}"

# Verificar compatibilidad
check_compatibility

# Actualizar paquetes
echo -e "${YELLOW}- Actualizando paquetes...${NC}"
opkg update
check_status

# Instalar OpenVPN
echo -e "${YELLOW}- Instalando OpenVPN...${NC}"
opkg install openvpn-easy-rsa openvpn-openssl luci-app-openvpn nano
check_status

# Detectar dispositivo
detect_device

# Crear client.ovpn interactivo
create_client_ovpn() {
    echo -e "${YELLOW}- Creando client.ovpn...${NC}"
    cat > /etc/openvpn/client.ovpn << 'EOF'
# === CONFIGURACIÓN CLIENTE OPENVPN ===
# Pegue debajo el contenido de client.ovpn

EOF
    
    echo -e "${YELLOW}Pegue contenido client.ovpn (Ctrl+D cuando termine):${NC}"
    cat >> /etc/openvpn/client.ovpn
    echo -e "${GREEN}- client.ovpn creado${NC}"
    
    # Verificar que el archivo no esté vacío
    if [ ! -s /etc/openvpn/client.ovpn ]; then
        echo -e "${RED}- Error: El archivo client.ovpn está vacío${NC}"
        exit 1
    fi
}

if [ -f /etc/openvpn/client.ovpn ]; then
    echo -e "${YELLOW}- client.ovpn existe, ¿sobrescribir? (s/n)${NC}"
    read -r response
    case "$response" in
        [sS]*) create_client_ovpn ;;
        *) echo -e "${YELLOW}- Manteniendo existente${NC}" ;;
    esac
else
    create_client_ovpn
fi

# Configurar OpenVPN
echo -e "${YELLOW}- Configurando OpenVPN...${NC}"
if [ ! -f /etc/config/openvpn ]; then
    cat <<EOF > /etc/config/openvpn
config openvpn 'VPN_Tap_Client'
    option config '/etc/openvpn/client.ovpn'
    option enabled '1'
EOF
else
    uci set openvpn.VPN_Tap_Client=openvpn
    uci set openvpn.VPN_Tap_Client.config='/etc/openvpn/client.ovpn'
    uci set openvpn.VPN_Tap_Client.enabled='1'
    uci commit openvpn
fi

# Configuración específica por dispositivo
echo -e "${YELLOW}- Configurando red para $DEVICE_BRAND $DEVICE_MODEL...${NC}"

case "$DEVICE_TYPE" in
    "GL_MT300")
        echo -e "${YELLOW}- Configurando GL-MT300 (VLAN eth0.2)...${NC}"
        uci delete network.wan 2>/dev/null
        uci delete network.wan6 2>/dev/null
        ;;
    "GL_AX3000")
        echo -e "${YELLOW}- Configurando GL-AX3000 (eth0)...${NC}"
        ;;
    "Cudy_TR3000")
        echo -e "${YELLOW}- Configurando Cudy TR3000 ($WAN_INTERFACE)...${NC}"
        configure_dsa_network
        ;;
    *)
        echo -e "${YELLOW}- Configurando dispositivo genérico ($WAN_INTERFACE)...${NC}"
        ;;
esac

# Configurar bridge (común para todos)
echo -e "${YELLOW}- Configurando bridge br-vpn...${NC}"
uci delete network.br-vpn 2>/dev/null
uci set network.br-vpn=device
uci set network.br-vpn.type='bridge'
uci set network.br-vpn.name='br-vpn'
uci add_list network.br-vpn.ports="$WAN_INTERFACE"
uci add_list network.br-vpn.ports='tap0'
uci set network.br-vpn.ipv6='0'
uci set network.br-vpn.igmp_snooping='1'

# Configurar interfaz VPN
uci delete network.vpn 2>/dev/null
uci set network.vpn=interface
uci set network.vpn.proto='none'
uci set network.vpn.device='br-vpn'

# Configurar IGMP snooping para br-lan
if uci get network.@device[0].name 2>/dev/null | grep -q "br-lan"; then
    uci set network.@device[0].igmp_snooping='1'
fi

# Desactivar WiFi si existe
if [ -f /etc/config/wireless ]; then
    wifi_devices=$(uci show wireless | grep "=wifi-device" | cut -d'.' -f2 | cut -d'=' -f1 | uniq 2>/dev/null)
    if [ -n "$wifi_devices" ]; then
        for device in $wifi_devices; do
            uci set wireless.$device.disabled='1' 2>/dev/null
            echo -e "${GREEN}- WiFi $device desactivado${NC}"
        done
    else
        echo -e "${YELLOW}- No se encontraron dispositivos WiFi para desactivar${NC}"
    fi
fi

# Aplicar cambios
echo -e "${YELLOW}- Aplicando configuración...${NC}"
uci commit network
uci commit openvpn
if [ -f /etc/config/wireless ]; then
    uci commit wireless
fi

# Iniciar OpenVPN
echo -e "${YELLOW}- Iniciando OpenVPN...${NC}"
/etc/init.d/openvpn enable
/etc/init.d/openvpn start
check_status

# Mostrar resumen
echo -e "\n${GREEN}=== CONFIGURACIÓN COMPLETADA ===${NC}"
echo -e "Dispositivo: $DEVICE_BRAND $DEVICE_MODEL"
echo -e "Tipo: $DEVICE_TYPE"
echo -e "Interfaz WAN: $WAN_INTERFACE"
echo -e "Bridge: br-vpn ($WAN_INTERFACE + tap0)"
echo -e "OpenVPN: activado"

# Verificación final específica para TR3000
if [ "$DEVICE_TYPE" = "Cudy_TR3000" ]; then
    echo -e "\n${YELLOW}- Verificación específica TR3000:${NC}"
    echo -e "Interfaces de red:"
    ip link show | grep -E "(eth|wan|lan|br-)" | grep -v "link/"
    echo -e "Configuración DSA:"
    uci show network | grep -E "(device|switch|dsa)" | head -10
fi

echo -e "\n${YELLOW}¿Reiniciar dispositivo? (s/n)${NC}"
echo -e "${YELLOW}(Recomendado para aplicar cambios de red completamente)${NC}"
read -r response
case "$response" in
    [sS]*) 
        echo -e "${YELLOW}- Reiniciando en 5 segundos...${NC}"
        sleep 5
        reboot 
        ;;
    *) 
        echo -e "${YELLOW}- Ejecute 'reboot' manualmente cuando sea conveniente${NC}" 
        ;;
esac

echo -e "\n${GREEN}¡Configuración completada para $DEVICE_BRAND $DEVICE_MODEL!${NC}"
