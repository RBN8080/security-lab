#!/usr/bin/env bash
# Panel de bots - nivel SERVIDOR (Debian DMZ). Solo lectura.
# Junta: peticiones web (Apache), detecciones del WAF (ModSecurity) y baneos (fail2ban).
# Complementa Security Onion (red, https://192.168.1.200) y ver_alarma_dmz.ps1 (contencion).
#   bash panel_bots.sh            -> EN VIVO (Ctrl+C para salir): cada peticion anotada
#   bash panel_bots.sh resumen    -> foto: top IPs, codigos, ultimas detecciones WAF, baneos
# Pide la clave sudo de Debian (no se guarda).
S="-o BatchMode=yes"; MODO="${1:-vivo}"
if [ -t 0 ]; then read -rsp "Clave sudo de Debian (no se guarda): " PW; echo; else read -r PW; fi

if [ "$MODO" = resumen ]; then
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

echo "== PANEL EN VIVO (Ctrl+C para salir).  hora  IP  codigo  etiqueta  metodo ruta  navegador =="
# La clave se consume en Debian (read -r P) y el tail -f sigue vivo (no depende de stdin).
printf '%s\n' "$PW" | ssh $S rpi5 "ssh $S debian 'read -r P; echo \"\$P\" | sudo -S -p \"\" tail -n 0 -f /var/log/apache2/access.log'" 2>/dev/null \
| awk '
function tag(code, path) {
  if (path ~ /wp-login\.php/)                         return "LOGIN   ";
  if (path ~ /xmlrpc\.php/)                           return "XMLRPC  ";
  if (path ~ /(wp-config|\/\.env|\/\.git|phpmyadmin|\/vendor\/|\.bak|\.sql|readme|\/\.)/) return "SONDEO  ";
  if (code == 403 || code == 401)                     return "BLOQUEADO";
  if (code == 404)                                    return "404     ";
  if (code ~ /^(200|301|302|304)$/)                   return "ok      ";
  return code"     ";
}
{
  ip=$1; code=$9;
  # hora entre corchetes: [16/Oct/2026:22:40:01
  h=$4; gsub(/.*:/,"",h);           # deja ss; mejor tomar HH:MM:SS
  t=$4; sub(/^\[[0-9]+\/[A-Za-z]+\/[0-9]+:/,"",t); sub(/ .*/,"",t);
  # metodo y ruta: campo 6 y 7
  m=$6; gsub(/"/,"",m); p=$7;
  # navegador: ultimo campo entre comillas (resumido)
  ua=$0; sub(/.*" "/,"",ua); gsub(/".*/,"",ua);
  short=ua; if (length(short)>28) short=substr(short,1,28);
  printf "%s  %-15s %3s  %-9s %s %s  | %s\n", t, ip, code, tag(code,p), m, p, short;
  fflush();
}'
