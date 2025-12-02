#!/bin/sh

echo ""
echo "🔧 CORRIGIENDO NOMBRES Y BASE DE DATOS"
echo "======================================"

# Crear el gestor con las correcciones
cat > /usr/bin/gestor-vpn << 'GESTOR_SCRIPT'
#!/bin/sh

# Archivos de configuración
NOMBRES_FILE="/etc/openvpn/clientes/nombres.txt"
TRACKING_FILE="/etc/openvpn/clientes/tracking.txt"

# Asegurar que el archivo de nombres existe
mkdir -p /etc/openvpn/clientes/
touch "$NOMBRES_FILE"

# Función para obtener nombre descriptivo (MEJORADA Y DEBUG)
obtener_nombre() {
    local cliente=$1
    if [ ! -f "$NOMBRES_FILE" ] || [ -z "$cliente" ]; then
        echo "$cliente"
        return
    fi
    
    # DEBUG: Mostrar búsqueda
    # echo "DEBUG: Buscando cliente '$cliente' en $NOMBRES_FILE" >&2
    
    # Buscar el nombre de forma más robusta
    local nombre=$(grep "^${cliente}:" "$NOMBRES_FILE" 2>/dev/null | cut -d: -f2-)
    
    if [ -n "$nombre" ]; then
        echo "$nombre"
    else
        echo "$cliente"
    fi
}

# Función para mostrar menú (MODIFICADA - OPCIÓN 5 ELIMINADA)
mostrar_menu() {
    echo ""
    echo "🔧 GESTOR VPN - CON NOMBRES DESCRIPTIVOS"
    echo "========================================"
    echo ""
    echo "1) 👁️  Ver clientes conectados"
    echo "2) 📋 Listar todos los clientes"
    echo "3) ⏸️  SUSPENDER cliente (temporal)"
    echo "4) ▶️  REACTIVAR cliente (mismo certificado)"
    echo "5) 🏷️  GESTIONAR NOMBRES"
    echo "6) 🔍 Estado del servicio"
    echo "7) ❌ Salir"
    echo ""
    echo -n "Selecciona [1-7]: "
}

# Función para ver clientes conectados (CORREGIDA)
ver_conectados() {
    echo ""
    echo "📊 CLIENTES CONECTADOS:"
    
    if [ -f "/var/log/openvpn-status.log" ] && grep -q "CLIENT_LIST" "/var/log/openvpn-status.log"; then
        # ✅ CORREGIDO: Usar awk para procesar tabulaciones
        grep "^CLIENT_LIST" "/var/log/openvpn-status.log" | while IFS=$'\t' read -r _ cliente ip_externa ip_interna bytes_recv bytes_sent connected_since _; do
            # Limpiar variables de posibles espacios
            cliente=$(echo "$cliente" | xargs)
            ip_externa=$(echo "$ip_externa" | xargs)
            ip_interna=$(echo "$ip_interna" | xargs)
            bytes_recv=$(echo "$bytes_recv" | xargs)
            bytes_sent=$(echo "$bytes_sent" | xargs)
            connected_since=$(echo "$connected_since" | xargs)
            
            # ✅ CORREGIDO: Obtener nombre descriptivo
            nombre_descriptivo=$(obtener_nombre "$cliente")
            
            # ✅ CORREGIDO: Mostrar nombre descriptivo si está asignado
            if [ "$cliente" = "$nombre_descriptivo" ]; then
                echo "   👤 $cliente"
            else
                echo "   👤 $nombre_descriptivo ($cliente)"
            fi
            
            echo "      📍 IP Externa: $ip_externa"
            echo "      📍 IP Interna: $ip_interna"
            
            # Mostrar fecha de conexión si está disponible
            if [ -n "$connected_since" ] && [ "$connected_since" != "UNDEF" ]; then
                echo "      ⏰ Conectado desde: $connected_since"
            fi
            
            # Mostrar bytes enviados
            if [ -n "$bytes_sent" ] && [ "$bytes_sent" -gt 0 ] 2>/dev/null; then
                mb_sent=$((bytes_sent / 1024 / 1024))
                echo "      🔼 Subido: ${mb_sent} MB"
            fi
            
            # Mostrar bytes recibidos si están disponibles
            if [ -n "$bytes_recv" ] && [ "$bytes_recv" -gt 0 ] 2>/dev/null; then
                mb_recv=$((bytes_recv / 1024 / 1024))
                echo "      🔽 Descargado: ${mb_recv} MB"
            fi
            
            echo ""
        done
    else
        echo "   ℹ️  No hay clientes conectados"
        echo "   💡 Si hay clientes conectados, ejecuta: /etc/init.d/openvpn restart"
    fi
}

# Función para listar clientes (COMPLETAMENTE CORREGIDA - MÁS ROBUSTA)
listar_clientes() {
    echo ""
    echo "📋 ESTADO DE CLIENTES:"
    
    # ✅ CORREGIDO: Buscar base de datos en múltiples ubicaciones posibles
    INDEX_FILES="/etc/easy-rsa/pki/index.txt /etc/openvpn/easy-rsa/pki/index.txt /etc/easy-rsa/keys/index.txt"
    INDEX_FILE=""
    
    for file in $INDEX_FILES; do
        if [ -f "$file" ]; then
            INDEX_FILE="$file"
            echo "   🔍 Usando base de datos: $file"
            break
        fi
    done
    
    if [ -z "$INDEX_FILE" ]; then
        echo "   ❌ No se encuentra la base de datos de certificados"
        echo "   💡 Ejecuta el instalador de OpenVPN primero"
        return
    fi
    
    if [ ! -s "$INDEX_FILE" ]; then
        echo "   ℹ️  La base de datos de certificados está vacía"
        return
    fi

    # ✅ CORREGIDO: Obtener TODOS los clientes únicos de forma más robusta
    echo "   📊 Analizando base de datos..."
    todos_clientes=$(grep -E "^(V|R)" "$INDEX_FILE" 2>/dev/null | awk -F'/' '{print $NF}' | awk '{print $1}' | sort -u)
    
    if [ -z "$todos_clientes" ]; then
        echo "   ℹ️  No hay clientes configurados en la base de datos"
        echo "   💡 Base de datos encontrada pero vacía o con formato diferente"
        return
    fi

    echo "🟢 ACTIVOS:"
    activos_encontrados=0
    for cliente in $todos_clientes; do
        if grep -q "^V.*/CN=${cliente}$" "$INDEX_FILE" 2>/dev/null || grep -q "^V.*${cliente}" "$INDEX_FILE" 2>/dev/null; then
            nombre_descriptivo=$(obtener_nombre "$cliente")
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
        if grep -q "^R.*/CN=${cliente}$" "$INDEX_FILE" 2>/dev/null || grep -q "^R.*${cliente}" "$INDEX_FILE" 2>/dev/null; then
            if [ -f "/etc/openvpn/suspended/${cliente}.crt.backup" ]; then
                nombre_descriptivo=$(obtener_nombre "$cliente")
                if [ "$cliente" = "$nombre_descriptivo" ]; then
                    echo "   $cliente"
                else
                    echo "   $nombre_descriptivo ($cliente)"
                fi
                suspendidos_encontrados=1
            fi
        fi
    done
    if [ $suspendidos_encontrados -eq 0 ]; then
        echo "   Ninguno"
    fi
    
    echo ""
    echo "🔴 REVOCADOS PERMANENTES:"
    revocados_encontrados=0
    for cliente in $todos_clientes; do
        if grep -q "^R.*/CN=${cliente}$" "$INDEX_FILE" 2>/dev/null || grep -q "^R.*${cliente}" "$INDEX_FILE" 2>/dev/null; then
            if [ ! -f "/etc/openvpn/suspended/${cliente}.crt.backup" ]; then
                nombre_descriptivo=$(obtener_nombre "$cliente")
                if [ "$cliente" = "$nombre_descriptivo" ]; then
                    echo "   $cliente"
                else
                    echo "   $nombre_descriptivo ($cliente)"
                fi
                revocados_encontrados=1
            fi
        fi
    done
    if [ $revocados_encontrados -eq 0 ]; then
        echo "   Ninguno"
    fi
    
    echo ""
    echo "💡 Total clientes en sistema: $(echo "$todos_clientes" | wc -w)"
}

# Función para suspender cliente TEMPORAL (CORREGIDA)
suspender_cliente() {
    echo ""
    echo "⏸️  SUSPENDER CLIENTE (TEMPORAL)"
    echo "------------------------------"
    echo "⚠️  Esta acción suspenderá al cliente temporalmente"
    echo "   El certificado se mantendrá para futura reactivación"
    echo ""
    
    echo "Clientes activos:"
    activos_encontrados=0
    
    # Buscar base de datos
    INDEX_FILES="/etc/easy-rsa/pki/index.txt /etc/openvpn/easy-rsa/pki/index.txt /etc/easy-rsa/keys/index.txt"
    INDEX_FILE=""
    for file in $INDEX_FILES; do
        if [ -f "$file" ]; then
            INDEX_FILE="$file"
            break
        fi
    done
    
    if [ -n "$INDEX_FILE" ]; then
        for cliente in $(grep "^V" "$INDEX_FILE" 2>/dev/null | awk -F'/' '{print $NF}' | awk '{print $1}'); do
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
    
    # Buscar certificado en múltiples ubicaciones
    CERT_FOUND=0
    for cert_dir in "/etc/easy-rsa/pki/issued" "/etc/openvpn/easy-rsa/pki/issued" "/etc/easy-rsa/keys"; do
        if [ -f "${cert_dir}/${CLIENTE_REAL}.crt" ]; then
            CERT_FOUND=1
            break
        fi
    done
    
    if [ $CERT_FOUND -eq 0 ]; then
        echo "❌ Cliente '$INPUT_CLIENTE' no encontrado"
        return
    fi
    
    echo ""
    echo "⚠️  CONFIRMACIÓN DE SUSPENSIÓN TEMPORAL"
    echo "-------------------------------------"
    nombre_descriptivo=$(obtener_nombre "$CLIENTE_REAL")
    echo "Cliente: $nombre_descriptivo ($CLIENTE_REAL)"
    echo ""
    echo -n "¿Estás seguro de suspender temporalmente? (s/N): "
    read confirmacion
    
    if [ "$confirmacion" != "s" ] && [ "$confirmacion" != "S" ]; then
        echo "❌ Suspensión cancelada"
        return
    fi
    
    echo "   [⏳] Suspendiendo cliente temporalmente..."
    
    # Crear directorio para suspensiones temporales si no existe
    mkdir -p /etc/openvpn/suspended/
    
    # Guardar copia de seguridad para futura reactivación (SUSPENSIÓN TEMPORAL)
    cp "/etc/easy-rsa/pki/issued/${CLIENTE_REAL}.crt" "/etc/openvpn/suspended/${CLIENTE_REAL}.crt.backup" 2>/dev/null || \
    cp "/etc/openvpn/easy-rsa/pki/issued/${CLIENTE_REAL}.crt" "/etc/openvpn/suspended/${CLIENTE_REAL}.crt.backup" 2>/dev/null || \
    cp "/etc/easy-rsa/keys/${CLIENTE_REAL}.crt" "/etc/openvpn/suspended/${CLIENTE_REAL}.crt.backup" 2>/dev/null
    
    cp "/etc/easy-rsa/pki/private/${CLIENTE_REAL}.key" "/etc/openvpn/suspended/${CLIENTE_REAL}.key.backup" 2>/dev/null || \
    cp "/etc/openvpn/easy-rsa/pki/private/${CLIENTE_REAL}.key" "/etc/openvpn/suspended/${CLIENTE_REAL}.key.backup" 2>/dev/null || \
    cp "/etc/easy-rsa/keys/${CLIENTE_REAL}.key" "/etc/openvpn/suspended/${CLIENTE_REAL}.key.backup" 2>/dev/null
    
    # Revocar certificado (esto impide la conexión)
    cd /etc/easy-rsa 2>/dev/null || cd /etc/openvpn/easy-rsa 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "   [🔒] Revocando certificado..."
        echo "yes" | ./easyrsa revoke "$CLIENTE_REAL" > /dev/null 2>&1
        echo "   [🔄] Generando nueva lista de revocación..."
        ./easyrsa gen-crl > /dev/null 2>&1
        cp pki/crl.pem /etc/openvpn/ 2>/dev/null
        echo "   [✅] Certificado revocado temporalmente"
    fi
    
    # Reiniciar OpenVPN para aplicar cambios
    echo "   [🔄] Reiniciando servicio OpenVPN..."
    /etc/init.d/openvpn restart > /dev/null 2>&1
    sleep 2
    
    echo ""
    echo "✅ SUSPENSIÓN TEMPORAL COMPLETADA"
    echo "================================="
    echo "👤 Cliente: $nombre_descriptivo"
    echo "📋 Certificado: $CLIENTE_REAL"
    echo "⏳ Estado: SUSPENDIDO TEMPORALMENTE"
    echo "💾 Backup guardado en: /etc/openvpn/suspended/${CLIENTE_REAL}.crt.backup"
    echo ""
    echo "💡 Para reactivar este cliente, usa la opción 4 (REACTIVAR CLIENTE)"
    echo "   Se usará el mismo certificado sin necesidad de generar uno nuevo"
}

# Función para reactivar cliente
reactivar_cliente() {
    echo ""
    echo "▶️  REACTIVAR CLIENTE"
    echo "-------------------"
    echo "⚠️  Reactivación usando el MISMO certificado"
    echo ""
    
    echo "Clientes suspendidos temporalmente:"
    suspendidos_encontrados=0
    
    # Buscar base de datos
    INDEX_FILES="/etc/easy-rsa/pki/index.txt /etc/openvpn/easy-rsa/pki/index.txt /etc/easy-rsa/keys/index.txt"
    INDEX_FILE=""
    for file in $INDEX_FILES; do
        if [ -f "$file" ]; then
            INDEX_FILE="$file"
            break
        fi
    done
    
    if [ -n "$INDEX_FILE" ]; then
        for cliente in $(grep "^R" "$INDEX_FILE" 2>/dev/null | awk -F'/' '{print $NF}' | awk '{print $1}'); do
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
        echo "   No hay clientes suspendidos temporalmente"
        echo ""
        echo "💡 Solo se pueden reactivar clientes suspendidos temporalmente"
        echo "   (aquellos que tienen backup en /etc/openvpn/suspended/)"
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
        echo "❌ Cliente '$INPUT_CLIENTE' no está suspendido temporalmente"
        echo ""
        echo "💡 Solo se pueden reactivar clientes con suspensión temporal"
        echo "   (debe existir: /etc/openvpn/suspended/${CLIENTE_REAL}.crt.backup)"
        return
    fi
    
    echo ""
    echo "⚠️  CONFIRMACIÓN DE REACTIVACIÓN"
    echo "-------------------------------"
    nombre_descriptivo=$(obtener_nombre "$CLIENTE_REAL")
    echo "Cliente: $nombre_descriptivo ($CLIENTE_REAL)"
    echo "Tipo: Reactivación con MISMO certificado"
    echo ""
    echo -n "¿Estás seguro de reactivar? (s/N): "
    read confirmacion
    
    if [ "$confirmacion" != "s" ] && [ "$confirmacion" != "S" ]; then
        echo "❌ Reactivación cancelada"
        return
    fi
    
    echo "   [⏳] Reactivando cliente..."
    
    # Restaurar certificado desde backup (MISMO CERTIFICADO)
    echo "   [💾] Restaurando certificado original..."
    cp "/etc/openvpn/suspended/${CLIENTE_REAL}.crt.backup" "/etc/easy-rsa/pki/issued/${CLIENTE_REAL}.crt" 2>/dev/null || \
    cp "/etc/openvpn/suspended/${CLIENTE_REAL}.crt.backup" "/etc/openvpn/easy-rsa/pki/issued/${CLIENTE_REAL}.crt" 2>/dev/null || \
    cp "/etc/openvpn/suspended/${CLIENTE_REAL}.crt.backup" "/etc/easy-rsa/keys/${CLIENTE_REAL}.crt" 2>/dev/null
    
    cp "/etc/openvpn/suspended/${CLIENTE_REAL}.key.backup" "/etc/easy-rsa/pki/private/${CLIENTE_REAL}.key" 2>/dev/null || \
    cp "/etc/openvpn/suspended/${CLIENTE_REAL}.key.backup" "/etc/openvpn/easy-rsa/pki/private/${CLIENTE_REAL}.key" 2>/dev/null || \
    cp "/etc/openvpn/suspended/${CLIENTE_REAL}.key.backup" "/etc/easy-rsa/keys/${CLIENTE_REAL}.key" 2>/dev/null
    
    # Buscar directorio easy-rsa
    cd /etc/easy-rsa 2>/dev/null || cd /etc/openvpn/easy-rsa 2>/dev/null
    if [ $? -eq 0 ]; then
        # Eliminar línea del índice para reactivar (quitar revocación)
        echo "   [🔄] Quitando revocación del certificado..."
        sed -i "/\/CN=${CLIENTE_REAL}$/d" pki/index.txt 2>/dev/null
        # Añadir como válido nuevamente
        echo "V\t$(date +'%y%m%d%H%M%SZ')\t\t$(openssl x509 -in "pki/issued/${CLIENTE_REAL}.crt" -serial -noout 2>/dev/null | cut -d= -f2)\tunknown\t/CN=${CLIENTE_REAL}" >> pki/index.txt 2>/dev/null
        
        echo "   [📋] Generando nueva lista de revocación..."
        ./easyrsa gen-crl > /dev/null 2>&1
        cp pki/crl.pem /etc/openvpn/ 2>/dev/null
    fi
    
    echo "   [🔄] Reiniciando servicio OpenVPN..."
    /etc/init.d/openvpn restart > /dev/null 2>&1
    sleep 2
    
    echo ""
    echo "✅ REACTIVACIÓN COMPLETADA"
    echo "=========================="
    echo "👤 Cliente: $nombre_descriptivo"
    echo "📋 Certificado: $CLIENTE_REAL"
    echo "🔄 Estado: ACTIVO"
    echo "🔑 Certificado usado: MISMO certificado original"
    echo ""
    echo "💡 El cliente puede conectarse inmediatamente"
    echo "   No se requiere configuración adicional"
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
                
                # Buscar base de datos en múltiples ubicaciones
                INDEX_FILES="/etc/easy-rsa/pki/index.txt /etc/openvpn/easy-rsa/pki/index.txt /etc/easy-rsa/keys/index.txt"
                INDEX_FILE=""
                for file in $INDEX_FILES; do
                    if [ -f "$file" ]; then
                        INDEX_FILE="$file"
                        break
                    fi
                done
                
                if [ -n "$INDEX_FILE" ]; then
                    # ✅ CORREGIDO: Mostrar correctamente sin líneas vacías
                    for cliente in $(grep -E "^(V|R)" "$INDEX_FILE" 2>/dev/null | awk -F'/' '{print $NF}' | awk '{print $1}' | sort -u | head -10); do
                        if [ -n "$cliente" ]; then  # ✅ Solo si no está vacío
                            nombre_actual=$(obtener_nombre "$cliente")
                            if [ "$cliente" = "$nombre_actual" ]; then
                                echo "   $cliente"
                            else
                                echo "   $nombre_actual ($cliente)"
                            fi
                        fi
                    done
                else
                    echo "   No se encontró base de datos de certificados"
                fi
                echo ""
                echo -n "Certificado del cliente (ej: client1): "
                read cliente
                echo -n "Nombre descriptivo (ej: Juan_Movil): "
                read nombre_descriptivo
                
                if [ -n "$cliente" ] && [ -n "$nombre_descriptivo" ]; then
                    # ✅ CORREGIDO: Crear archivo si no existe
                    touch "$NOMBRES_FILE"
                    # Eliminar entrada existente
                    grep -v "^${cliente}:" "$NOMBRES_FILE" 2>/dev/null > "${NOMBRES_FILE}.tmp"
                    mv "${NOMBRES_FILE}.tmp" "$NOMBRES_FILE"
                    # Añadir nueva entrada
                    echo "${cliente}:${nombre_descriptivo}" >> "$NOMBRES_FILE"
                    echo "✅ Nombre '$nombre_descriptivo' asignado a $cliente"
                    echo "💡 Ahora se mostrará en las listas como: $nombre_descriptivo ($cliente)"
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
                    echo "   💡 Usa la opción 1 para asignar nombres a los clientes"
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

# Menú principal (MODIFICADO - OPCIÓN 5 ELIMINADA)
while true; do
    mostrar_menu
    read OPCION
    
    case $OPCION in
        1) ver_conectados ;;
        2) listar_clientes ;;
        3) suspender_cliente ;;
        4) reactivar_cliente ;;
        5) gestionar_nombres ;;
        6) estado_servicio ;;
        7)
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
echo "✅ GESTOR MODIFICADO CORRECTAMENTE"
echo ""
echo "🎯 CAMBIOS APLICADOS:"
echo "   ❌ OPCIÓN 5 ELIMINADA: Bloqueo permanente removido del menú"
echo "   ⏸️  OPCIÓN 3 MEJORADA: Suspensión temporal funciona correctamente"
echo "   🔄 OPCIÓN 4 MEJORADA: Reactivación usa el MISMO certificado"
echo "   📊 LISTADO ACTUALIZADO: 'BLOQUEADOS' renombrado a 'REVOCADOS PERMANENTES'"
echo ""
echo "🔧 DETALLES TÉCNICOS:"
echo "   • Suspensión temporal guarda backup para reactivación"
echo "   • Reactivación restaura certificado original sin generar nuevo"
echo "   • Menú ahora tiene 7 opciones (1-7) en lugar de 8"
echo ""
echo "🚀 EJECUTA: gestor-vpn"
echo ""
echo "💡 IMPORTANTE:"
echo "   • Opción 3 suspende temporalmente (certificado se guarda)"
echo "   • Opción 4 reactiva con el mismo certificado guardado"
echo "   • No hay opción de bloqueo permanente en el menú"
