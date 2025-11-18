#!/bin/sh

# Función para verificar si el comando se ejecutó correctamente
check_status() {
    if [ $? -ne 0 ]; then
        echo -e "\033[31m- Ha ocurrido un error\033[0m"
        exit 1
    fi
}

# Función para validar token DuckDNS
validar_token() {
    local token=$1
    if echo "$token" | grep -qE '^[a-f0-9-]{20,36}$'; then
        return 0
    else
        return 1
    fi
}

# Función para verificar puerto
verificar_puerto() {
    local puerto=$1
    if netstat -tulpn 2>/dev/null | grep ":$puerto " >/dev/null; then
        return 1
    else
        return 0
    fi
}

# Función para crear backup del firmware
crear_backup_firmware() {
    echo -e "\n\033[36m=== CREANDO BACKUP DEL FIRMWARE ===\033[0m"
    
    # Verificar si sysupgrade está disponible
    if ! command -v sysupgrade >/dev/null 2>&1; then
        echo -e "\033[33m- sysupgrade no disponible, instalando...\033[0m"
        opkg update
        opkg install sysupgrade
        check_status
    fi
    
    # Crear nombre único para el backup
    FIRMWARE_BACKUP="/root/backup_firmware_$(date +%Y%m%d_%H%M%S).bin"
    
    echo "- Creando backup del firmware..."
    if sysupgrade -b "$FIRMWARE_BACKUP" 2>/dev/null; then
        echo -e "\033[32m- Backup del firmware creado: $FIRMWARE_BACKUP\033[0m"
        echo -e "\033[33m- Tamaño: $(du -h $FIRMWARE_BACKUP | cut -f1)\033[0m"
        return 0
    else
        echo -e "\033[31m- No se pudo crear el backup del firmware\033[0m"
        echo -e "\033[33m- Esto es normal en algunas versiones de OpenWrt\033[0m"
        return 1
    fi
}

# Función para crear backup completo de configuración AL FINAL
crear_backup_configuracion() {
    echo -e "\n\033[36m=== CREANDO BACKUP COMPLETO DE CONFIGURACIÓN ===\033[0m"
    
    BACKUP_DIR="/root/backup_openvpn_completo_$(date +%Y%m%d_%H%M%S)"
    mkdir -p $BACKUP_DIR
    
    echo "- Copiando configuraciones INSTALADAS..."
    
    # 1. ARCHIVOS DE CONFIGURACIÓN PRINCIPALES
    cp /etc/config/network $BACKUP_DIR/ 2>/dev/null
    cp /etc/config/openvpn $BACKUP_DIR/ 2>/dev/null
    cp /etc/config/ddns $BACKUP_DIR/ 2>/dev/null
    cp /etc/config/firewall $BACKUP_DIR/ 2>/dev/null
    cp /etc/config/dhcp $BACKUP_DIR/ 2>/dev/null
    cp /etc/config/system $BACKUP_DIR/ 2>/dev/null
    
    # 2. CERTIFICADOS OPENVPN GENERADOS
    mkdir -p $BACKUP_DIR/openvpn
    cp /etc/openvpn/*.crt $BACKUP_DIR/openvpn/ 2>/dev/null
    cp /etc/openvpn/*.key $BACKUP_DIR/openvpn/ 2>/dev/null
    cp /etc/openvpn/*.pem $BACKUP_DIR/openvpn/ 2>/dev/null
    cp /etc/openvpn/*.ovpn $BACKUP_DIR/openvpn/ 2>/dev/null
    cp /etc/openvpn/clientes_openvpn.tar.gz $BACKUP_DIR/openvpn/ 2>/dev/null
    
    # 3. EASY-RSA CON CERTIFICADOS GENERADOS
    mkdir -p $BACKUP_DIR/easy-rsa
    cp -r /etc/easy-rsa/* $BACKUP_DIR/easy-rsa/ 2>/dev/null
    
    # 4. CONFIGURACIONES DE SERVICIOS
    mkdir -p $BACKUP_DIR/services
    cp /etc/rc.local $BACKUP_DIR/services/ 2>/dev/null
    
    # 5. INFORMACIÓN DEL SISTEMA CON OPENVPN INSTALADO
    echo "- Guardando información del sistema..."
    date > $BACKUP_DIR/fecha_backup.txt
    cat /etc/openwrt_release > $BACKUP_DIR/openwrt_info.txt 2>/dev/null
    uname -a > $BACKUP_DIR/system_info.txt
    df -h > $BACKUP_DIR/disk_usage.txt
    opkg list-installed > $BACKUP_DIR/paquetes_instalados.txt
    
    # 6. CONFIGURACIÓN ACTUAL DE RED
    ifconfig > $BACKUP_DIR/network_interfaces.txt
    netstat -tulpn > $BACKUP_DIR/network_ports.txt
    ps w > $BACKUP_DIR/processes_running.txt
    
    # 7. CREAR CHECKSUM DE VERIFICACIÓN
    find $BACKUP_DIR -type f -exec md5sum {} \; > $BACKUP_DIR/checksums.md5 2>/dev/null
    
    # 8. COMPRIMIR BACKUP
    echo "- Comprimiendo backup completo..."
    tar -czf ${BACKUP_DIR}.tar.gz -C /root/ $(basename $BACKUP_DIR) 2>/dev/null
    
    # VERIFICAR COMPRESIÓN
    if [ -f "${BACKUP_DIR}.tar.gz" ]; then
        rm -rf $BACKUP_DIR  # Eliminar directorio sin comprimir
        BACKUP_FILE="${BACKUP_DIR}.tar.gz"
        echo -e "\033[32m- ✓ Backup COMPLETO creado: $BACKUP_FILE\033[0m"
        echo -e "\033[33m- Tamaño: $(du -h $BACKUP_FILE | cut -f1)\033[0m"
        return 0
    else
        echo -e "\033[31m- Error al comprimir el backup\033[0m"
        echo -e "\033[32m- Backup en directorio: $BACKUP_DIR\033[0m"
        return 1
    fi
}

# --- COMIENZO DEL SCRIPT PRINCIPAL ---

echo -e "\033[36m=== CONFIGURACIÓN SERVIDOR OPENVPN + DUCKDNS (CRIS) ===\033[0m"

# Parte 1: Configuración dinámica

# Preguntar si instalar DuckDNS
echo -e "\033[33m- ¿Quieres instalar y configurar DuckDNS? (s/n):\033[0m"
read -p "Instalar DuckDNS: " INSTALAR_DUCKDNS

if [ "$INSTALAR_DUCKDNS" = "s" ] || [ "$INSTALAR_DUCKDNS" = "S" ]; then
    # Instalar TODOS los paquetes DDNS
    echo "- Instalando DuckDNS y complementos..."
    opkg update
    opkg install ddns-scripts ddns-scripts-duckdns luci-app-ddns
    check_status
    
    # Configuración avanzada de DuckDNS
    echo -e "\033[33m- Configuración avanzada de DuckDNS:\033[0m"
    
    while true; do
        read -p "Tu dominio DuckDNS (SOLO el nombre, ej: midominio): " DUCKDNS_DOMAIN
        if [ -n "$DUCKDNS_DOMAIN" ]; then
            break
        else
            echo -e "\033[31m- Error: El dominio no puede estar vacío\033[0m"
        fi
    done
    
    while true; do
        read -p "Token de DuckDNS: " DUCKDNS_TOKEN
        if validar_token "$DUCKDNS_TOKEN"; then
            break
        else
            echo -e "\033[31m- Error: Formato de token inválido\033[0m"
            echo -e "\033[33m- El token debe ser un string hexadecimal con guiones\033[0m"
        fi
    done
    
    DOMAIN_COMPLETO="${DUCKDNS_DOMAIN}.duckdns.org"
    
    echo "- Configurando DuckDNS con opciones avanzadas..."
    
    # Eliminar configuraciones existentes de DDNS
    while uci delete ddns.@service[0] 2>/dev/null; do :; done
    
    # Crear nueva configuración DuckDNS
    uci add ddns service
    uci set ddns.@service[-1].enabled='1'
    uci set ddns.@service[-1].service_name='duckdns.org'
    uci set ddns.@service[-1].domain="$DOMAIN_COMPLETO"
    uci set ddns.@service[-1].lookup_host="$DOMAIN_COMPLETO"
    uci set ddns.@service[-1].username="$DUCKDNS_DOMAIN"
    uci set ddns.@service[-1].password="$DUCKDNS_TOKEN"
    uci set ddns.@service[-1].interface='wan'
    
    # Configuración avanzada
    uci set ddns.@service[-1].ip_source='url'
    uci set ddns.@service[-1].ip_url='http://checkip.dyndns.com'
    uci set ddns.@service[-1].ip_network='wan'
    
    # Timer settings
    uci set ddns.@service[-1].check_interval='300'
    uci set ddns.@service[-1].force_interval='5'
    uci set ddns.@service[-1].force_unit='minutes'
    
    uci commit ddns
    check_status
    
    # Habilitar e iniciar servicio
    /etc/init.d/ddns enable
    /etc/init.d/ddns start
    check_status
    
    DDNS_SERVER="$DOMAIN_COMPLETO"
    echo -e "\033[32m- DuckDNS configurado avanzado: $DDNS_SERVER\033[0m"
    
else
    # Usar DDNS manual
    echo -e "\033[33m- Introduce tu DDNS o IP pública:\033[0m"
    while true; do
        read -p "DDNS o IP: " DDNS_SERVER
        if [ -n "$DDNS_SERVER" ]; then
            break
        else
            echo -e "\033[31m- Error: Debes introducir un DDNS o IP\033[0m"
        fi
    done
fi

# Pedir puerto con verificación
while true; do
    echo -e "\033[33m- Introduce el puerto OpenVPN (Enter para 1194):\033[0m"
    read -p "Puerto: " VPN_PORT
    VPN_PORT=${VPN_PORT:-1194}
    
    if verificar_puerto "$VPN_PORT"; then
        break
    else
        echo -e "\033[31m- Error: El puerto $VPN_PORT ya está en uso\033[0m"
        echo -e "\033[33m- Elige otro puerto\033[0m"
    fi
done

# Pedir número de clientes
echo -e "\033[33m- Número de clientes a crear (Enter para 4):\033[0m"
read -p "Clientes: " NUM_CLIENTES
NUM_CLIENTES=${NUM_CLIENTES:-4}

echo -e "\033[32m- Configurando servidor: $DDNS_SERVER:$VPN_PORT\033[0m"
echo -e "\033[32m- Creando $NUM_CLIENTES clientes\033[0m"

# Parte 2: Instalación de OpenVPN
echo "- Instalando OpenVPN y herramientas..."
opkg install openvpn-easy-rsa openvpn-openssl luci-app-openvpn nano
check_status

# Verificar la instalación
echo "- Paquetes instalados:"
opkg list-installed | grep -E 'openvpn-easy-rsa|openvpn-openssl|luci-app-openvpn|nano'
echo -e "\033[32m- Instalación completada.\033[0m"

# Parte 3: Generación de certificados
cd /etc/easy-rsa
check_status

# Configurar easy-rsa
sed -i 's/#set_var EASYRSA_CA_EXPIRE.*/set_var EASYRSA_CA_EXPIRE      99999/' vars
sed -i 's/#set_var EASYRSA_CERT_EXPIRE.*/set_var EASYRSA_CERT_EXPIRE    99999/' vars
check_status

echo -e "yes\nyes" | easyrsa init-pki
check_status

# Crear CA y certificados
echo -e "yes\nserver" | easyrsa build-ca nopass
check_status

echo -e "yes" | easyrsa build-server-full server nopass
check_status

# Crear certificados clientes
echo -e "\033[32m- Generando certificados para $NUM_CLIENTES clientes...\033[0m"
for i in $(seq 1 $NUM_CLIENTES); do
    echo "- Generando certificado para client$i..."
    echo -e "yes" | easyrsa build-client-full client$i nopass
    check_status
    echo -e "\033[32m- Certificado para client$i generado con éxito.\033[0m"
done

# Generar DH
easyrsa gen-dh
check_status

# Copiar archivos
cp /etc/easy-rsa/pki/ca.crt /etc/openvpn/
cp /etc/easy-rsa/pki/private/server.key /etc/openvpn/
cp /etc/easy-rsa/pki/issued/server.crt /etc/openvpn/
cp /etc/easy-rsa/pki/dh.pem /etc/openvpn/
check_status

# Configuración OpenVPN servidor
cat > /etc/config/openvpn <<EOF
config openvpn 'VPN_Tap_Server'
    option enabled '1'
    option mode 'server'
    option dev 'tap0' 
    option proto 'udp'
    option port '$VPN_PORT'
    option float '1'
    option persist_key '1'
    option persist_tun '1'
    option keepalive '10 60'
    option cipher 'AES-256-GCM'
    option reneg_sec '0'
    option verb '5'
    option client_to_client '1'
    option remote_cert_tls 'client'
    option tls_server '1'
    option ca '/etc/openvpn/ca.crt'
    option cert '/etc/openvpn/server.crt'
    option key '/etc/openvpn/server.key'
    option dh '/etc/openvpn/dh.pem'
EOF
check_status

# Configurar firewall
echo "- Configurando firewall..."
uci add firewall rule
uci set firewall.@rule[-1].name='Allow-OpenVPN'
uci set firewall.@rule[-1].src='wan'
uci set firewall.@rule[-1].proto='udp'
uci set firewall.@rule[-1].dest_port="$VPN_PORT"
uci set firewall.@rule[-1].target='ACCEPT'
uci commit firewall
/etc/init.d/firewall restart
check_status
echo -e "\033[32m- Firewall configurado para puerto $VPN_PORT\033[0m"

# Parte 4: Generación de archivos .ovpn con ambas opciones de guardado
CLIENTS=()
for i in $(seq 1 $NUM_CLIENTES); do
    CLIENTS+=("client$i")
done

for CLIENT_NAME in "${CLIENTS[@]}"; do
    echo "- Generando $CLIENT_NAME.ovpn..."
    
    cat > /etc/openvpn/${CLIENT_NAME}.ovpn <<EOF
client
dev tap
proto udp
remote $DDNS_SERVER $VPN_PORT
resolv-retry infinite
nobind
float
data-ciphers AES-256-GCM
keepalive 15 60
remote-cert-tls server
route-nopull
route-noexec
mute-replay-warnings
<ca>
$(cat /etc/openvpn/ca.crt)
</ca>
<cert>
$(sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' /etc/easy-rsa/pki/issued/${CLIENT_NAME}.crt)
</cert>
<key>
$(cat /etc/easy-rsa/pki/private/${CLIENT_NAME}.key)
</key>
EOF
    check_status
    
    # OPCIÓN 1: Crear copia en /tmp/ para fácil acceso
    cp /etc/openvpn/${CLIENT_NAME}.ovpn /tmp/${CLIENT_NAME}.ovpn
    echo -e "\033[32m- Copia creada en: /tmp/${CLIENT_NAME}.ovpn\033[0m"
    
    # Obtener IP del router para el comando SCP
    ROUTER_IP=$(uci get network.lan.ipaddr 2>/dev/null | cut -d'/' -f1)
    if [ -z "$ROUTER_IP" ]; then
        ROUTER_IP="IP_DEL_ROUTER"
    fi
    
    echo -e "\033[33m- Para descargar: scp root@$ROUTER_IP:/tmp/${CLIENT_NAME}.ovpn .\033[0m"
    
    # OPCIÓN 2: Mostrar contenido para copiar manualmente
    echo -e "\033[33m- ¿Quieres ver el contenido completo para copiarlo? (s/n):\033[0m"
    read -p "Ver contenido: " VER_CONTENIDO
    
    if [ "$VER_CONTENIDO" = "s" ] || [ "$VER_CONTENIDO" = "S" ]; then
        echo -e "\n\033[35m"  # Color magenta para el contenido
        echo "╔══════════════════════════════════════════════════════════════╗"
        echo "║                 INICIO ${CLIENT_NAME}.ovpn                   ║"
        echo "╚══════════════════════════════════════════════════════════════╝"
        echo -e "\033[0m"
        
        cat /etc/openvpn/${CLIENT_NAME}.ovpn
        
        echo -e "\033[35m"
        echo "╔══════════════════════════════════════════════════════════════╗"
        echo "║                 FIN ${CLIENT_NAME}.ovpn                      ║"
        echo "╚══════════════════════════════════════════════════════════════╝"
        echo -e "\033[0m"
        
        echo -e "\033[32m- Contenido mostrado arriba. Puedes copiarlo y guardarlo.\033[0m"
        echo -e "\033[33m- Presiona Enter para continuar...\033[0m"
        read -p ""
    else
        echo -e "\033[32m- ${CLIENT_NAME}.ovpn generado correctamente\033[0m"
    fi
    
    echo -e "\033[32m- ✓ ${CLIENT_NAME}.ovpn completado\033[0m"
    echo ""

    # Preguntar si quiere procesar el siguiente cliente inmediatamente
    if [ "$i" -lt "$NUM_CLIENTES" ]; then
        echo -e "\033[33m- ¿Continuar con el siguiente cliente? (s/n):\033[0m"
        read -p "Continuar: " CONTINUAR
        if [ "$CONTINUAR" != "s" ] && [ "$CONTINUAR" != "S" ]; then
            echo -e "\033[33m- Continuando automáticamente en 5 segundos...\033[0m"
            sleep 5
        fi
    fi
done

# Crear bundle
tar -czf /etc/openvpn/clientes_openvpn.tar.gz -C /etc/openvpn/ *.ovpn
check_status

# Configurar red
sed -i "/option name 'br-lan'/a \    option igmp_snooping '1'" /etc/config/network
sed -i "/option igmp_snooping '1'/a \    list ports 'tap0'" /etc/config/network
check_status

# Reiniciar servicios
/etc/init.d/network restart
/etc/init.d/openvpn enable
/etc/init.d/openvpn start
check_status

# Verificación de servicios
echo "- Verificando servicios..."
sleep 10

echo -e "\n\033[36m=== VERIFICACIÓN FINAL ===\033[0m"
if pgrep openvpn >/dev/null; then
    echo -e "\033[32m- OpenVPN funcionando ✓\033[0m"
else
    echo -e "\033[31m- OpenVPN no está corriendo\033[0m"
fi

if ifconfig tap0 >/dev/null 2>&1; then
    echo -e "\033[32m- Interfaz tap0 activa ✓\033[0m"
else
    echo -e "\033[31m- Interfaz tap0 no activa\033[0m"
fi

if netstat -tulpn | grep ":$VPN_PORT " >/dev/null; then
    echo -e "\033[32m- Puerto $VPN_PORT escuchando ✓\033[0m"
else
    echo -e "\033[31m- Puerto $VPN_PORT no escuchando\033[0m"
fi

# --- CREAR BACKUPS AL FINAL CON TODO INSTALADO ---
echo -e "\n\033[36m=== CREANDO BACKUPS FINALES ===\033[0m"

# 1. Backup de configuración COMPLETA (con todo instalado)
if crear_backup_configuracion; then
    BACKUP_CONFIG_FILE="$BACKUP_FILE"
    BACKUP_CONFIG_EXITOSO=true
else
    BACKUP_CONFIG_EXITOSO=false
fi

# 2. Backup del firmware (si es posible)
if crear_backup_firmware; then
    FIRMWARE_BACKUP_CREADO=true
else
    FIRMWARE_BACKUP_CREADO=false
fi

# EXTRA: Resumen de archivos disponibles
echo -e "\n\033[36m=== RESUMEN DE ARCHIVOS GENERADOS ===\033[0m"
echo -e "\033[32m- Archivos originales en /etc/openvpn/:\033[0m"
for CLIENT_NAME in "${CLIENTS[@]}"; do
    echo -e "  • /etc/openvpn/${CLIENT_NAME}.ovpn"
done

echo -e "\033[32m- Copias temporales en /tmp/ (fácil acceso):\033[0m"
for CLIENT_NAME in "${CLIENTS[@]}"; do
    echo -e "  • /tmp/${CLIENT_NAME}.ovpn"
done

echo -e "\033[32m- Bundle completo:\033[0m"
echo -e "  • /etc/openvpn/clientes_openvpn.tar.gz"

# Mostrar comandos de descarga
echo -e "\n\033[33m=== COMANDOS PARA DESCARGAR ===\033[0m"
echo -e "\033[33m- Descargar cliente específico:\033[0m"
echo -e "  scp root@$ROUTER_IP:/tmp/client1.ovpn ."

echo -e "\033[33m- Descargar todos los clientes:\033[0m"
echo -e "  scp root@$ROUTER_IP:/etc/openvpn/clientes_openvpn.tar.gz ."

echo -e "\033[33m- O extraer del bundle:\033[0m"
echo -e "  tar -xzf clientes_openvpn.tar.gz"

# Crear reporte final
cat > /root/openvpn_config_summary.txt <<EOF
=== CONFIGURACIÓN OPENVPN SERVIDOR ===
Fecha: $(date)
Servidor: $DDNS_SERVER:$VPN_PORT
Clientes creados: $NUM_CLIENTES

ARCHIVOS GENERADOS:
- /etc/openvpn/ca.crt
- /etc/openvpn/server.crt  
- /etc/openvpn/server.key
- /etc/openvpn/dh.pem
- /etc/openvpn/clientes_openvpn.tar.gz

CLIENTES:
$(for i in $(seq 1 $NUM_CLIENTES); do echo "- client$i.ovpn"; done)

CONFIGURACIÓN DUCKDNS: $([ "$INSTALAR_DUCKDNS" = "s" ] && echo "SÍ - $DOMAIN_COMPLETO" || echo "NO")
BACKUP CONFIGURACIÓN: $([ "$BACKUP_CONFIG_EXITOSO" = "true" ] && echo "SÍ - $BACKUP_CONFIG_FILE" || echo "NO")
BACKUP FIRMWARE: $([ "$FIRMWARE_BACKUP_CREADO" = "true" ] && echo "SÍ" || echo "NO DISPONIBLE")

INSTRUCCIONES:
1. Los archivos .ovpn están listos en /etc/openvpn/ y /tmp/
2. Usar install_Cliente_openvpn.sh en routers clientes
3. Backup disponible para restauración completa

PARA RESTAURAR CONFIGURACIÓN:
tar -xzf $(basename $BACKUP_CONFIG_FILE)
# Copiar archivos de configuración y certificados

EOF

echo -e "\033[32m- Reporte guardado en: /root/openvpn_config_summary.txt\033[0m"

# Ofrecer test de conexión
echo -e "\n\033[33m- ¿Quieres probar la conexión VPN? (s/n):\033[0m"
read -p "Test conexión: " TEST_CONEXION
if [ "$TEST_CONEXION" = "s" ] || [ "$TEST_CONEXION" = "S" ]; then
    echo "- Realizando test básico de conectividad..."
    if ping -c 2 8.8.8.8 >/dev/null 2>&1; then
        echo -e "\033[32m- Conexión a internet funcionando ✓\033[0m"
    else
        echo -e "\033[31m- Sin conexión a internet\033[0m"
    fi
fi

# Resumen final
echo -e "\n\033[32m=== CONFIGURACIÓN COMPLETADA ===\033[0m"
echo -e "\033[32m- Servidor: $DDNS_SERVER:$VPN_PORT\033[0m"
echo -e "\033[32m- Clientes creados: $NUM_CLIENTES\033[0m"
echo -e "\033[32m- Firewall configurado\033[0m"
if [ "$BACKUP_CONFIG_EXITOSO" = "true" ]; then
    echo -e "\033[32m- Backup configuración: $BACKUP_CONFIG_FILE ✓\033[0m"
else
    echo -e "\033[33m- Backup configuración: NO creado\033[0m"
fi
if [ "$FIRMWARE_BACKUP_CREADO" = "true" ]; then
    echo -e "\033[32m- Backup firmware: CREADO ✓\033[0m"
else
    echo -e "\033[33m- Backup firmware: NO creado (normal en algunos dispositivos)\033[0m"
fi
echo -e "\033[32m- Reporte en: /root/openvpn_config_summary.txt\033[0m"

if [ "$INSTALAR_DUCKDNS" = "s" ] || [ "$INSTALAR_DUCKDNS" = "S" ]; then
    echo -e "\033[32m- DuckDNS configurado y activo\033[0m"
fi

echo -e "\n\033[33m- Reiniciando en 15 segundos...\033[0m"
echo -e "\033[33m- Presiona Ctrl+C para cancelar el reinicio\033[0m"
sleep 15
reboot
