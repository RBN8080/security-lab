#!/usr/bin/env bash
# Debian DMZ "Servidor2" - configurar ModSecurity+CRS (modo OBSERVAR) y fail2ban. 2026-10-16.
# Paquetes ya instalados. Sin internet. Reversible.  Deshacer: lanzar.sh revertir
set -uo pipefail
[ "$(id -u)" = 0 ] || { echo "Correr con sudo"; exit 1; }
MOD=/etc/modsecurity/modsecurity.conf
F2B=/etc/fail2ban
R=/root/waf_fail2ban_$(date +%Y%m%d_%H%M%S)
mkdir -p "$R"; chmod 700 "$R"; echo "$R" > /root/waf_fail2ban_ULTIMO.txt

echo "=== 1. ModSecurity: config base (SecRuleEngine = DetectionOnly / observar)"
[ -f "$MOD" ] && cp -p "$MOD" "$R/modsecurity.conf" || echo "(no habia $MOD previo)"
cp /etc/modsecurity/modsecurity.conf-recommended "$MOD"
sed -i 's/^SecRuleEngine .*/SecRuleEngine DetectionOnly/' "$MOD"
# Afinado: no abortar por cuerpos grandes de subidas legitimas al panel
sed -i 's/^SecRequestBodyLimitAction .*/SecRequestBodyLimitAction ProcessPartial/' "$MOD" 2>/dev/null || true
echo "SecRuleEngine -> $(grep -m1 '^SecRuleEngine' "$MOD")"

echo "=== 2. fail2ban: jail.local + filtro wp-hard (banea con nftables)"
[ -f "$F2B/jail.local" ] && cp -p "$F2B/jail.local" "$R/jail.local"
cat > "$F2B/jail.local" <<'CONF'
# BLINDAJE 2026-10-16. Deshacer: borrar este archivo y reiniciar fail2ban.
[DEFAULT]
backend    = auto
banaction  = nftables-multiport
banaction_allports = nftables-allports
# No banear la casa ni el lab (para no autobanearme)
ignoreip   = 127.0.0.1/8 ::1 192.168.0.0/16 10.0.0.0/8
bantime    = 1h
findtime   = 10m
maxretry   = 5

[sshd]
enabled = true

[wp-hard]
enabled  = true
port     = http,https
filter   = wp-hard
logpath  = /var/log/apache2/access.log
maxretry = 5
findtime = 10m
bantime  = 1h
CONF
cat > "$F2B/filter.d/wp-hard.conf" <<'CONF'
# Banea escaneos/fuerza bruta contra el WordPress endurecido. 2026-10-16.
[Definition]
failregex = ^<HOST> .* "(GET|POST|HEAD) /(wp-login\.php|xmlrpc\.php)[^"]*" (200|403|405) \d+
            ^<HOST> .* "(GET|POST|HEAD) [^"]*" 403 \d+
            ^<HOST> .* "(GET|POST|HEAD) [^"]*(wp-config|/\.env|/\.git|phpmyadmin|/vendor/|/\.|\.bak|\.sql)[^"]*" (403|404) \d+
ignoreregex =
CONF

echo "=== 3. Pruebas de sintaxis"
OK=1
if apache2ctl configtest 2>&1 | grep -q "Syntax OK"; then systemctl reload apache2 && echo "Apache recargado (ModSecurity+CRS activos en observar)"; else apache2ctl configtest; echo "!! Apache error -> quito ModSecurity"; rm -f "$MOD"; a2dismod -f security2 >/dev/null 2>&1; systemctl reload apache2; OK=0; fi
if fail2ban-client -t 2>&1 | tail -2 | grep -qiE "OK|^$"; then systemctl restart fail2ban && echo "fail2ban reiniciado"; else fail2ban-client -t; echo "!! fail2ban error -> quito jail"; rm -f "$F2B/jail.local" "$F2B/filter.d/wp-hard.conf"; systemctl restart fail2ban; OK=0; fi

echo "=== 4. Estado"
sleep 2
fail2ban-client status 2>/dev/null | sed 's/^/  /'
echo "  jails: $(fail2ban-client status 2>/dev/null | awk -F: '/Jail list/{print $2}')"
echo "Respaldo: $R"
echo "Estado: $([ $OK = 1 ] && echo BIEN || echo REVISAR)"
echo "Para BLOQUEAR de verdad (cuando acabe la observacion):"
echo "  sudo sed -i 's/^SecRuleEngine .*/SecRuleEngine On/' $MOD && sudo systemctl reload apache2"
