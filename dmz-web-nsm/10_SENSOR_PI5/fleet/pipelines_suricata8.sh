#!/bin/bash
# pipelines_suricata8.sh — sub-pipelines de ingesta que faltan en Security Onion 3.3.0
#
# Rector: ../../rector.md §8.1. Se ejecuta EN Security Onion:  sudo bash pipelines_suricata8.sh
#
# Causa (2026-10-02): suricata.common termina en
#   {"pipeline": {"name": "suricata.{{event.dataset}}"}}   sin ignore_missing_pipeline.
# Suricata 8 (Pi 5) emite tipos sin sub-pipeline en SO 3.3.0 -> Elasticsearch responde 500
# ("non-existent pipeline [suricata.mdns]") y Logstash reintenta el lote sin fin,
# ATASCANDO toda la ingesta detras de el.
# Arreglo: un sub-pipeline minimo por tipo. Los campos comunes (IPs, puertos, community_id,
# observer.name, @timestamp) ya los resuelve suricata.common; el detalle propio del tipo
# queda en message2.<tipo>. No modifica ningun pipeline existente de SO.
# Idempotente: solo crea los que no existen.

set -eo pipefail

TIPOS="mdns quic bittorrent_dht anomaly stats"
BODY='{"description":"dmz-web-nsm: tipo de Suricata 8 sin sub-pipeline en SO 3.3.0; campos comunes via suricata.common","processors":[{"set":{"field":"event.module","value":"suricata","override":false}}]}'

for t in $TIPOS; do
	p="suricata.$t"
	if so-elasticsearch-query "_ingest/pipeline/$p" | jq -e --arg p "$p" 'has($p)' >/dev/null; then
		echo "$p: ya existe"
	else
		so-elasticsearch-query "_ingest/pipeline/$p" -XPUT -d "$BODY" | jq -c .
		echo "$p: creado"
	fi
done

echo "== Verificacion"
so-elasticsearch-query "_ingest/pipeline/suricata.*" | jq -r 'keys[]' | tr '\n' ' '; echo
