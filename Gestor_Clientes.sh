#!/bin/sh
echo ""
echo "🔧 GESTOR DE CLIENTES OPENVPN"
echo "============================"

while true; do
    echo ""
    echo "1️⃣  Ver clientes conectados"
    echo "2️⃣  Bloquear cliente (revocar certificado)"
    echo "3️⃣  Ver clientes revocados"
    echo "4️⃣  Desbloquear cliente"
    echo "5️⃣  Bloquear por IP"
    echo "6️⃣  Salir"
    echo ""
    echo "Selecciona una opción: "
    read OPCION

    case $OPCION in
        1)
            echo ""
            echo "📊 CLIENTES CONECTADOS:"
            if [ -f "/var/log/openvpn-status.log" ]; then
                grep -E "^CLIENT_LIST" /var/log/openvpn-status.log | awk '{print "   └─ " $2 " (IP: " $3 ")"}'
            else
                echo "   No hay clientes conectados o log no disponible"
            fi
            ;;
        2)
            echo ""
            echo "🔒 BLOQUEAR CLIENTE:"
            echo "Clientes disponibles:"
            ls /etc/easy-rsa/pki/issued/ | grep -E '^client[0-9]+\.crt$' | sed 's/\.crt//'
            echo ""
            echo "Nombre del cliente: "
            read CLIENTE
            if [ -f "/etc/easy-rsa/pki/issued/${CLIENTE}.crt" ]; then
                cd /etc/easy-rsa
                echo "yes" | easyrsa revoke "$CLIENTE" > /dev/null 2>&1
                easyrsa gen-crl > /dev/null 2>&1
                cp /etc/easy-rsa/pki/crl.pem /etc/openvpn/
                /etc/init.d/openvpn restart
                echo "✅ Cliente $CLIENTE bloqueado"
            else
                echo "❌ Cliente no encontrado"
            fi
            ;;
        3)
            echo ""
            echo "📋 CLIENTES REVOCADOS:"
            if [ -f "/etc/easy-rsa/pki/index.txt" ]; then
                revoked=$(grep -E "^R" /etc/easy-rsa/pki/index.txt | awk '{print $6}')
                if [ -n "$revoked" ]; then
                    echo "$revoked" | while read client; do
                        echo "   └─ $client"
                    done
                else
                    echo "   No hay clientes revocados"
                fi
            fi
            ;;
        4)
            echo ""
            echo "🔓 DESBLOQUEAR CLIENTE:"
            if [ -f "/etc/easy-rsa/pki/index.txt" ]; then
                revoked=$(grep -E "^R" /etc/easy-rsa/pki/index.txt | awk '{print $6}')
                if [ -n "$revoked" ]; then
                    echo "Clientes revocados:"
                    echo "$revoked"
                    echo ""
                    echo "Nombre del cliente: "
                    read CLIENTE
                    # Esto requiere regenerar el certificado
                    echo "⚠️  Esto regenerará el certificado del cliente"
                    echo "¿Continuar? (s/n): "
                    read CONFIRMAR
                    if [ "$CONFIRMAR" = "s" ]; then
                        cd /etc/easy-rsa
                        echo -e "yes" | easyrsa build-client-full "$CLIENTE" nopass > /dev/null 2>&1
                        easyrsa gen-crl > /dev/null 2>&1
                        cp /etc/easy-rsa/pki/crl.pem /etc/openvpn/
                        /etc/init.d/openvpn restart
                        echo "✅ Cliente $CLIENTE desbloqueado y nuevo certificado generado"
                    fi
                else
                    echo "   No hay clientes revocados"
                fi
            fi
            ;;
        5)
            echo ""
            echo "IP a bloquear: "
            read IP_BLOQUEAR
            uci add firewall rule
            uci set firewall.@rule[-1].name="Block-OpenVPN-$IP_BLOQUEAR"
            uci set firewall.@rule[-1].src='*'
            uci set firewall.@rule[-1].src_ip="$IP_BLOQUEAR"
            uci set firewall.@rule[-1].target='DROP'
            uci commit firewall
            /etc/init.d/firewall reload
            echo "✅ IP $IP_BLOQUEAR bloqueada"
            ;;
        6)
            echo "👋 Saliendo..."
            exit 0
            ;;
        *)
            echo "❌ Opción inválida"
            ;;
    esac
done
