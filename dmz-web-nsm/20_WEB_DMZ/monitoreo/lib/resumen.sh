#!/usr/bin/env bash
# monitor.sh resumen — foto del servidor: top IPs, codigos, rutas, ultimas detecciones del WAF y baneos
# de fail2ban, desde que arranco el log de Apache. Solo lectura; pide la clave sudo de Debian.
. "$(dirname "${BASH_SOURCE[0]}")/comun.sh"
clave_valida
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
} | debian 'sudo -S -p "" bash -s' 2>&1
pausa
