#!/usr/bin/env bash
# Panel de bots - nivel SERVIDOR (Debian DMZ). Solo lectura. UNA sola ventana:
#   bash panel_bots.sh           -> EN VIVO: pide la clave sudo de Debian una vez (la verifica, no la
#                                   guarda), muestra cada peticion y ADEMAS guarda el log en el taller
#                                   (logs/access_vivo.log) para el vigilante: transmitir_vivo.sh ya no
#                                   hace falta con el panel abierto. Si se cae la conexion, reconecta.
#                                   Ctrl+C para salir.
#   bash panel_bots.sh resumen   -> foto: top IPs, codigos, ultimas detecciones WAF, baneos
# El visor es panel_bots.py: columnas segun el ancho de la ventana (LUGAR desde 110, RED desde 130,
# NAVEGADOR desde 165), VISTA (NUEVA / VUELVE / xN) y resumen de cada rafaga. LUGAR y RED salen de
# bases locales DB-IP (geoip_actualizar.sh, una vez al mes): ninguna IP sale del equipo.
# Datos (logs, bases): siempre en el taller, se corra desde el repo o desde D:. Sin colores: NO_COLOR=1
# Complementa Security Onion (red, https://192.168.1.200) y ver_alarma_dmz.ps1 (contencion).
S="-o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=30 -o ServerAliveCountMax=3"
MODO="${1:-vivo}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATOS="${PANEL_DATOS:-/d/VMware_LAB/_lab/panel_bots}"; [ -d "$DATOS" ] || DATOS="$DIR"  # datos: el taller
COLS=${COLS:-$(tput cols 2>/dev/null)}; [ "${COLS:-0}" -ge 60 ] 2>/dev/null || COLS=120
ARCH="$DATOS/logs/access_vivo.log"; mkdir -p "$DATOS/logs"

# Un error que detiene el panel se queda en pantalla (abierto con doble clic, la ventana se cerraria)
fallo() { echo "ERROR: $*"; [ -t 0 ] && read -rp "Presiona Enter para cerrar..." _; exit 1; }
pedir_clave() { if [ -t 0 ]; then read -rsp "Clave sudo de Debian (no se guarda): " PW; echo; else read -r PW; fi; }
win() { cygpath -m "$1" 2>/dev/null || echo "$1"; }
debian() { ssh $S rpi5 "ssh $S debian '$1'"; }   # Debian se alcanza saltando por la Pi 5

# Pide la clave y la prueba contra sudo antes de abrir el panel (hasta 3 intentos si hay teclado)
clave_valida() {
  local intento r
  for intento in 1 2 3; do
    pedir_clave
    r=$({ printf '%s\n' "$PW"; echo "echo SUDO_OK"; } | debian 'sudo -S -p "" bash -s' 2>&1)
    case "$r" in *SUDO_OK*) return 0 ;; esac
    case "$r" in
      *ssh:*|*onnection*|*timed\ out*|*resolve*|*denied\ \(publickey*)
        fallo "no hay conexion con Debian (salto por la Pi 5). Detalle: $(printf '%s' "$r" | head -2)" ;;
    esac
    echo "Clave rechazada por sudo."
    [ -t 0 ] || break
  done
  fallo "clave rechazada"
}

if [ "$MODO" = resumen ]; then
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
  [ -t 0 ] && read -rp "Presiona Enter para cerrar..." _
  exit 0
fi

command -v python >/dev/null 2>&1 && [ -f "$DIR/panel_bots.py" ] || fallo "falta Python o panel_bots.py"
clave_valida

# Si transmitir_vivo.sh sigue abierto, el log ya se guarda: no duplicar lineas
if ps -ef 2>/dev/null | grep -v grep | grep -q "transmitir_vivo.sh"; then
  echo "transmitir_vivo.sh esta abierto: el panel no guarda el log (lo hace el). Ya puedes cerrarlo."
  guardar() { cat; }
else
  guardar() { tee -a "$ARCH"; }
fi

# El access.log de Debian en vivo; si la conexion se cae, reintenta. -F sigue al archivo tras la rotacion
transmitir() {
  while true; do
    printf '%s\n' "$PW" | debian 'read -r P; echo "$P" | sudo -S -p "" tail -n 0 -F /var/log/apache2/access.log'
    echo "$(date +%T) conexion con Debian caida; reintento en 10 s (Ctrl+C para salir)" >&2
    sleep 10
  done
}

echo "== PANEL EN VIVO (Ctrl+C para salir) =="
# El historial se lee hasta el tamano de antes de conectar: lo que guarde el panel no se cuenta dos veces
TAM=$(stat -c %s "$ARCH" 2>/dev/null || echo 0)
transmitir | guardar | COLS="$COLS" python -u "$DIR/panel_bots.py" --geoip "$(win "$DATOS/geoip")" \
  --historial "$(win "$ARCH")" --historial-bytes "$TAM" --mostrar 20
