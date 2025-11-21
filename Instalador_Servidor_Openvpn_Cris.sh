#!/bin/sh

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Símbolos y iconos
CHECK="✅"
CROSS="❌"
WARN="⚠️"
INFO="🔹"
ROCKET="🚀"
GEAR="🔧"
KEY="🔐"
FOLDER="📁"
FIRE="🔥"
NETWORK="🌐"
FILE="📄"
SEARCH="🔍"
PARTY="🎉"
DUCK="🦆"
SERVER="🖥️"
CLIENT="👤"
DOWNLOAD="📥"
LOCK="🔒"
EARTH="🌍"

# Función para imprimir header
print_header() {
    echo ""
    echo "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo "${CYAN}║${WHITE}                   INSTALADOR SERVIDOR OPENVPN                    ${CYAN}║${NC}"
    echo "${CYAN}║${WHITE}                 BR-VPN + DUCKDNS EDITABLE                        ${CYAN}║${NC}"
    echo "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Función para imprimir sección
print_section() {
    echo ""
    echo "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo "${BLUE}║${WHITE} $1 ${BLUE}║${NC}"
    echo "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
}

# Función para imprimir paso
print_step() {
    echo ""
    echo "${PURPLE}▸${WHITE} $1${NC}"
    echo "${PURPLE}────────────────────────────────────────────────────────────────${NC}"
}

# Función para mensaje de éxito
print_success() {
    echo "${GREEN}${CHECK} $1${NC}"
}

# Función para mensaje de error
print_error() {
    echo "${RED}${CROSS} $1${NC}"
}

# Función para mensaje de advertencia
print_warning() {
    echo "${YELLOW}${WARN} $1${NC}"
}

# Función para mensaje informativo
print_info() {
    echo "${CYAN}${INFO} $1${NC}"
}

# Función para entrada de usuario
user_input() {
    echo "${WHITE}┌─ ${YELLOW}? ${WHITE}$1${NC}"
    echo "${WHITE}└─${CYAN}→${NC} "
}

# Función para mostrar progreso
show_progress() {
    echo -n "${WHITE}   [${CYAN}....${WHITE}] $1${NC}"
}

# Función para completar progreso
complete_progress() {
    echo -e "\r${WHITE}   [${GREEN}DONE${WHITE}] ${NC}$1"
}

# Función para separador
separator() {
    echo ""
    echo "${BLUE}────────────────────────────────────────────────────────────────${NC}"
}

clear
print_header

# INSTRUCCIONES PREVIAS DUCKDNS
print_section "CONFIGURACIÓN PREVIA DUCKDNS"
echo "${WHITE}${DUCK} ANTES de ejecutar este script:${NC}"
echo ""
echo "${WHITE}   1. ${YELLOW}📍 Ve a LuCI: Services → Dynamic DNS${NC}"
echo "${WHITE}   2. ${YELLOW}➕ Crea un NUEVO servicio:${NC}"
echo "${WHITE}       ${CYAN}• Service Name: DuckDNS${NC}"
echo "${WHITE}       ${CYAN}• DDNS Service Provider: duckdns.org${NC}"
echo "${WHITE}   3. ${YELLOW}🔘 Haz click en 'Really switch service?'${NC}"
echo "${WHITE}   4. ${YELLOW}💾 Guarda (pero NO configures los demás campos)${NC}"
echo ""

user_input "¿Ya has creado el servicio DuckDNS? (s/n)"
read DUCKDNS_CREADO

if [ "$DUCKDNS_CREADO" != "s" ]; then
    print_error "Crea primero el servicio DuckDNS y luego ejecuta el script"
    exit 1
fi

separator

# CONFIGURACIÓN DUCKDNS
print_section "CONFIGURACIÓN DUCKDNS"
user_input "Tu dominio DuckDNS (sin .duckdns.org)"
read DUCKDNS_DOMAIN

user_input "Token de DuckDNS"
read DUCKDNS_TOKEN

DDNS_SERVER="${DUCKDNS_DOMAIN}.duckdns.org"

echo ""
print_success "Dominio DuckDNS: ${WHITE}$DDNS_SERVER${NC}"

separator

# CONFIGURACIÓN OPENVPN
print_section "CONFIGURACIÓN OPENVPN"
user_input "Puerto OpenVPN ${CYAN}[1194]${NC}"
read VPN_PORT
VPN_PORT=${VPN_PORT:-1194}

user_input "Número de clientes ${CYAN}[4]${NC}"
read NUM_CLIENTES
NUM_CLIENTES=${NUM_CLIENTES:-4}

separator

# RESUMEN DE CONFIGURACIÓN
print_section "RESUMEN DE CONFIGURACIÓN"
echo "${WHITE}${SERVER} ${GREEN}SERVIDOR:${NC}"
echo "   ${CYAN}•${WHITE} Dominio: ${YELLOW}$DDNS_SERVER${NC}"
echo "   ${CYAN}•${WHITE} Puerto: ${YELLOW}$VPN_PORT${NC}"
echo ""
echo "${WHITE}${CLIENT} ${GREEN}CLIENTES:${NC}"
echo "   ${CYAN}•${WHITE} Número: ${YELLOW}$NUM_CLIENTES${NC}"
echo ""
echo "${WHITE}${NETWORK} ${GREEN}RED:${NC}"
echo "   ${CYAN}•${WHITE} Interfaz: ${YELLOW}br-vpn${NC}"
echo "   ${CYAN}•${WHITE} Protocolo: ${YELLOW}UDP${NC}"

separator

user_input "¿Continuar con la instalación? (s/n)"
read CONFIRMAR
[ "$CONFIRMAR" != "s" ] && print_error "Instalación cancelada." && exit 0

echo ""
print_section "INICIANDO INSTALACIÓN COMPLETA"
echo "${WHITE}${ROCKET} Preparando sistema...${NC}"
echo ""

# 1. INSTALACIÓN DE PAQUETES
print_step "PASO 1: INSTALANDO PAQUETES"
show_progress "Actualizando repositorios..."
opkg update > /dev/null 2>&1
complete_progress "Repositorios actualizados"

show_progress "Instalando paquetes OpenVPN..."
opkg install openvpn-easy-rsa openvpn-openssl luci-app-openvpn > /dev/null 2>&1
complete_progress "OpenVPN instalado"

show_progress "Instalando paquetes DuckDNS..."
opkg install ddns-scripts ddns-scripts-duckdns luci-app-ddns > /dev/null 2>&1
complete_progress "DuckDNS instalado"

print_success "Todos los paquetes instalados correctamente"

# 2. CONFIGURAR DUCKDNS
print_step "PASO 2: CONFIGURANDO DUCKDNS"
DUCKDNS_SERVICE=$(uci show ddns | grep "service_name='duckdns.org'" | cut -d'.' -f2 | cut -d'=' -f1)

if [ -n "$DUCKDNS_SERVICE" ]; then
    show_progress "Configurando servicio DuckDNS..."
    
    uci set ddns.$DUCKDNS_SERVICE.lookup_host="$DDNS_SERVER"
    uci set ddns.$DUCKDNS_SERVICE.domain="$DDNS_SERVER"
    uci set ddns.$DUCKDNS_SERVICE.username="$DUCKDNS_DOMAIN"
    uci set ddns.$DUCKDNS_SERVICE.password="$DUCKDNS_TOKEN"
    uci set ddns.$DUCKDNS_SERVICE.enabled='1'
    uci set ddns.$DUCKDNS_SERVICE.interface='wan'
    uci set ddns.$DUCKDNS_SERVICE.ip_source='web'
    uci set ddns.$DUCKDNS_SERVICE.ip_url='http://checkip.dyndns.com'
    uci set ddns.$DUCKDNS_SERVICE.check_interval='300'
    uci set ddns.$DUCKDNS_SERVICE.check_unit='seconds'
    uci set ddns.$DUCKDNS_SERVICE.force_interval='5'
    uci set ddns.$DUCKDNS_SERVICE.force_unit='minutes'
    
    uci commit ddns > /dev/null 2>&1
    /etc/init.d/ddns restart > /dev/null 2>&1
    
    complete_progress "DuckDNS configurado automáticamente"
    echo "${WHITE}   └─ ${CYAN}Dominio: ${YELLOW}$DDNS_SERVER${NC}"
    echo "${WHITE}   └─ ${CYAN}Usuario: ${YELLOW}$DUCKDNS_DOMAIN${NC}"
    echo "${WHITE}   └─ ${CYAN}Check Unit: ${YELLOW}seconds${NC}"
else
    print_warning "No se encontró servicio DuckDNS existente"
    print_info "Configura DuckDNS manualmente en LuCI después de la instalación"
fi

# 3. GENERACIÓN DE CERTIFICADOS
print_step "PASO 3: GENERANDO CERTIFICADOS"
cd /etc/easy-rsa

show_progress "Inicializando PKI..."
echo -e "yes\nyes" | easyrsa init-pki > /dev/null 2>&1
complete_progress "PKI inicializado"

show_progress "Creando Autoridad Certificadora (CA)..."
echo -e "yes\nserver" | easyrsa build-ca nopass > /dev/null 2>&1
complete_progress "Autoridad Certificadora creada"

show_progress "Creando certificado del servidor..."
echo -e "yes" | easyrsa build-server-full server nopass > /dev/null 2>&1
complete_progress "Certificado del servidor generado"

show_progress "Creando certificados de clientes..."
for i in $(seq 1 $NUM_CLIENTES); do
    echo -e "yes" | easyrsa build-client-full client$i nopass > /dev/null 2>&1
    echo "${WHITE}     └─ ${GREEN}Cliente $i${NC} ${CHECK}${NC}"
done
complete_progress "Certificados de clientes generados"

show_progress "Generando parámetros Diffie-Hellman..."
easyrsa gen-dh > /dev/null 2>&1
complete_progress "Parámetros Diffie-Hellman generados"

print_success "Todos los certificados generados correctamente"

# 4. CONFIGURAR OPENVPN
print_step "PASO 4: CONFIGURANDO OPENVPN"
show_progress "Copiando certificados..."
cp /etc/easy-rsa/pki/ca.crt /etc/openvpn/
cp /etc/easy-rsa/pki/private/server.key /etc/openvpn/
cp /etc/easy-rsa/pki/issued/server.crt /etc/openvpn/
cp /etc/easy-rsa/pki/dh.pem /etc/openvpn/
complete_progress "Certificados copiados"

show_progress "Configurando servidor OpenVPN..."
cat > /etc/config/openvpn << CFG
config openvpn 'VPN_Server'
    option enabled '1'
    option mode 'server'
    option dev 'tap0'
    option proto 'udp'
    option port '$VPN_PORT'
    option tls_server '1'
    option ca '/etc/openvpn/ca.crt'
    option cert '/etc/openvpn/server.crt'
    option key '/etc/openvpn/server.key'
    option dh '/etc/openvpn/dh.pem'
CFG
complete_progress "Servidor OpenVPN configurado"

# 5. CONFIGURAR FIREWALL
print_step "PASO 5: CONFIGURANDO FIREWALL"
show_progress "Agregando reglas de firewall..."
uci add firewall rule
uci set firewall.@rule[-1].name='Allow-OpenVPN'
uci set firewall.@rule[-1].src='wan'
uci set firewall.@rule[-1].proto='udp'
uci set firewall.@rule[-1].dest_port="$VPN_PORT"
uci set firewall.@rule[-1].target='ACCEPT'
uci commit firewall > /dev/null 2>&1
/etc/init.d/firewall reload > /dev/null 2>&1
complete_progress "Firewall configurado"

# 6. CREAR BRIDGE BR-VPN
print_step "PASO 6: CREANDO BRIDGE BR-VPN"
show_progress "Creando interfaz tap0..."
ip tuntap add mode tap tap0
ifconfig tap0 up
complete_progress "Interfaz tap0 creada"

show_progress "Creando bridge br-vpn..."
brctl addbr br-vpn
brctl addif br-vpn tap0
ifconfig br-vpn up
complete_progress "Bridge br-vpn creado"

show_progress "Configurando persistencia..."
uci set network.br-vpn=device
uci set network.br-vpn.type='bridge'
uci set network.br-vpn.name='br-vpn'
uci add_list network.br-vpn.ports='tap0'
uci set network.br-vpn.igmp_snooping='1'

uci set network.vpn=interface
uci set network.vpn.proto='none'
uci set network.vpn.device='br-vpn'

uci commit network > /dev/null 2>&1
complete_progress "Configuración persistente aplicada"

# 7. GENERAR ARCHIVOS CLIENTE
print_step "PASO 7: GENERANDO ARCHIVOS CLIENTE"
for i in $(seq 1 $NUM_CLIENTES); do
    show_progress "Generando client$i.ovpn..."
    cat > /etc/openvpn/client$i.ovpn << OVPN
client
dev tap
proto udp
remote $DDNS_SERVER $VPN_PORT
resolv-retry infinite
nobind
float
cipher AES-256-GCM
keepalive 15 60
remote-cert-tls server
<ca>
$(cat /etc/openvpn/ca.crt)
</ca>
<cert>
$(cat /etc/easy-rsa/pki/issued/client$i.crt)
</cert>
<key>
$(cat /etc/easy-rsa/pki/private/client$i.key)
</key>
OVPN
    
    cp /etc/openvpn/client$i.ovpn /tmp/client$i.ovpn
    complete_progress "client$i.ovpn generado"
done

print_success "Todos los archivos .ovpn generados en /tmp/"

# 8. INICIAR SERVICIOS
print_step "PASO 8: INICIANDO SERVICIOS"
show_progress "Habilitando servicios..."
/etc/init.d/openvpn enable > /dev/null 2>&1
complete_progress "Servicios habilitados"

show_progress "Iniciando OpenVPN..."
/etc/init.d/openvpn start > /dev/null 2>&1
complete_progress "OpenVPN iniciado"

show_progress "Reiniciando DuckDNS..."
/etc/init.d/ddns restart > /dev/null 2>&1
complete_progress "DuckDNS reiniciado"

sleep 2
print_success "Todos los servicios iniciados correctamente"

# 9. VERIFICACIÓN FINAL
print_step "PASO 9: VERIFICACIÓN FINAL"
show_progress "Verificando servicios..."

echo ""
echo "${WHITE}${SEARCH} ${GREEN}ESTADO DE SERVICIOS:${NC}"

# Verificar OpenVPN
if pgrep openvpn >/dev/null; then
    echo "   ${CHECK} ${WHITE}OpenVPN: ${GREEN}ACTIVO ${CYAN}(PID: $(pgrep openvpn))${NC}"
else
    echo "   ${CROSS} ${WHITE}OpenVPN: ${RED}INACTIVO${NC}"
fi

# Verificar DuckDNS
if [ -n "$DUCKDNS_SERVICE" ]; then
    if uci get ddns.$DUCKDNS_SERVICE.enabled >/dev/null 2>&1; then
        echo "   ${CHECK} ${WHITE}DuckDNS: ${GREEN}CONFIGURADO${NC}"
    else
        echo "   ${CROSS} ${WHITE}DuckDNS: ${RED}NO CONFIGURADO${NC}"
    fi
else
    echo "   ${WARN} ${WHITE}DuckDNS: ${YELLOW}CONFIGURACIÓN MANUAL REQUERIDA${NC}"
fi

# Verificar interfaces
if ifconfig tap0 >/dev/null 2>&1; then
    echo "   ${CHECK} ${WHITE}Interfaz tap0: ${GREEN}ACTIVA${NC}"
else
    echo "   ${CROSS} ${WHITE}Interfaz tap0: ${RED}INACTIVA${NC}"
fi

if ifconfig br-vpn >/dev/null 2>&1; then
    echo "   ${CHECK} ${WHITE}Bridge br-vpn: ${GREEN}ACTIVO${NC}"
else
    echo "   ${CROSS} ${WHITE}Bridge br-vpn: ${RED}INACTIVO${NC}"
fi

# Verificar archivos
echo ""
echo "${WHITE}${FILE} ${GREEN}ARCHIVOS GENERADOS:${NC}"
for i in $(seq 1 $NUM_CLIENTES); do
    if [ -f "/tmp/client$i.ovpn" ]; then
        echo "   ${CHECK} ${WHITE}client$i.ovpn: ${GREEN}EXISTE${NC}"
    else
        echo "   ${CROSS} ${WHITE}client$i.ovpn: ${RED}FALTANTE${NC}"
    fi
done

complete_progress "Verificación completada"

separator

# RESUMEN FINAL
print_section "INSTALACIÓN COMPLETADA EXITOSAMENTE"
echo "${WHITE}${PARTY} ${GREEN}¡SERVIDOR CONFIGURADO CORRECTAMENTE!${NC}"
echo ""
echo "${WHITE}${SERVER} ${CYAN}INFORMACIÓN DEL SERVIDOR:${NC}"
echo "   ${CYAN}┌─${WHITE} Dominio: ${YELLOW}$DDNS_SERVER${NC}"
echo "   ${CYAN}├─${WHITE} Puerto: ${YELLOW}$VPN_PORT${NC}"
echo "   ${CYAN}├─${WHITE} Protocolo: ${YELLOW}UDP${NC}"
echo "   ${CYAN}└─${WHITE} Bridge: ${YELLOW}br-vpn${NC}"
echo ""
echo "${WHITE}${CLIENT} ${CYAN}ARCHIVOS DE CLIENTE:${NC}"
echo "   ${CYAN}└─${WHITE} Ruta: ${YELLOW}/tmp/client1.ovpn - client$NUM_CLIENTES.ovpn${NC}"
echo ""
echo "${WHITE}${DOWNLOAD} ${YELLOW}IMPORTANTE:${NC}"
echo "   ${CYAN}•${WHITE} Descarga los archivos .ovpn de ${YELLOW}/tmp/${WHITE} antes de reiniciar${NC}"
echo "   ${CYAN}•${WHITE} Configura el firewall si necesitas acceso a la red local${NC}"

separator

echo "${WHITE}El sistema se reiniciará en ${YELLOW}15 segundos${WHITE}...${NC}"
echo "${WHITE}Presiona ${RED}Ctrl+C${WHITE} para cancelar el reinicio${NC}"

for i in {15..1}; do
    echo -n -e "\r${WHITE}Reiniciando en ${YELLOW}$i${WHITE} segundos...${NC}"
    sleep 1
done

echo ""
print_info "Reiniciando sistema..."
reboot
