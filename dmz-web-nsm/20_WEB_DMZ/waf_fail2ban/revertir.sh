#!/usr/bin/env bash
# Deshace la config de ModSecurity+CRS y fail2ban (los paquetes quedan instalados).
# Corre EN Debian como root:  lanzar.sh revertir
set -uo pipefail
[ "$(id -u)" = 0 ] || { echo "Correr con sudo"; exit 1; }
MOD=/etc/modsecurity/modsecurity.conf; F2B=/etc/fail2ban
R="${1:-$(cat /root/waf_fail2ban_ULTIMO.txt 2>/dev/null)}"

echo "=== ModSecurity: desactivar (sin su config base no actua; ademas se apaga el modulo)"
a2dismod -f security2 >/dev/null 2>&1
if [ -n "${R:-}" ] && [ -f "$R/modsecurity.conf" ]; then cp -p "$R/modsecurity.conf" "$MOD"; else rm -f "$MOD"; fi
apache2ctl configtest && systemctl reload apache2

echo "=== fail2ban: quitar jail y filtro"
if [ -n "${R:-}" ] && [ -f "$R/jail.local" ]; then cp -p "$R/jail.local" "$F2B/jail.local"; else rm -f "$F2B/jail.local"; fi
rm -f "$F2B/filter.d/wp-hard.conf"
systemctl restart fail2ban
echo "Revertido. (ModSecurity apagado; fail2ban solo con su config por defecto.)"
