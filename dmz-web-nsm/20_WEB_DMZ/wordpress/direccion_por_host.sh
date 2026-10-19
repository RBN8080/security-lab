#!/usr/bin/env bash
# WordPress (Debian DMZ "Servidor2"): usar la direccion por la que lo llamaron, solo si esta
# en la lista blanca. Asi carga completo desde Ubuntu (10.10.20.40), el host y el celular de
# casa (192.168.1.23). Con otra direccion (un bot, o la IP publica mientras no se agregue)
# sigue usando la de la base de datos: http://10.10.20.40. 2026-10-16.
# Ademas: wp-cron se llama a si mismo por 127.0.0.1; si usara 192.168.1.23 la DMZ lo
# bloquearia y saldria como CONTENCION en pfSense/SO.
# Corre EN Debian como root:  sudo bash direccion_por_host.sh            -> aplicar
#                             sudo bash direccion_por_host.sh revertir   -> quitar
# Para agregar la IP publica o un nombre DDNS: sumarlo a $lab_hosts y volver a aplicar.
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "Correr con sudo"; exit 1; }
WP=/var/www/html
CFG=$WP/wp-config.php
MU=$WP/wp-content/mu-plugins/lab-cron-local.php
RESP=/root/wp-config.antes_direccion_$(date +%Y%m%d_%H%M%S).php

cp -p "$CFG" "$RESP"
sed -i '/BEGIN LAB-DIRECCION/,/END LAB-DIRECCION/d' "$CFG"
rm -f "$MU"
if [ "${1:-}" = revertir ]; then
  php -l "$CFG" >/dev/null && echo "Revertido (respaldo previo: $RESP)"; exit 0
fi

T=$(mktemp)
cat > "$T" <<'PHP'
/* BEGIN LAB-DIRECCION (2026-10-16): usar la direccion por la que llamaron, solo si esta en la lista. */
$lab_hosts = array( '10.10.20.40', '192.168.1.23', '192.168.85.128', 'localhost', 'sitio-ejemplo.duckdns.org' );
$lab_host  = isset( $_SERVER['HTTP_HOST'] ) ? strtolower( $_SERVER['HTTP_HOST'] ) : '';
if ( in_array( $lab_host, $lab_hosts, true ) ) {
	define( 'WP_HOME', 'http://' . $lab_host );
	define( 'WP_SITEURL', 'http://' . $lab_host );
}
/* END LAB-DIRECCION */
PHP
awk -v f="$T" '/stop editing!/ && !hecho { while ((getline l < f) > 0) print l; hecho = 1 } { print }' "$CFG" > "$T.cfg"
cat "$T.cfg" > "$CFG"   # escribir encima conserva dueno y permisos (root:www-data 640)
rm -f "$T" "$T.cfg"
if ! php -l "$CFG" >/dev/null; then
  cp -p "$RESP" "$CFG"; echo "!! wp-config con error: restaurado"; exit 1
fi

cat > "$MU" <<'PHP'
<?php
/*
 * Plugin Name: Cron local (lab DMZ)
 * Description: wp-cron se llama a si mismo por 127.0.0.1 y no por la direccion del visitante (la DMZ no puede salir a 192.168.x). 2026-10-16.
 */
add_filter( 'cron_request', function ( $req ) {
	$req['url'] = preg_replace( '#^https?://[^/]+#', 'http://127.0.0.1', $req['url'] );
	return $req;
} );
PHP
chown root:www-data "$MU"; chmod 644 "$MU"

grep -n "LAB-DIRECCION" "$CFG"
echo "Aplicado (respaldo previo: $RESP)"
