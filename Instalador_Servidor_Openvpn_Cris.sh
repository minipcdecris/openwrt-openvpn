#!/bin/sh

echo "=== CONFIGURACIÓN SERVIDOR OPENVPN - MODO VERBOSO ==="

# Configuración
read -p "DDNS o IP pública: " DDNS_SERVER
read -p "Puerto (1194): " VPN_PORT
VPN_PORT=${VPN_PORT:-1194}
read -p "Clientes (4): " NUM_CLIENTES
NUM_CLIENTES=${NUM_CLIENTES:-4}

echo ""
echo "📋 CONFIGURACIÓN:"
echo "   Servidor: $DDNS_SERVER:$VPN_PORT"
echo "   Clientes: $NUM_CLIENTES"
echo ""

# Instalar
echo "📦 INSTALANDO PAQUETES..."
opkg update
opkg install openvpn-easy-rsa openvpn-openssl

echo ""
echo "🔐 GENERANDO CERTIFICADOS..."
echo ""

# Ir al directorio de easy-rsa
cd /etc/easy-rsa
echo "📁 Directorio: $(pwd)"
echo ""

# 1. Inicializar PKI
echo "1️⃣  INICIANDO PKI..."
echo -e "yes\nyes" | easyrsa init-pki
echo "✅ PKI inicializado"
ls -la pki/
echo ""

# 2. Crear CA
echo "2️⃣  CREANDO AUTORIDAD CERTIFICADORA (CA)..."
echo -e "yes\nserver" | easyrsa build-ca nopass
echo "✅ CA creada"
ls -la pki/ca.crt
echo ""

# 3. Certificado del servidor
echo "3️⃣  CREANDO CERTIFICADO DEL SERVIDOR..."
echo -e "yes" | easyrsa build-server-full server nopass
echo "✅ Certificado del servidor creado"
ls -la pki/issued/server.crt
ls -la pki/private/server.key
echo ""

# 4. Certificados de clientes
echo "4️⃣  CREANDO CERTIFICADOS DE CLIENTES..."
for i in $(seq 1 $NUM_CLIENTES); do
    echo "   👤 Creando cliente $i..."
    echo -e "yes" | easyrsa build-client-full client$i nopass
    echo "   ✅ client$i - Certificado creado"
    ls -la pki/issued/client$i.crt
    ls -la pki/private/client$i.key
done
echo ""

# 5. Parámetros Diffie-Hellman
echo "5️⃣  GENERANDO PARÁMETROS DIFFIE-HELLMAN..."
easyrsa gen-dh
echo "✅ Parámetros DH generados"
ls -la pki/dh.pem
echo ""

# Mostrar resumen de certificados
echo "📊 RESUMEN DE CERTIFICADOS GENERADOS:"
echo "📍 CA:"
ls -la pki/ca.crt
echo ""
echo "📍 Servidor:"
ls -la pki/issued/server.crt
ls -la pki/private/server.key
echo ""
echo "📍 Clientes:"
for i in $(seq 1 $NUM_CLIENTES); do
    echo "   client$i:"
    ls -la pki/issued/client$i.crt
    ls -la pki/private/client$i.key
done
echo ""
echo "📍 Diffie-Hellman:"
ls -la pki/dh.pem

echo ""
echo "📋 CONTINUANDO CON CONFIGURACIÓN..."
echo ""

# Copiar archivos a OpenVPN
echo "📁 COPIANDO CERTIFICADOS A /etc/openvpn/..."
cp pki/ca.crt /etc/openvpn/
cp pki/private/server.key /etc/openvpn/
cp pki/issued/server.crt /etc/openvpn/
cp pki/dh.pem /etc/openvpn/

echo "✅ Certificados copiados:"
ls -la /etc/openvpn/*.crt
ls -la /etc/openvpn/*.key
ls -la /etc/openvpn/*.pem
echo ""

# Configurar OpenVPN
echo "⚙️  CONFIGURANDO OPENVPN..."
cat > /etc/config/openvpn <<CFG
config openvpn 'VPN_Server'
    option enabled '1'
    option mode 'server'
    option dev 'tap0'
    option proto 'udp'
    option port '$VPN_PORT'
    option ca '/etc/openvpn/ca.crt'
    option cert '/etc/openvpn/server.crt'
    option key '/etc/openvpn/server.key'
    option dh '/etc/openvpn/dh.pem'
CFG
echo "✅ Configuración OpenVPN creada"
echo ""

# Firewall
echo "🔥 CONFIGURANDO FIREWALL..."
uci add firewall rule
uci set firewall.@rule[-1].name='OpenVPN'
uci set firewall.@rule[-1].src='wan'
uci set firewall.@rule[-1].proto='udp'
uci set firewall.@rule[-1].dest_port="$VPN_PORT"
uci set firewall.@rule[-1].target='ACCEPT'
uci commit firewall
/etc/init.d/firewall restart
echo "✅ Firewall configurado para puerto $VPN_PORT"
echo ""

# Generar archivos .ovpn
echo "📄 GENERANDO ARCHIVOS .OVPN..."
for i in $(seq 1 $NUM_CLIENTES); do
    echo "   📝 Creando client$i.ovpn..."
    cat > /etc/openvpn/client$i.ovpn <<OVPN
client
dev tap
proto udp
remote $DDNS_SERVER $VPN_PORT
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
    echo "   ✅ client$i.ovpn creado y copiado a /tmp/"
done
echo ""

# Configurar red
echo "🌐 CONFIGURANDO RED..."
uci set network.lan.igmp_snooping='1'
uci add_list network.lan.ports='tap0'
uci commit network
/etc/init.d/network restart
echo "✅ Red configurada"
echo ""

# Iniciar servicios
echo "🚀 INICIANDO SERVICIOS..."
/etc/init.d/openvpn enable
/etc/init.d/openvpn start
echo "✅ OpenVPN iniciado"
echo ""

# Verificación final
echo "🔍 VERIFICANDO INSTALACIÓN..."
sleep 3

if pgrep openvpn >/dev/null; then
    echo "✅ OpenVPN está corriendo"
else
    echo "❌ OpenVPN NO está corriendo"
fi

if ifconfig tap0 >/dev/null 2>&1; then
    echo "✅ Interfaz tap0 activa"
else
    echo "❌ Interfaz tap0 NO activa"
fi

echo ""
echo "🎉 CONFIGURACIÓN COMPLETADA!"
echo "📍 Servidor: $DDNS_SERVER:$VPN_PORT"
echo "📍 Clientes creados: $NUM_CLIENTES"
echo "📍 Archivos en /tmp/: client1.ovpn ... client$NUM_CLIENTES.ovpn"
echo ""

echo "🔄 Reiniciando en 10 segundos..."
sleep 10
reboot
