#!/bin/sh

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Variable para el nombre de la instancia VPN
VPN_NAME=""

check_status() {
    if [ $? -ne 0 ]; then
        echo -e "${RED}- Ha ocurrido un error${NC}"
        exit 1
    fi
}

# Solicitar nombre para la instancia VPN
get_vpn_name() {
    echo -e "${YELLOW}- Configuración del nombre de la instancia VPN${NC}"
    echo -e "${YELLOW}Nombre actual de la instancia: custom_vpn${NC}"
    echo -e "${YELLOW}¿Desea cambiar el nombre? (s/n)${NC}"
    read -r change_name
    
    case "$change_name" in
        [sS]*)
            echo -e "${YELLOW}Ingrese el nuevo nombre (solo letras, números y guiones bajos):${NC}"
            read -r new_name
            
            # Validar el nombre
            if echo "$new_name" | grep -qE '^[a-zA-Z0-9_]+$'; then
                VPN_NAME="$new_name"
                echo -e "${GREEN}- Nombre cambiado a: $VPN_NAME${NC}"
            else
                echo -e "${RED}- Nombre inválido. Usando 'custom_vpn' por defecto${NC}"
                VPN_NAME="custom_vpn"
            fi
            ;;
        *)
            VPN_NAME="custom_vpn"
            echo -e "${YELLOW}- Usando nombre por defecto: custom_vpn${NC}"
            ;;
    esac
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

# Obtener configuración de red actual
get_current_network_config() {
    echo -e "${YELLOW}- Obteniendo configuración de red actual...${NC}"
    
    # Obtener IP actual de la interfaz LAN
    CURRENT_LAN_IP=$(uci get network.lan.ipaddr 2>/dev/null)
    if [ -z "$CURRENT_LAN_IP" ]; then
        CURRENT_LAN_IP="192.168.1.1"
    fi
    
    # Obtener interfaz LAN actual
    CURRENT_LAN_DEVICE=$(uci get network.lan.device 2>/dev/null)
    if [ -z "$CURRENT_LAN_DEVICE" ]; then
        CURRENT_LAN_DEVICE="br-lan"
    fi
    
    echo -e "${GREEN}- IP LAN actual: $CURRENT_LAN_IP${NC}"
    echo -e "${GREEN}- Dispositivo LAN actual: $CURRENT_LAN_DEVICE${NC}"
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

# Crear bridge br-vpn sin afectar la LAN
create_bridge_device() {
    echo -e "${YELLOW}- Creando dispositivo bridge br-vpn...${NC}"
    
    # Primero eliminar cualquier configuración previa del bridge VPN
    uci delete network.br-vpn 2>/dev/null
    
    # Buscar y eliminar dispositivo br-vpn si existe
    local device_index=0
    while uci get network.@device[$device_index] >/dev/null 2>&1; do
        if [ "$(uci get network.@device[$device_index].name 2>/dev/null)" = "br-vpn" ]; then
            uci delete network.@device[$device_index]
            break
        fi
        device_index=$((device_index + 1))
    done
    
    # Crear nuevo dispositivo bridge para VPN
    uci add network device
    uci set network.@device[-1].name='br-vpn'
    uci set network.@device[-1].type='bridge'
    
    # Solo usar eth0 para VPN en el bridge VPN, NO eth1
    uci set network.@device[-1].ports='eth0 tap0'
    
    uci set network.@device[-1].ipv6='0'
    uci set network.@device[-1].igmp_snooping='1'
    uci set network.@device[-1].stp='0'
    uci set network.@device[-1].forward_delay='0'
    uci set network.@device[-1].enabled='1'
    
    echo -e "${GREEN}- Dispositivo bridge br-vpn creado con puertos: eth0 tap0${NC}"
    echo -e "${YELLOW}- NOTA: eth1 se mantiene para la LAN${NC}"
}

# Configurar interfaces de red manteniendo accesibilidad (SIN WAN)
configure_network_interfaces() {
    echo -e "${YELLOW}- Configurando interfaces de red (LAN y VPN solamente)...${NC}"
    
    # Configurar interfaz LAN (br-lan) - MANTENER ACCESIBILIDAD
    uci set network.lan.proto='static'
    uci set network.lan.ipaddr='192.168.1.2'
    uci set network.lan.netmask='255.255.255.0'
    uci set network.lan.device='br-lan'
    uci set network.lan.force_link='1'
    
    # ELIMINAR INTERFACES WAN
    echo -e "${YELLOW}- Eliminando interfaces WAN...${NC}"
    uci delete network.wan 2>/dev/null
    uci delete network.wan6 2>/dev/null
    
    # Configurar interfaz VPN - CORREGIDO
    echo -e "${YELLOW}- Configurando interfaz VPN...${NC}"
    uci delete network.vpn 2>/dev/null
    uci set network.vpn=interface
    uci set network.vpn.proto='none'
    uci set network.vpn.device='br-vpn'
    uci set network.vpn.auto='1'
    
    echo -e "${GREEN}- Interfaces de red configuradas${NC}"
    echo -e "${GREEN}- LAN: 192.168.1.2 en br-lan (eth1)${NC}"
    echo -e "${GREEN}- VPN: br-vpn (eth0 + tap0)${NC}"
    echo -e "${GREEN}- WAN: ELIMINADA${NC}"
}

# Verificar y configurar TAP manualmente
setup_tap_interface() {
    echo -e "${YELLOW}- Configurando interfaz TAP...${NC}"
    
    # Instalar kmod-tun si no está instalado
    if ! opkg list-installed | grep -q kmod-tun; then
        echo -e "${YELLOW}- Instalando kmod-tun...${NC}"
        opkg update
        opkg install kmod-tun
    fi
    
    # Crear interfaz tap0 si no existe
    if ! ip link show tap0 >/dev/null 2>&1; then
        echo -e "${YELLOW}- Creando interfaz tap0...${NC}"
        ip tuntap add mode tap tap0
        ip link set tap0 up
        echo -e "${GREEN}- Interfaz tap0 creada y activada${NC}"
    else
        echo -e "${GREEN}- Interfaz tap0 ya existe${NC}"
        ip link set tap0 up
    fi
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
    
    # Asegurarse de que use TAP
    if ! grep -q "dev tap" /etc/openvpn/client.ovpn && ! grep -q "dev tap0" /etc/openvpn/client.ovpn; then
        echo -e "${YELLOW}- Añadiendo configuración dev tap0 al archivo client.ovpn...${NC}"
        echo "" >> /etc/openvpn/client.ovpn
        echo "# Configuración añadida automáticamente" >> /etc/openvpn/client.ovpn
        echo "dev tap0" >> /etc/openvpn/client.ovpn
        echo "persist-tun" >> /etc/openvpn/client.ovpn
        echo "persist-key" >> /etc/openvpn/client.ovpn
    fi
    
    echo -e "${GREEN}- client.ovpn creado exitosamente${NC}"
}

# Configurar OpenVPN
configure_openvpn() {
    echo -e "${YELLOW}- Configurando servicio OpenVPN...${NC}"
    
    if [ ! -f /etc/config/openvpn ]; then
        cat <<EOF > /etc/config/openvpn
config openvpn '$VPN_NAME'
    option enabled '1'
    option config '/etc/openvpn/client.ovpn'

EOF
    else
        # Limpiar configuraciones previas de openvpn con el mismo nombre
        uci delete openvpn.$VPN_NAME 2>/dev/null
        uci set openvpn.$VPN_NAME=openvpn
        uci set openvpn.$VPN_NAME.enabled='1'
        uci set openvpn.$VPN_NAME.config='/etc/openvpn/client.ovpn'
    fi
    
    uci commit openvpn
    echo -e "${GREEN}- Configuración OpenVPN '$VPN_NAME' completada${NC}"
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
            uci commit wireless
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
    
    # Recargar configuración de red
    echo -e "${YELLOW}- Recargando configuración de red...${NC}"
    /etc/init.d/network reload
    sleep 5
    
    echo -e "${GREEN}- Configuración aplicada${NC}"
}

# Iniciar servicios
start_services() {
    echo -e "${YELLOW}- Iniciando servicios...${NC}"
    
    # Asegurarse de que la interfaz TAP esté creada
    setup_tap_interface
    
    /etc/init.d/openvpn enable
    /etc/init.d/openvpn restart
    check_status
    
    echo -e "${GREEN}- Servicios iniciados${NC}"
}

# Limpiar instancias de OpenVPN no deseadas
cleanup_openvpn_instances() {
    echo -e "${YELLOW}- Limpiando instancias de OpenVPN no deseadas...${NC}"
    
    # Lista de instancias a eliminar (excluyendo la instancia actual)
    UNWANTED_INSTANCES="custom_config sample_server sample_client custom_vpn"
    
    for instance in $UNWANTED_INSTANCES; do
        # No eliminar la instancia actual si coincide con algún nombre de la lista
        if [ "$instance" != "$VPN_NAME" ] && uci get openvpn.$instance >/dev/null 2>&1; then
            uci delete openvpn.$instance
            echo -e "${GREEN}- Eliminado: $instance${NC}"
        fi
    done
    
    uci commit openvpn
    echo -e "${GREEN}- Instancias de OpenVPN limpiadas${NC}"
    echo -e "${GREEN}- Instancia activa: $VPN_NAME${NC}"
}

# Eliminar completamente WAN al final
remove_wan_completely() {
    echo -e "${YELLOW}- Eliminación completa de interfaces WAN...${NC}"
    
    # Eliminar cualquier interfaz WAN residual
    uci delete network.wan 2>/dev/null
    uci delete network.wan6 2>/dev/null
    
    # Buscar y eliminar cualquier otra interfaz que pueda ser WAN
    local interface_index=0
    while uci get network.@interface[$interface_index] >/dev/null 2>&1; do
        local ifname=$(uci get network.@interface[$interface_index].ifname 2>/dev/null)
        local device=$(uci get network.@interface[$interface_index].device 2>/dev/null)
        
        # Si la interfaz usa eth0 o parece ser WAN, eliminarla (excepto VPN)
        if [ "$ifname" = "eth0" ] || [ "$device" = "br-vpn" ] || \
           echo "$(uci get network.@interface[$interface_index].proto 2>/dev/null)" | grep -q "dhcp"; then
            local interface_name=$(uci get network.@interface[$interface_index].interface 2>/dev/null)
            if [ "$interface_name" != "vpn" ] && [ "$interface_name" != "lan" ]; then
                echo -e "${YELLOW}- Eliminando interfaz residual: $interface_name${NC}"
                uci delete network.@interface[$interface_index]
                continue
            fi
        fi
        interface_index=$((interface_index + 1))
    done
    
    uci commit network
    echo -e "${GREEN}- Limpieza completa de WAN realizada${NC}"
}

# Verificar configuración de interfaces
verify_network_config() {
    echo -e "${YELLOW}- Verificando configuración de interfaces...${NC}"
    
    # Mostrar todas las interfaces
    echo -e "${YELLOW}- Interfaces configuradas:${NC}"
    uci show network | grep "network.*=interface" | cut -d'.' -f2 | cut -d'=' -f1
    
    # Verificar interfaz LAN
    echo -e "${YELLOW}- Configuración LAN:${NC}"
    uci show network.lan
    
    # Verificar interfaz VPN
    echo -e "${YELLOW}- Configuración VPN:${NC}"
    if uci get network.vpn >/dev/null 2>&1; then
        uci show network.vpn
    else
        echo -e "${RED}- ERROR: Interfaz VPN no existe${NC}"
        # Crear la interfaz VPN si no existe
        echo -e "${YELLOW}- Creando interfaz VPN...${NC}"
        uci set network.vpn=interface
        uci set network.vpn.proto='none'
        uci set network.vpn.device='br-vpn'
        uci set network.vpn.auto='1'
        uci commit network
        /etc/init.d/network reload
        echo -e "${GREEN}- Interfaz VPN creada${NC}"
    fi
    
    # Verificar bridge br-vpn
    echo -e "${YELLOW}- Verificando bridge br-vpn:${NC}"
    if ip link show br-vpn >/dev/null 2>&1; then
        echo -e "${GREEN}- Bridge br-vpn activo${NC}"
        brctl show br-vpn
    else
        echo -e "${RED}- ERROR: Bridge br-vpn no existe${NC}"
    fi
    
    # Verificar interfaces de red
    echo -e "${YELLOW}- Interfaces de red activas:${NC}"
    ip addr show | grep -E "(eth|br-|tap)" | grep inet || echo "No hay direcciones IP asignadas"
}

# Mostrar resumen final y advertencias
show_summary() {
    echo -e "\n${GREEN}=== CONFIGURACIÓN COMPLETADA PARA CUDY TR3000 ===${NC}"
    echo -e "${GREEN}- Dispositivo bridge: br-vpn${NC}"
    echo -e "${GREEN}- Puertos del bridge: eth0 tap0${NC}"
    echo -e "${GREEN}- Interfaz VPN: br-vpn${NC}"
    echo -e "${GREEN}- Interfaz LAN: br-lan (eth1)${NC}"
    echo -e "${GREEN}- OpenVPN: activado y ejecutándose${NC}"
    echo -e "${GREEN}- Instancia OpenVPN: $VPN_NAME${NC}"
    echo -e "${GREEN}- WiFi: desactivado${NC}"
    echo -e "${GREEN}- WAN: ELIMINADA${NC}"
    echo -e "${GREEN}- IP de administración: 192.168.1.2${NC}"
    
    # Verificar instancias OpenVPN
    echo -e "\n${YELLOW}- Instancias OpenVPN activas:${NC}"
    uci show openvpn | grep "=openvpn" | cut -d'.' -f2 | cut -d'=' -f1
    
    echo -e "\n${YELLOW}=== IMPORTANTE ===${NC}"
    echo -e "${YELLOW}- El dispositivo sigue accesible en: ${GREEN}http://192.168.1.2${NC}"
    echo -e "${YELLOW}- eth1 se mantiene en br-lan para la LAN${NC}"
    echo -e "${YELLOW}- eth0 se usa para VPN en el bridge br-vpn${NC}"
    echo -e "${YELLOW}- No hay interfaz WAN configurada${NC}"
    
    # Verificación final
    verify_network_config
}

# Función principal
main() {
    echo -e "${YELLOW}- Iniciando configuración OpenVPN para Cudy TR3000...${NC}"
    
    # Solicitar nombre de la instancia VPN
    get_vpn_name
    
    # Verificar que es un TR3000
    verify_tr3000
    
    # Obtener configuración actual
    get_current_network_config
    
    # Verificar compatibilidad
    check_compatibility
    
    # Actualizar paquetes
    echo -e "${YELLOW}- Actualizando paquetes...${NC}"
    opkg update
    check_status
    
    # Instalar OpenVPN y dependencias
    echo -e "${YELLOW}- Instalando OpenVPN y dependencias...${NC}"
    opkg install openvpn-openssl luci-app-openvpn kmod-tun
    check_status
    
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
    
    # Crear dispositivo bridge
    create_bridge_device
    
    # Configurar interfaces de red (sin WAN)
    configure_network_interfaces
    
    # Configurar interfaz TAP
    setup_tap_interface
    
    # Desactivar WiFi
    disable_wifi
    
    # Aplicar configuración
    apply_configuration
    
    # Iniciar servicios
    start_services
    
    # Limpiar instancias de OpenVPN no deseadas
    cleanup_openvpn_instances
    
    # Eliminación completa de WAN al final
    remove_wan_completely
    
    # Mostrar resumen
    show_summary
    
    echo -e "\n${YELLOW}¿Reiniciar dispositivo? (s/n)${NC}"
    echo -e "${YELLOW}(Recomendado para aplicar cambios completamente)${NC}"
    echo -e "${RED}ADVERTENCIA: Si pierde acceso, conecte por cable y use la IP 192.168.1.2${NC}"
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
