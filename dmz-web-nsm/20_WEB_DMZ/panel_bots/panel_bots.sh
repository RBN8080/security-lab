#!/usr/bin/env bash
# Panel de bots - nivel SERVIDOR (Debian DMZ). Solo lectura.
# Junta: peticiones web (Apache), detecciones del WAF (ModSecurity) y baneos (fail2ban).
# Complementa Security Onion (red, https://192.168.1.200) y ver_alarma_dmz.ps1 (contencion).
#   bash panel_bots.sh             -> EN VIVO directo desde Debian (pide la clave sudo). NO necesita
#                                     transmitir_vivo.sh. Ctrl+C para salir
#   bash panel_bots.sh local [N]   -> EN VIVO desde logs/access_vivo.log, sin clave. SI necesita
#                                     transmitir_vivo.sh corriendo (avisa si no). Contexto: ultimas N (40)
#   bash panel_bots.sh resumen     -> foto: top IPs, codigos, ultimas detecciones WAF, baneos
# El visor es panel_bots.py: columnas segun el ancho de la ventana (LUGAR desde 110, RED desde 130,
# NAVEGADOR desde 165), VISTA (NUEVA / VUELVE / xN) y resumen de cada rafaga. LUGAR y RED salen de
# bases locales DB-IP (geoip_actualizar.sh, una vez al mes): ninguna IP sale del equipo.
# Datos (logs, bases): siempre en el taller, se corra desde el repo o desde D:. Sin colores: NO_COLOR=1
S="-o BatchMode=yes"; MODO="${1:-vivo}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATOS="${PANEL_DATOS:-/d/VMware_LAB/_lab/panel_bots}"; [ -d "$DATOS" ] || DATOS="$DIR"  # datos: el taller
COLS=${COLS:-$(tput cols 2>/dev/null)}; [ "${COLS:-0}" -ge 60 ] 2>/dev/null || COLS=120
ARCH="$DATOS/logs/access_vivo.log"

pedir_clave() { if [ -t 0 ]; then read -rsp "Clave sudo de Debian (no se guarda): " PW; echo; else read -r PW; fi; }
win() { cygpath -m "$1" 2>/dev/null || echo "$1"; }

# vista N: pinta lo que llega por stdin; usa el historial del taller para "ya vino otro dia"
vista() {
  if command -v python >/dev/null 2>&1 && [ -f "$DIR/panel_bots.py" ]; then
    COLS="$COLS" python -u "$DIR/panel_bots.py" --geoip "$(win "$DATOS/geoip")" \
      --historial "$(win "$ARCH")" --mostrar "$1"
  else
    echo "AVISO: sin Python el visor muestra las lineas crudas"; cat
  fi
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
  [ -f "$ARCH" ] || { echo "ERROR: no existe $ARCH (corre transmitir_vivo.sh primero)"; exit 1; }
  if ! ps -ef 2>/dev/null | grep -v grep | grep -q "transmitir_vivo.sh"; then
    echo "AVISO: transmitir_vivo.sh NO esta corriendo: veras el historial, pero no llegaran peticiones nuevas."
    echo "       Abrelo en otra ventana:  bash \"$DIR/transmitir_vivo.sh\""
  fi
  echo "== PANEL EN VIVO desde $ARCH (Ctrl+C para salir) =="
  tail -n 0 -F "$ARCH" 2>/dev/null | vista "${2:-40}"
  exit 0
fi

pedir_clave
echo "== PANEL EN VIVO desde Debian (Ctrl+C para salir) =="
# La clave se consume en Debian (read -r P) y el tail -f sigue vivo (no depende de stdin).
printf '%s\n' "$PW" | ssh $S rpi5 "ssh $S debian 'read -r P; echo \"\$P\" | sudo -S -p \"\" tail -n 0 -f /var/log/apache2/access.log'" 2>/dev/null \
| vista 20
