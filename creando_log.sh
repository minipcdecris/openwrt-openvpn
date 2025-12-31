#!/bin/sh

echo ""
echo "🔧 CONFIGURANDO OPENVPN EN OPENWRT (UCI)"
echo "========================================="

# Detectar si ya existe configuración OpenVPN
if uci show openvpn 2>/dev/null | grep -q "openvpn\."; then
    echo "✅ Configuración OpenVPN encontrada"
    
    # Obtener el nombre de la configuración
    OVPN_CONFIG=$(uci show openvpn | grep "=openvpn$" | cut -d. -f2 | cut -d= -f1 | head -1)
    
    if [ -z "$OVPN_CONFIG" ]; then
        OVPN_CONFIG="custom_config"
        echo "ℹ️  Creando nueva configuración: $OVPN_CONFIG"
        uci set openvpn.$OVPN_CONFIG='openvpn'
    fi
    
    echo "📝 Usando configuración: $OVPN_CONFIG"
else
    echo "ℹ️  No hay configuración OpenVPN, creando nueva..."
    OVPN_CONFIG="server_vpn"
    uci set openvpn.$OVPN_CONFIG='openvpn'
fi

# Configurar opciones básicas
echo ""
echo "⚙️  Configurando opciones de OpenVPN..."

# Asegurarse de que está habilitado
uci set openvpn.$OVPN_CONFIG.enabled='1'

# Configurar archivo de estado
echo "📊 Configurando archivo de estado..."
uci set openvpn.$OVPN_CONFIG.status='/var/log/openvpn-status.log'
uci set openvpn.$OVPN_CONFIG.status_version='2'

# Si no tiene archivo de configuración, crear uno básico
if ! uci get openvpn.$OVPN_CONFIG.config 2>/dev/null; then
    echo "📄 Creando archivo de configuración básica..."
    
    # Crear directorio si no existe
    mkdir -p /etc/openvpn
    
    # Crear configuración básica
    cat > /etc/openvpn/server.conf << 'CONFEOF'
port 1194
proto udp
dev tun
server 10.8.0.0 255.255.255.0
persist-key
persist-tun
keepalive 10 120
cipher AES-256-CBC
verb 3
CONFEOF
    
    uci set openvpn.$OVPN_CONFIG.config='/etc/openvpn/server.conf'
fi

# Guardar cambios
echo "💾 Guardando configuración..."
uci commit openvpn

# Mostrar configuración resultante
echo ""
echo "✅ CONFIGURACIÓN GUARDADA:"
echo "=========================="
uci show openvpn.$OVPN_CONFIG

# Reiniciar OpenVPN
echo ""
echo "🔄 Reiniciando servicio OpenVPN..."
/etc/init.d/openvpn restart 2>/dev/null || /etc/init.d/openvpn start

# Verificar
echo ""
echo "🔍 VERIFICANDO CONFIGURACIÓN..."
sleep 3

if pgrep openvpn >/dev/null; then
    echo "✅ OpenVPN está ejecutándose"
    
    # Esperar a que se cree el archivo
    echo "⏳ Esperando creación del archivo de estado..."
    sleep 5
    
    if [ -f "/var/log/openvpn-status.log" ]; then
        echo "✅ Archivo de estado creado: /var/log/openvpn-status.log"
        echo "📄 Contenido (primeras líneas):"
        head -5 /var/log/openvpn-status.log 2>/dev/null || echo "   (vacío por ahora)"
    else
        echo "⚠️  Archivo no creado aún. Los clientes deben conectarse primero."
        echo "💡 Creando archivo vacío para pruebas..."
        touch /var/log/openvpn-status.log
    fi
else
    echo "❌ OpenVPN no se inició"
    echo "💡 Intenta iniciarlo manualmente:"
    echo "   /etc/init.d/openvpn start"
fi

echo ""
echo "🎯 AHORA PUEDES USAR EL SISTEMA DE GESTIÓN:"
echo "   gestion"
