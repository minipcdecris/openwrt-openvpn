cat > /root/install-tailscale.sh <<'EOF'
#!/bin/sh

# ============================================================
# Tailscale Installer - Cudy / OpenWrt
# Versión DEFINITIVA 1.0
# ============================================================

set -u

GREEN='\033[32m'
RED='\033[31m'
YELLOW='\033[33m'
NC='\033[0m'

ok() {
    printf '%b[OK]%b %s\n' "$GREEN" "$NC" "$1"
}

warn() {
    printf '%b[AVISO]%b %s\n' "$YELLOW" "$NC" "$1"
}

error() {
    printf '%b[ERROR]%b %s\n' "$RED" "$NC" "$1"
}

echo ""
echo "============================================================"
echo "        INSTALADOR TAILSCALE - CUDY / OPENWRT"
echo "                    VERSION DEFINITIVA"
echo "============================================================"
echo ""

# ------------------------------------------------------------
# 1. Comprobar root
# ------------------------------------------------------------

if [ "$(id -u)" != "0" ]; then
    error "Este script debe ejecutarse como root."
    exit 1
fi

ok "Ejecutando como root"

# ------------------------------------------------------------
# 2. Detectar OpenWrt
# ------------------------------------------------------------

if [ ! -f /etc/openwrt_release ]; then
    error "No parece ser un sistema OpenWrt."
    exit 1
fi

. /etc/openwrt_release

ok "OpenWrt detectado: $DISTRIB_RELEASE"
ok "Arquitectura: $DISTRIB_ARCH"

# ------------------------------------------------------------
# 3. Comprobar espacio
# ------------------------------------------------------------

AVAILABLE=$(df -k /overlay 2>/dev/null | awk 'NR==2 {print $4}')

if [ -n "$AVAILABLE" ] && [ "$AVAILABLE" -lt 10000 ]; then
    error "Espacio insuficiente en /overlay."
    exit 1
fi

ok "Espacio disponible en /overlay: ${AVAILABLE:-desconocido} KB"

# ------------------------------------------------------------
# 4. Comprobar conectividad
# ------------------------------------------------------------

if ! wget -q -O /dev/null --timeout=10 https://controlplane.tailscale.com 2>/dev/null; then
    error "No hay conectividad con Tailscale."
    exit 1
fi

ok "Conectividad con Tailscale: OK"

# ------------------------------------------------------------
# 5. Detectar hostname
# ------------------------------------------------------------

HOSTNAME=$(uci -q get system.@system[0].hostname)

if [ -z "$HOSTNAME" ]; then
    error "No se ha podido obtener el hostname de OpenWrt."
    exit 1
fi

ok "Hostname OpenWrt: $HOSTNAME"

# ------------------------------------------------------------
# 6. Validar hostname
# ------------------------------------------------------------

case "$HOSTNAME" in
    *[A-Z]*)
        error "El hostname debe estar escrito completamente en minúsculas."
        error "Ejemplo válido: cliente4"
        exit 1
        ;;
esac

case "$HOSTNAME" in
    *[!a-z0-9-]*)
        error "El hostname contiene caracteres no válidos."
        error "Utiliza únicamente: a-z, 0-9 y -"
        exit 1
        ;;
esac

case "$HOSTNAME" in
    -*|*-)
        error "El hostname no puede comenzar ni terminar con '-'."
        exit 1
        ;;
esac

TS_HOSTNAME="$HOSTNAME"

ok "Hostname Tailscale: $TS_HOSTNAME"

# ------------------------------------------------------------
# 7. Instalar Tailscale si no existe
# ------------------------------------------------------------

if command -v tailscale >/dev/null 2>&1; then

    ok "Tailscale ya está instalado."

else

    warn "Tailscale no está instalado."
    echo "Actualizando repositorios..."

    if ! opkg update; then
        error "Fallo ejecutando opkg update."
        exit 1
    fi

    ok "Repositorios actualizados."

    if ! opkg install tailscale; then
        error "No se pudo instalar Tailscale."
        exit 1
    fi

    ok "Tailscale instalado."

fi

# ------------------------------------------------------------
# 8. Habilitar y arrancar servicio
# ------------------------------------------------------------

/etc/init.d/tailscale enable

if ! /etc/init.d/tailscale status >/dev/null 2>&1; then
    echo "Iniciando servicio tailscale..."
    /etc/init.d/tailscale start
    sleep 3
fi

if /etc/init.d/tailscale status >/dev/null 2>&1; then
    ok "Servicio tailscale: RUNNING"
else
    error "El servicio tailscale no está funcionando."
    exit 1
fi

# ------------------------------------------------------------
# 9. Comprobar autenticación
# ------------------------------------------------------------

TS_STATE=$(tailscale status 2>&1)

if echo "$TS_STATE" | grep -q "Logged out"; then

    echo ""
    warn "Este Cudy todavía no está registrado en Tailscale."
    echo ""
    echo "Introduce la Auth Key de Tailscale."
    echo "La entrada no será visible en pantalla."
    echo ""

    read -r -s AUTHKEY
    echo ""

    if [ -z "$AUTHKEY" ]; then
        error "No se introdujo ninguna Auth Key."
        exit 1
    fi

    echo "Registrando Cudy en Tailscale..."

    if ! tailscale up \
        --auth-key="$AUTHKEY" \
        --hostname="$TS_HOSTNAME" \
        --accept-dns=false; then

        error "No se pudo registrar el Cudy en Tailscale."
        unset AUTHKEY
        exit 1
    fi

    unset AUTHKEY

    ok "Cudy registrado correctamente."

else

    ok "Tailscale está autenticado y funcionando."
    ok "No se modifica la autenticación existente."

    if tailscale set --hostname="$TS_HOSTNAME" >/dev/null 2>&1; then
        ok "Hostname Tailscale actualizado."
    else
        warn "No se pudo actualizar el hostname de Tailscale."
    fi

fi

# ------------------------------------------------------------
# 10. Comprobar IP Tailscale
# ------------------------------------------------------------

sleep 2

TS_IP=$(tailscale ip -4 2>/dev/null | head -n 1)

if [ -z "$TS_IP" ]; then
    error "Tailscale no ha obtenido una dirección IPv4."
    exit 1
fi

ok "IP Tailscale: $TS_IP"

# ------------------------------------------------------------
# 11. Comprobar estado final
# ------------------------------------------------------------

FINAL_STATE=$(tailscale status 2>&1)

if echo "$FINAL_STATE" | grep -q "$TS_IP"; then
    ok "Estado final Tailscale: RUNNING"
else
    error "No se ha podido confirmar el estado final de Tailscale."
    exit 1
fi

# ------------------------------------------------------------
# 12. Asegurar permisos
# ------------------------------------------------------------

chmod +x /root/install-tailscale.sh 2>/dev/null || true

# ------------------------------------------------------------
# 13. Resumen final
# ------------------------------------------------------------

echo ""
echo "============================================================"
echo "              TAILSCALE CONFIGURADO CORRECTAMENTE"
echo "============================================================"
echo ""
echo "Hostname OpenWrt   : $HOSTNAME"
echo "Hostname Tailscale : $TS_HOSTNAME"
echo "IP Tailscale       : $TS_IP"
echo "Servicio           : RUNNING"
echo "Autenticación      : OK"
echo "DNS Tailscale      : DESACTIVADO"
echo ""
echo "============================================================"
echo ""

exit 0
EOF
