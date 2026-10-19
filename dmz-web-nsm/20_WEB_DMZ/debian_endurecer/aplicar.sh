#!/usr/bin/env bash
# Debian DMZ "Servidor2" - endurecer el servidor dejando WordPress visible (opcion 1, 2026-10-16).
# Corre EN Debian como root; lo lanza lanzar.sh desde el host. No toca la base de datos.
# Antes de cambiar nada respalda en /root/respaldo_endurecer_<fecha>/.
# Deshacer:  bash lanzar.sh revertir /root/respaldo_endurecer_<fecha>
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "Correr con sudo"; exit 1; }
WP=/var/www/html
SEC=/etc/apache2/conf-available/security.conf
WPC=/etc/apache2/conf-available/wordpress.conf
SSHD=/etc/ssh/sshd_config.d/10-lab-endurecer.conf
R=/root/respaldo_endurecer_$(date +%Y%m%d_%H%M%S)

echo "=== 0. Respaldo en $R"
mkdir -p "$R"; chmod 700 "$R"
cp -p "$SEC" "$WPC" "$WP/wp-config.php" "$R/"
find "$WP" -printf '%m %u %g %p\n' > "$R/permisos_wp.txt"
tar -czf "$R/etc_apache2_ssh.tgz" /etc/apache2 /etc/ssh 2>/dev/null

echo "=== 1. WordPress: sin editor de temas/plugins en el panel"
wp --allow-root --path="$WP" config set DISALLOW_FILE_EDIT true --raw

echo "=== 2. WordPress: quitar la version del HTML, feeds y ?ver= (mu-plugin)"
mkdir -p "$WP/wp-content/mu-plugins"
cat > "$WP/wp-content/mu-plugins/ocultar-version.php" <<'PHP'
<?php
/*
 * Plugin Name: Ocultar version (lab DMZ)
 * Description: Quita la version de WordPress del HTML, de los feeds y del ?ver= de CSS/JS. Endurecimiento 2026-10-16.
 */
remove_action( 'wp_head', 'wp_generator' );
add_filter( 'the_generator', '__return_empty_string' );

function lab_quitar_ver( $src ) {
	if ( $src && strpos( $src, 'ver=' . get_bloginfo( 'version' ) ) !== false ) {
		$src = remove_query_arg( 'ver', $src );
	}
	return $src;
}
add_filter( 'style_loader_src', 'lab_quitar_ver', 9999 );
add_filter( 'script_loader_src', 'lab_quitar_ver', 9999 );
PHP

echo "=== 3. Archivos: dueno root, Apache solo lee; solo escribe en uploads"
chown -R root:www-data "$WP"
find "$WP" -type d -exec chmod 755 {} +
find "$WP" -type f -exec chmod 644 {} +
chown -R www-data:www-data "$WP/wp-content/uploads"
chmod 640 "$WP/wp-config.php"

echo "=== 4. Apache: sin listado de carpetas, sin PHP en uploads, sin readme/license, version oculta"
cat > "$WPC" <<'CONF'
<Directory /var/www/html>
    Options -Indexes +FollowSymLinks
    AllowOverride All
</Directory>

# Endurecimiento 2026-10-16: uploads no ejecuta PHP ni acepta .htaccess
<Directory /var/www/html/wp-content/uploads>
    AllowOverride None
    <FilesMatch "\.(php\d?|phar|phtml)$">
        Require all denied
    </FilesMatch>
</Directory>

# Archivos que delatan la version
<FilesMatch "^(readme\.html|license\.txt|wp-config-sample\.php)$">
    Require all denied
</FilesMatch>
CONF
sed -i 's/^ServerTokens OS$/ServerTokens Prod/; s/^ServerSignature On$/ServerSignature Off/' "$SEC"
if apache2ctl configtest 2>&1 | grep -q "Syntax OK"; then
  systemctl reload apache2; echo "Apache recargado"
else
  apache2ctl configtest || true
  cp -p "$R/security.conf" "$SEC"; cp -p "$R/wordpress.conf" "$WPC"
  echo "!! Apache con error: se restauraron sus dos archivos"; exit 1
fi

echo "=== 5. SSH: solo llave, sin root, sin X11 (las sesiones abiertas siguen)"
cat > "$SSHD" <<'CONF'
# Endurecimiento 2026-10-16 (lab DMZ): solo llave, sin root, sin X11.
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
X11Forwarding no
CONF
if sshd -t; then
  systemctl reload ssh; echo "SSH recargado"
else
  rm -f "$SSHD"; echo "!! sshd con error: se quito $SSHD"; exit 1
fi

echo "=== Resultado"
stat -c '%a %U:%G %n' "$WP/wp-config.php" "$WP/wp-content/uploads"
echo "Archivos que Apache puede escribir fuera de uploads: $(find "$WP" -path "$WP/wp-content/uploads" -prune -o -user www-data -print | wc -l)"
sshd -T | grep -E '^(passwordauthentication|kbdinteractiveauthentication|permitrootlogin|x11forwarding) '
grep -E '^Server(Tokens|Signature)' "$SEC"
echo "Respaldo: $R"
