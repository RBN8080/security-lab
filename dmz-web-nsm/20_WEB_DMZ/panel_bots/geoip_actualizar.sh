#!/usr/bin/env bash
# Descarga las bases DB-IP Lite (ciudad y red/ASN) que usa geo.py. Gratis, sin cuenta, CC BY 4.0
# ("IP Geolocation by DB-IP", https://db-ip.com). Se publican el dia 1 de cada mes: correr una vez al mes.
# Las consultas despues son LOCALES: ninguna IP de los registros sale del equipo.
# Uso (Git Bash en el host): bash geoip_actualizar.sh
set -euo pipefail
DIR="${PANEL_DATOS:-/d/VMware_LAB/_lab/panel_bots}"  # datos en el taller, se corra desde donde se corra
[ -d "$DIR" ] || DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; DIR="$DIR/geoip"; mkdir -p "$DIR"
mes=$(date +%Y-%m); previo=$(date -d "$(date +%Y-%m-01) -1 day" +%Y-%m)
for base in city asn; do
  ok=
  for m in "$mes" "$previo"; do
    f="dbip-$base-lite-$m.mmdb"
    [ -s "$DIR/$f" ] && { echo "ya esta: $f"; ok=1; break; }
    if curl -fsSL --max-time 300 -o "$DIR/$f.gz.tmp" "https://download.db-ip.com/free/$f.gz"; then
      gzip -t "$DIR/$f.gz.tmp" && gzip -dc "$DIR/$f.gz.tmp" > "$DIR/$f.tmp" && mv "$DIR/$f.tmp" "$DIR/$f"
      rm -f "$DIR/$f.gz.tmp"; echo "descargada: $f ($(du -h "$DIR/$f" | cut -f1))"; ok=1; break
    fi
    rm -f "$DIR/$f.gz.tmp"
  done
  [ -n "$ok" ] || { echo "ERROR: no se pudo bajar la base $base"; exit 1; }
  # se queda solo la mas reciente
  ls -1 "$DIR"/dbip-"$base"-lite-*.mmdb | sort | head -n -1 | xargs -r rm -f
done
