#!/usr/bin/env bash
# Avisa al operador sin parar al vigilante: TERMINA (y asi despierta a quien espera) cuando
# aparece una alerta nueva en reportes/alertas.log, o cuando vigilante.log lleva 15 min sin escribirse
# (vigilante caido o fin de turno). Solo lectura. Relanzar despues de cada aviso.
# Uso (Git Bash en el host, en segundo plano): bash despertador.sh
DIR="${PANEL_DATOS:-/d/VMware_LAB/_lab/panel_bots}"  # datos en el taller, se corra desde donde se corra
[ -d "$DIR" ] || DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
A="$DIR/reportes/alertas.log"; L="$DIR/vigilante.log"
n=0; [ -f "$A" ] && n=$(wc -l < "$A")
while true; do
  sleep 30
  if [ -f "$A" ] && [ "$(wc -l < "$A")" -gt "$n" ]; then sleep 5; tail -n +$((n + 1)) "$A"; exit 1; fi
  edad=$(( $(date +%s) - $(stat -c %Y "$L") ))
  [ "$edad" -gt 900 ] && { echo "MUDO: vigilante.log sin escribirse hace $((edad / 60)) min (caido o fin de turno)"; exit 2; }
done
