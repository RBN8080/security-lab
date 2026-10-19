#!/usr/bin/env bash
# Transmite EN VIVO el access.log de Apache (Debian) a panel_bots/logs/access_vivo.log
# para que vigilante.sh detecte ataques web sin sudo. Solo lectura en Debian.
# Con panel_bots.sh abierto NO hace falta: el panel ya guarda el log. Sirve para alimentar al vigilante
# sin panel. Uso (en una ventana de Git Bash, NO con "!"): bash transmitir_vivo.sh
#   Dejar la ventana abierta; Ctrl+C para parar. Si se cae la conexion, reintenta sola.
# La clave sudo vive solo en la memoria de esta ventana mientras corre; no se escribe en disco.
DIR="${PANEL_DATOS:-/d/VMware_LAB/_lab/panel_bots}"  # datos en el taller, se corra desde donde se corra
[ -d "$DIR" ] || DIR="$(cd "$(dirname "$0")" && pwd)"; DIR="$DIR/logs"; mkdir -p "$DIR"; OUT="$DIR/access_vivo.log"
S="-o BatchMode=yes -o ServerAliveInterval=30"
[ -t 0 ] || { echo "ERROR: no hay teclado para la clave. Abre Git Bash y correlo ahi."; exit 1; }
read -rsp "Clave sudo de Debian (no se guarda): " PW; echo
[ -n "$PW" ] || { echo "ERROR: clave vacia"; exit 1; }
{ printf '%s\n' "$PW"; echo "echo SUDO_OK"; } | ssh $S rpi5 "ssh $S debian 'sudo -S -p \"\" bash -s'" 2>&1 \
  | grep -q SUDO_OK || { echo "ERROR: sudo rechazo la clave o no hay conexion"; exit 1; }
echo "Transmitiendo a $OUT  (deja esta ventana abierta; Ctrl+C para parar)"
while true; do
  printf '%s\n' "$PW" | ssh $S rpi5 \
    "ssh $S debian 'read -r P; echo \"\$P\" | sudo -S -p \"\" tail -n 0 -F /var/log/apache2/access.log'" >> "$OUT"
  echo "$(date +%T) conexion caida; reintento en 10 s"; sleep 10
done
