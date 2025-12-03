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
