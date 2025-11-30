#!/bin/sh

echo ""
echo "🔧 CORRIGIENDO TODOS LOS ERRORES"
echo "================================"

# Crear el gestor completamente corregido
cat > /usr/bin/gestor-vpn << 'GESTOR_SCRIPT'
#!/bin/sh

# Archivos de configuración
NOMBRES_FILE="/etc/openvpn/clientes/nombres.txt"
TRACKING_FILE="/etc/openvpn/clientes/tracking.txt"

# Asegurar que el archivo de nombres existe
mkdir -p /etc/openvpn/clientes/
touch "$NOMBRES_FILE"

# Función para obtener nombre descriptivo (MEJORADA)
obtener_nombre() {
    local cliente=$1
    if [ ! -f "$NOMBRES_FILE" ] || [ -z "$cliente" ]; then
        echo "$cliente"
        return
    fi
    
    # Buscar el nombre de forma más robusta
    local nombre=$(grep "^${cliente}:" "$NOMBRES_FILE" 2>/dev/null | cut -d: -f2-)
    
    if [ -n "$nombre" ]; then
        echo "$nombre"
    else
        echo "$cliente"
    fi
}

# Función para mostrar menú
mostrar_menu() {
    echo ""
    echo "🔧 GESTOR VPN - CON NOMBRES DESCRIPTIVOS"
    echo "========================================"
    echo ""
    echo "1) 👁️  Ver clientes conectados"
    echo "2) 📋 Listar todos los clientes"
    echo "3) ⏸️  SUSPENDER cliente (temporal)"
    echo "4) ▶️  REACTIVAR cliente (mismo certificado)"
    echo "5) 🚫 BLOQUEAR permanente (nuevo certificado)"
    echo "6) 🏷️  GESTIONAR NOMBRES"
    echo "7) 🔍 Estado del servicio"
    echo "8) ❌ Salir"
    echo ""
    echo -n "Selecciona [1-8]: "
}

# Función para ver clientes conectados (COMPLETAMENTE CORREGIDA - CON NOMBRES)
ver_conectados() {
    echo ""
    echo "📊 CLIENTES CONECTADOS:"
    
    if [ -f "/var/log/openvpn-status.log" ] && grep -q "CLIENT_LIST" "/var/log/openvpn-status.log"; then
        # ✅ CORREGIDO: Usar método más robusto y mostrar nombres
        grep "^CLIENT_LIST" "/var/log/openvpn-status.log" | while IFS= read -r line; do
            cliente=$(echo "$line" | awk '{print $2}')
            ip=$(echo "$line" | awk '{print $3}')
            bytes_recv=$(echo "$line" | awk '{print $4}')
            bytes_sent=$(echo "$line" | awk '{print $5}')
            connected_since=$(echo "$line" | awk '{print $6 " " $7}')
            
            # ✅ CORREGIDO: Obtener nombre correctamente
            nombre_descriptivo=$(obtener_nombre "$cliente")
            
            # ✅ CORREGIDO: Mostrar nombre descriptivo y certificado
            if [ "$cliente" = "$nombre_descriptivo" ]; then
                echo "   👤 $cliente"
            else
                echo "   👤 $nombre_descriptivo (certificado: $cliente)"
            fi
            
            echo "      📍 IP: $ip"
            
            if [ -n "$connected_since" ] && [ "$connected_since" != "UNDEF" ]; then
                echo "      ⏰ Conectado desde: $connected_since"
            fi
            
            if [ -n "$bytes_recv" ] && [ "$bytes_recv" -gt 0 ] 2>/dev/null; then
                mb_recv=$((bytes_recv / 1024 / 1024))
                echo "      🔽 Descargado: ${mb_recv} MB"
            fi
            
            if [ -n "$bytes_sent" ] && [ "$bytes_sent" -gt 0 ] 2>/dev/null; then
                mb_sent=$((bytes_sent / 1024 / 1024))
                echo "      🔼 Subido: ${mb_sent} MB"
            fi
            echo ""
        done
    else
        echo "   ℹ️  No hay clientes conectados"
        echo "   💡 Si hay clientes conectados, ejecuta: /etc/init.d/openvpn restart"
    fi
}

# Función para listar clientes (COMPLETAMENTE CORREGIDA)
listar_clientes() {
    echo ""
    echo "📋 ESTADO DE CLIENTES:"
    
    # ✅ CORREGIDO: Verificar que el archivo index.txt existe y tiene contenido
    if [ ! -f "/etc/easy-rsa/pki/index.txt" ]; then
        echo "   ❌ No se encuentra la base de datos de certificados"
        echo "   💡 Ejecuta el instalador de OpenVPN primero"
        return
    fi
    
    if [ ! -s "/etc/easy-rsa/pki/index.txt" ]; then
        echo "   ℹ️  La base de datos de certificados está vacía"
        return
    fi

    # ✅ CORREGIDO: Obtener TODOS los clientes únicos de forma segura
    todos_clientes=$(grep -E "^(V|R)" "/etc/easy-rsa/pki/index.txt" 2>/dev/null | awk '{print $6}' | sort -u)
    
    if [ -z "$todos_clientes" ]; then
        echo "   ℹ️  No hay clientes configurados en la base de datos"
        return
    fi

    echo "🟢 ACTIVOS:"
    activos_encontrados=0
    for cliente in $todos_clientes; do
        if grep -q "^V.*/CN=${cliente}$" "/etc/easy-rsa/pki/index.txt" 2>/dev/null; then
            nombre_descriptivo=$(obtener_nombre "$cliente")
            # ✅ CORREGIDO: Mostrar correctamente nombre (certificado)
            if [ "$cliente" = "$nombre_descriptivo" ]; then
                echo "   $cliente"
            else
                echo "   $nombre_descriptivo ($cliente)"
            fi
            activos_encontrados=1
        fi
    done
    if [ $activos_encontrados -eq 0 ]; then
        echo "   Ninguno"
    fi
    
    echo ""
    echo "⏸️  SUSPENDIDOS:"
    suspendidos_encontrados=0
    for cliente in $todos_clientes; do
        if grep -q "^R.*/CN=${cliente}$" "/etc/easy-rsa/pki/index.txt" 2>/dev/null && \
           [ -f "/etc/openvpn/suspended/${cliente}.crt.backup" ]; then
            nombre_descriptivo=$(obtener_nombre "$cliente")
            if [ "$cliente" = "$nombre_descriptivo" ]; then
                echo "   $cliente"
            else
                echo "   $nombre_descriptivo ($cliente)"
            fi
            suspendidos_encontrados=1
        fi
    done
    if [ $suspendidos_encontrados -eq 0 ]; then
        echo "   Ninguno"
    fi
    
    echo ""
    echo "🔴 BLOQUEADOS:"
    bloqueados_encontrados=0
    for cliente in $todos_clientes; do
        if grep -q "^R.*/CN=${cliente}$" "/etc/easy-rsa/pki/index.txt" 2>/dev/null && \
           [ ! -f "/etc/openvpn/suspended/${cliente}.crt.backup" ]; then
            nombre_descriptivo=$(obtener_nombre "$cliente")
            if [ "$cliente" = "$nombre_descriptivo" ]; then
                echo "   $cliente"
            else
                echo "   $nombre_descriptivo ($cliente)"
            fi
            bloqueados_encontrados=1
        fi
    done
    if [ $bloqueados_encontrados -eq 0 ]; then
        echo "   Ninguno"
    fi
    
    echo ""
    echo "💡 Total clientes en sistema: $(echo "$todos_clientes" | wc -w)"
}

# Función para suspender cliente
suspender_cliente() {
    echo ""
    echo "⏸️  SUSPENDER CLIENTE (TEMPORAL)"
    echo "------------------------------"
    
    echo "Clientes activos:"
    activos_encontrados=0
    if [ -f "/etc/easy-rsa/pki/index.txt" ]; then
        for cliente in $(grep "^V" /etc/easy-rsa/pki/index.txt 2>/dev/null | awk '{print $6}'); do
            nombre_descriptivo=$(obtener_nombre "$cliente")
            if [ "$cliente" = "$nombre_descriptivo" ]; then
                echo "   $cliente"
            else
                echo "   $nombre_descriptivo ($cliente)"
            fi
            activos_encontrados=1
        done
    fi
    
    if [ $activos_encontrados -eq 0 ]; then
        echo "   No hay clientes activos"
        return
    fi
    
    echo ""
    echo -n "Cliente a suspender (usar nombre o certificado): "
    read INPUT_CLIENTE
    
    CLIENTE_REAL=""
    if [ -f "$NOMBRES_FILE" ] && grep -q ":${INPUT_CLIENTE}$" "$NOMBRES_FILE" 2>/dev/null; then
        CLIENTE_REAL=$(grep ":${INPUT_CLIENTE}$" "$NOMBRES_FILE" | cut -d: -f1)
        echo "   🔍 Encontrado: $INPUT_CLIENTE → $CLIENTE_REAL"
    else
        CLIENTE_REAL=$INPUT_CLIENTE
    fi
    
    if [ ! -f "/etc/easy-rsa/pki/issued/${CLIENTE_REAL}.crt" ]; then
        echo "❌ Cliente '$INPUT_CLIENTE' no encontrado"
        return
    fi
    
    echo "   [....] Suspendiendo cliente..."
    mkdir -p /etc/openvpn/suspended/
    cp "/etc/easy-rsa/pki/issued/${CLIENTE_REAL}.crt" "/etc/openvpn/suspended/${CLIENTE_REAL}.crt.backup"
    cp "/etc/easy-rsa/pki/private/${CLIENTE_REAL}.key" "/etc/openvpn/suspended/${CLIENTE_REAL}.key.backup"
    
    cd /etc/easy-rsa
    echo "yes" | easyrsa revoke "$CLIENTE_REAL" > /dev/null 2>&1
    easyrsa gen-crl > /dev/null 2>&1
    cp /etc/easy-rsa/pki/crl.pem /etc/openvpn/
    /etc/init.d/openvpn restart > /dev/null 2>&1
    sleep 2
    
    nombre_descriptivo=$(obtener_nombre "$CLIENTE_REAL")
    echo "✅ CLIENTE '$nombre_descriptivo' SUSPENDIDO"
}

# Función para reactivar cliente
reactivar_cliente() {
    echo ""
    echo "▶️  REACTIVAR CLIENTE"
    echo "-------------------"
    
    echo "Clientes suspendidos:"
    suspendidos_encontrados=0
    if [ -f "/etc/easy-rsa/pki/index.txt" ]; then
        for cliente in $(grep "^R" /etc/easy-rsa/pki/index.txt 2>/dev/null | awk '{print $6}'); do
            if [ -f "/etc/openvpn/suspended/${cliente}.crt.backup" ]; then
                nombre_descriptivo=$(obtener_nombre "$cliente")
                if [ "$cliente" = "$nombre_descriptivo" ]; then
                    echo "   $cliente"
                else
                    echo "   $nombre_descriptivo ($cliente)"
                fi
                suspendidos_encontrados=1
            fi
        done
    fi
    
    if [ $suspendidos_encontrados -eq 0 ]; then
        echo "   No hay clientes suspendidos"
        return
    fi
    
    echo ""
    echo -n "Cliente a reactivar (usar nombre o certificado): "
    read INPUT_CLIENTE
    
    CLIENTE_REAL=""
    if [ -f "$NOMBRES_FILE" ] && grep -q ":${INPUT_CLIENTE}$" "$NOMBRES_FILE" 2>/dev/null; then
        CLIENTE_REAL=$(grep ":${INPUT_CLIENTE}$" "$NOMBRES_FILE" | cut -d: -f1)
        echo "   🔍 Encontrado: $INPUT_CLIENTE → $CLIENTE_REAL"
    else
        CLIENTE_REAL=$INPUT_CLIENTE
    fi
    
    if [ ! -f "/etc/openvpn/suspended/${CLIENTE_REAL}.crt.backup" ]; then
        echo "❌ Cliente '$INPUT_CLIENTE' no está suspendido"
        return
    fi
    
    echo "   [....] Reactivando cliente..."
    cp "/etc/openvpn/suspended/${CLIENTE_REAL}.crt.backup" "/etc/easy-rsa/pki/issued/${CLIENTE_REAL}.crt"
    cp "/etc/openvpn/suspended/${CLIENTE_REAL}.key.backup" "/etc/easy-rsa/pki/private/${CLIENTE_REAL}.key"
    
    cd /etc/easy-rsa
    sed -i "/\/CN=${CLIENTE_REAL}$/d" /etc/easy-rsa/pki/index.txt
    easyrsa gen-crl > /dev/null 2>&1
    cp /etc/easy-rsa/pki/crl.pem /etc/openvpn/
    /etc/init.d/openvpn restart > /dev/null 2>&1
    sleep 2
    
    nombre_descriptivo=$(obtener_nombre "$CLIENTE_REAL")
    echo "✅ CLIENTE '$nombre_descriptivo' REACTIVADO"
}

# Función para bloquear permanente
bloquear_permanentemente() {
    echo ""
    echo "🚫 BLOQUEO PERMANENTE"
    echo "-------------------"
    
    echo "Clientes activos:"
    activos_encontrados=0
    if [ -f "/etc/easy-rsa/pki/index.txt" ]; then
        for cliente in $(grep "^V" /etc/easy-rsa/pki/index.txt 2>/dev/null | awk '{print $6}'); do
            nombre_descriptivo=$(obtener_nombre "$cliente")
            if [ "$cliente" = "$nombre_descriptivo" ]; then
                echo "   $cliente"
            else
                echo "   $nombre_descriptivo ($cliente)"
            fi
            activos_encontrados=1
        done
    fi
    
    if [ $activos_encontrados -eq 0 ]; then
        echo "   No hay clientes activos"
        return
    fi
    
    echo ""
    echo -n "Cliente a bloquear (usar nombre o certificado): "
    read INPUT_CLIENTE
    
    CLIENTE_REAL=""
    if [ -f "$NOMBRES_FILE" ] && grep -q ":${INPUT_CLIENTE}$" "$NOMBRES_FILE" 2>/dev/null; then
        CLIENTE_REAL=$(grep ":${INPUT_CLIENTE}$" "$NOMBRES_FILE" | cut -d: -f1)
        echo "   🔍 Encontrado: $INPUT_CLIENTE → $CLIENTE_REAL"
    else
        CLIENTE_REAL=$INPUT_CLIENTE
    fi
    
    if [ ! -f "/etc/easy-rsa/pki/issued/${CLIENTE_REAL}.crt" ]; then
        echo "❌ Cliente '$INPUT_CLIENTE' no encontrado"
        return
    fi
    
    echo "   [....] Bloqueando cliente..."
    cd /etc/easy-rsa
    echo "yes" | easyrsa revoke "$CLIENTE_REAL" > /dev/null 2>&1
    easyrsa gen-crl > /dev/null 2>&1
    cp /etc/easy-rsa/pki/crl.pem /etc/openvpn/
    /etc/init.d/openvpn restart > /dev/null 2>&1
    sleep 2
    
    nombre_descriptivo=$(obtener_nombre "$CLIENTE_REAL")
    echo "✅ CLIENTE '$nombre_descriptivo' BLOQUEADO PERMANENTEMENTE"
}

# Función para gestionar nombres (CORREGIDA)
gestionar_nombres() {
    while true; do
        echo ""
        echo "🏷️  GESTIÓN DE NOMBRES DESCRIPTIVOS"
        echo "=================================="
        echo ""
        echo "1) Asignar nombre a cliente"
        echo "2) Ver todos los nombres"
        echo "3) Eliminar nombre"
        echo "4) Volver al menú principal"
        echo ""
        echo -n "Selecciona [1-4]: "
        read opcion_nombre
        
        case $opcion_nombre in
            1)
                echo ""
                echo "📝 ASIGNAR NOMBRE"
                echo "----------------"
                echo "Clientes disponibles:"
                if [ -f "/etc/easy-rsa/pki/index.txt" ]; then
                    # ✅ CORREGIDO: Mostrar correctamente sin líneas vacías
                    for cliente in $(grep -E "^(V|R)" /etc/easy-rsa/pki/index.txt 2>/dev/null | awk '{print $6}' | sort -u); do
                        if [ -n "$cliente" ]; then  # ✅ Solo si no está vacío
                            nombre_actual=$(obtener_nombre "$cliente")
                            if [ "$cliente" = "$nombre_actual" ]; then
                                echo "   $cliente"
                            else
                                echo "   $nombre_actual ($cliente)"
                            fi
                        fi
                    done | head -10
                fi
                echo ""
                echo -n "Certificado del cliente (ej: client1): "
                read cliente
                echo -n "Nombre descriptivo (ej: Juan_Movil): "
                read nombre_descriptivo
                
                if [ -n "$cliente" ] && [ -n "$nombre_descriptivo" ]; then
                    # ✅ CORREGIDO: Crear archivo si no existe
                    touch "$NOMBRES_FILE"
                    grep -v "^${cliente}:" "$NOMBRES_FILE" 2>/dev/null > "${NOMBRES_FILE}.tmp"
                    mv "${NOMBRES_FILE}.tmp" "$NOMBRES_FILE"
                    echo "${cliente}:${nombre_descriptivo}" >> "$NOMBRES_FILE"
                    echo "✅ Nombre '$nombre_descriptivo' asignado a $cliente"
                else
                    echo "❌ Nombre no válido"
                fi
                ;;
            2)
                echo ""
                echo "📋 NOMBRES ASIGNADOS:"
                # ✅ CORREGIDO: Verificar correctamente si el archivo tiene contenido
                if [ -f "$NOMBRES_FILE" ] && [ -s "$NOMBRES_FILE" ]; then
                    echo ""
                    # ✅ CORREGIDO: Filtrar líneas vacías y comentarios
                    grep -v "^#" "$NOMBRES_FILE" | grep -v "^$" | while read linea; do
                        if [ -n "$linea" ]; then
                            cliente=$(echo "$linea" | cut -d: -f1)
                            nombre=$(echo "$linea" | cut -d: -f2)
                            if [ -n "$cliente" ] && [ -n "$nombre" ]; then
                                echo "   🏷️  $nombre ($cliente)"
                            fi
                        fi
                    done
                else
                    echo "   No hay nombres asignados"
                fi
                ;;
            3)
                echo ""
                echo "🗑️  ELIMINAR NOMBRE"
                if [ -f "$NOMBRES_FILE" ] && [ -s "$NOMBRES_FILE" ]; then
                    echo "Nombres asignados:"
                    grep -v "^#" "$NOMBRES_FILE" | grep -v "^$" | while read linea; do
                        if [ -n "$linea" ]; then
                            cliente=$(echo "$linea" | cut -d: -f1)
                            nombre=$(echo "$linea" | cut -d: -f2)
                            if [ -n "$cliente" ] && [ -n "$nombre" ]; then
                                echo "   $nombre ($cliente)"
                            fi
                        fi
                    done
                    echo ""
                    echo -n "Nombre a eliminar: "
                    read nombre_eliminar
                    if [ -n "$nombre_eliminar" ]; then
                        CLIENTE_REAL=$(grep ":${nombre_eliminar}$" "$NOMBRES_FILE" 2>/dev/null | cut -d: -f1)
                        if [ -n "$CLIENTE_REAL" ]; then
                            grep -v "^${CLIENTE_REAL}:" "$NOMBRES_FILE" > "${NOMBRES_FILE}.tmp"
                            mv "${NOMBRES_FILE}.tmp" "$NOMBRES_FILE"
                            echo "✅ Nombre '$nombre_eliminar' eliminado"
                        else
                            echo "❌ Nombre '$nombre_eliminar' no encontrado"
                        fi
                    else
                        echo "❌ Nombre no válido"
                    fi
                else
                    echo "   No hay nombres asignados"
                fi
                ;;
            4)
                return
                ;;
            *)
                echo "❌ Opción inválida"
                ;;
        esac
    done
}

# Función para estado del servicio
estado_servicio() {
    echo ""
    echo "🔍 ESTADO DEL SERVICIO:"
    if pgrep openvpn >/dev/null; then
        echo "   ✅ OpenVPN: ACTIVO"
    else
        echo "   ❌ OpenVPN: INACTIVO"
    fi
    
    if [ -f "/var/log/openvpn-status.log" ]; then
        echo "   ✅ Archivo de estado: EXISTE"
    else
        echo "   ❌ Archivo de estado: NO EXISTE"
    fi
}

# Menú principal
while true; do
    mostrar_menu
    read OPCION
    
    case $OPCION in
        1) ver_conectados ;;
        2) listar_clientes ;;
        3) suspender_cliente ;;
        4) reactivar_cliente ;;
        5) bloquear_permanentemente ;;
        6) gestionar_nombres ;;
        7) estado_servicio ;;
        8)
            echo ""
            echo "👋 Saliendo..."
            exit 0
            ;;
        *)
            echo "❌ Opción inválida"
            ;;
    esac
    echo ""
done
GESTOR_SCRIPT

# Dar permisos
chmod +x /usr/bin/gestor-vpn

echo ""
echo "✅ GESTOR COMPLETAMENTE CORREGIDO"
echo ""
echo "🎯 PROBLEMAS SOLUCIONADOS:"
echo "   ✅ Opción 1: Ahora muestra 'Nombre_Asignado (certificado: client1)'"
echo "   ✅ Opción 2: Ya no dice 'No hay clientes configurados'"
echo "   ✅ Opción 6: Eliminadas líneas vacías en nombres"
echo "   ✅ Todos: Manejo robusto de archivos y variables"
echo ""
echo "🚀 EJECUTA: gestor-vpn"
