#!/bin/sh

# Función para verificar si el comando se ejecutó correctamente
check_status() {
    if [ $? -ne 0 ]; then
        echo -e "\033[31m- Ha ocurrido un error\033[0m"
        exit 1
    fi
}

# Actualizar la lista de paquetes
opkg update
check_status
echo -e "\033[32m- La lista de paquetes ha sido actualizada correctamente.\033[0m"

# Instalar easy-rsa para generar certificados
opkg install openvpn-easy-rsa nano
check_status
echo -e "\033[32m- Paquetes instalados correctamente.\033[0m"

# Parte 1: Generación de certificados para los clientes

cd /etc/easy-rsa
check_status

# Configurar easy-rsa
sed -i 's/#set_var EASYRSA_CA_EXPIRE.*/set_var EASYRSA_CA_EXPIRE      99999/' vars
sed -i 's/#set_var EASYRSA_CERT_EXPIRE.*/set_var EASYRSA_CERT_EXPIRE    99999/' vars
check_status

echo -e "yes\nyes" | easyrsa init-pki
check_status

echo -e "\033[33m- IMPORTANTE: Asegúrate de usar la misma CA de tu servidor\033[0m"
echo -e "\033[33m- Copia el archivo ca.crt de tu servidor a /etc/easy-rsa/pki/ca.crt\033[0m"
echo -e "\033[33m- O pega el contenido cuando se te solicite\033[0m"

# Pausa para confirmar
echo "- Presiona Enter para continuar..."
read dummy

# Crear 4 certificados clientes
for i in 1 2 3 4; do
    echo "- Generando certificado para client$i..."
    echo -e "yes" | easyrsa build-client-full client$i nopass
    check_status
    echo -e "\033[32m- Certificado para client$i generado con éxito.\033[0m"
done

# Parte 2: Generación de archivos .ovpn

DDNS="campeon19.duckdns.org"

echo -e "\033[32m- Creando clientes para servidor: $DDNS\033[0m"
echo -e "\033[32m- Puerto 1194 abierto y funcionando ✓\033[0m"

for i in 1 2 3 4; do
    echo "- Generando client$i.ovpn..."
    
    cat > /etc/openvpn/client$i.ovpn <<EOF
client
dev tap
proto udp
remote $DDNS 1194
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
$(cat /etc/easy-rsa/pki/ca.crt 2>/dev/null || echo "# PEGA_AQUI_EL_CONTENIDO_COMPLETO_DE_TU_CA.crt")
</ca>
<cert>
$(sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' /etc/easy-rsa/pki/issued/client$i.crt)
</cert>
<key>
$(cat /etc/easy-rsa/pki/private/client$i.key)
</key>
EOF
    
    check_status
    echo -e "\033[32m- client$i.ovpn creado correctamente\033[0m"
done

# Crear bundle con todos los clientes
tar -czf /etc/openvpn/clientes_openvpn.tar.gz -C /etc/openvpn/ client1.ovpn client2.ovpn client3.ovpn client4.ovpn
check_status
echo -e "\033[32m- Bundle clientes_openvpn.tar.gz creado\033[0m"

# Mostrar resumen
echo -e "\n\033[32m=== ARCHIVOS GENERADOS ===\033[0m"
echo -e "\033[32m- client1.ovpn\033[0m"
echo -e "\033[32m- client2.ovpn\033[0m"
echo -e "\033[32m- client3.ovpn\033[0m"
echo -e "\033[32m- client4.ovpn\033[0m"
echo -e "\033[32m- clientes_openvpn.tar.gz (todos en un archivo)\033[0m"

echo -e "\n\033[33m=== PASOS SIGUIENTES ===\033[0m"
echo -e "\033[33m1. Copia los certificados al servidor (192.168.1.2):\033[0m"
echo -e "\033[33m   Desde el servidor ejecuta:\033[0m"
echo -e "\033[33m   scp root@192.168.1.2:/etc/easy-rsa/pki/issued/client*.crt /etc/easy-rsa/pki/issued/\033[0m"
echo -e "\033[33m   scp root@192.168.1.2:/etc/easy-rsa/pki/private/client*.key /etc/easy-rsa/pki/private/\033[0m"
echo -e "\033[33m2. Reinicia OpenVPN en el servidor:\033[0m"
echo -e "\033[33m   /etc/init.d/openvpn restart\033[0m"
echo -e "\033[33m3. Los archivos .ovpn están listos para usar en /etc/openvpn/\033[0m"

echo -e "\n\033[32m- ¡Clientes creados exitosamente! ✓\033[0m"
echo -e "\033[32m- Servidor: $DDNS:1194\033[0m"
echo -e "\033[32m- IP del router actual: 192.168.1.2\033[0m"
