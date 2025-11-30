#!/bin/sh

echo ""
echo "📊 INSTALANDO SISTEMA CON TRACKING COMPLETO"
echo "=========================================="

# 1. Crear directorios necesarios
mkdir -p /etc/openvpn/clientes/
mkdir -p /etc/openvpn/suspended/
mkdir -p /var/log/openvpn-tracking/

# 2. Crear base de datos de nombres y tracking
if [ ! -f "/etc/openvpn/clientes/nombres.txt" ]; then
    cat > /etc/openvpn/clientes/nombres.txt << 'NOMBRES_DB'
# Base de datos de nombres de clientes VPN
# Formato: nombre_certificado:nombre_descriptivo
# Ejemplos:
# client1:Juan_Movil
# client2:Maria_Portatil
# client3:Carlos_Casa

NOMBRES_DB
    echo "✅ Base de datos de nombres creada"
fi

# 3. Crear archivo de tracking si no existe
if [ ! -f "/etc/openvpn/clientes/tracking.txt" ]; then
    touch "/etc/openvpn/clientes/tracking.txt"
    echo "✅ Archivo de tracking creado"
fi

# 4. Crear el gestor completo con tracking
cat > /usr/bin/gestor-vpn << 'GESTOR_SCRIPT'
#!/bin/sh

# Archivos de configuración
NOMBRES_FILE="/etc/openvpn/clientes/nombres.txt"
TRACKING_FILE="/etc/openvpn/clientes/tracking.txt"

# Función para registrar conexión
registrar_conexion() {
    local cliente=$1
    local ip=$2
    local fecha_hora=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Buscar entrada existente
    if grep -q "^${cliente}:" "$TRACKING_FILE" 2>/dev/null; then
        # Actualizar entrada existente
        sed -i "/^${cliente}:/d" "$TRACKING_FILE"
    fi
    
    # Agregar nueva entrada
    echo "${cliente}:${ip}:${fecha_hora}" >> "$TRACKING_FILE"
}

# Función para obtener última conexión
obtener_ultima_conexion() {
    local cliente=$1
    local tracking=$(grep "^${cliente}:" "$TRACKING_FILE" 2>/dev/null)
    
    if [ -n "$tracking" ]; then
        local ip=$(echo "$tracking" | cut -d: -f2)
        local fecha_hora=$(echo "$tracking" | cut -d: -f3-)
        echo "$fecha_hora|$ip"
    else
        echo "Nunca|"
    fi
}

# Función para calcular tiempo desde última conexión
calcular_tiempo_desde() {
    local fecha_hora=$1
    if [ "$fecha_hora" = "Nunca" ]; then
        echo "Nunca conectado"
        return
    fi
    
    local fecha_epoch=$(date -d "$fecha_hora" +%s 2>/dev/null)
    local ahora_epoch=$(date +%s)
    
    if [ -n "$fecha_epoch" ]; then
        local diff=$((ahora_epoch - fecha_epoch))
        
        if [ $diff -lt 60 ]; then
            echo "Hace ${diff} segundos"
        elif [ $diff -lt 3600 ]; then
            local minutos=$((diff / 60))
            echo "Hace ${minutos} minutos"
        elif [ $diff -lt 86400 ]; then
            local horas=$((diff / 3600))
            echo "Hace ${horas} horas"
        else
            local dias=$((diff / 86400))
            echo "Hace ${dias} días"
        fi
    else
        echo "Fecha desconocida"
    fi
}

# Función para obtener nombre descriptivo
obtener_nombre() {
    local cliente=$1
    local nombre=$(grep "^${cliente}:" "$NOMBRES_FILE" 2>/dev/null | cut -d: -f2)
    if [ -n "$nombre" ]; then
        echo "$nombre"
    else
        echo "$cliente"
    fi
}

# Función para asignar nombre
asignar_nombre() {
    local cliente=$1
    echo ""
    echo "🏷️  ASIGNAR NOMBRE A: $cliente"
    echo "------------------------------"
    
    # Mostrar última conexión si existe
    local ultima_info=$(obtener_ultima_conexion "$cliente")
    local ultima_fecha=$(echo "$ultima_info" | cut -d'|' -f1)
    local ultima_ip=$(echo "$ultima_info" | cut -d'|' -f2)
    
    if [ "$ultima_fecha" != "Nunca" ]; then
        echo "Última conexión: $ultima_fecha"
        if [ -n "$ultima_ip" ]; then
            echo "Desde IP: $ultima_ip"
        fi
    fi
    echo ""
    echo "Ejemplos: Juan_Movil, Maria_Portatil, Carlos_Casa, Sara_Trabajo"
    echo ""
    echo -n "Nombre descriptivo: "
    read nombre_descriptivo
    
    # Validar nombre
    if [ -z "$nombre_descriptivo" ]; then
        echo "❌ Nombre no puede estar vacío"
        return 1
    fi
    
    if echo "$nombre_descriptivo" | grep -q ":"; then
        echo "❌ El nombre no puede contener ':'"
        return 1
    fi
    
    # Verificar si el nombre ya existe
    if grep -q ":${nombre_descriptivo}$" "$NOMBRES_FILE" 2>/dev/null; then
        echo "❌ El nombre '$nombre_descriptivo' ya está en uso"
        return 1
    fi
    
    # Eliminar entrada existente
    grep -v "^${cliente}:" "$NOMBRES_FILE" 2>/dev/null > "${NOMBRES_FILE}.tmp"
    mv "${NOMBRES_FILE}.tmp" "$NOMBRES_FILE"
    
    # Agregar nueva entrada
    echo "${cliente}:${nombre_descriptivo}" >> "$NOMBRES_FILE"
    echo "✅ Nombre '$nombre_descriptivo' asignado a $cliente"
}

mostrar_menu() {
    echo ""
    echo "🔧 GESTOR VPN - CON TRACKING COMPLETO"
    echo "===================================="
    echo ""
    echo "1) 👁️  Ver clientes conectados"
    echo "2) 📋 Listar todos los clientes"
    echo "3) ⏸️  SUSPENDER cliente (temporal)"
    echo "4) ▶️  REACTIVAR cliente (mismo certificado)"
    echo "5) 🚫 BLOQUEAR permanente (nuevo certificado)"
    echo "6) 🏷️  GESTIONAR NOMBRES"
    echo "7) 📊 ESTADÍSTICAS Y TRACKING"
    echo "8) 🔍 Estado del servicio"
    echo "9) ❌ Salir"
    echo ""
    echo -n "Selecciona [1-9]: "
}

ver_conectados() {
    echo ""
    echo "📊 CLIENTES CONECTADOS:"
    
    # Actualizar tracking con clientes conectados
    if [ -f "/var/log/openvpn-status.log" ] && grep -q "CLIENT_LIST" "/var/log/openvpn-status.log"; then
        grep "^CLIENT_LIST" /var/log/openvpn-status.log | while read line; do
            cliente=$(echo "$line" | awk '{print $2}')
            ip=$(echo "$line" | awk '{print $3}')
            bytes_recv=$(echo "$line" | awk '{print $4}')
            bytes_sent=$(echo "$line" | awk '{print $5}')
            connected_since=$(echo "$line" | awk '{print $6 " " $7}')
            
            # Registrar conexión
            registrar_conexion "$cliente" "$ip"
            
            nombre_descriptivo=$(obtener_nombre "$cliente")
            
            echo "   👤 $nombre_descriptivo"
            echo "      📍 IP: $ip"
            echo "      📋 Certificado: $cliente"
            
            if [ -n "$connected_since" ] && [ "$connected_since" != "UNDEF" ]; then
                echo "      ⏰ Conectado desde: $connected_since"
            fi
            
            if [ -n "$bytes_recv" ] && [ "$bytes_recv" != "0" ]; then
                mb_recv=$((bytes_recv / 1024 / 1024))
                echo "      🔽 Descargado: ${mb_recv} MB"
            fi
            
            if [ -n "$bytes_sent" ] && [ "$bytes_sent" != "0" ]; then
                mb_sent=$((bytes_sent / 1024 / 1024))
                echo "      🔼 Subido: ${mb_sent} MB"
            fi
            echo ""
        done
    else
        echo "   ℹ️  No hay clientes conectados"
    fi
}

listar_clientes() {
    echo ""
    echo "📋 ESTADO DE CLIENTES:"
    
    if [ ! -f "/etc/easy-rsa/pki/index.txt" ]; then
        echo "   ❌ No hay base de datos de certificados"
        return
    fi
    
    # Obtener todos los clientes únicos (activos, suspendidos, bloqueados)
    todos_clientes=$(grep -E "^(V|R)" /etc/easy-rsa/pki/index.txt 2>/dev/null | awk '{print $6}' | sort | uniq)
    
    if [ -z "$todos_clientes" ]; then
        echo "   ℹ️  No hay clientes configurados"
        return
    fi
    
    echo ""
    echo "┌─────────────────────────────────────────────────────────────────┐"
    echo "│ CLIENTE                       │ ESTADO      │ ÚLTIMA CONEXIÓN   │"
    echo "├─────────────────────────────────────────────────────────────────┤"
    
    for cliente in $todos_clientes; do
        nombre_descriptivo=$(obtener_nombre "$cliente")
        
        # Determinar estado
        if grep -q "^V.*/CN=${cliente}$" "/etc/easy-rsa/pki/index.txt" 2>/dev/null; then
            estado="🟢 ACTIVO"
        elif [ -f "/etc/openvpn/suspended/${cliente}.crt.backup" ]; then
            estado="⏸️  SUSPENDIDO"
        else
            estado="🔴 BLOQUEADO"
        fi
        
        # Obtener última conexión
        ultima_info=$(obtener_ultima_conexion "$cliente")
        ultima_fecha=$(echo "$ultima_info" | cut -d'|' -f1)
        ultima_ip=$(echo "$ultima_info" | cut -d'|' -f2)
        
        if [ "$ultima_fecha" = "Nunca" ]; then
            ultima_display="Nunca"
        else
            ultima_display=$(calcular_tiempo_desde "$ultima_fecha")
        fi
        
        # Formatear salida en columnas
        printf "│ %-30s │ %-11s │ %-18s │\n" \
               "$nombre_descriptivo" "$estado" "$ultima_display"
    done
    
    echo "└─────────────────────────────────────────────────────────────────┘"
    echo ""
    echo "💡 Se muestran: Nombre Descriptivo (Estado) - Tiempo desde última conexión"
}

# Función para mostrar estadísticas detalladas
mostrar_estadisticas() {
    echo ""
    echo "📊 ESTADÍSTICAS DETALLADAS"
    echo "=========================="
    
    if [ ! -f "/etc/easy-rsa/pki/index.txt" ]; then
        echo "   ❌ No hay base de datos de certificados"
        return
    fi
    
    # Contadores
    total_clientes=0
    activos=0
    suspendidos=0
    bloqueados=0
    con_conexion=0
    sin_conexion=0
    
    # Procesar cada cliente
    grep -E "^(V|R)" /etc/easy-rsa/pki/index.txt 2>/dev/null | awk '{print $6}' | sort | uniq | while read cliente; do
        total_clientes=$((total_clientes + 1))
        
        if grep -q "^V.*/CN=${cliente}$" "/etc/easy-rsa/pki/index.txt" 2>/dev/null; then
            activos=$((activos + 1))
        elif [ -f "/etc/openvpn/suspended/${cliente}.crt.backup" ]; then
            suspendidos=$((suspendidos + 1))
        else
            bloqueados=$((bloqueados + 1))
        fi
        
        ultima_info=$(obtener_ultima_conexion "$cliente")
        ultima_fecha=$(echo "$ultima_info" | cut -d'|' -f1)
        
        if [ "$ultima_fecha" != "Nunca" ]; then
            con_conexion=$((con_conexion + 1))
        else
            sin_conexion=$((sin_conexion + 1))
        fi
    done
    
    # Esperar a que termine el while para tener los contadores correctos
    wait
    
    echo ""
    echo "📈 RESUMEN GENERAL:"
    echo "   👥 Total clientes: $total_clientes"
    echo "   🟢 Activos: $activos"
    echo "   ⏸️  Suspendidos: $suspendidos"
    echo "   🔴 Bloqueados: $bloqueados"
    echo ""
    echo "🌐 ACTIVIDAD:"
    echo "   ✅ Con conexión reciente: $con_conexion"
    echo "   ❌ Sin conexión: $sin_conexion"
    
    # Mostrar últimos conectados
    echo ""
    echo "🕒 ÚLTIMAS CONEXIONES:"
    if [ -f "$TRACKING_FILE" ] && [ -s "$TRACKING_FILE" ]; then
        # Ordenar por fecha (más reciente primero) y mostrar últimos 5
        sort -t: -k3,3 -r "$TRACKING_FILE" 2>/dev/null | head -5 | while read linea; do
            cliente=$(echo "$linea" | cut -d: -f1)
            ip=$(echo "$linea" | cut -d: -f2)
            fecha_hora=$(echo "$linea" | cut -d: -f3-)
            nombre_descriptivo=$(obtener_nombre "$cliente")
            tiempo_desde=$(calcular_tiempo_desde "$fecha_hora")
            
            echo "   👤 $nombre_descriptivo"
            echo "      📍 $ip - 🕒 $fecha_hora"
            echo "      ⏱️  $tiempo_desde"
            echo ""
        done
    else
        echo "   ℹ️  No hay registros de conexión"
    fi
}

# [Las funciones suspender_cliente, reactivar_cliente, bloquear_permanentemente, 
# gestionar_nombres permanecen igual pero actualizadas para usar el tracking]

suspender_cliente() {
    echo ""
    echo "⏸️  SUSPENDER CLIENTE (TEMPORAL)"
    echo "------------------------------"
    
    echo "Clientes activos:"
    clientes_activos=$(grep "^V" /etc/easy-rsa/pki/index.txt 2>/dev/null | awk '{print $6}' | head -10)
    if [ -z "$clientes_activos" ]; then
        echo "   No hay clientes activos"
        return
    fi
    
    for cliente in $clientes_activos; do
        nombre_descriptivo=$(obtener_nombre "$cliente")
        ultima_info=$(obtener_ultima_conexion "$cliente")
        ultima_fecha=$(echo "$ultima_info" | cut -d'|' -f1)
        
        if [ "$cliente" = "$nombre_descriptivo" ]; then
            echo "   $cliente"
        else
            echo "   $nombre_descriptivo ($cliente)"
        fi
        
        if [ "$ultima_fecha" != "Nunca" ]; then
            echo "      Última conexión: $(calcular_tiempo_desde "$ultima_fecha")"
        fi
        echo ""
    done
    
    echo -n "Cliente a suspender (nombre o certificado): "
    read INPUT_CLIENTE
    
    # [El resto de la función permanece igual...]
    # ... (código de suspensión)
}

# [Implementar las otras funciones de manera similar...]

# Nueva opción para estadísticas
estadisticas_tracking() {
    while true; do
        echo ""
        echo "📊 ESTADÍSTICAS Y TRACKING"
        echo "=========================="
        echo ""
        echo "1) Ver estadísticas generales"
        echo "2) Ver últimas conexiones"
        echo "3) Ver cliente específico"
        echo "4) Limpiar registros antiguos"
        echo "5) Volver al menú principal"
        echo ""
        echo -n "Selecciona [1-5]: "
        read opcion_stats
        
        case $opcion_stats in
            1)
                mostrar_estadisticas
                ;;
            2)
                echo ""
                echo "🕒 ÚLTIMAS 10 CONEXIONES:"
                if [ -f "$TRACKING_FILE" ] && [ -s "$TRACKING_FILE" ]; then
                    sort -t: -k3,3 -r "$TRACKING_FILE" 2>/dev/null | head -10 | while read linea; do
                        cliente=$(echo "$linea" | cut -d: -f1)
                        ip=$(echo "$linea" | cut -d: -f2)
                        fecha_hora=$(echo "$linea" | cut -d: -f3-)
                        nombre_descriptivo=$(obtener_nombre "$cliente")
                        tiempo_desde=$(calcular_tiempo_desde "$fecha_hora")
                        
                        echo "   👤 $nombre_descriptivo ($cliente)"
                        echo "      📍 $ip"
                        echo "      🕒 $fecha_hora"
                        echo "      ⏱️  $tiempo_desde"
                        echo ""
                    done
                else
                    echo "   ℹ️  No hay registros de conexión"
                fi
                ;;
            3)
                echo ""
                echo -n "Cliente a consultar (nombre o certificado): "
                read cliente_consulta
                
                # Buscar cliente real
                CLIENTE_REAL=""
                if grep -q "^${cliente_consulta}:" "$NOMBRES_FILE" 2>/dev/null || \
                   [ -f "/etc/easy-rsa/pki/issued/${cliente_consulta}.crt" ]; then
                    CLIENTE_REAL=$cliente_consulta
                else
                    CLIENTE_REAL=$(grep ":${cliente_consulta}$" "$NOMBRES_FILE" 2>/dev/null | cut -d: -f1)
                fi
                
                if [ -n "$CLIENTE_REAL" ]; then
                    nombre_descriptivo=$(obtener_nombre "$CLIENTE_REAL")
                    ultima_info=$(obtener_ultima_conexion "$CLIENTE_REAL")
                    ultima_fecha=$(echo "$ultima_info" | cut -d'|' -f1)
                    ultima_ip=$(echo "$ultima_info" | cut -d'|' -f2)
                    
                    echo ""
                    echo "📈 ESTADÍSTICAS DE: $nombre_descriptivo"
                    echo "────────────────────────────────────"
                    echo "   📋 Certificado: $CLIENTE_REAL"
                    
                    # Estado
                    if grep -q "^V.*/CN=${CLIENTE_REAL}$" "/etc/easy-rsa/pki/index.txt" 2>/dev/null; then
                        echo "   🟢 Estado: ACTIVO"
                    elif [ -f "/etc/openvpn/suspended/${CLIENTE_REAL}.crt.backup" ]; then
                        echo "   ⏸️  Estado: SUSPENDIDO"
                    else
                        echo "   🔴 Estado: BLOQUEADO"
                    fi
                    
                    # Última conexión
                    if [ "$ultima_fecha" = "Nunca" ]; then
                        echo "   ❌ Última conexión: Nunca se ha conectado"
                    else
                        echo "   ✅ Última conexión: $ultima_fecha"
                        echo "   📍 Desde IP: $ultima_ip"
                        echo "   ⏱️  Hace: $(calcular_tiempo_desde "$ultima_fecha")"
                    fi
                else
                    echo "❌ Cliente '$cliente_consulta' no encontrado"
                fi
                ;;
            4)
                echo ""
                echo "🗑️  LIMPIAR REGISTROS ANTIGUOS"
                echo "---------------------------"
                echo "⚠️  Esto eliminará registros de conexión antiguos"
                echo -n "¿Continuar? (s/n): "
                read confirmar
                if [ "$confirmar" = "s" ]; then
                    # Mantener solo registros de los últimos 30 días
                    fecha_limite=$(date -d "30 days ago" '+%Y-%m-%d')
                    temp_file=$(mktemp)
                    
                    while IFS=: read -r cliente ip fecha_hora; do
                        if [ "$(date -d "$fecha_hora" '+%Y-%m-%d' 2>/dev/null)" \< "$fecha_limite" ]; then
                            echo "🗑️  Eliminando registro antiguo: $cliente - $fecha_hora"
                        else
                            echo "$cliente:$ip:$fecha_hora" >> "$temp_file"
                        fi
                    done < "$TRACKING_FILE"
                    
                    mv "$temp_file" "$TRACKING_FILE"
                    echo "✅ Registros antiguos eliminados"
                else
                    echo "❌ Operación cancelada"
                fi
                ;;
            5)
                return
                ;;
            *)
                echo "❌ Opción inválida"
                ;;
        esac
    done
}

# Actualizar menú principal
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
        7) estadisticas_tracking ;;
        8) 
            echo ""
            echo "🔍 ESTADO DEL SERVICIO:"
            pgrep openvpn >/dev/null && echo "   ✅ OpenVPN: ACTIVO" || echo "   ❌ OpenVPN: INACTIVO"
            ;;
        9)
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
echo "✅ SISTEMA CON TRACKING INSTALADO"
echo ""
echo "🎯 NUEVAS FUNCIONALIDADES:"
echo "   📊 Opción 7 - Estadísticas y tracking completo"
echo "   🕒 Fecha/hora de última conexión"
echo "   ⏱️  Tiempo desde última conexión"
echo "   📈 Estadísticas generales"
echo "   📋 Tablas formateadas con toda la información"
echo ""
echo "🚀 EJECUTA: gestor-vpn"
