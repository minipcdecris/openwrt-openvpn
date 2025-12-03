echo "=== FORMATO DEL ARCHIVO DE ESTADO ==="
FILE="/tmp/openvpn-status.log"
[ -f "$FILE" ] || FILE="/var/log/openvpn-status.log"

if [ -f "$FILE" ]; then
    echo "Archivo: $FILE"
    echo ""
    echo "Primera línea:"
    head -1 "$FILE"
    echo ""
    echo "Primera línea con CLIENT_LIST:"
    grep "^CLIENT_LIST" "$FILE" | head -1
    echo ""
    echo "¿Tiene comas o espacios?"
    echo "- Comas: $(grep -c ',' <(head -1 "$FILE") 2>/dev/null)"
    echo "- Espacios: $(grep -c ' ' <(head -1 "$FILE") 2>/dev/null)"
else
    echo "❌ Archivo no encontrado"
fi
# Comando de prueba directa
echo "=== PRUEBA DIRECTA ==="
FILE="/var/log/openvpn-status.log"
if [ -f "$FILE" ]; then
    echo "Clientes encontrados en $FILE:"
    echo ""
    grep "^CLIENT_LIST" "$FILE" | grep -v "UNDEF" | while read line; do
        cliente=$(echo "$line" | awk '{print $2}')
        ip=$(echo "$line" | awk '{print $3}')
        fecha=$(echo "$line" | awk '{print $7}')
        hora=$(echo "$line" | awk '{print $8}')
        echo "✅ $cliente desde $ip - $fecha $hora"
    done
else
    echo "Archivo no encontrado"
fi
