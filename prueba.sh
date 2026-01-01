#!/bin/sh

echo ""
echo "🔧 INSTALANDO VERSIÓN SIMPLIFICADA"
echo "=================================="

cat > /usr/bin/gestion << 'EOF'
#!/bin/sh

# Función para mostrar menú
mostrar_menu() {
    clear
    echo ""
    echo "🔧 GESTIÓN VPN"
    echo "=============="
    echo ""
    echo "1) 👁️  Ver clientes conectados"
    echo "2) 📋 Listar estado de clientes"
    echo "3) 🚫 BLOQUEAR cliente"
    echo "4) ✅ DESBLOQUEAR cliente"
    echo "5) 🏷️  Gestionar nombres"
    echo "6) ❌ Salir"
    echo ""
    echo -n "Selecciona [1-6]: "
}

# FUNCIÓN VER_CONECTADOS SIMPLIFICADA
ver_conectados() {
    echo ""
    echo "📊 CLIENTES CONECTADOS:"
    echo ""
    
    # Archivo de estado
    STATUS_FILE="/tmp/run/openvpn.VPN_Server.status"
    
    if [ ! -f "$STATUS_FILE" ] || [ ! -s "$STATUS_FILE" ]; then
        echo "❌ No se encuentra archivo de estado"
        return
    fi
    
    # Verificar formato CSV
    if head -1 "$STATUS_FILE" | grep -q "OpenVPN CLIENT LIST"; then
        # Formato CSV con comas
        # Saltar primeras 3 líneas (encabezados)
        # Línea 4+ son datos: client2,88.0.78.97:37861,42844,537034213,2026-01-02 00:10:47
        
        # Buscar líneas con datos reales
        tail -n +4 "$STATUS_FILE" | head -20 > /tmp/clientes_temp.txt
        
        if [ ! -s /tmp/clientes_temp.txt ]; then
            echo "ℹ️  No hay clientes conectados"
            rm -f /tmp/clientes_temp.txt
            return
        fi
        
        # Procesar cada cliente
        while IFS= read -r linea; do
            # Ignorar líneas vacías
            if [ -z "$linea" ]; then
                continue
            fi
            
            # Separar por comas
            cliente=$(echo "$linea" | cut -d',' -f1)
            ip_puerto=$(echo "$linea" | cut -d',' -f2)
            bytes_rx=$(echo "$linea" | cut -d',' -f3)
            bytes_tx=$(echo "$linea" | cut -d',' -f4)
            fecha_hora=$(echo "$linea" | cut -d',' -f5)
            
            # Verificar que sea un cliente real
            if [ -n "$cliente" ] && [ "$cliente" != "Common Name" ]; then
                # Mostrar información EXACTAMENTE como la necesitas
                echo "👤 $cliente"
                echo "   🔑 Certificado: $cliente"
                echo "   🌐 IP: $ip_puerto"
                
                # Formatear tráfico
                if echo "$bytes_rx" | grep -q '^[0-9]\+$'; then
                    if [ "$bytes_rx" -lt 1024 ]; then
                        echo "   📥 Descargado: ${bytes_rx} B"
                    elif [ "$bytes_rx" -lt 1048576 ]; then
                        kb_rx=$((bytes_rx / 1024))
                        echo "   📥 Descargado: ${kb_rx} KB"
                    else
                        mb_rx=$((bytes_rx / 1024 / 1024))
                        echo "   📥 Descargado: ${mb_rx} MB"
                    fi
                fi
                
                if echo "$bytes_tx" | grep -q '^[0-9]\+$'; then
                    if [ "$bytes_tx" -lt 1024 ]; then
                        echo "   📤 Enviado: ${bytes_tx} B"
                    elif [ "$bytes_tx" -lt 1048576 ]; then
                        kb_tx=$((bytes_tx / 1024))
                        echo "   📤 Enviado: ${kb_tx} KB"
                    else
                        mb_tx=$((bytes_tx / 1024 / 1024))
                        echo "   📤 Enviado: ${mb_tx} MB"
                    fi
                fi
                
                if [ -n "$fecha_hora" ]; then
                    echo "   🕒 Conectado: $fecha_hora"
                fi
                
                echo ""
            fi
        done < /tmp/clientes_temp.txt
        
        rm -f /tmp/clientes_temp.txt
    else
        echo "⚠️  Formato de archivo no compatible"
    fi
}

# Función para listar estado de clientes (simplificada)
listar_clientes() {
    echo ""
    echo "📋 CLIENTES REGISTRADOS:"
    echo ""
    echo "ℹ️  Función no implementada en versión simplificada"
}

# Función para bloquear cliente (simplificada)
bloquear_cliente() {
    echo ""
    echo "🚫 BLOQUEAR CLIENTE"
    echo ""
    echo "ℹ️  Función no implementada en versión simplificada"
}

# Función para desbloquear cliente (simplificada)
desbloquear_cliente() {
    echo ""
    echo "✅ DESBLOQUEAR CLIENTE"
    echo ""
    echo "ℹ️  Función no implementada en versión simplificada"
}

# Función para gestionar nombres (simplificada)
gestionar_nombres() {
    echo ""
    echo "🏷️  GESTIONAR NOMBRES"
    echo ""
    echo "ℹ️  Función no implementada en versión simplificada"
}

# Programa principal
while true; do
    mostrar_menu
    read opcion
    
    case $opcion in
        1)
            ver_conectados
            ;;
        2)
            listar_clientes
            ;;
        3)
            bloquear_cliente
            ;;
        4)
            desbloquear_cliente
            ;;
        5)
            gestionar_nombres
            ;;
        6)
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

chmod +x /usr/bin/gestion

echo ""
echo "✅ SISTEMA INSTALADO"
echo ""
echo "📋 FORMATO DE SALIDA:"
echo ""
echo "📊 CLIENTES CONECTADOS:"
echo ""
echo "👤 client2"
echo "   🔑 Certificado: client2"
echo "   🌐 IP: 88.0.78.97:37861"
echo "   📥 Descargado: 42844 KB"
echo "   📤 Enviado: 537034213 MB"
echo "   🕒 Conectado: 2026-01-02 00:10:47"
echo ""
echo "🚀 Ejecuta: gestion"
