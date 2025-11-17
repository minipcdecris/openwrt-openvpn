#!/bin/sh

# Función para verificar si el comando se ejecutó correctamente
check_status() {
    if [ $? -ne 0 ]; then
        echo -e "\033[31m- Ha ocurrido un error\033[0m"
        exit 1
    fi
}

# Parte 1: Instalación y generación de certificados

# Actualizar la lista de paquetes
opkg update
check_status

# Instalar OpenVPN, herramientas necesarias y nano
opkg install openvpn-easy-rsa openvpn-openssl luci-app-openvpn nano
check_status

# Verificar la instalación
echo "- Paquetes instalados:"
opkg list-installed | grep -E 'openvpn-easy-rsa|openvpn-openssl|luci-app-openvpn|nano'

echo -e "\033[32m- Instalación completada.\033[0m"

# Acceder al directorio de easy-rsa
cd /etc/easy-rsa
check_status

# Activar las variables de expiración en el archivo vars
sed -i 's/#set_var EASYRSA_CA_EXPIRE.*/set_var EASYRSA_CA_EXPIRE      99999/' vars
sed -i 's/#set_var EASYRSA_CERT_EXPIRE.*/set_var EASYRSA_CERT_EXPIRE    99999/' vars
check_status

# Inicializar el PKI automáticamente respondiendo 'yes' a las preguntas
echo -e "yes\nyes" | easyrsa init-pki
check_status

# Crear la autoridad certificadora (CA) sin contraseña
echo -e "yes\nserver" | easyrsa build-ca nopass
check_status

# Crear el certificado para el servidor sin contraseña y responder 'yes'
echo -e "yes" | easyrsa build-server-full server nopass
check_status

# Crear 4 certificados clientes adicionales
echo -e "\033[32m- Generando certificados para clientes adicionales...\033[0m"

for i in 1 2 3 4; do
    echo "- Generando certificado para client$i..."
    echo -e "yes" | easyrsa build-client-full client$i nopass
    check_status
    echo -e "\033[32m- Certificado para client$i generado con éxito.\033[0m"
done

# Generar los parámetros Diffie-Hellman
easyrsa gen-dh
check_status

# Parte 2: Copiar los archivos generados al directorio de configuración de OpenVPN

# Copiar los archivos generados al directorio de configuración de OpenVPN
cp /etc/easy-rsa/pki/ca.crt /etc/openvpn/
cp /etc/easy-rsa/pki/private/server.key /etc/openvpn/
cp /etc/easy-rsa/pki/issued/server.crt /etc/openvpn/
cp /etc/easy-rsa/pki/dh.pem /etc/openvpn/
check_status

echo -e "\033[32m- Archivos de configuración copiados con éxito.\033[0m"

# Parte 3: Generación del archivo /etc/config/openvpn

cat > /etc/config/openvpn <<EOF
config openvpn 'VPN_Tap_Server'
    option enabled '1'
    option mode 'server'
    option dev 'tap0' 
    option proto 'udp'
    option port '1194'
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

echo -e "\033[32m- Archivo de configuración /etc/config/openvpn generado con éxito.\033[0m"

# Parte 4: Extraer el valor DDNS del archivo /etc/config/ddns si existe

DDNS=""
DDNS_CONFIGURED=false

if [ -f /etc/config/ddns ]; then
    DDNS=$(awk -F"'" '/option lookup_host/ {print $2}' /etc/config/ddns)
    check_status
    DDNS_CONFIGURED=true
else
    echo -e "\033[33m- DDNS no instalado, recuerda modificar manualmente los archivos .ovpn con la dirección correcta.\033[0m"
fi

# Parte 5: Generación de archivos .ovpn para todos los clientes

CLIENTS=("client1" "client2" "client3" "client4")

for CLIENT_NAME in "${CLIENTS[@]}"; do
    echo "- Generando archivo de configuración para $CLIENT_NAME..."
    
    cat > /etc/openvpn/${CLIENT_NAME}.ovpn <<EOF
client
dev tap
proto udp
remote ${DDNS:-"DDNS_AQUI"} 1194
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
    echo -e "\033[32m- Archivo ${CLIENT_NAME}.ovpn generado con éxito.\033[0m"
done

# Crear un archivo bundle con todos los clientes
echo "- Creando bundle con todos los archivos de cliente..."
tar -czf /etc/openvpn/clientes_openvpn.tar.gz -C /etc/openvpn/ client1.ovpn client2.ovpn client3.ovpn client4.ovpn
check_status
echo -e "\033[32m- Bundle clientes_openvpn.tar.gz creado con éxito.\033[0m"

# Parte 6: Añadir la interfaz tap0 al bridge br-lan

echo -e "\033[32m- Añadiendo tap0 al bridge br-lan...\033[0m"
sed -i "/option name 'br-lan'/a \ \ \ \ list ports 'tap0'\n    option igmp_snooping '1'" /etc/config/network
check_status

echo -e "\033[32m- La interfaz tap0 ha sido añadida al bridge br-lan y se ha activado el IGMP snooping.\033[0m"

# Parte 7: Añadir el reinicio de DDNS en /etc/rc.local antes de exit 0, solo si DDNS está configurado
if $DDNS_CONFIGURED; then
    sed -i '/exit 0/i /etc/init.d/ddns restart' /etc/rc.local
    check_status
    echo -e "\033[32m- Se ha configurado el reinicio de DDNS en /etc/rc.local.\033[0m"
fi

# Mostrar resumen de archivos generados
echo -e "\n\033[32m=== RESUMEN DE ARCHIVOS GENERADOS ===\033[0m"
echo -e "\033[32m- Archivos de configuración cliente:\033[0m"
for CLIENT_NAME in "${CLIENTS[@]}"; do
    echo -e "  • /etc/openvpn/${CLIENT_NAME}.ovpn"
done
echo -e "\033[32m- Bundle completo:\033[0m"
echo -e "  • /etc/openvpn/clientes_openvpn.tar.gz"
echo -e "\033[32m- Certificados del servidor:\033[0m"
echo -e "  • /etc/openvpn/ca.crt"
echo -e "  • /etc/openvpn/server.crt"
echo -e "  • /etc/openvpn/server.key"
echo -e "  • /etc/openvpn/dh.pem"

echo -e "\n\033[32m- Servidor configurado con éxito con 4 clientes disponibles.\033[0m"

# Informar que el dispositivo se va a reiniciar en 5 segundos
echo "- El dispositivo se reiniciará en 5 segundos..."

# Esperar 5 segundos
sleep 5

# Reiniciar el dispositivo
reboot
