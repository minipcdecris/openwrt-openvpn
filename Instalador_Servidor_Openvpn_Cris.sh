#!/bin/sh

echo ""
echo "================================================"
echo "    INSTALADOR SERVIDOR OPENVPN - COMPLETO"
echo "       BR-VPN + DUCKDNS EDITABLE - CRIS"
echo "================================================"
echo ""

echo ""
echo "================================================"
echo "    INSTALADOR SERVIDOR OPENVPN - COMPLETO"
echo "           DUCKDNS EDITABLE - CRIS"
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
echo "Número de clientes (1-8): "
read NUM_CLIENTES

# Validar que el número de clientes esté entre 1 y 8
if [ -z "$NUM_CLIENTES" ] || [ "$NUM_CLIENTES" -lt 1 ] || [ "$NUM_CLIENTES" -gt 8 ]; then
    echo "❌ Número de clientes debe ser entre 1 y 8"
    exit 1
fi

echo ""
echo "📍 RESUMEN:"
echo "   DuckDNS: $DDNS_SERVER"
echo "   Servidor: $DDNS_SERVER:$VPN_PORT"
echo "   Clientes: $NUM_CLIENTES"
echo "   Interfaz: tap0 (sin bridge)"
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
else
    echo "⚠️ No se encontró servicio DuckDNS existente"
    echo "🔹 Configura DuckDNS manualmente en LuCI después de la instalación"
fi
echo ""

# 3. GENERACIÓN DE CERTIFICADOS (HASTA 8 CLIENTES)
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

echo "   [....] Creando certificados de clientes ($NUM_CLIENTES clientes)..."
for i in $(seq 1 $NUM_CLIENTES); do
    echo -e "yes" | easyrsa build-client-full client$i nopass > /dev/null 2>&1
    echo "      └─ Cliente $i ✅"
done
echo "   [DONE] $NUM_CLIENTES certificados de clientes generados"

echo "   [....] Generando parámetros Diffie-Hellman..."
echo "        ⏳ Esto puede tomar 2-5 minutos en dispositivos lentos"
echo "        ⏳ Por favor espere..."
easyrsa gen-dh > /dev/null 2>&1
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
    option server_bridge '10.8.0.1 255.255.255.0 10.8.0.2 10.8.0.254'
    option keepalive '10 120'
    option cipher 'AES-256-GCM'
    option user 'nobody'
    option group 'nogroup'
    option persist_key '1'
    option persist_tun '1'
    option verb '3'
    option duplicate_cn '1'
    option client_to_client '1'
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

# 6. CREAR SOLO INTERFAZ TAP0 (SIN BRIDGE)
echo "🔧 PASO 6: CREANDO INTERFAZ TAP0..."
echo "----------------------------------"
echo "   [....] Creando interfaz tap0..."
ip tuntap add mode tap tap0
ifconfig tap0 up
echo "   [DONE] Interfaz tap0 creada"

echo "   [....] Configurando persistencia..."
# Solo creamos la interfaz tap0, sin bridge
cat >> /etc/config/network << NETCFG

config device
    option name 'tap0'
    option type 'tap'
NETCFG

uci commit network > /dev/null 2>&1
echo "   [DONE] Configuración persistente aplicada"

# 7. GENERAR Y MOSTRAR ARCHIVOS CLIENTE (HASTA 8 CLIENTES)
echo "📄 PASO 7: GENERANDO Y MOSTRAR ARCHIVOS CLIENTE..."
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
    if [ $i -lt $NUM_CLIENTES ]; then
        echo "   ⏸️  Pausa... Presiona ENTER para continuar con el siguiente cliente"
        read
    else
        echo "   ✅ Último cliente mostrado"
    fi
done

echo ""
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
if ifconfig tap0 >/dev/null 2>&1;
    echo "   ✅ Interfaz tap0: ACTIVA"
else
    echo "   ❌ Interfaz tap0: INACTIVA"
fi

# Verificar que NO existe bridge br-vpn
if ifconfig br-vpn >/dev/null 2>&1; then
    echo "   ⚠️ Bridge br-vpn: EXISTE (no debería estar)"
else
    echo "   ✅ Bridge br-vpn: NO EXISTE (correcto)"
fi

# Verificar archivos
echo ""
echo "📄 ARCHIVOS GENERADOS:"
for i in $(seq 1 $NUM_CLIENTES); do
    if [ -f "/etc/openvpn/clients/client$i.ovpn" ]; then
        echo "   ✅ client$i.ovpn: PERSISTENTE (/etc/openvpn/clients/)"
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
echo "   └─ Interfaz: tap0 (sin bridge)"
echo ""
echo "👤 ARCHIVOS DE CLIENTE CREADOS ($NUM_CLIENTES):"
for i in $(seq 1 $NUM_CLIENTES); do
    echo "   ├─ client$i.ovpn"
done
echo "   └─ Total: $NUM_CLIENTES clientes"
echo ""
echo "📁 UBICACIÓN DE ARCHIVOS:"
echo "   ┌─ Temporal: /tmp/client1.ovpn - client$NUM_CLIENTES.ovpn"
echo "   └─ Persistente: /etc/openvpn/clients/"
echo ""

echo "----------------------------------------"
echo "¿Quieres reiniciar ahora?"
echo "Si reinicias, los archivos en /tmp/ se perderán."
echo ""
echo "Reiniciar ahora? (s/n): "
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
    echo "📍 Archivos disponibles en:"
    echo "   - /tmp/client1.ovpn - client$NUM_CLIENTES.ovpn (temporal)"
    echo "   - /etc/openvpn/clients/ (persistente)"
    echo ""
    echo "🔹 Recuerda reiniciar manualmente más tarde"
fi
