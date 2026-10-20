#!/usr/bin/env bash
# monitor.sh logs — trae al taller los registros completos de Debian (Apache access/error y el audit del
# WAF) para analizarlos a fondo. Solo lectura en Debian; pide la clave sudo. Quedan en datos/logs/.
. "$(dirname "${BASH_SOURCE[0]}")/comun.sh"
clave_valida
remoto() { { printf '%s\n' "$PW"; echo "$1"; } | debian 'sudo -S -p "" bash -s'; }
for f in access.log access.log.1 error.log modsec_audit.log; do
  remoto "cat /var/log/apache2/$f 2>/dev/null" > "$DATOS/logs/$f"
  echo "$f: $(wc -l < "$DATOS/logs/$f") lineas"
done
echo "En $DATOS/logs/"
pausa
