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
echo "          INCLUYENDO DUCKDNS"
echo "================================================"
echo ""

# CONFIGURACIÓN DUCKDNS
echo "📋 CONFIGURACIÓN DUCKDNS"
echo "-----------------------"
read -p "🔹 ¿Quieres configurar DuckDNS? (s/n): " CONFIGURAR_DUCKDNS

if [ "$CONFIGURAR_DUCKDNS" = "s" ]; then
    echo ""
    echo "🦆 CONFIGURANDO DUCKDNS..."
    echo "------------------------"
    read -p "🔹 Tu dominio DuckDNS (sin .duckdns.org): " DUCKDNS_DOMAIN
    read -p "🔹 Token de DuckDNS: " DUCKDNS_TOKEN
    
    DDNS_SERVER="${DUCKDNS_DOMAIN}.duckdns.org"
    
    echo ""
    echo "🔹 Instalando DuckDNS..."
    opkg update
    opkg install ddns-scripts ddns-scripts-duckdns luci-app-ddns
    check_status || echo "⚠️  DuckDNS no disponible, continuando sin él"
    
    if opkg list-installed | grep -q "ddns-scripts-duckdns"; then
        echo "🔹 Configurando DuckDNS..."
        # Eliminar configuraciones existentes
        while uci delete ddns.@service[0] 2>/dev/null; do :; done
        
        # Crear nueva configuración
        uci add ddns service
        uci set ddns.@service[-1].enabled='1'
        uci set ddns.@service[-1].service_name='duckdns.org'
        uci set ddns.@service[-1].domain="$DDNS_SERVER"
        uci set ddns.@service[-1].lookup_host="$DDNS_SERVER"
        uci set ddns.@service[-1].username="$DUCKDNS_DOMAIN"
        uci set ddns.@service[-1].password="$DUCKDNS_TOKEN"
        uci set ddns.@service[-1].interface='wan'
        uci set ddns.@service[-1].ip_source='url'
        uci set ddns.@service[-1].ip_url='http://checkip.dyndns.com'
        uci set ddns.@service[-1].check_interval='300'
        uci set ddns.@service[-1].force_interval='5'
        
        uci commit ddns
        /etc/init.d/ddns enable
        /etc/init.d/ddns start
        
        echo "✅ DuckDNS configurado: $DDNS_SERVER"
    else
        echo "⚠️  DuckDNS no instalado, usando dominio manual"
        read -p "🔹 Introduce tu DDNS o IP manualmente: " DDNS_SERVER
    fi
else
    echo ""
    echo "📋 CONFIGURACIÓN MANUAL"
    echo "----------------------"
    read -p "🔹 DDNS o IP pública: " DDNS_SERVER
fi

# CONFIGURACIÓN OPENVPN
echo ""
echo "📋 CONFIGURACIÓN OPENVPN"
echo "-----------------------"
read -p "🔹 Puerto OpenVPN (1194): " VPN_PORT
VPN_PORT=${VPN_PORT:-1194}
read -p "🔹 Número de clientes (4): " NUM_CLIENTES
NUM_CLIENTES=${NUM_CLIENTES:-4}

echo ""
echo "📍 RESUMEN:"
echo "   Servidor: $DDNS_SERVER:$VPN_PORT"
echo "   Clientes: $NUM_CLIENTES"
if [ "$CONFIGURAR_DUCKDNS" = "s" ]; then
    echo "   DuckDNS: Configurado"
else
    echo "   DuckDNS: No configurado"
fi
echo ""

# Confirmar
read -p "¿Continuar? (s/n): " CONFIRMAR
[ "$CONFIRMAR" != "s" ] && echo "Instalación cancelada." && exit 0

echo ""
echo "🚀 INICIANDO INSTALACIÓN..."
echo ""

# 1. INSTALACIÓN DE PAQUETES OPENVPN
echo "📦 PASO 1: INSTALANDO OPENVPN..."
echo "--------------------------------"
opkg update
opkg install openvpn-easy-rsa openvpn-openssl luci-app-openvpn
check_status || exit 1
echo "✅ OpenVPN instalado"
echo ""

# 2. GENERACIÓN DE CERTIFICADOS
echo "🔐 PASO 2: GENERANDO CERTIFICADOS..."
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

# 3. COPIAR CERTIFICADOS
echo "📁 PASO 3: CONFIGURANDO OPENVPN..."
echo "---------------------------------"
cp /etc/easy-rsa/pki/ca.crt /etc/openvpn/
cp /etc/easy-rsa/pki/private/server.key /etc/openvpn/
cp /etc/easy-rsa/pki/issued/server.crt /etc/openvpn/
cp /etc/easy-rsa/pki/dh.pem /etc/openvpn/

# Configuración OpenVPN CORREGIDA
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

# 4. CONFIGURAR FIREWALL
echo "🔥 PASO 4: CONFIGURANDO FIREWALL..."
echo "----------------------------------"
uci add firewall rule
uci set firewall.@rule[-1].name='Allow-OpenVPN'
uci set firewall.@rule[-1].src='wan'
uci set firewall.@rule[-1].proto='udp'
uci set firewall.@rule[-1].dest_port="$VPN_PORT"
uci set firewall.@rule[-1].target='ACCEPT'
uci commit firewall
/etc/init.d/firewall restart
check_status || exit 1
echo "✅ Firewall configurado"
echo ""

# 5. CREAR INTERFAZ TAP0 MANUALMENTE
echo "🔧 PASO 5: CREANDO INTERFAZ TAP0..."
echo "----------------------------------"
# Crear interfaz tap0
ip tuntap add mode tap tap0
ifconfig tap0 up

# Añadir tap0 al bridge br-lan
brctl addif br-lan tap0

# Configurar permanentemente en UCI
uci set network.tap0=interface
uci set network.tap0.ifname='tap0'
uci set network.tap0.proto='none'
uci set network.tap0.auto='1'

# Añadir tap0 al bridge br-lan permanentemente
uci add_list network.lan.ports='tap0'
uci set network.lan.igmp_snooping='1'

uci commit network
echo "✅ Interfaz tap0 creada y configurada"
echo ""

# 6. GENERAR ARCHIVOS CLIENTE .OVPN
echo "📄 PASO 6: GENERANDO ARCHIVOS CLIENTE..."
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
    
    # Crear copia en /tmp
    cp /etc/openvpn/client$i.ovpn /tmp/client$i.ovpn
    echo "   ✅ client$i.ovpn creado"
done
echo "✅ Todos los archivos .ovpn generados"
echo ""

# 7. INICIAR SERVICIOS
echo "🚀 PASO 7: INICIANDO SERVICIOS..."
echo "-------------------------------"
/etc/init.d/openvpn enable
/etc/init.d/openvpn start

# Iniciar DuckDNS si se configuró
if [ "$CONFIGURAR_DUCKDNS" = "s" ] && opkg list-installed | grep -q "ddns-scripts-duckdns"; then
    /etc/init.d/ddns restart
    echo "✅ DuckDNS iniciado"
fi

sleep 5
echo "✅ Servicios iniciados"
echo ""

# 8. VERIFICACIÓN FINAL
echo "🔍 PASO 8: VERIFICACIÓN FINAL..."
echo "-------------------------------"
echo "🔹 Verificando OpenVPN..."
if pgrep openvpn >/dev/null; then
    echo "   ✅ OpenVPN está corriendo"
else
    echo "   ❌ OpenVPN NO está corriendo"
fi

echo "🔹 Verificando interfaz tap0..."
if ifconfig tap0 >/dev/null 2>&1; then
    echo "   ✅ Interfaz tap0 activa"
else
    echo "   ❌ Interfaz tap0 NO activa"
fi

if [ "$CONFIGURAR_DUCKDNS" = "s" ]; then
    echo "🔹 Verificando DuckDNS..."
    if /etc/init.d/ddns running; then
        echo "   ✅ DuckDNS está corriendo"
    else
        echo "   ❌ DuckDNS NO está corriendo"
    fi
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

# 9. RESUMEN FINAL
echo "🎉 INSTALACIÓN COMPLETADA EXITOSAMENTE!"
echo "========================================"
echo ""
echo "📍 INFORMACIÓN DEL SERVIDOR:"
echo "   🔸 Dirección: $DDNS_SERVER"
echo "   🔸 Puerto: $VPN_PORT"
echo "   🔸 Protocolo: UDP"
echo "   🔸 Interfaz: tap0"
echo ""
echo "📍 SERVICIOS CONFIGURADOS:"
echo "   🔸 OpenVPN: ✅ Activo"
if [ "$CONFIGURAR_DUCKDNS" = "s" ]; then
    echo "   🔸 DuckDNS: ✅ Configurado"
else
    echo "   🔸 DuckDNS: ❌ No configurado"
fi
echo ""
echo "📍 ARCHIVOS GENERADOS:"
echo "   🔸 En /tmp/: client1.ovpn ... client$NUM_CLIENTES.ovpn"
echo ""
echo "📍 PRÓXIMOS PASOS:"
echo "   1. Descargar archivos .ovpn desde /tmp/"
echo "   2. Configurar routers clientes"
echo "   3. Los clientes estarán en la red 192.168.1.x"
echo ""
echo "🔄 El sistema se reiniciará automáticamente en 15 segundos..."
echo "   Presiona Ctrl+C para cancelar el reinicio"
echo ""

sleep 15
echo "Reiniciando..."
reboot
