#!/usr/bin/env bash
# Deshace aplicar.sh (blindaje fuerte) con el respaldo que dejo en /root.
# Corre EN Debian como root:  lanzar.sh revertir /root/blindaje_fuerte_<fecha>
set -uo pipefail
[ "$(id -u)" = 0 ] || { echo "Correr con sudo"; exit 1; }
R="${1:-$(cat /root/blindaje_fuerte_ULTIMO.txt 2>/dev/null)}"
[ -f "$R/wp-config.php" ] || { echo "No es un respaldo valido: $R"; exit 1; }
WP=/var/www/html; A=/etc/apache2
PHPINI=$(ls /etc/php/*/apache2/php.ini | head -1); PHPDIR=$(dirname "$PHPINI")

echo "=== Apache"
rm -f "$A/conf-available/zz-blindaje.conf" "$A/conf-enabled/zz-blindaje.conf"
cp -p "$R/security.conf" "$A/conf-available/security.conf" 2>/dev/null
grep -q '^status\.load'    "$R/mods-enabled.txt" && a2enmod status >/dev/null 2>&1
grep -q '^autoindex\.load' "$R/mods-enabled.txt" && a2enmod autoindex >/dev/null 2>&1
echo "=== PHP"
rm -f "$PHPDIR/conf.d/99-blindaje.ini"
echo "=== WordPress"
cp -p "$R/wp-config.php" "$WP/wp-config.php"
rm -f "$WP/wp-content/mu-plugins/blindaje.php"
echo "=== Servicios (se vuelven a habilitar los que estaban)"
while read -r line; do
  svc=$(echo "$line" | awk '{print $1}'); st=$(echo "$line" | awk '{print $NF}')
  [ "$st" = enabled ] && systemctl enable --now "$svc" >/dev/null 2>&1
done < <(paste <(echo "cups cups-browsed avahi-daemon ModemManager" | tr ' ' '\n') "$R/servicios.txt" 2>/dev/null)
apache2ctl configtest && systemctl reload apache2
echo "Revertido desde $R (nota: el firewall nftables, si lo pusiste, se quita aparte: sudo nft flush ruleset; sudo systemctl disable --now nftables)"
