#!/usr/bin/env bash
# Copia al host los registros web de Debian (Apache + WAF) para analizarlos sin sudo.
# Solo lectura en Debian. Pide la clave sudo (no se guarda).
# Uso (en una ventana de Git Bash, NO desde un terminal sin teclado: hay que teclear la clave):
#   bash copiar_logs.sh   -> deja los archivos en panel_bots/logs/
DIR="$(cd "$(dirname "$0")" && pwd)/logs"; mkdir -p "$DIR"
[ -t 0 ] || { echo "ERROR: no hay teclado para la clave. Abre Git Bash y correlo ahi."; exit 1; }
read -rsp "Clave sudo de Debian (no se guarda): " PW; echo
[ -n "$PW" ] || { echo "ERROR: clave vacia"; exit 1; }
remoto() { { printf '%s\n' "$PW"; echo "$1"; } \
  | ssh -o BatchMode=yes rpi5 "ssh -o BatchMode=yes debian 'sudo -S -p \"\" bash -s'"; }
remoto "echo SUDO_OK" 2>&1 | grep -q SUDO_OK || { echo "ERROR: sudo rechazo la clave o no hay conexion"; exit 1; }
for f in access.log access.log.1 error.log modsec_audit.log; do
  remoto "cat /var/log/apache2/$f 2>/dev/null" > "$DIR/$f"
  echo "$f: $(wc -l < "$DIR/$f") lineas"
done
unset PW
