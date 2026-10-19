#!/usr/bin/env bash
# Copia aplicar.sh/revertir.sh a Debian (por la Pi 5) y corre uno con sudo.
# Pide la clave de sudo y NO la guarda (va por sudo -S).
#   bash "D:/VMware_LAB/_lab/blindaje_fuerte/lanzar.sh"                                  -> aplicar
#   bash "D:/VMware_LAB/_lab/blindaje_fuerte/lanzar.sh" revertir /root/blindaje_fuerte_<fecha>  -> deshacer
DIR="$(cd "$(dirname "$0")" && pwd)"; S="-o BatchMode=yes"
QUE="${1:-aplicar}"; ARG="${2:-}"
if [ -t 0 ]; then read -rsp "Clave sudo de Debian (no se guarda): " PW; echo; else read -r PW; fi
tar -C "$DIR" -cf - aplicar.sh revertir.sh \
  | ssh $S rpi5 "ssh $S debian 'mkdir -p ~/blindaje_fuerte && tar -C ~/blindaje_fuerte -xf -'"
printf '%s\n' "$PW" | ssh $S rpi5 "ssh $S debian 'sudo -S -p \"\" bash ~/blindaje_fuerte/$QUE.sh $ARG'"
