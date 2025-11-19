#!/bin/sh

# Función para configurar red con timeout
configurar_red_segura() {
    echo "🌐 CONFIGURANDO RED (con timeout)..."
    
    # Configurar
    uci set network.lan.igmp_snooping='1'
    uci add_list network.lan.ports='tap0'
    
    # Commit con verificación
    if uci commit network; then
        echo "✅ Configuración de red guardada"
    else
        echo "❌ Error al guardar configuración de red"
        return 1
    fi
    
    # Reiniciar network con timeout
    echo "🔄 Reiniciando servicios de red..."
    /etc/init.d/network restart &
    NETWORK_PID=$!
    
    # Esperar máximo 30 segundos
    for i in $(seq 1 30); do
        if ! ps | grep -q "[ $NETWORK_PID ]"; then
            echo "✅ Reinicio de red completado en ${i}s"
            return 0
        fi
        sleep 1
    done
    
    # Si llegó aquí, timeout
    echo "⚠️  Timeout en reinicio de red, continuando..."
    kill $NETWORK_PID 2>/dev/null
    return 0
}

echo "=== CONFIGURACIÓN SERVIDOR OPENVPN - MODO DEBUG ==="

# Configuración
read -p "DDNS o IP pública: " DDNS_SERVER
read -p "Puerto (1194): " VPN_PORT
VPN_PORT=${VPN_PORT:-1194}
read -p "Clientes (4): " NUM_CLIENTES
NUM_CLIENTES=${NUM_CLIENTES:-4}

echo "Configurando: $DDNS_SERVER:$VPN_PORT"

# Instalar
opkg update
opkg install openvpn-easy-rsa openvpn-openssl

# Certificados
cd /etc/easy-rsa
echo -e "yes\nyes" | easyrsa init-pki
echo -e "yes\nserver" | easyrsa build-ca nopass
echo -e "yes" | easyrsa build-server-full server nopass

for i in $(seq 1 $NUM_CLIENTES); do
    echo "Creando cliente $i..."
    echo -e "yes" | easyrsa build-client-full client$i nopass
done

easyrsa gen-dh

# Copiar archivos
cp pki/ca.crt /etc/openvpn/
cp pki/private/server.key /etc/openvpn/
cp pki/issued/server.crt /etc/openvpn/
cp pki/dh.pem /etc/openvpn/

# Configurar OpenVPN
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

# Firewall
uci add firewall rule
uci set firewall.@rule[-1].name='OpenVPN'
uci set firewall.@rule[-1].src='wan'
uci set firewall.@rule[-1].proto='udp'
uci set firewall.@rule[-1].dest_port="$VPN_PORT"
uci set firewall.@rule[-1].target='ACCEPT'
uci commit firewall
/etc/init.d/firewall restart

# Generar archivos .ovpn
for i in $(seq 1 $NUM_CLIENTES); do
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
done

# CONFIGURAR RED CON MÉTODO SEGURO
if configurar_red_segura; then
    echo "✅ Red configurada exitosamente"
else
    echo "⚠️  Continuando sin configuración completa de red"
fi

# Iniciar OpenVPN
echo "🚀 INICIANDO OPENVPN..."
/etc/init.d/openvpn enable
/etc/init.d/openvpn start

# Verificación final
sleep 5
echo "🔍 VERIFICACIÓN FINAL:"
pgrep openvpn && echo "✅ OpenVPN corriendo" || echo "❌ OpenVPN no corre"
ifconfig tap0 && echo "✅ tap0 activa" || echo "❌ tap0 no activa"

echo "🎉 CONFIGURACIÓN COMPLETADA!"
echo "Reiniciando en 10 segundos..."
sleep 10
reboot
