#!/usr/bin/env bash
# HTTPS - Fase 1: abre el 443 en pfSense (rdr WAN tcp/443 -> 10.10.20.40:443 con pase).
# Lo corre el responsable (usa llaves, no pide clave):
#   ! bash "D:/VMware_LAB/_lab/https/abrir_443_pfsense.sh"
# Deshacer (quitar el rdr): se hace por la GUI de pfSense.
S="-o BatchMode=yes"; DIR="$(cd "$(dirname "$0")" && pwd)"
echo "=== pfSense: anadir rdr 443 -> DMZ WordPress"
ssh $S rpi5 "ssh $S pfsense 'cat > /tmp/fase1_https.php && php -f /tmp/fase1_https.php; /etc/rc.filter_configure_sync >/dev/null 2>&1; rm -f /tmp/fase1_https.php'" < "$DIR/fase1_https.php"
echo "=== rdr 443 presente en pfSense?:"
ssh $S rpi5 "ssh $S pfsense 'pfctl -sn | grep \"port = https\" || echo NINGUNA'"
