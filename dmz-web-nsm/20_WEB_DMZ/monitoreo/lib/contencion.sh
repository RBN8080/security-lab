#!/usr/bin/env bash
# monitor.sh contencion [N] — alarma de la DMZ: lo que Debian (10.10.20.40) INTENTA y pfSense le BLOQUEA.
# Solo lee el log de pfSense (por la Pi 5); no cambia nada. Horas en hora local (pfSense va en UTC).
#   CONTENCION = intento hacia casa / lab / NAS (regla 1791590554). Con la web expuesta y sin que tu lo
#                provoques, significa que alguien esta DENTRO de la DMZ intentando moverse. Lo mas grave.
#   SALIDA     = intento hacia internet (bloqueo por defecto). apt y WordPress lo hacen a horas fijas
#                (vigilante_ignorar.txt); fuera de eso, sospechoso.
# Sin N: en vivo (Ctrl+C para salir). Con N: las ultimas N y termina. Sustituye a costura3/ver_alarma_dmz.ps1
. "$(dirname "${BASH_SOURCE[0]}")/comun.sh"
N=${1:-0}
color=1; [ -n "${NO_COLOR:-}" ] && color=0

formato() {
  awk -F': ' -v anio="$(date +%Y)" -v color="$color" '
    BEGIN { split("Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec", m, " "); for (i in m) mes[m[i]] = i }
    /em2,match,block/ {
      split($2, c, ","); split(substr($0, 1, 15), h, /[ :]+/)
      t = mktime(anio " " mes[h[1]] " " h[2] " " h[3] " " h[4] " " h[5], 1)   # UTC -> local
      tipo = (c[4] == "1791590554") ? "CONTENCION" : "SALIDA"
      puerto = (c[17] == "tcp" || c[17] == "udp") ? ":" c[22] : ""
      linea = sprintf("%s  %-10s  %s -> %s%s (%s)", strftime("%H:%M:%S", t), tipo, c[19], c[20], puerto, c[17])
      if (color) linea = (tipo == "CONTENCION" ? "\033[31;1m" : "\033[33m") linea "\033[0m"
      print linea; fflush() }'
}

if [ "$N" -gt 0 ] 2>/dev/null; then
  pfsense 'tail -n 20000 /var/log/filter.log' | formato | tail -n "$N"
  pausa
else
  echo "Alarma DMZ en vivo (Ctrl+C para salir). Esperando bloqueos... (Debian quieto = silencio)"
  pfsense 'tail -n 0 -F /var/log/filter.log' | formato
  fallo "se corto la lectura de pfSense (Pi 5 o pfSense apagados?)"
fi
