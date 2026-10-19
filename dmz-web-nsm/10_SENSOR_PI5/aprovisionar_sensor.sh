#!/bin/sh
# aprovisionar_sensor.sh — Pi 5 como sensor de red (Suricata + Zeek) de la LAN real
#
# Rector: ../rector.md D-10. Reproduce lo aplicado a mano el 2026-10-02 (charter P1).
# Estado: escrito a partir de la configuracion medida en el nodo; NO ejecutado aun
# de punta a punta sobre una Pi limpia. Idempotente: se puede relanzar.
#
# Uso (en la Pi 5, desde esta carpeta copiada al nodo):
#   sudo sh aprovisionar_sensor.sh
#
# Requisitos previos fuera de este script:
#   - Switch GS105Ev2: espejo origen puerto 1 (router) -> destino puerto 5 (Pi 5).
#   - Interfaz de captura = eth0 (el puerto destino del GS105Ev2 sigue siendo normal).

set -eu

DIR=$(cd "$(dirname "$0")" && pwd)
IFACE=eth0
ZEEK_IMAGE=zeek/zeek:lts

[ "$(id -u)" -eq 0 ] || { echo "ERROR: ejecutar con sudo" >&2; exit 1; }

echo "== 1/6 journald: tope de 200 MB"
install -D -m 0644 "$DIR/sistema/journald-lab.conf" /etc/systemd/journald.conf.d/lab.conf
systemctl restart systemd-journald

echo "== 2/6 cgroup memory (necesario para que MemoryMax y docker --memory se apliquen)"
CMDLINE=/boot/firmware/cmdline.txt
if ! grep -q 'cgroup_enable=memory' "$CMDLINE"; then
	cp "$CMDLINE" "$CMDLINE.bak-$(date +%Y%m%d)"
	sed -i '1 s/$/ cgroup_enable=memory cgroup_memory=1/' "$CMDLINE"
	[ "$(wc -l < "$CMDLINE")" -le 1 ] || { echo "ERROR: cmdline.txt dejo de ser una linea" >&2; exit 1; }
	REBOOT=1
fi

echo "== 3/6 Suricata"
DEBIAN_FRONTEND=noninteractive apt-get install -y -q suricata ethtool jq
[ -f /etc/suricata/suricata.yaml.orig ] || cp /etc/suricata/suricata.yaml /etc/suricata/suricata.yaml.orig
install -m 0644 "$DIR/suricata/lab.yaml" /etc/suricata/lab.yaml
# HOME_NET va en el archivo principal: un include reemplaza la clave de nivel
# superior completa y 'vars:' perderia HTTP_PORTS y demas grupos.
sed -i 's|^\(\s*HOME_NET:\).*|\1 "[192.168.1.0/24]"|' /etc/suricata/suricata.yaml
grep -q '^include:' /etc/suricata/suricata.yaml || printf '\ninclude:\n  - /etc/suricata/lab.yaml\n' >> /etc/suricata/suricata.yaml
install -D -m 0644 "$DIR/suricata/lab-limits.conf" /etc/systemd/system/suricata.service.d/lab-limits.conf
suricata-update
suricata -T -c /etc/suricata/suricata.yaml
systemctl daemon-reload
systemctl enable suricata
systemctl restart suricata

echo "== 4/6 Docker (iptables=false ya viene de /etc/default/docker; no duplicar en daemon.json)"
if [ -f /etc/docker/daemon.json ] && ! cmp -s "$DIR/sistema/docker-daemon.json" /etc/docker/daemon.json; then
	cp /etc/docker/daemon.json "/etc/docker/daemon.json.bak-$(date +%Y%m%d)"
fi
install -D -m 0644 "$DIR/sistema/docker-daemon.json" /etc/docker/daemon.json
systemctl enable docker containerd
systemctl restart docker

echo "== 5/6 Zeek (contenedor, limite 1 GB)"
install -d /opt/zeek/logs /opt/zeek/site
install -m 0644 "$DIR/zeek/lab.zeek" /opt/zeek/site/lab.zeek
install -m 0644 "$DIR/zeek/zeek-cleanup.cron" /etc/cron.d/zeek-cleanup
docker pull -q "$ZEEK_IMAGE"
docker rm -f zeek >/dev/null 2>&1 || true
docker run -d --name zeek --restart unless-stopped --network host \
	--cap-add NET_RAW --cap-add NET_ADMIN --memory 1g --memory-swap 1g \
	-v /opt/zeek/logs:/logs -v /opt/zeek/site:/site:ro -w /logs \
	"$ZEEK_IMAGE" zeek -C -i "af_packet::$IFACE" /site/lab.zeek

echo "== 6/6 Verificacion"
systemctl is-active suricata
docker ps --filter name=zeek --format '{{.Names}} {{.Status}}'
grep -qw memory /sys/fs/cgroup/cgroup.controllers \
	&& echo "cgroup memory: activo" \
	|| echo "AVISO: cgroup memory inactivo — los limites NO se aplican hasta reiniciar"

echo "== Modo automatico (rector §7.23): el sensor solo corre mientras el SOC responde"
# Deshace el enable de suricata y el --restart de zeek de arriba; sin esto, relanzar
# este script volveria a dejar el sensor encendido siempre.
sh "$DIR/auto/instalar_auto.sh"

if [ "${REBOOT:-0}" = 1 ]; then
	echo "REINICIO NECESARIO (cmdline.txt cambio). Tras reiniciar, relanzar este script para recrear Zeek con su limite."
fi
