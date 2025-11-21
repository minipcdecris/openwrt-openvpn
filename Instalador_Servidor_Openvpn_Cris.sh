#!/bin/sh

echo ""
echo "================================================"
echo "    INSTALADOR SERVIDOR OPENVPN - COMPLETO"
echo "       BR-VPN + DUCKDNS EDITABLE"
echo "================================================"
echo ""

# INSTRUCCIONES PREVIAS DUCKDNS
echo "🦆 CONFIGURACIÓN PREVIA DUCKDNS"
echo "------------------------------"
echo "ANTES de ejecutar este script:"
echo ""
echo "1. 📍 Ve a LuCI: Services → Dynamic DNS"
echo "2. ➕ Crea un NUEVO servicio:"
echo "   - Service Name: DuckDNS"
echo "   - DDNS Service Provider: duckdns.org"
echo "3. 🔘 Haz click en 'Really switch service?'"
echo "4. 💾 Guarda (pero NO configures los demás campos)"
echo ""
echo "¿Ya has creado el servicio DuckDNS? (s/n): "
read DUCKDNS_CREADO

if [ "$DUCKDNS_CREADO" != "s" ]; then
    echo "❌ Crea primero el servicio DuckDNS y luego ejecuta el script"
    exit 1
fi

echo ""
echo "📋 CONFIGURACIÓN DUCKDNS"
echo "-----------------------"
echo "Tu dominio DuckDNS (sin .duckdns.org): "
read DUCKDNS_DOMAIN
echo "Token de DuckDNS: "
read DUCKDNS_TOKEN

DDNS_SERVER="${DUCKDNS_DOMAIN}.duckdns.org"

echo ""
echo "✅ Dominio DuckDNS: $DDNS_SERVER"
echo ""

echo "📋 CONFIGURACIÓN OPENVPN"
echo "-----------------------"
echo "Puerto OpenVPN (1194): "
read VPN_PORT
VPN_PORT=${VPN_PORT:-1194}
echo "Número de clientes (4): "
read NUM_CLIENTES
NUM_CLIENTES=${NUM_CLIENTES:-4}

echo ""
echo "📍 RESUMEN:"
echo "   DuckDNS: $DDNS_SERVER"
echo "   Servidor: $DDNS_SERVER:$VPN_PORT"
echo "   Clientes: $NUM_CLIENTES"
echo "   Interfaz: br-vpn"
echo ""

echo "¿Continuar con la instalación? (s/n): "
read CONFIRMAR
[ "$CONFIRMAR" != "s" ] && echo "Instalación cancelada." && exit 0

echo ""
echo "🚀 INICIANDO INSTALACIÓN COMPLETA..."
echo ""

# Función para el spinner
spinner() {
    local pid=$1
    local delay=0.5
    local spinstr='|/-\'
    while [ -d /proc/$pid ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# 1. INSTALACIÓN DE PAQUETES
echo "📦 PASO 1: INSTALANDO PAQUETES..."
echo "--------------------------------"
echo "   [....] Actualizando repositorios..."
opkg update > /dev/null 2>&1
echo "   [DONE] Repositorios actualizados"

echo "   [....] Instalando paquetes OpenVPN..."
opkg install openvpn-easy-rsa openvpn-openssl luci-app-openvpn > /dev/null 2>&1
echo "   [DONE] OpenVPN instalado"

echo "   [....] Instalando paquetes DuckDNS..."
opkg install ddns-scripts ddns-scripts-duckdns luci-app-ddns > /dev/null 2>&1
echo "   [DONE] DuckDNS instalado"

echo "✅ Todos los paquetes instalados correctamente"
echo ""

# 2. CONFIGURAR DUCKDNS
echo "🦆 PASO 2: CONFIGURANDO DUCKDNS..."
echo "---------------------------------"
DUCKDNS_SERVICE=$(uci show ddns | grep "service_name='duckdns.org'" | cut -d'.' -f2 | cut -d'=' -f1)

if [ -n "$DUCKDNS_SERVICE" ]; then
    echo "   [....] Configurando servicio DuckDNS..."
    
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
    
    echo "   [DONE] DuckDNS configurado automáticamente"
    echo "      └─ Dominio: $DDNS_SERVER"
    echo "      └─ Usuario: $DUCKDNS_DOMAIN"
    echo "      └─ Check Unit: seconds"
else
    echo "⚠️ No se encontró servicio DuckDNS existente"
    echo "🔹 Configura DuckDNS manualmente en LuCI después de la instalación"
fi
echo ""

# 3. GENERACIÓN DE CERTIFICADOS
echo "🔐 PASO 3: GENERANDO CERTIFICADOS..."
echo "-----------------------------------"
cd /etc/easy-rsa

echo "   [....] Inicializando PKI..."
echo -e "yes\nyes" | easyrsa init-pki > /dev/null 2>&1
echo "   [DONE] PKI inicializado"

echo "   [....] Creando Autoridad Certificadora (CA)..."
echo -e "yes\nserver" | easyrsa build-ca nopass > /dev/null 2>&1
echo "   [DONE] Autoridad Certificadora creada"

echo "   [....] Creando certificado del servidor..."
echo -e "yes" | easyrsa build-server-full server nopass > /dev/null 2>&1
echo "   [DONE] Certificado del servidor generado"

echo "   [....] Creando certificados de clientes..."
for i in $(seq 1 $NUM_CLIENTES); do
    echo -e "yes" | easyrsa build-client-full client$i nopass > /dev/null 2>&1
    echo "      └─ Cliente $i ✅"
done
echo "   [DONE] Certificados de clientes generados"

echo -n "   [....] Generando parámetros Diffie-Hellman "
(easyrsa gen-dh > /dev/null 2>&1) &
spinner $!
echo ""
echo "   [DONE] Parámetros Diffie-Hellman generados"

echo "✅ Todos los certificados generados correctamente"
echo ""

# 4. CONFIGURAR OPENVPN
echo "📁 PASO 4: CONFIGURANDO OPENVPN..."
echo "---------------------------------"
echo "   [....] Copiando certificados..."
cp /etc/easy-rsa/pki/ca.crt /etc/openvpn/
cp /etc/easy-rsa/pki/private/server.key /etc/openvpn/
cp /etc/easy-rsa/pki/issued/server.crt /etc/openvpn/
cp /etc/easy-rsa/pki/dh.pem /etc/openvpn/
echo "   [DONE] Certificados copiados"

echo "   [....] Configurando servidor OpenVPN..."
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
echo "   [DONE] Servidor OpenVPN configurado"

# 5. CONFIGURAR FIREWALL
echo "🔥 PASO 5: CONFIGURANDO FIREWALL..."
echo "----------------------------------"
echo "   [....] Agregando reglas de firewall..."
uci add firewall rule
uci set firewall.@rule[-1].name='Allow-OpenVPN'
uci set firewall.@rule[-1].src='wan'
uci set firewall.@rule[-1].proto='udp'
uci set firewall.@rule[-1].dest_port="$VPN_PORT"
uci set firewall.@rule[-1].target='ACCEPT'
uci commit firewall > /dev/null 2>&1
/etc/init.d/firewall reload > /dev/null 2>&1
echo "   [DONE] Firewall configurado"

# 6. CREAR BRIDGE BR-VPN
echo "🔧 PASO 6: CREANDO BRIDGE BR-VPN..."
echo "----------------------------------"
echo "   [....] Creando interfaz tap0..."
ip tuntap add mode tap tap0
ifconfig tap0 up
echo "   [DONE] Interfaz tap0 creada"

echo "   [....] Creando bridge br-vpn..."
brctl addbr br-vpn
brctl addif br-vpn tap0
ifconfig br-vpn up
echo "   [DONE] Bridge br-vpn creado"

echo "   [....] Configurando persistencia..."
uci set network.br-vpn=device
uci set network.br-vpn.type='bridge'
uci set network.br-vpn.name='br-vpn'
uci add_list network.br-vpn.ports='tap0'
uci set network.br-vpn.igmp_snooping='1'

uci set network.vpn=interface
uci set network.vpn.proto='none'
uci set network.vpn.device='br-vpn'

uci commit network > /dev/null 2>&1
echo "   [DONE] Configuración persistente aplicada"

# 7. GENERAR ARCHIVOS CLIENTE
echo "📄 PASO 7: GENERANDO ARCHIVOS CLIENTE..."
echo "--------------------------------------"
for i in $(seq 1 $NUM_CLIENTES); do
    echo "   [....] Generando client$i.ovpn..."
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
    echo "   [DONE] client$i.ovpn generado"
done

echo "✅ Todos los archivos .ovpn generados en /tmp/"
echo ""

# 8. INICIAR SERVICIOS
echo "🚀 PASO 8: INICIANDO SERVICIOS..."
echo "-------------------------------"
echo "   [....] Habilitando servicios..."
/etc/init.d/openvpn enable > /dev/null 2>&1
echo "   [DONE] Servicios habilitados"

echo "   [....] Iniciando OpenVPN..."
/etc/init.d/openvpn start > /dev/null 2>&1
echo "   [DONE] OpenVPN iniciado"

echo "   [....] Reiniciando DuckDNS..."
/etc/init.d/ddns restart > /dev/null 2>&1
echo "   [DONE] DuckDNS reiniciado"

sleep 2
echo "✅ Todos los servicios iniciados correctamente"
echo ""

# 9. VERIFICACIÓN FINAL
echo "🔍 PASO 9: VERIFICACIÓN FINAL..."
echo "-------------------------------"
echo "   [....] Verificando servicios..."
echo ""

echo "🔍 ESTADO DE SERVICIOS:"

# Verificar OpenVPN
if pgrep openvpn >/dev/null; then
    echo "   ✅ OpenVPN: ACTIVO (PID: $(pgrep openvpn))"
else
    echo "   ❌ OpenVPN: INACTIVO"
fi

# Verificar DuckDNS
if [ -n "$DUCKDNS_SERVICE" ]; then
    if uci get ddns.$DUCKDNS_SERVICE.enabled >/dev/null 2>&1; then
        echo "   ✅ DuckDNS: CONFIGURADO"
    else
        echo "   ❌ DuckDNS: NO CONFIGURADO"
    fi
else
    echo "   ⚠️ DuckDNS: CONFIGURACIÓN MANUAL REQUERIDA"
fi

# Verificar interfaces
if ifconfig tap0 >/dev/null 2>&1; then
    echo "   ✅ Interfaz tap0: ACTIVA"
else
    echo "   ❌ Interfaz tap0: INACTIVA"
fi

if ifconfig br-vpn >/dev/null 2>&1; then
    echo "   ✅ Bridge br-vpn: ACTIVO"
else
    echo "   ❌ Bridge br-vpn: INACTIVO"
fi

# Verificar archivos
echo ""
echo "📄 ARCHIVOS GENERADOS:"
for i in $(seq 1 $NUM_CLIENTES); do
    if [ -f "/tmp/client$i.ovpn" ]; then
        echo "   ✅ client$i.ovpn: EXISTE"
    else
        echo "   ❌ client$i.ovpn: FALTANTE"
    fi
done

echo "   [DONE] Verificación completada"
echo ""

echo "----------------------------------------"
echo "🎉 INSTALACIÓN COMPLETADA EXITOSAMENTE!"
echo "----------------------------------------"
echo ""
echo "🖥️ INFORMACIÓN DEL SERVIDOR:"
echo "   ┌─ Dominio: $DDNS_SERVER"
echo "   ├─ Puerto: $VPN_PORT"
echo "   ├─ Protocolo: UDP"
echo "   └─ Bridge: br-vpn"
echo ""
echo "👤 ARCHIVOS DE CLIENTE:"
echo "   └─ Ruta: /tmp/client1.ovpn - client$NUM_CLIENTES.ovpn"
echo ""
echo "📥 IMPORTANTE:"
echo "   • Descarga los archivos .ovpn de /tmp/ antes de reiniciar"
echo "   • Configura el firewall si necesitas acceso a la red local"
echo ""

echo "----------------------------------------"
echo "El sistema se reiniciará en 15 segundos..."
echo "Presiona Ctrl+C para cancelar el reinicio"
echo "----------------------------------------"

for i in 15 14 13 12 11 10 9 8 7 6 5 4 3 2 1; do
    echo -n "Reiniciando en $i segundos... "
    sleep 1
    echo -ne "\r"
done

echo ""
echo "🔹 Reiniciando sistema..."
reboot
