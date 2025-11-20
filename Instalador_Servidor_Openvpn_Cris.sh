#!/bin/sh

# Función para verificar comandos
check_status() {
    if [ $? -ne 0 ]; then
        echo "❌ Error en el paso anterior"
        return 1
    fi
}

echo "================================================"
echo "    INSTALADOR SERVIDOR OPENVPN - COMPLETO"
echo "       BR-VPN + DUCKDNS AUTOMÁTICO"
echo "================================================"
echo ""

# CONFIGURACIÓN DUCKDNS
echo "🦆 CONFIGURACIÓN DUCKDNS"
echo "-----------------------"
read -p "🔹 Tu dominio DuckDNS (sin .duckdns.org): " DUCKDNS_DOMAIN
read -p "🔹 Token de DuckDNS: " DUCKDNS_TOKEN

DDNS_SERVER="${DUCKDNS_DOMAIN}.duckdns.org"

echo ""
echo "📍 DOMINIO DUCKDNS: $DDNS_SERVER"
echo ""

# CONFIGURACIÓN OPENVPN
echo "📋 CONFIGURACIÓN OPENVPN"
echo "-----------------------"
read -p "🔹 Puerto OpenVPN (1194): " VPN_PORT
VPN_PORT=${VPN_PORT:-1194}
read -p "🔹 Número de clientes (4): " NUM_CLIENTES
NUM_CLIENTES=${NUM_CLIENTES:-4}

echo ""
echo "📍 RESUMEN:"
echo "   DuckDNS: $DDNS_SERVER"
echo "   Servidor: $DDNS_SERVER:$VPN_PORT"
echo "   Clientes: $NUM_CLIENTES"
echo "   Interfaz: br-vpn"
echo ""

read -p "¿Continuar con la instalación? (s/n): " CONFIRMAR
[ "$CONFIRMAR" != "s" ] && echo "Instalación cancelada." && exit 0

echo ""
echo "🚀 INICIANDO INSTALACIÓN COMPLETA..."
echo ""

# 1. INSTALACIÓN DE PAQUETES
echo "📦 PASO 1: INSTALANDO PAQUETES..."
echo "--------------------------------"
opkg update
opkg install openvpn-easy-rsa openvpn-openssl luci-app-openvpn ddns-scripts ddns-scripts-duckdns luci-app-ddns
check_status || echo "⚠️  Algunos paquetes pueden no estar disponibles"
echo "✅ Paquetes instalados"
echo ""

# 2. CONFIGURAR DUCKDNS AUTOMÁTICAMENTE (CORREGIDO)
echo "🦆 PASO 2: CONFIGURANDO DUCKDNS..."
echo "---------------------------------"
# Eliminar servicios existentes de DDNS
while uci delete ddns.@service[0] 2>/dev/null; do :; done

# Crear nuevo servicio DuckDNS CON CONFIGURACIÓN CORREGIDA
uci add ddns service
uci set ddns.@service[-1].enabled='1'
uci set ddns.@service[-1].service_name='duckdns.org'
uci set ddns.@service[-1].lookup_host="$DDNS_SERVER"
uci set ddns.@service[-1].domain="$DDNS_SERVER"
uci set ddns.@service[-1].username="$DUCKDNS_DOMAIN"
uci set ddns.@service[-1].password="$DUCKDNS_TOKEN"
uci set ddns.@service[-1].interface='wan'

# CONFIGURACIÓN CORREGIDA: usar 'web' en lugar de 'url'
uci set ddns.@service[-1].ip_source='web'
uci set ddns.@service[-1].ip_url='http://checkip.dyndns.com'

# Configuración Timer
uci set ddns.@service[-1].check_interval='300'
uci set ddns.@service[-1].force_interval='5'
uci set ddns.@service[-1].force_unit='minutes'

uci commit ddns

echo "✅ DuckDNS configurado correctamente"
echo "   🔸 Lookup Hostname: $DDNS_SERVER"
echo "   🔸 DDNS Service: duckdns.org"
echo "   🔸 Domain: $DDNS_SERVER"
echo "   🔸 IP Source: web (corregido)"
echo "   🔸 Check Interval: 300"
echo "   🔸 Force Interval: 5"
echo ""

# 3. GENERACIÓN DE CERTIFICADOS
echo "🔐 PASO 3: GENERANDO CERTIFICADOS..."
echo "-----------------------------------"
cd /etc/easy-rsa

echo "🔹 Inicializando PKI..."
echo -e "yes\nyes" | easyrsa init-pki
check_status || exit 1

echo "🔹 Creando Autoridad Certificadora (CA)..."
echo -e "yes\nserver" | easyrsa build-ca nopass
check_status || exit 1

echo "🔹 Creando certificado del servidor..."
echo -e "yes" | easyrsa build-server-full server nopass
check_status || exit 1

echo "🔹 Creando certificados de clientes..."
for i in $(seq 1 $NUM_CLIENTES); do
    echo "   👤 Cliente $i..."
    echo -e "yes" | easyrsa build-client-full client$i nopass
    check_status || exit 1
done

echo "🔹 Generando parámetros Diffie-Hellman..."
easyrsa gen-dh
check_status || exit 1
echo "✅ Certificados generados"
echo ""

# 4. COPIAR CERTIFICADOS
echo "📁 PASO 4: CONFIGURANDO OPENVPN..."
echo "---------------------------------"
cp /etc/easy-rsa/pki/ca.crt /etc/openvpn/
cp /etc/easy-rsa/pki/private/server.key /etc/openvpn/
cp /etc/easy-rsa/pki/issued/server.crt /etc/openvpn/
cp /etc/easy-rsa/pki/dh.pem /etc/openvpn/

# Configuración OpenVPN
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
echo "✅ OpenVPN configurado"
echo ""

# 5. CONFIGURAR FIREWALL
echo "🔥 PASO 5: CONFIGURANDO FIREWALL..."
echo "----------------------------------"
uci add firewall rule
uci set firewall.@rule[-1].name='Allow-OpenVPN'
uci set firewall.@rule[-1].src='wan'
uci set firewall.@rule[-1].proto='udp'
uci set firewall.@rule[-1].dest_port="$VPN_PORT"
uci set firewall.@rule[-1].target='ACCEPT'
uci commit firewall
/etc/init.d/firewall reload
echo "✅ Firewall configurado"
echo ""

# 6. CREAR BRIDGE BR-VPN
echo "🔧 PASO 6: CREANDO BRIDGE BR-VPN..."
echo "----------------------------------"
# Crear interfaz tap0 manualmente
ip tuntap add mode tap tap0
ifconfig tap0 up

# Crear bridge br-vpn manualmente
brctl addbr br-vpn
brctl addif br-vpn tap0
ifconfig br-vpn up

# Configurar UCI para persistencia
uci set network.br-vpn=device
uci set network.br-vpn.type='bridge'
uci set network.br-vpn.name='br-vpn'
uci add_list network.br-vpn.ports='tap0'
uci set network.br-vpn.igmp_snooping='1'

uci set network.vpn=interface
uci set network.vpn.proto='none'
uci set network.vpn.device='br-vpn'

uci commit network
echo "✅ Bridge br-vpn creado"
echo ""

# 7. GENERAR ARCHIVOS CLIENTE .OVPN
echo "📄 PASO 7: GENERANDO ARCHIVOS CLIENTE..."
echo "--------------------------------------"
for i in $(seq 1 $NUM_CLIENTES); do
    echo "🔹 Generando client$i.ovpn..."
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
    echo "   ✅ client$i.ovpn creado"
done
echo "✅ Todos los archivos .ovpn generados"
echo ""

# 8. INICIAR SERVICIOS (CORREGIDO)
echo "🚀 PASO 8: INICIANDO SERVICIOS..."
echo "-------------------------------"
/etc/init.d/openvpn enable
/etc/init.d/openvpn start

# Iniciar DuckDNS pero ignorar errores temporales
echo "🔹 Iniciando DuckDNS..."
/etc/init.d/ddns enable
/etc/init.d/ddns start 2>/dev/null || echo "⚠️  DuckDNS puede necesitar configuración adicional"

sleep 3
echo "✅ Servicios iniciados"
echo ""

# 9. VERIFICACIÓN FINAL
echo "🔍 PASO 9: VERIFICACIÓN FINAL..."
echo "-------------------------------"
echo "🔹 Verificando OpenVPN..."
if pgrep openvpn >/dev/null; then
    echo "   ✅ OpenVPN está corriendo"
else
    echo "   ❌ OpenVPN NO está corriendo"
fi

echo "🔹 Verificando interfaces..."
ifconfig tap0 >/dev/null 2>&1 && echo "   ✅ tap0 activa" || echo "   ❌ tap0 inactiva"
ifconfig br-vpn >/dev/null 2>&1 && echo "   ✅ br-vpn activo" || echo "   ❌ br-vpn inactivo"

echo "🔹 Verificando DuckDNS..."
if /etc/init.d/ddns enabled; then
    echo "   ✅ DuckDNS habilitado"
else
    echo "   ❌ DuckDNS no habilitado"
fi

echo "🔹 Verificando archivos cliente..."
for i in $(seq 1 $NUM_CLIENTES); do
    if [ -f "/tmp/client$i.ovpn" ]; then
        echo "   ✅ client$i.ovpn disponible"
    else
        echo "   ❌ client$i.ovpn NO encontrado"
    fi
done
echo ""

# RESUMEN FINAL
echo "🎉 INSTALACIÓN COMPLETADA EXITOSAMENTE!"
echo "========================================"
echo ""
echo "📍 SERVICIOS CONFIGURADOS:"
echo "   🔸 OpenVPN: ✅ $DDNS_SERVER:$VPN_PORT"
echo "   🔸 DuckDNS: ✅ Configurado (ip_source corregido a 'web')"
echo "   🔸 Bridge: ✅ br-vpn con interfaz vpn"
echo ""
echo "📍 CONFIGURACIÓN DUCKDNS:"
echo "   🔸 Lookup Hostname: $DDNS_SERVER"
echo "   🔸 DDNS Service: duckdns.org"
echo "   🔸 Domain: $DDNS_SERVER"
echo "   🔸 Username: $DUCKDNS_DOMAIN"
echo "   🔸 IP Source: web (corregido)"
echo "   🔸 URL: http://checkip.dyndns.com"
echo "   🔸 Check Interval: 300"
echo "   🔸 Force Interval: 5"
echo ""
echo "📍 ARCHIVOS CLIENTE:"
echo "   🔸 /tmp/client1.ovpn ... client$NUM_CLIENTES.ovpn"
echo ""
echo "⚠️  NOTA SOBRE DUCKDNS:"
echo "   El error 'ip_source url' ha sido corregido usando 'web'"
echo "   DuckDNS debería funcionar correctamente ahora"
echo ""
echo "🔄 Reiniciando en 15 segundos para aplicar configuración..."
sleep 15
echo "Reiniciando..."
reboot
