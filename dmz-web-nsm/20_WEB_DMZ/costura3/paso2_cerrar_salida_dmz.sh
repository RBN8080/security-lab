#!/usr/bin/env bash
# Costura 3 - Paso 2: cerrar la salida de la DMZ a internet (pfSense), por la Pi 5.
# Lo ejecuta el responsable desde el host:
#   ! bash "D:/VMware_LAB/_lab/costura3/paso2_cerrar_salida_dmz.sh"            -> cerrar
#   ! bash "D:/VMware_LAB/_lab/costura3/paso2_cerrar_salida_dmz.sh" revertir   -> reabrir (actualizar)
DIR="$(cd "$(dirname "$0")" && pwd)"
MODO="${1:-}"

echo "=== pfSense: aplicar ($([ "$MODO" = revertir ] && echo reabrir || echo cerrar))"
ssh -o BatchMode=yes rpi5 "ssh -o BatchMode=yes pfsense 'cat > /tmp/costura3_cerrar_salida_dmz.php && php -f /tmp/costura3_cerrar_salida_dmz.php $MODO && /etc/rc.filter_configure_sync >/dev/null && echo RECARGA-OK'" < "$DIR/costura3_cerrar_salida_dmz.php"

echo "=== Reglas pass http/https que quedan en la DMZ (em2):"
ssh -o BatchMode=yes rpi5 'ssh -o BatchMode=yes pfsense "pfctl -sr | grep \"on em2\" | grep -E \"port = (http|https)\" || echo NINGUNA"'

echo "=== La web sigue respondiendo desde la Pi:"
ssh -o BatchMode=yes rpi5 'curl -s -o /dev/null -w "HTTP %{http_code}\n" --max-time 5 http://10.10.20.40/'

echo "=== Debian hacia internet (cerrado = HTTP 000 / SALIDA-BLOQUEADA):"
ssh -o BatchMode=yes rpi5 'ssh -o BatchMode=yes debian "curl -s -o /dev/null -w \"HTTP %{http_code}\n\" --max-time 6 http://deb.debian.org/ || echo SALIDA-BLOQUEADA"'
