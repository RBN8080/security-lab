#!/usr/bin/env bash
# Debian DMZ "Servidor2" - copia aplicar.sh/revertir.sh a Debian (por la Pi 5) y corre uno con sudo.
# Pide la clave de sudo de Debian y NO la guarda (va por la entrada de sudo -S).
# Uso desde el host (Git Bash):
#   bash "D:/VMware_LAB/_lab/debian_endurecer/lanzar.sh"                                         -> aplicar
#   bash "D:/VMware_LAB/_lab/debian_endurecer/lanzar.sh" revertir /root/respaldo_endurecer_<fecha> -> deshacer
DIR="$(cd "$(dirname "$0")" && pwd)"
S="-o BatchMode=yes"
QUE="${1:-aplicar}"; ARG="${2:-}"

if [ -t 0 ]; then read -rsp "Clave sudo de Debian (no se guarda): " PW; echo; else read -r PW; fi

tar -C "$DIR" -cf - aplicar.sh revertir.sh \
  | ssh $S rpi5 "ssh $S debian 'mkdir -p ~/debian_endurecer && tar -C ~/debian_endurecer -xf -'"
printf '%s\n' "$PW" | ssh $S rpi5 "ssh $S debian 'sudo -S -p \"\" bash ~/debian_endurecer/$QUE.sh $ARG'"
