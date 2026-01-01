#!/bin/sh

echo ""
echo "🔧 INSTALANDO VERSIÓN CON FILTRO MEJORADO"
echo "========================================="

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
    echo "2) ❌ Salir"
    echo ""
    echo -n "Selecciona [1-2]: "
}

# FUNCIÓN VER_CONECTADOS CON FILTRO MEJORADO
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
        # Solo procesar líneas que tengan el formato correcto:
        # client2,88.0.78.97:37861,42844,537034213,2026-01-02 00:10:47
        
        # Buscar en la sección CLIENT LIST (antes de ROUTING_TABLE)
        encontrados=0
        
        # Leer línea por línea
        while IFS= read -r linea; do
            # Filtrar líneas que NO queremos mostrar
            if echo "$linea" | grep -q -i "ROUTING_TABLE\|GLOBAL_STATS\|END\|Virtual Address\|Common Name\|Max bcast"; then
                continue
            fi
            
            # Filtrar líneas que SÍ queremos (formato cliente,ip,bytes,bytes,fecha)
            if echo "$linea" | grep -q "^[a-zA-Z0-9_]\+,[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+:[0-9]\+,.*,.*,20[0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9]$"; then
                
                # Separar por comas
                cliente=$(echo "$linea" | cut -d',' -f1)
                ip_puerto=$(echo "$linea" | cut -d',' -f2)
                bytes_rx=$(echo "$linea" | cut -d',' -f3)
                bytes_tx=$(echo "$linea" | cut -d',' -f4)
                fecha_hora=$(echo "$linea" | cut -d',' -f5)
                
                # Mostrar información
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
                encontrados=1
            fi
        done < "$STATUS_FILE"
        
        if [ $encontrados -eq 0 ]; then
            echo "ℹ️  No hay clientes conectados"
        fi
        
    else
        echo "⚠️  Formato de archivo no compatible"
    fi
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
echo "🔧 FILTROS APLICADOS:"
echo "   ❌ ROUTING_TABLE"
echo "   ❌ GLOBAL_STATS"
echo "   ❌ END"
echo "   ❌ Virtual Address"
echo "   ❌ Common Name"
echo "   ❌ Max bcast"
echo ""
echo "✅ Solo mostrará clientes reales con formato:"
echo "   cliente,ip:puerto,bytes_rx,bytes_tx,fecha"
echo ""
echo "🚀 Ejecuta: gestion"
