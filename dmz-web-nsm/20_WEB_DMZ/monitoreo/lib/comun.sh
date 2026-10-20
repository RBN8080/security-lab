# lib/comun.sh — lo que comparten los subcomandos de monitor.sh. Se carga con:  . "$LIB/comun.sh"
# Datos (logs, reportes, bases GeoIP, fotos del vigilante): siempre en el taller, se corra desde el
# repo o desde D: (rector D-17). Sin el taller, junto al codigo en datos/ (ignorado por git).
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RAIZ="$(dirname "$LIB")"
TALLER=/d/VMware_LAB/_lab/monitoreo
if [ -n "${MONITOR_DATOS:-}" ]; then DATOS=$MONITOR_DATOS
elif [ -d "$TALLER" ]; then DATOS="$TALLER/datos"
else DATOS="$RAIZ/datos"; fi
mkdir -p "$DATOS/logs" "$DATOS/reportes"
ARCH="$DATOS/logs/access_vivo.log"      # el log en vivo que guarda el panel y lee el vigilante
CONFIG="$RAIZ/config"
WEB_PUBLICA="https://sitio-ejemplo.duckdns.org/"
VPS="root@203.0.113.10"; VPS_LLAVE="$HOME/.ssh/id_vps"
S="-o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=30 -o ServerAliveCountMax=3"

# Debian y pfSense se alcanzan saltando por la Pi 5 (tunel WireGuard al lab)
debian()  { ssh $S rpi5 "ssh $S debian '$1'"; }
pfsense() { ssh $S rpi5 "ssh $S pfsense '$1'"; }
win() { cygpath -m "$1" 2>/dev/null || echo "$1"; }

# Abierto con doble clic, bash es el primer shell (SHLVL=1) y la ventana se cierra al terminar
pausa() { [ -t 0 ] && [ "${SHLVL:-1}" -le 1 ] && read -rp "Presiona Enter para cerrar..." _; return 0; }
fallo() { echo; echo "ERROR: $*"; [ -t 0 ] && read -rp "Presiona Enter para cerrar..." _; exit 1; }

pedir_clave() { if [ -t 0 ]; then read -rsp "Clave sudo de Debian (no se guarda): " PW; echo; else read -r PW; fi; }
# Pide la clave y la prueba contra sudo (hasta 3 intentos si hay teclado). Deja la clave en $PW
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

# Descendientes de un proceso (ps de MSYS: PID en $2, PPID en $3), para no dejar huerfanos al salir
hijos() { local p; for p in $(ps -ef | awk -v pp="$1" '$3 == pp {print $2}'); do hijos "$p"; echo "$p"; done; }
