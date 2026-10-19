#!/usr/bin/env bash
# Debian DMZ "Servidor2" - deshace aplicar.sh con el respaldo que dejo en /root.
# Corre EN Debian como root; lo lanza:  bash lanzar.sh revertir /root/respaldo_endurecer_<fecha>
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "Correr con sudo"; exit 1; }
R="${1:?Falta la carpeta de respaldo: /root/respaldo_endurecer_<fecha>}"
WP=/var/www/html
[ -f "$R/permisos_wp.txt" ] || { echo "No es un respaldo valido: $R"; exit 1; }

echo "=== SSH"
rm -f /etc/ssh/sshd_config.d/10-lab-endurecer.conf
sshd -t && systemctl reload ssh

echo "=== Apache"
cp -p "$R/security.conf" /etc/apache2/conf-available/security.conf
cp -p "$R/wordpress.conf" /etc/apache2/conf-available/wordpress.conf
apache2ctl configtest && systemctl reload apache2

echo "=== WordPress (wp-config, mu-plugin, duenos y permisos)"
cp -p "$R/wp-config.php" "$WP/wp-config.php"
rm -f "$WP/wp-content/mu-plugins/ocultar-version.php"
rmdir "$WP/wp-content/mu-plugins" 2>/dev/null || true
while read -r m u g p; do
  [ -e "$p" ] && chown "$u:$g" "$p" && chmod "$m" "$p"
done < "$R/permisos_wp.txt"

echo "Revertido desde $R"
