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
echo "       CONFIGURACIÓN BR-VPN PERSONALIZADA"
echo "================================================"
echo ""

# CONFIGURACIÓN BÁSICA
echo "📋 CONFIGURACIÓN DEL SERVIDOR"
echo "-----------------------------"
read -p "🔹 DDNS o IP pública: " DDNS_SERVER
read -p "🔹 Puerto OpenVPN (1194): " VPN_PORT
VPN_PORT=${VPN_PORT:-1194}
read -p "🔹 Número de clientes (4): " NUM_CLIENTES
NUM_CLIENTES=${NUM_CLIENTES:-4}

echo ""
echo "📍 RESUMEN:"
echo "   Servidor: $DDNS_SERVER:$VPN_PORT"
echo "   Clientes: $NUM_CLIENTES"
echo "   Interfaz: br-vpn (bridge personalizado)"
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

# 5. CREAR BRIDGE BR-VPN PERSONALIZADO
echo "🔧 PASO 5: CREANDO BRIDGE BR-VPN..."
echo "----------------------------------"
# Crear interfaz tap0
ip tuntap add mode tap tap0
ifconfig tap0 up

# Configurar bridge br-vpn personalizado
uci set network.br-vpn=device
uci set network.br-vpn.type='bridge'
uci set network.br-vpn.name='br-vpn'
uci add_list network.br-vpn.ports='tap0'
uci set network.br-vpn.igmp_snooping='1'

# Crear interfaz vpn
uci set network.vpn=interface
uci set network.vpn.proto='none'
uci set network.vpn.device='br-vpn'

uci commit network
echo "✅ Bridge br-vpn creado y configurado"
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

echo "🔹 Verificando bridge br-vpn..."
if ifconfig br-vpn >/dev/null 2>&1; then
    echo "   ✅ Bridge br-vpn activo"
    echo "   📊 Estado del bridge:"
    brctl show br-vpn
else
    echo "   ❌ Bridge br-vpn NO activo"
fi

echo "🔹 Verificando configuración de red..."
echo "   📊 Interfaz vpn:"
uci show network.vpn
echo "   📊 Dispositivo br-vpn:"
uci show network.br-vpn

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
echo "   🔸 Interfaz: br-vpn (bridge personalizado)"
echo ""
echo "📍 CONFIGURACIÓN DE RED:"
echo "   🔸 Dispositivo: br-vpn (bridge)"
echo "   🔸 Interfaz: vpn"
echo "   🔸 Puertos: tap0"
echo "   🔸 IGMP Snooping: Activado"
echo ""
echo "📍 ARCHIVOS GENERADOS:"
echo "   🔸 En /tmp/: client1.ovpn ... client$NUM_CLIENTES.ovpn"
echo "   🔸 En /etc/openvpn/: Configuración del servidor"
echo ""
echo "📍 PRÓXIMOS PASOS:"
echo "   1. Descargar archivos .ovpn desde /tmp/"
echo "   2. Configurar routers clientes"
echo "   3. Los clientes se conectarán al bridge br-vpn"
echo ""
echo "📍 CONFIGURACIÓN LUCI:"
echo "   🔸 Interfaz: Network → Interfaces → vpn"
echo "   🔸 Dispositivo: Network → Devices → br-vpn"
echo ""
echo "🔄 El sistema se reiniciará automáticamente en 15 segundos..."
echo "   Presiona Ctrl+C para cancelar el reinicio"
echo ""

sleep 15
echo "Reiniciando..."
reboot
