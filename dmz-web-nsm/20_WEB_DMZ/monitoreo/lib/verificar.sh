#!/usr/bin/env bash
# monitor.sh verificar — chequeo de todo antes de empezar a vigilar. SOLO LECTURA: no cambia nada.
# Antes, encender: pfSense -> Debian (la web vuelve sola en ~30 s). Security Onion es a demanda.
# Sustituye a costura3/retomar_verificar.sh, que revisaba la publicacion vieja por el router (inutil
# desde que la web sale por el VPS, D-15).
. "$(dirname "${BASH_SOURCE[0]}")/comun.sh"
ok(){ echo "  [OK]  $*"; }; mal(){ echo "  [!!]  $*"; malos=$((malos + 1)); }; info(){ echo "  [--]  $*"; }
malos=0; C="-o BatchMode=yes -o ConnectTimeout=8"

echo "=== 1. Pi 5 y tunel al lab"
ssh $C rpi5 true 2>/dev/null && ok "Pi 5 accesible (ssh rpi5)" || { mal "Pi 5 no responde: no se puede seguir"; pausa; exit 1; }
ssh $C rpi5 'ping -c1 -W3 10.10.10.1 >/dev/null' && ok "Tunel WireGuard al lab (pfSense)" || mal "Tunel al lab caido (pfSense apagado o arrancando?)"

echo "=== 2. pfSense: contencion y salida de la DMZ"
R=$(pfsense 'pfctl -sr' 2>/dev/null)
echo "$R" | grep -q 'ridentifier 1791590554' && ok "CONTENCION activa: la DMZ no llega a casa, lab ni NAS" || mal "NO esta la regla de contencion (grave)"
N=$(echo "$R" | grep 'on em2' | grep '^pass' | grep -cE 'port = (http|https)')
[ "$N" = 0 ] && ok "Salida de la DMZ a internet CERRADA" || mal "La DMZ puede salir a internet ($N reglas pass http/https)"
echo "$R" | grep 'on em2' | grep -q 'port = 51820' && ok "Regla del tunel al VPS (WGedge) activa" || mal "Falta la regla WGedge: la web no puede salir por el VPS"

echo "=== 3. Debian (servidor de la web)"
D=$(debian 'curl -s -o /dev/null -w %{http_code} --max-time 6 http://deb.debian.org/; echo; ping -c1 -W3 10.9.0.1 >/dev/null && echo TUNEL_OK' 2>/dev/null)
[ "$(echo "$D" | head -1)" = 000 ] && ok "Debian NO sale a internet" || mal "Debian SALE a internet (codigo $(echo "$D" | head -1))"
echo "$D" | grep -q TUNEL_OK && ok "Tunel Debian -> VPS arriba (responde 10.9.0.1)" || mal "Tunel Debian -> VPS caido: la web no esta en internet"

echo "=== 4. Web publica (vista desde internet)"
W=$(curl -s -o /dev/null -w %{http_code} --max-time 15 "$WEB_PUBLICA")
[ "$W" = 200 ] && ok "La web responde ($WEB_PUBLICA = 200)" || mal "La web publica responde '$W'"
L=$(curl -s -o /dev/null -w %{http_code} --max-time 15 "${WEB_PUBLICA}wp-login.php")
[ "$L" = 403 ] && ok "Panel de WordPress cerrado a internet (wp-login = 403)" || mal "wp-login.php desde internet = $L (esperado 403)"

echo "=== 5. VPS (puente)"
V=$(ssh $C -i "$VPS_LLAVE" "$VPS" 'systemctl is-active wg-quick@wg0 nginx ufw | tr "\n" " "' 2>/dev/null)
[ "$V" = "active active active " ] && ok "VPS: WireGuard, nginx y ufw activos" || mal "VPS: estado '$V' (esperado: active active active)"

echo "=== 6. Security Onion (a demanda)"
B=$(ssh $C soc 'cat /sys/class/net/bond0/bonding/slaves' 2>/dev/null)
if [ -n "$B" ]; then
  echo "$B" | grep -q ens35 && ok "SO encendido y capturando la DMZ ($B)" || mal "SO encendido pero sin ens35 en bond0 ($B)"
else info "SO apagado (normal si no lo estas usando)"; fi

echo "=== 7. Monitoreo"
g=$(ls -1t "$DATOS"/geoip/dbip-city-lite-*.mmdb 2>/dev/null | head -1)
if [ -n "$g" ]; then
  e=$(( ( $(date +%s) - $(stat -c %Y "$g") ) / 86400 ))
  [ "$e" -le 35 ] && ok "Bases GeoIP al dia ($(basename "$g"), $e dias)" || mal "Bases GeoIP con $e dias: corre 'monitor.sh geoip'"
else mal "Sin bases GeoIP: corre 'monitor.sh geoip'"; fi
python -c "import maxminddb" 2>/dev/null && ok "Libreria maxminddb instalada" || mal "Falta maxminddb: pip install --user maxminddb"
ps -ef | grep -v grep | grep -q "lib/panel.sh\|panel_bots.sh" && info "Panel abierto" || info "Panel cerrado (abrelo: bash monitor.sh)"
ps -ef | grep -v grep | grep -q "vigilante.sh" && info "Vigilante corriendo" || info "Vigilante apagado (bash monitor.sh vigilar)"

echo
[ "$malos" = 0 ] && echo "TODO EN ORDEN." || echo "$malos punto(s) a revisar arriba ([!!])."
pausa
