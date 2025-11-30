#!/bin/sh

echo ""
echo "🔧 INSTALANDO SOLUCIÓN DEFINITIVA"
echo "================================"

# Crear el gestor con diagnóstico integrado
cat > /usr/bin/gestor-vpn << 'GESTOR_SCRIPT'
#!/bin/sh

# Archivos de configuración
NOMBRES_FILE="/etc/openvpn/clientes/nombres.txt"
TRACKING_FILE="/etc/openvpn/clientes/tracking.txt"

# Asegurar que los directorios y archivos existen
mkdir -p /etc/openvpn/clientes/
touch "$NOMBRES_FILE"

# Función para obtener nombre descriptivo (MEJORADA CON DIAGNÓSTICO)
obtener_nombre() {
    local cliente=$1
    
    # Verificar que el archivo existe y tiene contenido
    if [ ! -f "$NOMBRES_FILE" ] || [ ! -s "$NOMBRES_FILE" ]; then
        echo "$cliente"
        return
    fi
    
    # Buscar el nombre con método más robusto
    local nombre=$(grep "^${cliente}:" "$NOMBRES_FILE" 2>/dev/null | head -1 | cut -d: -f2-)
    
    # Limpiar el nombre (eliminar espacios en blanco)
    nombre=$(echo "$nombre" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    if [ -n "$nombre" ] && [ "$nombre" != "$cliente" ]; then
        echo "$nombre"
    else
        echo "$cliente"
    fi
}

# Función para diagnosticar problemas de nombres
diagnosticar_nombres() {
    echo ""
    echo "🔍 DIAGNÓSTICO DE NOMBRES"
    echo "========================"
    
    if [ ! -f "$NOMBRES_FILE" ]; then
        echo "❌ El archivo de nombres NO existe: $NOMBRES_FILE"
        echo "💡 Ejecuta: mkdir -p /etc/openvpn/clientes/ && touch /etc/openvpn/clientes/nombres.txt"
        return 1
    fi
    
    if [ ! -s "$NOMBRES_FILE" ]; then
        echo "❌ El archivo de nombres está VACÍO"
        echo "💡 Usa la opción 6 para asignar nombres a los clientes"
        return 1
    fi
    
    echo "✅ Archivo de nombres: EXISTE"
    echo "📊 Contenido:"
    echo "┌────────────────────────────────────┐"
    cat "$NOMBRES_FILE" | while read linea; do
        if [ -n "$linea" ] && [ "${linea:0:1}" != "#" ]; then
            echo "│ $linea"
        fi
    done
    echo "└────────────────────────────────────┘"
    
    echo ""
    echo "🔧 PROBANDO CLIENTES CONECTADOS:"
    if [ -f "/var/log/openvpn-status.log" ] && grep -q "CLIENT_LIST" "/var/log/openvpn-status.log"; then
        grep "^CLIENT_LIST" "/var/log/openvpn-status.log" | awk '{print $2}' | while read cliente; do
            nombre=$(obtener_nombre "$cliente")
            if [ "$cliente" = "$nombre" ]; then
                echo "   ❌ $cliente → SIN NOMBRE"
            else
                echo "   ✅ $cliente → $nombre"
            fi
        done
    else
        echo "   ℹ️  No hay clientes conectados para probar"
    fi
}

# Función para mostrar menú
mostrar_menu() {
    echo ""
    echo "🔧 GESTOR VPN - CON NOMBRES DESCRIPTIVOS"
    echo "========================================"
    echo ""
    echo "1) 👁️  Ver clientes conectados"
    echo "2) 📋  Listar todos los clientes"
    echo "3) ⏸️  SUSPENDER cliente (temporal)"
    echo "4) ▶️  REACTIVAR cliente (mismo certificado)"
    echo "5) 🚫  BLOQUEAR permanente (nuevo certificado)"
    echo "6) 🏷️  GESTIONAR NOMBRES"
    echo "7) 🔍  DIAGNÓSTICO de nombres"
    echo "8) ❌  Salir"
    echo ""
    echo -n "Selecciona [1-8]: "
}

# Función para ver clientes conectados (CON MÁS DEBUG)
ver_conectados() {
    echo ""
    echo "📊 CLIENTES CONECTADOS:"
    
    if [ -f "/var/log/openvpn-status.log" ] && grep -q "CLIENT_LIST" "/var/log/openvpn-status.log"; then
        grep "^CLIENT_LIST" "/var/log/openvpn-status.log" | while IFS= read -r line; do
            cliente=$(echo "$line" | awk '{print $2}')
            ip=$(echo "$line" | awk '{print $3}')
            bytes_recv=$(echo "$line" | awk '{print $4}')
            bytes_sent=$(echo "$line" | awk '{print $5}')
            connected_since=$(echo "$line" | awk '{print $6 " " $7}')
            
            # Obtener nombre - SIEMPRE llamar a la función
            nombre_descriptivo=$(obtener_nombre "$cliente")
            
            # DEBUG: Mostrar qué está pasando
            if [ "$cliente" = "$nombre_descriptivo" ]; then
                # Si son iguales, el cliente no tiene nombre asignado
                echo "   👤 $cliente ⚠️"
            else
                # Si son diferentes, tiene nombre asignado
                echo "   👤 $nombre_descriptivo ✅"
            fi
            
            echo "      📍 IP: $ip"
            
            # Solo mostrar certificado si es diferente del nombre
            if [ "$cliente" != "$nombre_descriptivo" ]; then
                echo "      📋 Certificado: $cliente"
            fi
            
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
        
# Mostrar ayuda si no se ven nombres
if ver_conectados 2>/dev/null | grep -q "⚠️"; then
    echo "💡 ¿No ves los nombres? Usa la opción 6 para asignar nombres o 7 para diagnóstico"
fi
    else
        echo "   ℹ️  No hay clientes conectados"
    fi
}

# [Las otras funciones listar_clientes, suspender_cliente, etc. permanecen igual...]
# ... (mantener el código anterior de estas funciones)

# Función para gestionar nombres (MEJORADA)
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
                    for cliente in $(grep -E "^(V|R)" /etc/easy-rsa/pki/index.txt 2>/dev/null | awk '{print $6}' | sort -u | head -10); do
                        if [ -n "$cliente" ]; then
                            nombre_actual=$(obtener_nombre "$cliente")
                            if [ "$cliente" = "$nombre_actual" ]; then
                                echo "   📋 $cliente"
                            else
                                echo "   ✅ $nombre_actual ($cliente)"
                            fi
                        fi
                    done
                fi
                echo ""
                echo -n "Certificado del cliente (ej: client1): "
                read cliente
                echo -n "Nombre descriptivo (ej: Juan_Movil): "
                read nombre_descriptivo
                
                if [ -n "$cliente" ] && [ -n "$nombre_descriptivo" ]; then
                    # Crear archivo si no existe
                    touch "$NOMBRES_FILE"
                    # Eliminar entrada existente
                    grep -v "^${cliente}:" "$NOMBRES_FILE" 2>/dev/null > "${NOMBRES_FILE}.tmp"
                    # Agregar nueva entrada
                    echo "${cliente}:${nombre_descriptivo}" >> "${NOMBRES_FILE}.tmp"
                    mv "${NOMBRES_FILE}.tmp" "$NOMBRES_FILE"
                    echo "✅ Nombre '$nombre_descriptivo' asignado a $cliente"
                    echo "🔍 Prueba la opción 1 para ver el cambio"
                else
                    echo "❌ Nombre no válido"
                fi
                ;;
            2)
                echo ""
                echo "📋 NOMBRES ASIGNADOS:"
                if [ -f "$NOMBRES_FILE" ] && [ -s "$NOMBRES_FILE" ]; then
                    echo ""
                    grep -v "^#" "$NOMBRES_FILE" | grep -v "^$" | while read linea; do
                        if [ -n "$linea" ]; then
                            cliente=$(echo "$linea" | cut -d: -f1)
                            nombre=$(echo "$linea" | cut -d: -f2-)
                            if [ -n "$cliente" ] && [ -n "$nombre" ]; then
                                echo "   🏷️  $nombre ($cliente)"
                            fi
                        fi
                    done
                else
                    echo "   No hay nombres asignados"
                    echo "   💡 Usa la opción 1 para asignar nombres"
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
                            nombre=$(echo "$linea" | cut -d: -f2-)
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

# Menú principal (ACTUALIZADO)
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
        7) diagnosticar_nombres ;;
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
echo "✅ SOLUCIÓN DEFINITIVA INSTALADA"
echo ""
echo "🎯 NUEVAS FUNCIONALIDADES:"
echo "   🔍 Opción 7 - Diagnóstico completo de nombres"
echo "   ✅ Función obtener_nombre mejorada"
echo "   🐛 Debug integrado en la visualización"
echo ""
echo "🚀 EJECUTA ESTOS PASOS:"
echo "   1. gestor-vpn → Opción 7 (diagnóstico)"
echo "   2. gestor-vpn → Opción 6 → 1 (asignar nombres)"
echo "   3. gestor-vpn → Opción 1 (ver resultados)"
