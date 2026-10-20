#!/usr/bin/env bash
# monitor.sh — monitoreo del honeypot web (rector D-14 a D-17). Un solo comando, solo lectura:
#   bash monitor.sh                 panel en vivo: cada peticion con lugar, red y etiqueta (pide la clave)
#   bash monitor.sh vigilar [M] [H] vigilante: alertas de web, archivos, DMZ, caida (cada M min, H horas)
#   bash monitor.sh contencion [N]  alarma en vivo: lo que Debian intenta y pfSense bloquea (N: ultimas N)
#   bash monitor.sh verificar       chequeo de todo antes de empezar
#   bash monitor.sh resumen         foto: top IPs, codigos, WAF, fail2ban (pide la clave)
#   bash monitor.sh logs            trae los logs completos de Debian para analizar (pide la clave)
#   bash monitor.sh geoip           actualiza las bases de ciudad y red (una vez al mes)
# Datos en D:\VMware_LAB\_lab\monitoreo\datos. Puntos ciegos de cada deteccion: puntos_ciegos.md
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
cmd=${1:-panel}; [ $# -gt 0 ] && shift
case "$cmd" in
  panel|contencion|verificar|resumen|logs|geoip) exec bash "$LIB/$cmd.sh" "$@" ;;
  vigilar)    exec bash "$LIB/vigilante.sh" "$@" ;;
  ayuda|-h|--help) sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' ;;
  *) echo "No conozco '$cmd'. Opciones:"; sed -n '3,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
