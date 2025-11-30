#!/bin/sh

echo ""
echo "🌐 CONFIGURANDO ACCESO WEB OPENVPN EN LUCi"
echo "=========================================="

# 1. Instalar paquetes necesarios
echo ""
echo "📦 PASO 1: INSTALANDO PAQUETES LUCi..."
echo "------------------------------------"

if ! opkg list-installed | grep -q "luci-app-openvpn"; then
    echo "   [....] Instalando luci-app-openvpn..."
    opkg update > /dev/null 2>&1
    opkg install luci-app-openvpn > /dev/null 2>&1
    echo "   [DONE] luci-app-openvpn instalado"
else
    echo "   ✅ luci-app-openvpn ya instalado"
fi

# 2. Configurar la interfaz para que aparezca en LuCI
echo ""
echo "⚙️  PASO 2: CONFIGURANDO INTERFAZ EN LUCi..."
echo "------------------------------------------"

# Asegurarse de que la configuración de OpenVPN sea compatible con LuCI
if [ -f "/etc/config/openvpn" ]; then
    echo "   [....] Verificando configuración OpenVPN..."
    
    # LuCI necesita una configuración específica, asegurarnos de que existe
    if ! uci get openvpn.VPN_Server >/dev/null 2>&1; then
        echo "   ❌ No se encontró configuración VPN_Server"
        echo "   🔹 Creando configuración básica para LuCI..."
        
        cat > /etc/config/openvpn << 'OVPN_LUCI'
config openvpn 'VPN_Server'
    option enabled '1'
    option mode 'server'
    option dev 'tap0'
    option proto 'udp'
    option port '1194'
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
    option status '/var/log/openvpn-status.log'
    option status_version '3'
    option log '/var/log/openvpn.log'
    option crl_verify '/etc/openvpn/crl.pem'
OVPN_LUCI
        echo "   [DONE] Configuración creada"
    else
        echo "   ✅ Configuración existente detectada"
    fi
fi

# 3. Crear archivos de ejemplo para clientes en LuCI
echo ""
echo "📁 PASO 3: PREPARANDO ARCHIVOS PARA LUCi..."
echo "-----------------------------------------"

# Crear directorio para archivos de clientes si no existe
mkdir -p /etc/openvpn/luci-clients

# Crear archivo de ejemplo para mostrar en LuCI
cat > /etc/openvpn/luci-clients/README.txt << 'README'
Archivos de clientes OpenVPN disponibles:

- Los archivos .ovpn están en: /etc/openvpn/clients/
- Para descargar: Usa SCP o WinSCP
- IP del router: [Tu IP local]

Comandos útiles:
- gestor-openvpn : Gestión de clientes por terminal
- /etc/init.d/openvpn restart : Reiniciar servicio

Los clientes deben usar el archivo .ovpn correspondiente.
README

echo "   [DONE] Archivos preparados"

# 4. Configurar permisos y reiniciar servicios
echo ""
echo "🔧 PASO 4: CONFIGURANDO PERMISOS..."
echo "---------------------------------"

# Asegurar permisos correctos para los archivos
chmod 644 /etc/openvpn/*.crt 2>/dev/null
chmod 600 /etc/openvpn/*.key 2>/dev/null
chmod 644 /etc/openvpn/*.pem 2>/dev/null

echo "   [DONE] Permisos configurados"

# 5. Reiniciar servicios
echo ""
echo "🔄 PASO 5: REINICIANDO SERVICIOS..."
echo "---------------------------------"

echo "   [....] Reiniciando LuCI..."
/etc/init.d/uhttpd restart >/dev/null 2>&1
echo "   [DONE] LuCI reiniciado"

echo "   [....] Reiniciando OpenVPN..."
/etc/init.d/openvpn restart >/dev/null 2>&1
sleep 3
echo "   [DONE] OpenVPN reiniciado"

# 6. Verificación final
echo ""
echo "✅ VERIFICACIÓN FINAL:"
echo "---------------------"

# Verificar que LuCI puede ver OpenVPN
if [ -d "/usr/lib/lua/luci/model/cbi/openvpn" ]; then
    echo "   ✅ Módulo LuCI OpenVPN: INSTALADO"
else
    echo "   ❌ Módulo LuCI OpenVPN: FALTANTE"
fi

# Verificar servicio OpenVPN
if pgrep openvpn >/dev/null; then
    echo "   ✅ Servicio OpenVPN: ACTIVO"
else
    echo "   ❌ Servicio OpenVPN: INACTIVO"
fi

# Verificar interfaz web
if netstat -tulpn | grep -q ":80"; then
    echo "   ✅ Servicio web (LuCI): ACTIVO"
else
    echo "   ❌ Servicio web (LuCI): INACTIVO"
fi

# Mostrar información de acceso
ROUTER_IP=$(uci get network.lan.ipaddr 2>/dev/null || ip addr show br-lan 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 || echo "192.168.1.1")

echo ""
echo "🌐 INFORMACIÓN DE ACCESO:"
echo "------------------------"
echo "   📍 URL de acceso: http://$ROUTER_IP"
echo "   👤 Usuario: root"
echo "   🔐 Contraseña: [tu contraseña de router]"
echo ""
echo "📍 RUTA EN LUCi:"
echo "   Services → OpenVPN"
echo ""
echo "📊 QUÉ PUEDES HACER EN LUCi:"
echo "   ✅ Ver estado del servidor"
echo "   ✅ Iniciar/Detener servicio"
echo "   ✅ Ver logs en tiempo real"
echo "   ✅ Ver clientes conectados"
echo "   ✅ Configurar opciones avanzadas"
echo ""
echo "🔧 GESTIÓN ADICIONAL:"
echo "   Para gestión avanzada de clientes usa: gestor-openvpn"
echo ""

echo "🎉 CONFIGURACIÓN COMPLETADA!"
