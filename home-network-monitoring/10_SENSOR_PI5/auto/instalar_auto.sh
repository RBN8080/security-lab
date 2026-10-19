#!/bin/sh
# instalar_auto.sh — sensor de la Pi 5 automatico segun el SOC (rector §7.23)
#
#   sudo sh instalar_auto.sh            instala (idempotente)
#   sudo sh instalar_auto.sh --quitar   deshace: el sensor vuelve a arrancar siempre con la Pi
#
# Tras instalar, el sensor (Suricata + Zeek + Elastic Agent) ya NO arranca con la Pi:
# lo enciende sensor-vigia cuando el SOC responde y lo apaga ~5 min despues de que
# deje de responder. Requiere el contenedor zeek creado por aprovisionar_sensor.sh.

set -eu

DIR=$(cd "$(dirname "$0")" && pwd)
U=/etc/systemd/system

[ "$(id -u)" -eq 0 ] || { echo "ERROR: ejecutar con sudo" >&2; exit 1; }
docker inspect zeek >/dev/null 2>&1 || { echo "ERROR: no existe el contenedor zeek (aprovisionar_sensor.sh)" >&2; exit 1; }

if [ "${1:-}" = "--quitar" ]; then
	systemctl disable --now sensor-vigia.timer 2>/dev/null || true
	systemctl stop sensor.target 2>/dev/null || true
	rm -f "$U/sensor.target" "$U/sensor-zeek.service" "$U/sensor-vigia.service" "$U/sensor-vigia.timer" \
		"$U/suricata.service.d/sensor-parte.conf" "$U/elastic-agent.service.d/sensor-parte.conf" \
		/usr/local/sbin/sensor
	rmdir "$U/elastic-agent.service.d" 2>/dev/null || true
	systemctl daemon-reload
	docker update --restart unless-stopped zeek >/dev/null
	systemctl enable --now suricata elastic-agent
	docker start zeek >/dev/null
	echo "Quitado: el sensor arranca siempre con la Pi (como antes de §7.23). /etc/default/sensor se conserva."
	exit 0
fi

echo "== 1/4 archivos"
install -m 0755 "$DIR/sensor" /usr/local/sbin/sensor
install -m 0644 "$DIR/sensor.target" "$DIR/sensor-zeek.service" "$DIR/sensor-vigia.service" "$DIR/sensor-vigia.timer" "$U/"
install -D -m 0644 "$DIR/sensor-parte.conf" "$U/suricata.service.d/sensor-parte.conf"
install -D -m 0644 "$DIR/sensor-parte.conf" "$U/elastic-agent.service.d/sensor-parte.conf"
[ -e /etc/default/sensor ] || install -m 0644 "$DIR/sensor.default" /etc/default/sensor
systemctl daemon-reload

echo "== 2/4 el sensor deja de arrancar solo; systemd gobierna el contenedor zeek"
systemctl disable suricata elastic-agent
docker update --restart no zeek >/dev/null

echo "== 3/4 apagar lo que corre fuera de sensor.target (el vigia lo enciende si el SOC responde)"
systemctl stop sensor.target suricata elastic-agent 2>/dev/null || systemctl stop suricata elastic-agent
docker stop -t 30 zeek >/dev/null 2>&1 || true

echo "== 4/4 vigia"
systemd-analyze verify "$U/sensor.target" "$U/sensor-zeek.service" "$U/sensor-vigia.service" "$U/sensor-vigia.timer"
systemctl enable --now sensor-vigia.timer
systemctl start sensor-vigia.service
/usr/local/sbin/sensor estado
