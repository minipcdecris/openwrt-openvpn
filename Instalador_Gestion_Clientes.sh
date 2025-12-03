#!/bin/sh

echo ""
echo "🔧 CORRIGIENDO FUNCIÓN ver_conectados()"
echo "======================================="

# Crear script temporal con la función corregida
cat > /tmp/fix_ver_conectados.sh << 'EOF'
#!/bin/sh

# Extraer el script actual
cp /usr/bin/gestion /tmp/gestion_backup.sh

# Reemplazar la función ver_conectados
sed -i '/^ver_conectados() {/,/^}/d' /usr/bin/gestion

# Insertar la nueva función después de mostrar_menu()
sed -i '/^mostrar_menu() {/,/^}/!b; /^}/a\
\
# Función para ver clientes conectados CON FECHA/HORA CORREGIDA\
ver_conectados() {\
    echo ""\
    echo "📊 CLIENTES CONECTADOS (registrando fecha/hora):"\
    echo ""\
    \
    # Buscar archivo de estado\
    if [ -f "/var/log/openvpn-status.log" ]; then\
        STATUS_FILE="/var/log/openvpn-status.log"\
    elif [ -f "/tmp/openvpn-status.log" ]; then\
        STATUS_FILE="/tmp/openvpn-status.log"\
    else\
        echo "   ⚠️  No se encuentra archivo de estado"\
        escribir_log "⚠️  No se encuentra archivo de estado openvpn-status.log"\
        return\
    fi\
    \
    # DEBUG: Mostrar formato del archivo\
    echo "🔍 Analizando archivo: \$STATUS_FILE"\
    echo "📏 Tamaño: \$(wc -l < "\$STATUS_FILE") líneas"\
    echo ""\
    \
    # Leer clientes conectados - MÚLTIPLES FORMATOS\
    registradas=0\
    \
    # Obtener fecha y hora actual\
    fecha_hora_actual=\$(date '+%d/%m/%Y %H:%M')\
    echo "🕒 Fecha actual: \$fecha_hora_actual"\
    echo ""\
    \
    # FORMATO 1: CLIENT_LIST con comas (OpenVPN 2.4+)\
    if grep -q "^CLIENT_LIST," "\$STATUS_FILE"; then\
        echo "📋 Formato detectado: CLIENT_LIST (separado por comas)"\
        echo ""\
        \
        grep "^CLIENT_LIST," "\$STATUS_FILE" > /tmp/clientes_temp.txt 2>/dev/null\
        \
        while IFS=, read -r tipo cliente ip_puerto bytes_rx bytes_tx conectado_desde username; do\
            if [ -n "\$cliente" ] && [ "\$cliente" != "Common Name" ] && [ "\$cliente" != "UNDEF" ]; then\
                cliente_limpio=\$(limpiar_nombre "\$cliente")\
                nombre_descriptivo=\$(obtener_nombre "\$cliente")\
                \
                # Extraer IP (puede venir con puerto: 192.168.1.1:12345)\
                ip=\$(echo "\$ip_puerto" | cut -d: -f1)\
                \
                # Convertir fecha si está disponible\
                if [ -n "\$conectado_desde" ] && [ "\$conectado_desde" != "UNDEF" ]; then\
                    # Intentar diferentes formatos de fecha\
                    fecha_conexion=""\
                    \
                    # Formato timestamp Unix (ej: 1700000000)\
                    if echo "\$conectado_desde" | grep -q '^[0-9][0-9]*\$' && [ "\$conectado_desde" -gt 1000000000 ]; then\
                        fecha_conexion=\$(date -d @"\$conectado_desde" '+%d/%m/%Y %H:%M' 2>/dev/null || echo "Conectado recientemente")\
                    else\
                        fecha_conexion="Conectado recientemente"\
                    fi\
                else\
                    fecha_conexion="Conectado recientemente"\
                fi\
                \
                # Registrar en historial\
                timestamp=\$(date '+%Y-%m-%d %H:%M:%S')\
                \
                # Eliminar entrada antigua si existe\
                grep -v "^\$cliente_limpio:\$ip:" "\$IP_HISTORY_FILE" > /tmp/ip_temp.txt 2>/dev/null\
                mv /tmp/ip_temp.txt "\$IP_HISTORY_FILE" 2>/dev/null\
                \
                # Añadir nueva entrada\
                echo "\$cliente_limpio:\$ip:\$timestamp:\$fecha_conexion" >> "\$IP_HISTORY_FILE"\
                registradas=\$((registradas + 1))\
                \
                # Registrar en log\
                escribir_log "📡 Cliente \$nombre_descriptivo (\$cliente_limpio) conectado desde \$ip_puerto"\
                \
                # Mostrar información\
                echo "👤 \$nombre_descriptivo (\$cliente_limpio)"\
                echo "   📍 IP: \$ip_puerto"\
                echo "   🕒 Conectado: \$fecha_conexion"\
                echo ""\
            fi\
        done < /tmp/clientes_temp.txt\
        \
        rm -f /tmp/clientes_temp.txt\
    \
    # FORMATO 2: CLIENT_LIST con espacios (formato antiguo que SÍ funcionaba)\
    elif grep -q "^CLIENT_LIST" "\$STATUS_FILE" && grep "^CLIENT_LIST" "\$STATUS_FILE" | head -1 | grep -q " "; then\
        echo "📋 Formato detectado: CLIENT_LIST (separado por espacios)"\
        echo ""\
        \
        grep "^CLIENT_LIST" "\$STATUS_FILE" > /tmp/clientes_temp.txt 2>/dev/null\
        \
        while read linea; do\
            # Usar el formato de la versión ANTERIOR que SÍ funcionaba\
            cliente=\$(echo "\$linea" | awk '{print \$2}')\
            ip_externa=\$(echo "\$linea" | awk '{print \$3}')\
            fecha_conexion_raw=\$(echo "\$linea" | awk '{print \$9, \$10}')\
            \
            if [ -n "\$cliente" ] && [ "\$ip_externa" != "UNDEF" ]; then\
                cliente_limpio=\$(limpiar_nombre "\$cliente")\
                nombre_descriptivo=\$(obtener_nombre "\$cliente")\
                \
                # Convertir fecha de conexión a formato legible\
                if [ -n "\$fecha_conexion_raw" ] && [ "\$fecha_conexion_raw" != "UNDEF" ]; then\
                    # OpenVPN usa formato timestamp Unix\
                    if echo "\$fecha_conexion_raw" | grep -q "^[0-9]"; then\
                        fecha_conexion=\$(date -d @"\$fecha_conexion_raw" '+%d/%m/%Y %H:%M' 2>/dev/null || echo "Conectado recientemente")\
                    else\
                        fecha_conexion="Conectado recientemente"\
                    fi\
                else\
                    fecha_conexion="Conectado recientemente"\
                fi\
                \
                # Registrar IP automáticamente con fecha/hora de conexión\
                timestamp=\$(date '+%Y-%m-%d %H:%M:%S')\
                \
                # Eliminar entrada antigua si existe\
                grep -v "^\$cliente_limpio:\$ip_externa:" "\$IP_HISTORY_FILE" > /tmp/ip_temp.txt 2>/dev/null\
                mv /tmp/ip_temp.txt "\$IP_HISTORY_FILE" 2>/dev/null\
                \
                # Añadir nueva entrada con fecha/hora de conexión\
                echo "\$cliente_limpio:\$ip_externa:\$timestamp:\$fecha_conexion" >> "\$IP_HISTORY_FILE"\
                registradas=\$((registradas + 1))\
                \
                # Registrar en log\
                escribir_log "📡 Cliente \$nombre_descriptivo (\$cliente_limpio) conectado desde \$ip_externa - \$fecha_conexion"\
                \
                # Mostrar información\
                if [ "\$cliente_limpio" = "\$nombre_descriptivo" ]; then\
                    echo "👤 \$cliente_limpio"\
                else\
                    echo "👤 \$nombre_descriptivo (\$cliente_limpio)"\
                fi\
                echo "   📍 IP: \$ip_externa"\
                echo "   🕒 Conectado: \$fecha_conexion"\
                echo ""\
            fi\
        done < /tmp/clientes_temp.txt\
        \
        rm -f /tmp/clientes_temp.txt\
    \
    # FORMATO 3: ROUTING_TABLE (clientes realmente conectados)\
    elif grep -q "^ROUTING_TABLE" "\$STATUS_FILE"; then\
        echo "📋 Formato detectado: ROUTING_TABLE"\
        echo ""\
        \
        # Extraer sección ROUTING_TABLE\
        sed -n '/^ROUTING_TABLE/,/^GLOBAL_STATS/p' "\$STATUS_FILE" | grep -v "^ROUTING_TABLE\|^GLOBAL_STATS" > /tmp/clientes_temp.txt\
        \
        while IFS=, read -r cliente ip_puerto bytes_rx bytes_tx conectado_desde; do\
            if [ -n "\$cliente" ] && [ "\$cliente" != "Common Name" ]; then\
                cliente_limpio=\$(limpiar_nombre "\$cliente")\
                nombre_descriptivo=\$(obtener_nombre "\$cliente")\
                \
                # Registrar en historial\
                timestamp=\$(date '+%Y-%m-%d %H:%M:%S')\
                fecha_conexion=\$(date '+%d/%m/%Y %H:%M')\
                \
                # Eliminar entrada antigua si existe\
                grep -v "^\$cliente_limpio:\$ip_puerto:" "\$IP_HISTORY_FILE" > /tmp/ip_temp.txt 2>/dev/null\
                mv /tmp/ip_temp.txt "\$IP_HISTORY_FILE" 2>/dev/null\
                \
                # Añadir nueva entrada\
                echo "\$cliente_limpio:\$ip_puerto:\$timestamp:\$fecha_conexion" >> "\$IP_HISTORY_FILE"\
                registradas=\$((registradas + 1))\
                \
                # Registrar en log\
                escribir_log "📡 Cliente \$nombre_descriptivo (\$cliente_limpio) conectado desde \$ip_puerto"\
                \
                # Mostrar información\
                echo "👤 \$nombre_descriptivo (\$cliente_limpio)"\
                echo "   📍 IP: \$ip_puerto"\
                echo "   🕒 Conectado: \$fecha_conexion"\
                echo ""\
            fi\
        done < /tmp/clientes_temp.txt\
        \
        rm -f /tmp/clientes_temp.txt\
    \
    else\
        echo "❓ Formato de archivo no reconocido"\
        echo ""\
        echo "📄 Mostrando primeras 5 líneas del archivo para diagnóstico:"\
        head -5 "\$STATUS_FILE" | while read line; do\
            echo "   \$line"\
        done\
        echo ""\
        echo "💡 Ejecuta para ver formato:"\
        echo "   head -10 \$STATUS_FILE"\
        return\
    fi\
    \
    if [ \$registradas -eq 0 ]; then\
        echo "ℹ️  No se encontraron clientes conectados"\
        echo ""\
        echo "💡 Posibles razones:"\
        echo "   1. Realmente no hay clientes conectados"\
        echo "   2. El archivo de estado tiene formato diferente"\
        echo "   3. OpenVPN no está generando información de clientes"\
    else\
        escribir_log "✅ Se registraron \$registradas conexiones en \$IP_HISTORY_FILE"\
        echo "✅ Se registraron \$registradas conexiones"\
    fi\
}
' /usr/bin/gestion

echo "✅ Función ver_conectados() actualizada"
echo "📋 Backup guardado en: /tmp/gestion_backup.sh"
EOF

chmod +x /tmp/fix_ver_conectados.sh
/tmp/fix_ver_conectados.sh

echo ""
echo "✅ CORRECCIÓN APLICADA"
echo ""
echo "🔧 LA NUEVA FUNCIÓN:"
echo "   1. Detecta automáticamente el formato del archivo"
echo "   2. Maneja 3 formatos diferentes:"
echo "      - CLIENT_LIST con comas"
echo "      - CLIENT_LIST con espacios (el que funcionaba antes)"
echo "      - ROUTING_TABLE"
echo "   3. Muestra información de diagnóstico"
echo ""
echo "🚀 Prueba ahora con: gestion (opción 1)"
