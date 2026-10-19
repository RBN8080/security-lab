#!/usr/bin/env bash
# Panel de bots - nivel SERVIDOR (Debian DMZ). Solo lectura.
# Junta: peticiones web (Apache), detecciones del WAF (ModSecurity) y baneos (fail2ban).
# Complementa Security Onion (red, https://192.168.1.200) y ver_alarma_dmz.ps1 (contencion).
#   bash panel_bots.sh               -> EN VIVO desde Debian (pide la clave sudo; Ctrl+C para salir)
#   bash panel_bots.sh local [N]     -> EN VIVO desde logs/access_vivo.log, sin clave (necesita
#                                       transmitir_vivo.sh corriendo); arranca con las ultimas N (40)
#   bash panel_bots.sh resumen       -> foto: top IPs, codigos, ultimas detecciones WAF, baneos
# Columnas de ancho fijo, ajustadas al ancho de la ventana: LUGAR desde 100 columnas, RED desde
# 125, NAVEGADOR desde 160. LUGAR y RED salen de geo.py (bases locales DB-IP; ninguna IP sale del
# equipo; se actualizan con geoip_actualizar.sh una vez al mes). Sin colores: NO_COLOR=1 bash ...
S="-o BatchMode=yes"; MODO="${1:-vivo}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATOS="${PANEL_DATOS:-/d/VMware_LAB/_lab/panel_bots}"; [ -d "$DATOS" ] || DATOS="$DIR"  # datos: el taller
COLS=${COLS:-$(tput cols 2>/dev/null)}; [ "${COLS:-0}" -ge 60 ] 2>/dev/null || COLS=120

pedir_clave() { if [ -t 0 ]; then read -rsp "Clave sudo de Debian (no se guarda): " PW; echo; else read -r PW; fi; }

# Agrega lugar y red a cada linea (TAB lugar TAB red). Sin Python, pasa las lineas tal cual.
enriquecer() {
  if command -v python >/dev/null 2>&1 && [ -f "$DIR/geo.py" ]; then
    python -u "$DIR/geo.py" "$(cygpath -m "$DATOS/geoip" 2>/dev/null || echo "$DATOS/geoip")"
  else cat; fi
}

# Lee lineas del access.log de Apache (formato combinado) y las pinta en columnas.
formatear() {
  awk -v cols="$COLS" -v nocolor="${NO_COLOR:-}" '
function corta(s, n) { return (length(s) > n) ? substr(s, 1, n - 1) "~" : s }
function pinta(txt, c) { return (nocolor != "" || c == "") ? txt : "\033[" c "m" txt "\033[0m" }
function cabecera() {
  print pinta(sprintf("%-8s  %-15s %s%s%-3s  %-9s %-7s %-" wp "s%s", "HORA", "IP",
                      (wl ? sprintf("%-" wl "s ", "LUGAR") : ""), (wr ? sprintf("%-" wr "s ", "RED") : ""),
                      "COD", "ETIQUETA", "METODO", "RUTA", (wua ? " | NAVEGADOR" : "")), "1")
}
function etiqueta(   lp) {
  lp = tolower(p)
  if (ua ~ /vigilante-lab/) return "PROPIO"
  if (m == "-") return (req ~ /^\\x16\\x03/) ? "TLS" : "ROTA"
  if (m !~ /^(GET|HEAD|POST)$/) return "METODO"
  if (lp ~ /(\.\.\/|%2e%2e|%ad|allow_url_include|auto_prepend_file|eval-stdin|invokefunction|pearcmd|\/bin\/(ba)?sh|cgi-bin|base64_decode|union.+select|<script|[$][{]jndi|\/containers\/json|\/images\/json|169\.254\.169\.254|=(https?|php|data|file):)/) return "ATAQUE"
  if (lp ~ /wp-login\.php/) return "LOGIN"
  if (lp ~ /xmlrpc\.php/) return "XMLRPC"
  if (lp ~ /(\/\.env|\/\.git|\/\.aws|\/\.ssh|\/\.docker|\/\.ds_store|\/\.ht|wp-config|phpmyadmin|\/vendor\/|\.bak|\.sql|\.old|\.swp|\.zip|\.tar|backup|readme|phpinfo|server-(status|info)|config\.(json|js|php|ya?ml)|composer\.(json|lock)|package(-lock)?\.json|yarn\.lock|credentials|secrets?\.|settings\.|docker-compose|\.(map|ya?ml|ini|log|conf|cfg|toml|key|pem)$)/) return "SONDEO"
  if (lp ~ /\.php/ && code == "404") return "WEBSHELL"
  if (code == "403" || code == "401") return "BLOQUEADO"
  if (code == "404") return "404"
  if (code ~ /^[23]/) return "ok"
  return code
}
BEGIN {
  wl = (cols >= 100) ? 18 : 0; wr = (cols >= 125) ? 14 : 0; wua = (cols >= 160) ? 24 : 0
  # fijo: hora 8+2, ip 15+1, codigo 3+2, etiqueta 9+1, metodo 7+1; reserva 4 para " !!"
  wp = cols - 49 - (wl ? wl + 1 : 0) - (wr ? wr + 1 : 0) - (wua ? wua + 3 : 0) - 4; if (wp < 20) wp = 20
  color["ok"] = "32"; color["PROPIO"] = "2"; color["SONDEO"] = "33"; color["WEBSHELL"] = "33;1"
  color["ATAQUE"] = "31;1"; color["LOGIN"] = "35"; color["XMLRPC"] = "35"; color["METODO"] = "36"
  color["TLS"] = "2"; color["ROTA"] = "2"; color["BLOQUEADO"] = "31"
  print pinta("ok=visita normal  SONDEO=busca secretos o archivos olvidados  WEBSHELL=busca puertas traseras .php", "2")
  print pinta("ATAQUE=intenta ejecutar algo  LOGIN/XMLRPC=panel de WordPress  METODO=metodo raro (OPTIONS, CONNECT...)", "2")
  print pinta("TLS/ROTA=conexion rota o en otro idioma  BLOQUEADO=403  PROPIO=latido del vigilante  !!=200 a algo sospechoso: revisar", "2")
  print pinta("LUGAR=ciudad y pais (aproximado si es una nube)  RED=dueno de la IP (Microsoft, Oracle, Cloudflare...)", "2")
  cabecera()
  re = "^([^ ]+) [^ ]+ [^ ]+ \\[([^]]+)\\] \"(.*)\" ([0-9]{3}|-) [^ ]+( \"(.*)\" \"(.*)\")?$"
}
{
  k = split($0, c, "\t"); lin = c[1]; lugar = (k >= 2) ? c[2] : "-"; red = (k >= 3) ? c[3] : "-"
  if (!match(lin, re, a)) { print pinta(corta("?? " lin, cols - 1), "2"); fflush(); next }
  ip = a[1]; req = a[3]; code = a[4]; ua = a[7]
  t = a[2]; sub(/^[^:]*:/, "", t); sub(/ .*/, "", t)
  if (match(req, /^([A-Za-z_]+) ([^ ]+)( HTTP\/[0-9.]+)?$/, r)) { m = r[1]; p = r[2] }
  else { m = "-"; p = "(" req ")" }
  e = etiqueta()
  linea = sprintf("%-8s  %-15s ", t, ip) (wl ? sprintf("%-" wl "s ", corta(lugar, wl)) : "") \
          (wr ? sprintf("%-" wr "s ", corta(red, wr)) : "") sprintf("%-3s  ", code) pinta(sprintf("%-9s", e), color[e]) \
          sprintf(" %-7s %-" wp "s", corta(m, 7), corta(p, wp))
  if (wua) linea = linea " | " corta((ua == "" || ua == "-") ? "(sin navegador)" : ua, wua)
  # !! como el vigilante: 200 sospechoso fuera de la portada (WordPress ignora la carga y da la
  # portada normal) y de los index.php vacios de fabrica
  base = p; sub(/\?.*/, "", base)
  if (code ~ /^2/ && e ~ /^(SONDEO|WEBSHELL|ATAQUE)$/ && base !~ /^\/(index\.php)?$/ &&
      base !~ /^\/wp-content\/((themes|plugins|uploads)\/)?index\.php$/) linea = linea " " pinta("!!", "31;1")
  print linea
  if (++n % 40 == 0) cabecera()
  fflush()
}'
}

if [ "$MODO" = resumen ]; then
  pedir_clave
  { printf '%s\n' "$PW"; cat <<'REMOTE'
export LC_ALL=C; L=/var/log/apache2/access.log
echo "===== PETICIONES (desde que arranco el log) ====="
echo "-- Top 8 IPs --"; awk '{print $1}' "$L" | sort | uniq -c | sort -rn | head -8
echo "-- Codigos de respuesta --"; awk '{print $9}' "$L" | sort | uniq -c | sort -rn
echo "-- Rutas mas pedidas (top 8) --"; awk '{print $7}' "$L" | sort | uniq -c | sort -rn | head -8
echo; echo "===== WAF ModSecurity (ultimas 8 detecciones) ====="
grep -hoE "\[id \"9[0-9]{5}\"\].*\[msg \"[^\"]+\"\]" /var/log/apache2/modsec_audit.log 2>/dev/null \
  | sed -E 's/\[id /id /; s/\].*\[msg / : /; s/[][]//g; s/"//g' | tail -8
echo "(total eventos en audit: $(wc -l < /var/log/apache2/modsec_audit.log 2>/dev/null))"
echo; echo "===== fail2ban ====="
for j in sshd wp-hard; do echo "-- $j --"; fail2ban-client status "$j" 2>/dev/null | grep -E "Currently failed|Total failed|Currently banned|Banned IP"; done
REMOTE
  } | ssh $S rpi5 "ssh $S debian 'sudo -S -p \"\" bash -s'" 2>&1
  exit 0
fi

if [ "$MODO" = local ]; then
  ARCH="$DATOS/logs/access_vivo.log"
  [ -f "$ARCH" ] || { echo "ERROR: no existe $ARCH (corre transmitir_vivo.sh primero)"; exit 1; }
  echo "== PANEL EN VIVO desde $ARCH (Ctrl+C para salir) =="
  tail -n "${2:-40}" -F "$ARCH" 2>/dev/null | enriquecer | formatear
  exit 0
fi

pedir_clave
echo "== PANEL EN VIVO desde Debian (Ctrl+C para salir) =="
# La clave se consume en Debian (read -r P) y el tail -f sigue vivo (no depende de stdin).
printf '%s\n' "$PW" | ssh $S rpi5 "ssh $S debian 'read -r P; echo \"\$P\" | sudo -S -p \"\" tail -n 20 -f /var/log/apache2/access.log'" 2>/dev/null \
| enriquecer | formatear
