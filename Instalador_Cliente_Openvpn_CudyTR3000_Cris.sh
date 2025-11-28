#!/bin/sh

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

# Verificar que es un Cudy TR3000
verify_tr3000() {
    echo -e "${YELLOW}- Verificando dispositivo Cudy TR3000...${NC}"
    
    # Obtener modelo del dispositivo
    if [ -f /tmp/sysinfo/model ]; then
        MODEL=$(cat /tmp/sysinfo/model)
        echo -e "${YELLOW}- Modelo detectado: $MODEL${NC}"
    else
        MODEL=$(cat /proc/cpuinfo | grep -i machine | cut -d: -f2 | tr -d ' ')
        echo -e "${YELLOW}- Modelo (CPU): $MODEL${NC}"
    fi
    
    # Verificar que es un TR3000
    if ! echo "$MODEL" | grep -i -q "tr3000"; then
        echo -e "${RED}- ERROR: Este script es exclusivo para Cudy TR3000${NC}"
        echo -e "${RED}- Dispositivo detectado: $MODEL${NC}"
        echo -e "${RED}- Ejecución cancelada${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}- Cudy TR3000 confirmado${NC}"
}

# Detectar interfaz WAN para TR3000
detect_wan_interface() {
    echo -e "${YELLOW}- Detectando interfaz WAN para TR3000...${NC}"
    
    # Para TR3000 con DSA, detectar la interfaz WAN correcta
    if ip link show | grep -q "wan"; then
        WAN_INTERFACE=$(ip link show | grep "wan" | head -1 | cut -d: -f2 | tr -d ' ')
        echo -e "${GREEN}- Interfaz WAN detectada: $WAN_INTERFACE${NC}"
    elif uci get network.wan.ifname >/dev/null 2>&1; then
        WAN_INTERFACE=$(uci get network.wan.ifname)
        echo -e "${GREEN}- Interfaz WAN configurada: $WAN_INTERFACE${NC}"
    else
        # Para TR3000, la interfaz física suele ser eth0
        WAN_INTERFACE="eth0"
        echo -e "${YELLOW}- Usando interfaz WAN por defecto: $WAN_INTERFACE${NC}"
    fi
}

# Verificar compatibilidad
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
    
    echo -e "${GREEN}- Cudy TR3000 compatible${NC}"
}

# Configurar bridge específico para TR3000
configure_tr3000_bridge() {
    echo -e "${YELLOW}- Configurando bridge br-vpn para TR3000...${NC}"
    
    # Eliminar configuraciones previas si existen
    uci delete network.br-vpn 2>/dev/null
    uci delete network.vpn 2>/dev/null
    
    echo -e "${YELLOW}- Creando dispositivo bridge br-vpn...${NC}"
    
    # Crear el dispositivo bridge
    uci set network.br-vpn=device
    uci set network.br-vpn.type='bridge'
    uci set network.br-vpn.name='br-vpn'
    
    # Agregar puertos al bridge - eth0 y tap0
    echo -e "${YELLOW}- Agregando puertos eth0 y tap0 al bridge...${NC}"
    uci delete network.br-vpn.ports 2>/dev/null
    uci add_list network.br-vpn.ports='eth0'
    uci add_list network.br-vpn.ports='tap0'
    
    # Configurar opciones del bridge
    uci set network.br-vpn.ipv6='0'
    uci set network.br-vpn.igmp_snooping='1'
    uci set network.br-vpn.stp='0'
    uci set network.br-vpn.forward_delay='0'
    
    echo -e "${GREEN}- Dispositivo bridge br-vpn creado con puertos: eth0, tap0${NC}"
    
    # Configurar interfaz VPN que usa el bridge
    uci set network.vpn=interface
    uci set network.vpn.proto='none'
    uci set network.vpn.device='br-vpn'
    
    echo -e "${GREEN}- Interfaz VPN configurada en br-vpn${NC}"
}

# Crear client.ovpn interactivo
create_client_ovpn() {
    echo -e "${YELLOW}- Creando configuración OpenVPN...${NC}"
    
    # Crear directorio si no existe
    mkdir -p /etc/openvpn
    
    cat > /etc/openvpn/client.ovpn << 'EOF'
# === CONFIGURACIÓN CLIENTE OPENVPN ===
# Pegue debajo el contenido de client.ovpn

EOF
    
    echo -e "${YELLOW}Pegue el contenido de client.ovpn (Ctrl+D cuando termine):${NC}"
    cat >> /etc/openvpn/client.ovpn
    
    # Verificar que el archivo no esté vacío
    if [ ! -s /etc/openvpn/client.ovpn ]; then
        echo -e "${RED}- Error: El archivo client.ovpn está vacío${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}- client.ovpn creado exitosamente${NC}"
}

# Configurar OpenVPN
configure_openvpn() {
    echo -e "${YELLOW}- Configurando servicio OpenVPN...${NC}"
    
    if [ ! -f /etc/config/openvpn ]; then
        cat <<EOF > /etc/config/openvpn
config openvpn 'VPN_Tap_Client'
    option config '/etc/openvpn/client.ovpn'
    option enabled '1'
    option dev 'tap0'
    option dev_type 'tap'
EOF
    else
        uci set openvpn.VPN_Tap_Client=openvpn
        uci set openvpn.VPN_Tap_Client.config='/etc/openvpn/client.ovpn'
        uci set openvpn.VPN_Tap_Client.enabled='1'
        uci set openvpn.VPN_Tap_Client.dev='tap0'
        uci set openvpn.VPN_Tap_Client.dev_type='tap'
        uci commit openvpn
    fi
    
    echo -e "${GREEN}- Configuración OpenVPN completada${NC}"
}

# Desactivar WiFi en TR3000
disable_wifi() {
    echo -e "${YELLOW}- Desactivando interfaces WiFi...${NC}"
    
    if [ -f /etc/config/wireless ]; then
        wifi_devices=$(uci show wireless | grep "=wifi-device" | cut -d'.' -f2 | cut -d'=' -f1 | uniq 2>/dev/null)
        if [ -n "$wifi_devices" ]; then
            for device in $wifi_devices; do
                uci set wireless.$device.disabled='1' 2>/dev/null
                echo -e "${GREEN}- WiFi $device desactivado${NC}"
            done
        else
            echo -e "${YELLOW}- No se encontraron dispositivos WiFi${NC}"
        fi
    else
        echo -e "${YELLOW}- No hay configuración WiFi disponible${NC}"
    fi
}

# Aplicar configuración
apply_configuration() {
    echo -e "${YELLOW}- Aplicando configuración...${NC}"
    
    uci commit network
    uci commit openvpn
    if [ -f /etc/config/wireless ]; then
        uci commit wireless
    fi
    
    echo -e "${GREEN}- Configuración aplicada${NC}"
}

# Iniciar servicios
start_services() {
    echo -e "${YELLOW}- Iniciando servicios...${NC}"
    
    /etc/init.d/openvpn enable
    /etc/init.d/openvpn start
    check_status
    
    echo -e "${GREEN}- Servicios iniciados${NC}"
}

# Mostrar resumen final
show_summary() {
    echo -e "\n${GREEN}=== CONFIGURACIÓN COMPLETADA PARA CUDY TR3000 ===${NC}"
    echo -e "Dispositivo bridge: br-vpn"
    echo -e "Puertos del bridge: eth0, tap0"
    echo -e "Interfaz VPN: br-vpn"
    echo -e "OpenVPN: activado y ejecutándose"
    echo -e "WiFi: desactivado"
    
    echo -e "\n${YELLOW}- Estado del bridge br-vpn:${NC}"
    brctl show br-vpn 2>/dev/null || {
        echo -e "${YELLOW}- Comando brctl no disponible, mostrando interfaces...${NC}"
        ip link show br-vpn
    }
    
    echo -e "\n${YELLOW}- Interfaces de red:${NC}"
    ip link show | grep -E "(eth0|tap0|br-vpn)" | grep -v "link/"
    
    echo -e "\n${YELLOW}- Configuración de puertos del bridge:${NC}"
    uci show network.br-vpn.ports
}

# Función principal
main() {
    echo -e "${YELLOW}- Iniciando configuración OpenVPN para Cudy TR3000...${NC}"
    
    # Verificar que es un TR3000
    verify_tr3000
    
    # Verificar compatibilidad
    check_compatibility
    
    # Actualizar paquetes
    echo -e "${YELLOW}- Actualizando paquetes...${NC}"
    opkg update
    check_status
    
    # Instalar OpenVPN
    echo -e "${YELLOW}- Instalando OpenVPN...${NC}"
    opkg install openvpn-easy-rsa openvpn-openssl luci-app-openvpn
    check_status
    
    # Detectar interfaz WAN
    detect_wan_interface
    
    # Configurar client.ovpn
    if [ -f /etc/openvpn/client.ovpn ]; then
        echo -e "${YELLOW}- client.ovpn existe, ¿sobrescribir? (s/n)${NC}"
        read -r response
        case "$response" in
            [sS]*) create_client_ovpn ;;
            *) echo -e "${YELLOW}- Manteniendo archivo existente${NC}" ;;
        esac
    else
        create_client_ovpn
    fi
    
    # Configurar OpenVPN
    configure_openvpn
    
    # Configurar bridge específico para TR3000
    configure_tr3000_bridge
    
    # Desactivar WiFi
    disable_wifi
    
    # Aplicar configuración
    apply_configuration
    
    # Iniciar servicios
    start_services
    
    # Mostrar resumen
    show_summary
    
    # Preguntar por reinicio
    echo -e "\n${YELLOW}¿Reiniciar dispositivo? (s/n)${NC}"
    echo -e "${YELLOW}(Recomendado para aplicar cambios completamente)${NC}"
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
    
    echo -e "\n${GREEN}¡Configuración completada para Cudy TR3000!${NC}"
}

# Ejecutar función principal
main
