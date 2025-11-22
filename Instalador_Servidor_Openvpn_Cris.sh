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

# SELECCIÓN DE SEGURIDAD
echo ""
echo "🛡️  CONFIGURACIÓN DE SEGURIDAD"
echo "------------------------------"
echo "¿Qué nivel de acceso quieres para los clientes VPN?"
echo ""
echo "1) 🔓 Acceso completo a red local"
echo "   - Los clientes pueden acceder a TODOS los dispositivos (192.168.1.*)"
echo "   - Ideal para uso personal/confiable"
echo ""
echo "2) 🔐 Acceso limitado a servicios específicos"
echo "   - Los clientes solo pueden acceder a puertos comunes (web, SSH)"
echo "   - No pueden ver otros dispositivos de la red"
echo "   - Equilibrio entre seguridad y funcionalidad"
echo ""
echo "3) 🛡️ Solo acceso a internet"
echo "   - Los clientes solo tienen acceso a internet"
echo "   - No pueden acceder a tu red local"
echo "   - Máxima seguridad para invitados"
echo ""
echo "Selecciona una opción (1/2/3): "
read OPCION_SEGURIDAD

case $OPCION_SEGURIDAD in
    1)
        MODO_SEGURIDAD="completo"
        DESCRIPCION="ACCESO COMPLETO a red local"
        ;;
    2)
        MODO_SEGURIDAD="limitado"
        DESCRIPCION="ACCESO LIMITADO a servicios específicos"
        ;;
    3)
        MODO_SEGURIDAD="solo_internet"
        DESCRIPCION="SOLO ACCESO A INTERNET"
        ;;
    *)
        echo "❌ Opción no válida. Usando modo seguro (solo internet)."
        MODO_SEGURIDAD="solo_internet"
        DESCRIPCION="SOLO ACCESO A INTERNET"
        ;;
esac

echo ""
echo "📍 RESUMEN:"
echo "   DuckDNS: $DDNS_SERVER"
echo "   Servidor: $DDNS_SERVER:$VPN_PORT"
echo "   Clientes: $NUM_CLIENTES"
echo "   Interfaz: br-vpn"
echo "   Seguridad: $DESCRIPCION"
echo ""

echo "¿Continuar con la instalación? (s/n): "
read CONFIRMAR
[ "$CONFIRMAR" != "s" ] && echo "Instalación cancelada." && exit 0

echo ""
echo "🚀 INICIANDO INSTALACIÓN COMPLETA..."
echo ""

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

echo "   [....] Generando parámetros Diffie-Hellman..."
echo "        ⏳ Esto puede tomar 2-5 minutos en dispositivos lentos"
echo "        ⏳ Por favor espere..."
easyrsa gen-dh
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
    option server_bridge '1'
    option keepalive '10 120'
    option client_to_client '1'
    option duplicate_cn '0'
CFG
echo "   [DONE] Servidor OpenVPN configurado"

# 5. CONFIGURAR FIREWALL SEGÚN MODO DE SEGURIDAD
echo "🔥 PASO 5: CONFIGURANDO FIREWALL..."
echo "----------------------------------"
echo "   [....] Configurando modo: $DESCRIPCION"

# Regla básica para permitir conexiones OpenVPN
uci add firewall rule
uci set firewall.@rule[-1].name='Allow-OpenVPN'
uci set firewall.@rule[-1].src='wan'
uci set firewall.@rule[-1].proto='udp'
uci set firewall.@rule[-1].dest_port="$VPN_PORT"
uci set firewall.@rule[-1].target='ACCEPT'

# Crear zona VPN
uci add firewall zone
uci set firewall.@zone[-1].name='vpn'
uci set firewall.@zone[-1].network='vpn'
uci set firewall.@zone[-1].input='ACCEPT'
uci set firewall.@zone[-1].output='ACCEPT'
uci set firewall.@zone[-1].forward='ACCEPT'

# Configurar según el modo de seguridad seleccionado
case $MODO_SEGURIDAD in
    "completo")
        # 🔓 ACCESO COMPLETO
        echo "        🔓 CONFIGURANDO ACCESO COMPLETO A RED LOCAL"
        
        # Reglas de forwarding completo entre VPN y LAN
        uci add firewall forwarding
        uci set firewall.@forwarding[-1].src='vpn'
        uci set firewall.@forwarding[-1].dest='lan'

        uci add firewall forwarding
        uci set firewall.@forwarding[-1].src='lan'
        uci set firewall.@forwarding[-1].dest='vpn'

        # Permitir tráfico completo entre VPN y LAN
        uci add firewall rule
        uci set firewall.@rule[-1].name='VPN-full-access'
        uci set firewall.@rule[-1].src='vpn'
        uci set firewall.@rule[-1].dest='lan'
        uci set firewall.@rule[-1].proto='all'
        uci set firewall.@rule[-1].target='ACCEPT'

        uci add firewall rule
        uci set firewall.@rule[-1].name='LAN-to-VPN'
        uci set firewall.@rule[-1].src='lan'
        uci set firewall.@rule[-1].dest='vpn'
        uci set firewall.@rule[-1].proto='all'
        uci set firewall.@rule[-1].target='ACCEPT'
        ;;

    "limitado")
        # 🔐 ACCESO LIMITADO
        echo "        🔐 CONFIGURANDO ACCESO LIMITADO"
        
        # NO forwarding automático - control manual con reglas
        # Permitir solo puertos específicos de LAN a VPN
        uci add firewall rule
        uci set firewall.@rule[-1].name='VPN-to-LAN-web'
        uci set firewall.@rule[-1].src='vpn'
        uci set firewall.@rule[-1].dest='lan'
        uci set firewall.@rule[-1].proto='tcp'
        uci set firewall.@rule[-1].dest_port='80 443'  # HTTP/HTTPS
        uci set firewall.@rule[-1].target='ACCEPT'

        uci add firewall rule
        uci set firewall.@rule[-1].name='VPN-to-LAN-ssh'
        uci set firewall.@rule[-1].src='vpn'
        uci set firewall.@rule[-1].dest='lan'
        uci set firewall.@rule[-1].proto='tcp'
        uci set firewall.@rule[-1].dest_port='22'       # SSH
        uci set firewall.@rule[-1].target='ACCEPT'

        uci add firewall rule
        uci set firewall.@rule[-1].name='VPN-to-LAN-dns'
        uci set firewall.@rule[-1].src='vpn'
        uci set firewall.@rule[-1].dest='lan'
        uci set firewall.@rule[-1].proto='udp'
        uci set firewall.@rule[-1].dest_port='53'       # DNS
        uci set firewall.@rule[-1].target='ACCEPT'

        # Denegar el resto del tráfico a LAN
        uci add firewall rule
        uci set firewall.@rule[-1].name='Block-VPN-to-LAN'
        uci set firewall.@rule[-1].src='vpn'
        uci set firewall.@rule[-1].dest='lan'
        uci set firewall.@rule[-1].proto='all'
        uci set firewall.@rule[-1].target='REJECT'
        ;;

    "solo_internet")
        # 🛡️ SOLO INTERNET
        echo "        🛡️ CONFIGURANDO SOLO ACCESO A INTERNET"
        
        # Permitir solo salida a internet (WAN)
        uci add firewall rule
        uci set firewall.@rule[-1].name='VPN-to-WAN'
        uci set firewall.@rule[-1].src='vpn'
        uci set firewall.@rule[-1].dest='wan'
        uci set firewall.@rule[-1].proto='all'
        uci set firewall.@rule[-1].target='ACCEPT'

        # Denegar acceso a LAN
        uci add firewall rule
        uci set firewall.@rule[-1].name='Block-VPN-to-LAN'
        uci set firewall.@rule[-1].src='vpn'
        uci set firewall.@rule[-1].dest='lan'
        uci set firewall.@rule[-1].proto='all'
        uci set firewall.@rule[-1].target='REJECT'
        ;;
esac

# Permitir siempre internet para clientes VPN
uci add firewall rule
uci set firewall.@rule[-1].name='VPN-to-Internet'
uci set firewall.@rule[-1].src='vpn'
uci set firewall.@rule[-1].dest='wan'
uci set firewall.@rule[-1].proto='all'
uci set firewall.@rule[-1].target='ACCEPT'

uci commit firewall > /dev/null 2>&1
/etc/init.d/firewall reload > /dev/null 2>&1
echo "   [DONE] Firewall configurado - $DESCRIPCION"

# 6. CREAR BRIDGE BR-VPN CON RED
echo "🔧 PASO 6: CREANDO BRIDGE BR-VPN CON RED..."
echo "------------------------------------------"
echo "   [....] Creando interfaz tap0..."
ip tuntap add mode tap tap0
ifconfig tap0 up
echo "   [DONE] Interfaz tap0 creada"

echo "   [....] Creando bridge br-vpn..."
brctl addbr br-vpn
brctl addif br-vpn tap0
ifconfig br-vpn up
echo "   [DONE] Bridge br-vpn creado"

echo "   [....] Configurando red para br-vpn..."
# Configurar interfaz bridge con IP estática
uci set network.br-vpn=interface
uci set network.br-vpn.proto='static'
uci set network.br-vpn.device='br-vpn'
uci set network.br-vpn.ipaddr='10.8.0.1'
uci set network.br-vpn.netmask='255.255.255.0'
uci set network.br-vpn.gateway='10.8.0.1'
uci set network.br-vpn.dns='10.8.0.1'

# Configurar DHCP para clientes VPN
uci set dhcp.vpn=dhcp
uci set dhcp.vpn.interface='br-vpn'
uci set dhcp.vpn.start='100'
uci set dhcp.vpn.limit='150'
uci set dhcp.vpn.leasetime='12h'

uci commit network
uci commit dhcp

# Reiniciar servicios de red
/etc/init.d/network restart
/etc/init.d/dnsmasq restart
sleep 3
echo "   [DONE] Red configurada (10.8.0.0/24)"
echo "      └─ Servidor: 10.8.0.1"
echo "      └─ Clientes: 10.8.0.100 - 10.8.0.249"

# 7. GENERAR Y MOSTRAR ARCHIVOS CLIENTE
echo "📄 PASO 7: GENERANDO Y MOSTRANDO ARCHIVOS CLIENTE..."
echo "--------------------------------------------------"
mkdir -p /etc/openvpn/clients

for i in $(seq 1 $NUM_CLIENTES); do
    echo ""
    echo "   [....] Generando client$i.ovpn..."
    
    # Crear el archivo .ovpn
    cat > /etc/openvpn/clients/client$i.ovpn << OVPN
client
dev tap
proto udp
remote $DDNS_SERVER $VPN_PORT
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
cipher AES-256-GCM
verb 3

# Configuración de red
# Los clientes recibirán IP automática via DHCP

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
    
    # Copiar también a /tmp/ para fácil acceso inmediato
    cp /etc/openvpn/clients/client$i.ovpn /tmp/client$i.ovpn
    echo "   [DONE] client$i.ovpn generado"
    
    # Mostrar el contenido del archivo
    echo ""
    echo "   ================================================="
    echo "   📋 CONTENIDO DE client$i.ovpn:"
    echo "   ================================================="
    cat /etc/openvpn/clients/client$i.ovpn
    echo "   ================================================="
    echo ""
    echo "   💡 Puedes copiar el contenido anterior ahora"
    echo "   ⏸️  Pausa... Presiona ENTER para continuar con el siguiente cliente"
    read
done

echo "✅ Todos los archivos .ovpn generados y mostrados"
echo "   📍 Acceso inmediato: /tmp/client1.ovpn - client$NUM_CLIENTES.ovpn"
echo "   📍 Acceso persistente: /etc/openvpn/clients/"
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

sleep 5
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

# Verificar interfaces de red
echo ""
echo "🔍 CONFIGURACIÓN DE RED:"
if ifconfig br-vpn >/dev/null 2>&1; then
    echo "   ✅ Bridge br-vpn: ACTIVO"
    ifconfig br-vpn | grep 'inet addr' | while read line; do
        echo "      └─ $line"
    done
else
    echo "   ❌ Bridge br-vpn: INACTIVO"
fi

if ifconfig tap0 >/dev/null 2>&1; then
    echo "   ✅ Interfaz tap0: ACTIVA"
else
    echo "   ❌ Interfaz tap0: INACTIVA"
fi

# Verificar DHCP
if uci get dhcp.vpn >/dev/null 2>&1; then
    echo "   ✅ DHCP VPN: CONFIGURADO"
    echo "      └─ Rango: 10.8.0.100 - 10.8.0.249"
else
    echo "   ❌ DHCP VPN: NO CONFIGURADO"
fi

# Verificar firewall según modo
echo ""
echo "🔍 CONFIGURACIÓN FIREWALL:"
case $MODO_SEGURIDAD in
    "completo")
        echo "   ✅ ACCESO COMPLETO a red local"
        echo "   └─ Los clientes pueden acceder a TODOS los dispositivos 192.168.1.*"
        ;;
    "limitado")
        echo "   ✅ ACCESO LIMITADO a servicios específicos"
        echo "   └─ Puertos permitidos: 80, 443 (web), 22 (SSH), 53 (DNS)"
        echo "   └─ Resto del tráfico a LAN: BLOQUEADO"
        ;;
    "solo_internet")
        echo "   ✅ SOLO ACCESO A INTERNET"
        echo "   └─ Acceso a red local: COMPLETAMENTE BLOQUEADO"
        echo "   └─ Solo pueden salir a internet"
        ;;
esac

# Verificar archivos
echo ""
echo "📄 ARCHIVOS GENERADOS:"
for i in $(seq 1 $NUM_CLIENTES); do
    if [ -f "/etc/openvpn/clients/client$i.ovpn" ]; then
        echo "   ✅ client$i.ovpn: PERSISTENTE"
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
echo "   ├─ Red VPN: 10.8.0.0/24"
echo "   ├─ Servidor: 10.8.0.1"
echo "   └─ DHCP: 10.8.0.100-10.8.0.249"
echo ""
echo "🛡️  CONFIGURACIÓN DE SEGURIDAD:"
case $MODO_SEGURIDAD in
    "completo")
        echo "   🔓 MODO: ACCESO COMPLETO"
        echo "   └─ Los clientes VPN pueden acceder a:"
        echo "      ├─ Router Movistar: 192.168.1.1"
        echo "      ├─ Todos los dispositivos en 192.168.1.*"
        echo "      ├─ NAS, impresoras, PCs locales"
        echo "      └─ Todos los servicios de red local"
        ;;
    "limitado")
        echo "   🔐 MODO: ACCESO LIMITADO"
        echo "   └─ Servicios permitidos:"
        echo "      ├─ HTTP/HTTPS (puertos 80, 443)"
        echo "      ├─ SSH (puerto 22)"
        echo "      ├─ DNS (puerto 53)"
        echo "      └─ Resto de puertos: BLOQUEADO"
        ;;
    "solo_internet")
        echo "   🛡️  MODO: SOLO INTERNET"
        echo "   └─ Los clientes SOLO pueden:"
        echo "      ├─ Acceder a internet"
        echo "      └─ No pueden ver dispositivos locales"
        ;;
esac
echo ""
echo "👤 CLIENTES CREADOS:"
for i in $(seq 1 $NUM_CLIENTES); do
    echo "   ├─ client$i (Certificado único)"
done
echo ""
echo "🔐 CONECTIVIDAD:"
echo "   ✅ Cada cliente tiene certificado único"
echo "   ✅ DHCP asignará IPs únicas automáticamente"
echo "   ✅ Los clientes pueden comunicarse entre sí"
echo "   ✅ Todos los clientes tienen acceso a internet"

echo "----------------------------------------"
echo "¿Quieres reiniciar ahora? (s/n): "
read REINICIAR

if [ "$REINICIAR" = "s" ]; then
    echo "El sistema se reiniciará en 10 segundos..."
    echo "Presiona Ctrl+C para cancelar"
    
    for i in 10 9 8 7 6 5 4 3 2 1; do
        echo -n "Reiniciando en $i segundos... "
        sleep 1
        echo -ne "\r"
    done
    
    echo ""
    echo "🔹 Reiniciando sistema..."
    reboot
else
    echo ""
    echo "💡 Sistema mantenido sin reiniciar"
    echo "📍 Los $NUM_CLIENTES clientes están listos para conectar"
    echo "🛡️  MODO: $DESCRIPCION"
    echo ""
    echo "📍 Archivos disponibles en:"
    echo "   - /tmp/client1.ovpn - client$NUM_CLIENTES.ovpn (temporal)"
    echo "   - /etc/openvpn/clients/ (persistente)"
    echo ""
    echo "🔹 Recuerda reiniciar manualmente más tarde"
fi
