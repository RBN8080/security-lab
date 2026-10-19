#!/usr/bin/env bash
# Debian DMZ "Servidor2" - BLINDAJE FUERTE (2026-10-16), antes de abrir a internet.
# Enfoque del responsable: cerrar al limite ahora, luego quitar candados uno a uno
# para observar bots. Usa SOLO lo ya instalado (sin descargas). Panel solo desde casa/lab.
# Capa web (Apache + PHP + WordPress) + apagar servicios de escritorio. Todo reversible.
# El firewall de Debian (nftables) va aparte (firewall_debian.sh), lo corre el responsable.
# Corre EN Debian como root (lo lanza lanzar.sh).  Deshacer: lanzar.sh revertir <carpeta>
set -uo pipefail
[ "$(id -u)" = 0 ] || { echo "Correr con sudo"; exit 1; }
WP=/var/www/html
A=/etc/apache2
SECCONF=$A/conf-available/security.conf
BLIND=$A/conf-available/zz-blindaje.conf
PHPINI=$(ls /etc/php/*/apache2/php.ini | head -1)
PHPHARD=$(dirname "$PHPINI")/conf.d/99-blindaje.ini
MU=$WP/wp-content/mu-plugins/blindaje.php
R=/root/blindaje_fuerte_$(date +%Y%m%d_%H%M%S)
fail(){ echo "!! $*"; }

echo "=== 0. Respaldo en $R"
mkdir -p "$R"; chmod 700 "$R"
cp -p "$SECCONF" "$R/security.conf" 2>/dev/null
cp -p "$PHPINI" "$R/php.ini" 2>/dev/null
ls "$A/mods-enabled" > "$R/mods-enabled.txt"
systemctl is-enabled cups cups-browsed avahi-daemon ModemManager 2>/dev/null > "$R/servicios.txt" || true
cp -p "$WP/wp-config.php" "$R/wp-config.php"
echo "$R" > /root/blindaje_fuerte_ULTIMO.txt

echo "=== 1. Apache: modulos (headers on; status/autoindex off)"
a2enmod headers >/dev/null 2>&1
a2dismod -f status autoindex >/dev/null 2>&1 || true

echo "=== 2. Apache: reglas de blindaje ($BLIND)"
cat > "$BLIND" <<'CONF'
# BLINDAJE FUERTE 2026-10-16. Reversible: borrar este archivo y recargar Apache.
# Nota: las restricciones van DENTRO de <Directory> (un <Location "/"> anula los
# Require de los <FilesMatch> globales en peticiones GET).

# --- Cabeceras de seguridad ---
<IfModule mod_headers.c>
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set Referrer-Policy "strict-origin-when-cross-origin"
    Header always set Permissions-Policy "geolocation=(), microphone=(), camera=()"
    Header always set Content-Security-Policy "default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline'; object-src 'none'; frame-ancestors 'self'; base-uri 'self'"
    Header always unset X-Powered-By
    Header unset X-Pingback
</IfModule>

<Directory /var/www/html>
    # Solo metodos normales
    <LimitExcept GET POST HEAD>
        Require all denied
    </LimitExcept>
    # Panel: wp-login solo desde casa y el lab
    <FilesMatch "^wp-login\.php$">
        Require ip 127.0.0.1 ::1 192.168.0.0/16 10.0.0.0/8
    </FilesMatch>
    # xmlrpc cerrado del todo
    <FilesMatch "^xmlrpc\.php$">
        Require all denied
    </FilesMatch>
    # wp-cron solo desde el propio servidor (lo dispara el mu-plugin por 127.0.0.1)
    <FilesMatch "^wp-cron\.php$">
        Require ip 127.0.0.1 ::1
    </FilesMatch>
    # Archivos sensibles
    <FilesMatch "^(wp-config\.php|wp-config-sample\.php|readme\.html|license\.txt)$">
        Require all denied
    </FilesMatch>
    <FilesMatch "\.(sql|bak|old|orig|save|swp|log|ini|sh|inc)$">
        Require all denied
    </FilesMatch>
    <FilesMatch "^\.">
        Require all denied
    </FilesMatch>
    <Files "wp-trackback.php">
        Require all denied
    </Files>
</Directory>

# --- Panel wp-admin solo desde casa y el lab (admin-ajax abierto al front) ---
<Directory /var/www/html/wp-admin>
    Require ip 127.0.0.1 ::1 192.168.0.0/16 10.0.0.0/8
    <Files "admin-ajax.php">
        Require all granted
    </Files>
</Directory>

# --- uploads no ejecuta PHP; wp-includes no sirve PHP (salvo js para el editor) ---
<Directory /var/www/html/wp-content/uploads>
    <FilesMatch "\.(php\d?|phar|phtml)$">
        Require all denied
    </FilesMatch>
</Directory>
<Directory /var/www/html/wp-includes>
    <FilesMatch "\.php$">
        Require all denied
    </FilesMatch>
</Directory>
<Directory /var/www/html/wp-includes/js>
    <FilesMatch "\.php$">
        Require all granted
    </FilesMatch>
</Directory>
CONF
a2enconf zz-blindaje >/dev/null 2>&1

echo "=== 3. PHP: funciones peligrosas y cookies ($PHPHARD)"
cat > "$PHPHARD" <<'INI'
; BLINDAJE FUERTE 2026-10-16. Reversible: borrar este archivo y recargar Apache.
disable_functions = exec,passthru,shell_exec,system,proc_open,popen,proc_close,proc_nice,proc_terminate,proc_get_status,dl,pcntl_exec,show_source,curl_multi_exec
expose_php = Off
session.cookie_httponly = 1
session.cookie_samesite = "Lax"
session.use_strict_mode = 1
INI

echo "=== 4. WordPress: constantes + mu-plugin blindaje.php"
sed -i "/DISALLOW_FILE_MODS/d; /DISALLOW_UNFILTERED_HTML/d" "$WP/wp-config.php"
awk '/stop editing/ && !h { print "define( '\''DISALLOW_FILE_MODS'\'', true );"; print "define( '\''DISALLOW_UNFILTERED_HTML'\'', true );"; h=1 } { print }' "$WP/wp-config.php" > "$WP/.wpc.tmp" && cat "$WP/.wpc.tmp" > "$WP/wp-config.php" && rm -f "$WP/.wpc.tmp"
mkdir -p "$WP/wp-content/mu-plugins"
cat > "$MU" <<'PHP'
<?php
/*
 * Plugin Name: Blindaje fuerte (lab DMZ)
 * Description: Cierra xmlrpc, enumeracion de usuarios, pingback, comentarios y metadatos. 2026-10-16.
 */
// XML-RPC y pingback
add_filter( 'xmlrpc_enabled', '__return_false' );
add_filter( 'xmlrpc_methods', '__return_empty_array' );
add_filter( 'wp_headers', function ( $h ) { unset( $h['X-Pingback'] ); return $h; } );
add_filter( 'pings_open', '__return_false' );
// Contrasenas de aplicacion fuera
add_filter( 'wp_is_application_passwords_available', '__return_false' );
// Quitar pistas del <head>
remove_action( 'wp_head', 'rsd_link' );
remove_action( 'wp_head', 'wlwmanifest_link' );
remove_action( 'wp_head', 'wp_shortlink_wp_head' );
remove_action( 'wp_head', 'rest_output_link_wp_head' );
remove_action( 'template_redirect', 'rest_output_link_header', 11 );
// REST API: quitar el endpoint de usuarios (anti-enumeracion)
add_filter( 'rest_endpoints', function ( $e ) {
	unset( $e['/wp/v2/users'], $e['/wp/v2/users/(?P<id>[\d]+)'] );
	return $e;
} );
// Bloquear ?author=N y los archivos de autor
add_action( 'template_redirect', function () {
	if ( is_author() || isset( $_GET['author'] ) ) { wp_safe_redirect( home_url(), 301 ); exit; }
}, 0 );
// Comentarios cerrados en todo el sitio
add_filter( 'comments_open', '__return_false' );
add_filter( 'comments_array', '__return_empty_array' );
PHP
chown root:www-data "$MU"; chmod 644 "$MU"

echo "=== 5. Servicios de escritorio/impresion que un servidor no necesita"
systemctl disable --now cups cups-browsed avahi-daemon ModemManager >/dev/null 2>&1 || true

echo "=== 6. Verificacion"
OK=1
if apache2ctl configtest 2>&1 | grep -q "Syntax OK"; then
    systemctl reload apache2 && echo "Apache recargado"
else
    apache2ctl configtest; fail "Apache con error -> restaurando"; cp -p "$R/security.conf" "$SECCONF"; rm -f "$BLIND"; a2dismod -f headers >/dev/null 2>&1; systemctl reload apache2; OK=0
fi
php -l "$WP/wp-config.php" >/dev/null || { fail "wp-config con error -> restaurando"; cp -p "$R/wp-config.php" "$WP/wp-config.php"; OK=0; }
C=$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 http://127.0.0.1/)
echo "Web local responde: $C"
[ "$C" = 200 ] || fail "La web NO da 200 -> revisa; respaldo en $R"
echo
echo "=== RESUMEN"
echo "Respaldo: $R   (deshacer: lanzar.sh revertir $R)"
echo "Estado general: $([ $OK = 1 ] && [ "$C" = 200 ] && echo BIEN || echo 'REVISAR arriba')"
