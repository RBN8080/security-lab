#!/bin/bash
# crear_politica_pi5.sh — politica de Fleet "pi5-sensor" en Security Onion
#
# Rector: ../../rector.md D-10, §7.17. Se ejecuta EN Security Onion (soc-lab), no en la Pi:
#   sudo bash crear_politica_pi5.sh <AGENT_ID>
# AGENT_ID: en la Pi 5, `sudo elastic-agent status --output json | jq -r .info.id`
#
# Replica las integraciones suricata-logs / zeek-logs de so-grid-nodes_general
# (mismos datasets, pipelines y procesadores) cambiando solo las rutas a las de la Pi,
# y System (auth/syslog). Sin Elastic Defend ni osquery: Defend no arranca con el
# kernel de paginas de 16 KB de la Pi 5 (jemalloc: Unsupported system page size).
# Usa fleet_api() de so-elastic-fleet-common (credenciales internas de SO, root).
# Idempotente: si la politica o una integracion ya existe, no la duplica.

set -eo pipefail

AGENT_ID=${1:?Uso: sudo bash crear_politica_pi5.sh <AGENT_ID>}
POLICY=pi5-sensor
# so-elastic-fleet-common lee variables opcionales sin definir ($NOROOT): se carga
# ANTES de activar 'set -u'.
# shellcheck source=/dev/null
source /usr/sbin/so-elastic-fleet-common
set -u

pkg_version() { fleet_api "epm/packages/$1" | jq -r '.item.version'; }

existe_integracion() {
	fleet_api "package_policies?perPage=1000" | jq -e --arg n "$1" '.items[] | select(.name==$n)' >/dev/null
}

echo "== Politica $POLICY"
if fleet_api "agent_policies/$POLICY" >/dev/null; then
	echo "ya existe"
else
	elastic_fleet_policy_create "$POLICY" "Pi 5 sensor LAN real (home-network-monitoring D-10)" "false" "1209600" >/dev/null
	echo "creada"
fi

FS_VER=$(pkg_version filestream)
SYS_VER=$(pkg_version system)
echo "filestream $FS_VER · system $SYS_VER"

ZEEK_EXCL='(broker|capture_loss|cluster|conn-summary|console|ecat_arp_info|known_certs|known_hosts|known_services|loaded_scripts|ntp|ocsp|packet_filter|reporter|stats|stderr|stdout)(\..+)?\.log$|\.[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9-]+\.log$'

SURI_PROC='- add_fields:
    target: event
    fields:
      category: network
      module: suricata'

ZEEK_PROC='- dissect:
    tokenizer: "/opt/zeek/logs/%{pipeline}.log"
    field: "log.file.path"
    trim_chars: ".log"
    target_prefix: ""
- script:
      lang: javascript
      source: >
        function process(event) {
          var pl = event.Get("pipeline");
          event.Put("@metadata.pipeline", "zeek." + pl);
        }
- add_fields:
    target: event
    fields:
      category: network
      module: zeek'

filestream_json() { # nombre descripcion ruta dataset pipeline procesadores exclusion
	jq -n --arg name "$1" --arg desc "$2" --arg path "$3" --arg ds "$4" --arg pl "$5" \
		--arg proc "$6" --arg excl "$7" --arg ver "$FS_VER" --arg pol "$POLICY" '{
		package: {name: "filestream", version: $ver}, name: $name, namespace: "so",
		description: $desc, policy_ids: [$pol], force: true,
		inputs: {"filestream-filestream": {enabled: true, streams: {"filestream.filestream": {enabled: true, vars: {
			paths: [$path], "data_stream.dataset": $ds, pipeline: $pl, processors: $proc,
			exclude_files: ([$excl] | map(select(. != ""))), include_files: [],
			compression_gzip: false, use_logs_stream: false, tags: [], recursive_glob: true,
			clean_inactive: -1, harvester_limit: 0, fingerprint: false, fingerprint_offset: 0,
			file_identity_native: true, exclude_lines: [], include_lines: [], delete_enabled: false
		}}}}}}
		| .inputs["filestream-filestream"].streams["filestream.filestream"].vars
			|= (if .pipeline == "" then del(.pipeline) else . end)'
}

crear() { # nombre json
	if existe_integracion "$1"; then echo "$1: ya existe"; return; fi
	elastic_fleet_integration_create "$2" >/dev/null && echo "$1: creada"
}

echo "== Integraciones"
crear pi5-suricata-logs "$(filestream_json pi5-suricata-logs "Suricata eve.json de la Pi 5" \
	/var/log/suricata/eve.json suricata suricata.common "$SURI_PROC" '\.gz$')"

crear pi5-zeek-logs "$(filestream_json pi5-zeek-logs "Zeek de la Pi 5 (contenedor zeek/zeek:lts)" \
	'/opt/zeek/logs/*.log' zeek "" "$ZEEK_PROC" "$ZEEK_EXCL")"

crear pi5-system "$(jq -n --arg ver "$SYS_VER" --arg pol "$POLICY" '{
	package: {name: "system", version: $ver}, name: "pi5-system", namespace: "default",
	policy_ids: [$pol], force: true, inputs: {
		"system-logfile": {enabled: true, streams: {
			"system.auth": {enabled: true, vars: {paths: ["/var/log/auth.log*"], tags: ["pi5-sensor"]}},
			"system.syslog": {enabled: true, vars: {paths: ["/var/log/syslog*"], tags: ["pi5-sensor"]}}}},
		"system-winlog": {enabled: false},
		"system-system/metrics": {enabled: false}}}')"

echo "== Reasignar agente $AGENT_ID -> $POLICY"
fleet_api "agents/$AGENT_ID/reassign" -XPOST -H 'kbn-xsrf: true' -H 'Content-Type: application/json' \
	-d "{\"policy_id\":\"$POLICY\"}" >/dev/null && echo "reasignado"

echo "== Estado"
fleet_api "agents/$AGENT_ID" | jq -r '.item | "\(.local_metadata.host.hostname) policy=\(.policy_id) status=\(.status)"'
