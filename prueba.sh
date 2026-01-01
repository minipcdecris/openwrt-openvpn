#!/bin/sh

echo ""
echo "🔧 INSTALANDO SISTEMA DE GESTIÓN VPN"
echo "===================================="

# Primero, crear el directorio de configuración
mkdir -p /etc/openvpn/clientes

# Crear archivos de configuración
touch /etc/openvpn/clientes/nombres.txt
touch /etc/openvpn/clientes/ip_history.txt
touch /etc/openvpn/clientes/suspended.txt
touch /etc/openvpn/clientes/vpn_gestion.log

# Ahora crear el script principal en /usr/bin/gestion
cat > /usr/bin/gestion << 'EOF'
#!/bin/sh

# Archivos de configuración
NOMBRES_FILE="/etc/openvpn/clientes/nombres.txt"
IP_HISTORY_FILE="/etc/openvpn/clientes/ip_history.txt"
SUSPENDED_FILE="/etc/openvpn/clientes/suspended.txt"
LOG_FILE="/etc/openvpn/clientes/vpn_gestion.log"

# Función para escribir en log
escribir_log() {
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" >> "$LOG_FILE"
}

# Función para limpiar nombre de certificado
limpiar_nombre() {
    echo "$1" | sed 's|/CN=||'
}

# Función para obtener nombre descriptivo
obtener_nombre() {
    cliente="$1"
    cliente_limpio=$(limpiar_nombre "$cliente")
    
    if [ -f "$NOMBRES_FILE" ]; then
        nombre=$(grep "^$cliente_limpio:" "$NOMBRES_FILE" 2>/dev/null | cut -d: -f2-)
        if [ -n "$nombre" ]; then
            echo "$nombre"
            return
        fi
    fi
    echo "$cliente_limpio"
}

# Función para buscar archivo de estado
buscar_archivo_estado() {
    # Lista de posibles ubicaciones
    lugares="
        /var/log/openvpn-status.log
        /tmp/openvpn-status.log
        /etc/openvpn/status.log
        /etc/openvpn/server/status.log
    "
    
    for archivo in $lugares; do
        if [ -f "$archivo" ]; then
            echo "$archivo"
            return 0
        fi
    done
    echo ""
    return 1
}

# Función para mostrar menú
mostrar_menu() {
    clear
    echo ""
    echo "🔧 GESTIÓN VPN - SISTEMA COMPLETO"
    echo "=================================="
    echo ""
    echo "1) 👁️  Ver clientes conectados"
    echo "2) 📋 Listar estado de clientes"
    echo "3) 🚫 BLOQUEAR cliente"
    echo "4) ✅ DESBLOQUEAR cliente"
    echo "5) 🏷️  Gestionar nombres"
    echo "6) 🔍 Estado del sistema"
    echo "7) 📝 Registrar IP manualmente"
    echo "8) ❌ Salir"
    echo ""
    echo -n "Selecciona [1-8]: "
}

# Función para ver clientes conectados
ver_conectados() {
    echo ""
    echo "📊 CLIENTES CONECTADOS"
    echo "======================"
    echo ""
    
    # Buscar archivo de estado
    STATUS_FILE=$(buscar_archivo_estado)
    
    if [ -z "$STATUS_FILE" ]; then
        echo "❌ No se encuentra el archivo de estado de OpenVPN"
        echo ""
        echo "💡 SOLUCIONES:"
        echo "   1. Asegúrate de que OpenVPN esté ejecutándose"
        echo "   2. Configura OpenVPN para crear el archivo:"
        echo "      Añade esto a /etc/openvpn/server.conf:"
        echo "      status /var/log/openvpn-status.log 30"
        echo "   3. Reinicia OpenVPN: systemctl restart openvpn"
        echo ""
        return
    fi
    
    echo "📁 Archivo de estado: $STATUS_FILE"
    echo ""
    
    if [ ! -s "$STATUS_FILE" ]; then
        echo "ℹ️  El archivo está vacío"
        echo "   No hay clientes conectados actualmente"
        return
    fi
    
    # Procesar formato v2 (comma separated)
    if grep -q "^CLIENT_LIST," "$STATUS_FILE"; then
        contador=0
        grep "^CLIENT_LIST," "$STATUS_FILE" | while IFS= read -r linea; do
            cliente=$(echo "$linea" | cut -d, -f2 2>/dev/null)
            ip_real=$(echo "$linea" | cut -d, -f3 2>/dev/null)
            
            if [ -n "$cliente" ] && [ "$cliente" != "UNDEF" ] && [ -n "$ip_real" ]; then
                cliente_limpio=$(echo "$cliente" | sed 's|/CN=||')
                nombre_descriptivo=$(obtener_nombre "$cliente_limpio")
                
                contador=$((contador + 1))
                
                echo "    📍 Cliente $contador"
                echo "    👤 Nombre: $nombre_descriptivo"
                echo "    🔑 Certificado: $cliente_limpio"
                echo "    🌐 IP Real: $ip_real"
                echo ""
            fi
        done
        
        if [ $contador -eq 0 ]; then
            echo "ℹ️  No hay clientes conectados actualmente"
        else
            echo "📊 Total de clientes conectados: $contador"
        fi
    else
        echo "⚠️  Formato de archivo no reconocido"
        echo "Primeras líneas del archivo:"
        head -5 "$STATUS_FILE"
    fi
}

# Función para listar estado de clientes
listar_clientes() {
    echo ""
    echo "📋 CLIENTES DEL HISTORIAL"
    echo "========================"
    echo ""
    
    if [ ! -f "$IP_HISTORY_FILE" ] || [ ! -s "$IP_HISTORY_FILE" ]; then
        echo "📭 No hay clientes en el historial"
        return
    fi
    
    echo "Clientes con IPs registradas:"
    echo ""
    cut -d: -f1 "$IP_HISTORY_FILE" | sort -u | while read cliente; do
        if [ -n "$cliente" ]; then
            nombre=$(obtener_nombre "$cliente")
            echo "   👤 $nombre ($cliente)"
        fi
    done
}

# Función principal
escribir_log "🚀 Sistema de gestión VPN iniciado"

while true; do
    mostrar_menu
    read opcion
    
    escribir_log "📱 Opción seleccionada: $opcion"
    
    case $opcion in
        1)
            ver_conectados
            ;;
        2)
            listar_clientes
            ;;
        3)
            echo ""
            echo "🚫 BLOQUEAR CLIENTE"
            echo "=================="
            echo "Función en desarrollo..."
            ;;
        4)
            echo ""
            echo "✅ DESBLOQUEAR CLIENTE"
            echo "====================="
            echo "Función en desarrollo..."
            ;;
        5)
            echo ""
            echo "🏷️  GESTIONAR NOMBRES"
            echo "===================="
            echo "Función en desarrollo..."
            ;;
        6)
            echo ""
            echo "🔍 ESTADO DEL SISTEMA"
            echo "===================="
            echo ""
            
            if pgrep openvpn >/dev/null 2>&1; then
                echo "✅ OpenVPN: ACTIVO"
            else
                echo "❌ OpenVPN: INACTIVO"
            fi
            
            STATUS_FILE=$(buscar_archivo_estado)
            if [ -n "$STATUS_FILE" ]; then
                echo "📁 Archivo estado: $STATUS_FILE"
            else
                echo "📁 Archivo estado: NO ENCONTRADO"
            fi
            ;;
        7)
            echo ""
            echo "📝 REGISTRAR IP MANUALMENTE"
            echo "==========================="
            echo ""
            echo -n "Nombre del cliente: "
            read cliente
            echo -n "IP a registrar: "
            read ip
            
            if [ -n "$cliente" ] && [ -n "$ip" ]; then
                timestamp=$(date '+%Y-%m-%d %H:%M:%S')
                echo "$cliente:$ip:$timestamp" >> "$IP_HISTORY_FILE"
                echo "✅ IP registrada correctamente"
                escribir_log "IP registrada: $cliente - $ip"
            else
                echo "❌ Error: Datos incompletos"
            fi
            ;;
        8)
            escribir_log "👋 Sistema finalizado"
            echo ""
            echo "👋 Saliendo..."
            exit 0
            ;;
        *)
            echo "❌ Opción inválida"
            ;;
    esac
    
    echo ""
    echo "Presiona Enter para continuar..."
    read dummy
done
EOF

# Dar permisos al script
chmod +x /usr/bin/gestion

echo ""
echo "✅ SISTEMA INSTALADO CORRECTAMENTE"
echo ""
echo "📁 Directorios creados:"
echo "   /etc/openvpn/clientes/"
echo ""
echo "📄 Archivos creados:"
echo "   /etc/openvpn/clientes/nombres.txt"
echo "   /etc/openvpn/clientes/ip_history.txt"
echo "   /etc/openvpn/clientes/suspended.txt"
echo "   /etc/openvpn/clientes/vpn_gestion.log"
echo ""
echo "🚀 COMANDO PARA USAR:"
echo "   gestion"
echo ""
echo "💡 RECOMENDACIÓN:"
echo "   Configura OpenVPN para crear el archivo de estado:"
echo "   echo 'status /var/log/openvpn-status.log 30' >> /etc/openvpn/server.conf"
echo "   systemctl restart openvpn"
