#!/usr/bin/env bash
# Copia aplicar.sh/revertir.sh a Debian (por la Pi 5) y corre uno con sudo (clave no se guarda).
#   bash "D:/VMware_LAB/_lab/waf_fail2ban/lanzar.sh"            -> aplicar
#   bash "D:/VMware_LAB/_lab/waf_fail2ban/lanzar.sh" revertir   -> deshacer
DIR="$(cd "$(dirname "$0")" && pwd)"; S="-o BatchMode=yes"
QUE="${1:-aplicar}"; ARG="${2:-}"
if [ -t 0 ]; then read -rsp "Clave sudo de Debian (no se guarda): " PW; echo; else read -r PW; fi
tar -C "$DIR" -cf - aplicar.sh revertir.sh \
  | ssh $S rpi5 "ssh $S debian 'mkdir -p ~/waf_fail2ban && tar -C ~/waf_fail2ban -xf -'"
printf '%s\n' "$PW" | ssh $S rpi5 "ssh $S debian 'sudo -S -p \"\" bash ~/waf_fail2ban/$QUE.sh $ARG'"
