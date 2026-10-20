#!/usr/bin/env bash
# Vigilante del honeypot. Solo lectura: no cambia nada en ninguna maquina.
# Cada 30 s revisa la web en vivo; cada 5 min hace la revision completa. Anota "ALERTA ..." en
# reportes/alertas.log, lo muestra en esta ventana y SIGUE vigilando (un sensor parado es un punto ciego) si:
#   WEB      = ataque a la web: rafaga de AVISO_4XX+ errores 4xx, POST externo, 5xx o 200 en un .php raro
#              (necesita el panel abierto, que guarda el log; espera a que la rafaga acabe y la resume).
#              Rafagas de 10 a AVISO_4XX-1 solo 4xx = reconocimiento: van a ataques_auto.log sin alertar.
#              Campana repetida (rutas >= 90 % iguales a una ya vista, reportes/campanas/) sin POST, 5xx
#              ni 200 fuera de portada/estaticos/index.php vacios: se anota sin alertar.
#   FEED     = la transmision en vivo dejo de llegar (2 rondas sin ver el latido del propio vigilante)
#   ARCHIVOS = cambio, aparecio o desaparecio un archivo en /var/www/html (contra la foto inicial)
#   DMZ      = pfSense bloqueo a Debian intentando salir (CONTENCION = hacia casa/lab; SALIDA = internet)
#              salvo SALIDA ya explicada: vigilante_ignorar.txt (IPs fijas) y apt por contexto (ruido_apt)
#   CAIDA    = la web publica no da 200 en 3 rondas seguidas
#   CIEGO    = no pude leer Debian o pfSense en 3 rondas seguidas
# Los estados (FEED, CAIDA, CIEGO) avisan una vez por episodio, no en cada ronda.
# Uso: bash monitor.sh vigilar [minutos=5] [horas=10]
# Bitacoras (en datos/): vigilante/vigilante.log (una linea por ronda), reportes/alertas.log y
# reportes/ataques_auto.log. Listas: config/vigilante_ignorar.txt y config/rangos_fastly.txt.

. "$(dirname "${BASH_SOURCE[0]}")/comun.sh"
V="$DATOS/vigilante"; mkdir -p "$V"     # bitacora, fotos de /var/www/html y temporales
MIN=${1:-5}; HORAS=${2:-10}; TICK=30
URL=$WEB_PUBLICA
UA_PROPIO="vigilante-lab"
LOG="$V/vigilante.log"
FOTO="$V/foto_$(date +%Y%m%d_%H%M).txt"
VISTOS="$V/.vistos"
IGNORAR="$CONFIG/vigilante_ignorar.txt"
WEB="$ARCH"
ATAQUES="$DATOS/reportes/ataques_auto.log"
ALERTAS="$DATOS/reportes/alertas.log"
RANGOS="$CONFIG/rangos_fastly.txt"
VENTANA_APT=1200   # s tras un disparo de los timers de apt en los que su salida bloqueada es ruido
AVISO_4XX=50       # 4xx en una rafaga para alertar (debajo solo se anota)
CAMPANAS="$DATOS/reportes/campanas"; mkdir -p "$CAMPANAS"
# index.php vacios de fabrica de WordPress ("Silence is golden"); ARCHIVOS vigila que no cambien
VACIOS='^/wp-content/((themes|plugins|uploads)/)?index[.]php$'

log()    { echo "$(date '+%F %T') $*" >> "$LOG"; }
alerta() { log "ALERTA $1"; nal=$((nal + 1)); echo "ALERTA $1"
           { echo "=== $(date '+%F %T') ALERTA $1"; [ -n "$2" ] && echo "$2"; } >> "$ALERTAS"; }

huellas() {
  ssh -o ConnectTimeout=10 -o BatchMode=yes rpi5 "ssh -o ConnectTimeout=10 debian 'bash -s'" <<'EOF'
find /var/www/html -type f \( -readable -exec sha256sum {} + -o -printf 'NOLEGIBLE  %p\n' \) | sort -k2
EOF
}

bloqueos() {
  ssh -o ConnectTimeout=10 -o BatchMode=yes rpi5 \
    "ssh -o ConnectTimeout=10 pfsense 'grep em2,match,block /var/log/filter.log | tail -n 500'"
}

# Mismo formato que monitor.sh contencion (aqui la hora va en UTC)
formato() {
  awk -F': ' '{ split($2, c, ","); t = (c[4] == "1791590554") ? "CONTENCION" : "SALIDA";
    p = (c[17] == "tcp" || c[17] == "udp") ? ":" c[22] : "";
    print substr($0, 1, 15) " UTC  " t "  " c[19] " -> " c[20] p " (" c[17] ")" }'
}

# Ruido de apt: apt-daily y apt-daily-upgrade (hora aleatoria, hasta 12 h) intentan bajar de
# deb.debian.org, que es Fastly y rota IPs. Se reconoce por CONTEXTO, no por IP: SALIDA tcp/80
# + destino en los rangos publicados de Fastly + dentro de VENTANA_APT tras un disparo real.
# Punto ciego aceptado: algo que imite a apt en esa ventana. Si no se puede leer Debian, alerta.
apt_disparos() {
  ssh -o ConnectTimeout=10 -o BatchMode=yes rpi5 "ssh -o ConnectTimeout=10 debian 'bash -s'" <<'EOF' | tr '\n' ' '
for t in apt-daily apt-daily-upgrade; do v=$(TZ=UTC systemctl show -P LastTriggerUSec $t.timer); [ -n "$v" ] && date -d "$v" +%s; done
EOF
}
# stdin: bloqueos nuevos; $1: disparos (epoch). Saca los que NO son apt y al final "#APT <cuantos>"
ruido_apt() {
  awk -F': ' -v disp="$1" -v win="$VENTANA_APT" -v f="$RANGOS" -v anio="$(date +%Y)" '
    function n(ip,  o) { split(ip, o, "."); return ((o[1] * 256 + o[2]) * 256 + o[3]) * 256 + o[4] }
    function fastly(ip,  x, i) { x = n(ip); for (i = 1; i <= nr; i++) if (int(x / tam[i]) == int(red[i] / tam[i])) return 1; return 0 }
    function cerca(t,  i) { for (i = 1; i <= nd; i++) if (t >= d[i] && t <= d[i] + win) return 1; return 0 }
    BEGIN { while ((getline l < f) > 0) { sub(/[ \t#].*/, "", l); if (split(l, r, "/") == 2) { red[++nr] = n(r[1]); tam[nr] = 2 ^ (32 - r[2]) } }
            nd = split(disp, d, " "); split("Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec", m, " "); for (i in m) mes[m[i]] = i }
    { split($2, c, ","); split(substr($0, 1, 15), h, /[ :]+/)
      t = mktime(anio " " mes[h[1]] " " h[2] " " h[3] " " h[4] " " h[5], 1)   # filter.log va en UTC
      if (c[4] != "1791590554" && c[17] == "tcp" && c[22] == 80 && fastly(c[20]) && cerca(t)) apt++; else print }
    END { print "#APT " apt + 0 }'
}

# --- web en vivo (lee lo que el panel va dejando en $WEB) ---
pos=0; [ -f "$WEB" ] && pos=$(wc -c < "$WEB")
nuevas() {
  [ -f "$WEB" ] || return 0
  local t; t=$(wc -c < "$WEB"); [ "$t" -lt "$pos" ] && pos=0
  [ "$t" -gt "$pos" ] && tail -c +$((pos + 1)) "$WEB" | head -c $((t - pos))
  pos=$t
}
# Fuera: localhost, LAN, tunel (10.9.0.1 = conexiones rotas sin IP real) y el propio vigilante
externas() { grep -v "$UA_PROPIO" | awk '$1 !~ /^(127\.|10\.|192\.168\.)/'; }
motivo() {
  awk -v vacios="$VACIOS" '{ c = $9; m = $6; p = $7; sub(/\?.*/, "", p)
    if (c ~ /^4/ && p !~ /^\/(favicon\.ico|apple-touch-icon[^\/]*\.png)$/) n4++   # iconos que el navegador pide solo
    if (m == "\"POST") post++
    if (c ~ /^5/) n5++
    if (c == 200 && p ~ /\.php$/ && p != "/index.php" && p !~ vacios) raro++ }
    END { if (n4 >= 10) r = r "rafaga " n4 "x4xx; "; if (post) r = r post " POST; ";
          if (n5) r = r n5 "x5xx; "; if (raro) r = r raro " 200 en .php; "; printf "%s", r }'
}
resumen() {
  local L="$1"
  echo "  hora: $(echo "$L" | head -1 | awk '{print substr($4, 14)}') -> $(echo "$L" | tail -1 | awk '{print substr($4, 14)}')  peticiones: $(echo "$L" | grep -c .)"
  echo "  IPs ($(echo "$L" | awk '{print $1}' | sort -u | wc -l)): $(echo "$L" | awk '{print $1}' | sort | uniq -c | sort -rn | head -5 | awk '{printf "%s x%s  ", $2, $1}')"
  echo "  codigos: $(echo "$L" | awk '{print $9}' | sort | uniq -c | sort -rn | awk '{printf "%s x%s  ", $2, $1}')"
  echo "  navegador: $(echo "$L" | awk -F'"' '{print ($6 == "-" ? "(ninguno)" : substr($6, 1, 60))}' | sort | uniq -c | sort -rn | head -2 | sed 's/^ *//' | tr '\n' '|')"
  echo "  rutas: $(echo "$L" | awk '{print $7}' | head -10 | tr '\n' ' ')"
  local ok; ok=$(echo "$L" | awk '$9 == 200 && $7 != "/"' | awk '{print $1, $6, $7}' | head -5)
  [ -n "$ok" ] && echo "  CON 200 (revisar): $(echo "$ok" | tr '\n' ';')"
}
# Rutas de una rafaga, normalizadas (sin query, %2F -> /, // -> /), para reconocer campanas
rutas() { awk '{ p = $7; sub(/\?.*/, "", p); gsub(/%2[Ff]/, "/", p); gsub(/\/+/, "/", p); print p }' | sort -u; }
# Imprime la campana ya vista que coincide >= 90 % (Jaccard); si no hay, guarda esta como nueva
campana_vista() {
  local f a b c r="$V/.rutas_tmp"; rutas > "$r"; a=$(wc -l < "$r")
  for f in "$CAMPANAS"/*.txt; do [ -f "$f" ] || continue
    b=$(wc -l < "$f"); c=$(comm -12 "$r" "$f" | wc -l)
    [ $((c * 100)) -ge $(( (a + b - c) * 90 )) ] && { basename "$f" .txt; return; }
  done
  cp "$r" "$CAMPANAS/$(date +%Y%m%d_%H%M)_$(md5sum < "$r" | cut -c1-6).txt"
}
# 200 que si importan: todo menos la portada, estaticos e index.php vacios
sensibles200() {
  awk -v vacios="$VACIOS" '$9 == 200 { p = $7; sub(/\?.*/, "", p)
    if (p != "/" && p !~ /\.(js|css|png|jpe?g|gif|svg|ico|woff2?)$/ && p !~ vacios) n++ } END { print n + 0 }'
}
TMPW="$V/.web_tmp"
revisar_web() {
  local n ext m acum quietos=0 t0
  nuevas > "$TMPW"; n=$(cat "$TMPW"); [ -z "$n" ] && return   # sin subshell: nuevas actualiza pos
  echo "$n" | grep -q "$UA_PROPIO" && latido=1
  ext=$(echo "$n" | externas); [ -z "$ext" ] && return
  m=$(echo "$ext" | motivo); [ -z "$m" ] && return
  acum="$ext"; t0=$(date +%s)
  while [ "$quietos" -lt 2 ] && [ $(( $(date +%s) - t0 )) -lt 300 ]; do   # espera a que la rafaga acabe
    sleep "$TICK"; nuevas > "$TMPW"; n=$(externas < "$TMPW")
    [ -n "$n" ] && acum="$acum"$'\n'"$n"
    if echo "$n" | awk '$9 ~ /^4/ {f = 1} END {exit !f}'; then quietos=0; else quietos=$((quietos + 1)); fi
  done
  m=$(echo "$acum" | motivo); r=$(resumen "$acum")
  { echo "=== $(date '+%F %T')  $m"; echo "$r"; } >> "$ATAQUES"
  n4=$(echo "$m" | sed -n 's/.*rafaga \([0-9]*\)x4xx.*/\1/p')
  if [ "${n4:-0}" -lt "$AVISO_4XX" ] && ! echo "$m" | grep -qE 'POST|5xx|200 en'; then
    log "baja WEB: $m(anotado en ataques_auto.log)"; return
  fi
  camp=$(echo "$acum" | campana_vista)
  if [ -n "$camp" ] && ! echo "$m" | grep -qE 'POST|5xx|200 en' && [ "$(echo "$acum" | sensibles200)" = 0 ]; then
    echo "  campana repetida: $camp" >> "$ATAQUES"
    log "repetida WEB: $m(campana $camp; anotado en ataques_auto.log)"; return
  fi
  alerta "WEB: $m" "$r"
}

[ "${VIG_PRUEBA:-}" = 1 ] && return 0   # para probar las funciones con: VIG_PRUEBA=1 source vigilante.sh

# --- arranque ---
huellas > "$FOTO"
[ -s "$FOTO" ] || fallo "CIEGO: no pude tomar la foto inicial de Debian (Pi 5 o Debian apagados?)"
bloqueos > "$VISTOS" || fallo "CIEGO: no pude leer pfSense"
feed="sin log en vivo (abre el panel: bash monitor.sh)"; [ -f "$WEB" ] && feed="web en vivo ON"
log "INICIO cada $MIN min por $HORAS h; foto $(wc -l < "$FOTO") archivos; $feed"
echo "vigilante arriba: foto de $(wc -l < "$FOTO") archivos, cada $MIN min por $HORAS h; $feed"

fin=$(( $(date +%s) + HORAS * 3600 )); fweb=0; fciego=0; ffeed=0; ronda=0; latido=1; nal=0; proxima=0
while [ "$(date +%s)" -lt "$fin" ]; do
  revisar_web
  # por reloj, no por vueltas: una rafaga larga retiene revisar_web hasta 5 min y no debe aplazar ARCHIVOS/DMZ
  if [ "$(date +%s)" -ge "$proxima" ]; then
    proxima=$(( $(date +%s) + MIN * 60 ))
    ciego=0; arch=igual; dmz=sin-intentos

    if [ -f "$WEB" ] && [ "$ronda" -gt 0 ]; then
      if [ "$latido" = 1 ]; then ffeed=0; else ffeed=$((ffeed + 1)); fi
      [ "$ffeed" -eq 2 ] && alerta "FEED: la transmision en vivo no llega (reabre el panel: bash monitor.sh)"
    fi
    latido=0

    code=$(curl -s -A "$UA_PROPIO" -o /dev/null -w '%{http_code}' --max-time 20 "$URL")
    if [ "$code" = 200 ]; then fweb=0; else fweb=$((fweb + 1)); fi
    [ "$fweb" -eq 3 ] && alerta "CAIDA: la web publica responde '$code' 3 rondas seguidas"

    ahora=$(huellas)
    if [ -z "$ahora" ]; then ciego=1; else
      dif=$(diff "$FOTO" <(echo "$ahora"))
      if [ -n "$dif" ]; then
        echo "$dif" > "$V/diff_$(date +%Y%m%d_%H%M).txt"
        alerta "ARCHIVOS: cambiaron $(echo "$dif" | grep -c '^[<>]') lineas en /var/www/html" "$(echo "$dif" | head -10)"
        arch=CAMBIO   # nueva referencia: cada cambio posterior alerta aparte
        FOTO="$V/foto_$(date +%Y%m%d_%H%M).txt"; echo "$ahora" > "$FOTO"
      fi
    fi

    if bl=$(bloqueos); then
      nuevos=$(printf '%s\n' "$bl" | grep -Fxv -f "$VISTOS" | grep -v '^$')
      [ -n "$nuevos" ] && printf '%s\n' "$nuevos" >> "$VISTOS"
      # SALIDA a destinos ya revisados y benignos (vigilante_ignorar.txt) no alerta; CONTENCION siempre
      [ -n "$nuevos" ] && [ -f "$IGNORAR" ] && nuevos=$(echo "$nuevos" | awk -F': ' -v f="$IGNORAR" '
        BEGIN { while ((getline l < f) > 0) { sub(/[ \t#].*/, "", l); if (l != "") ign[l] = 1 } }
        { split($2, c, ","); if (!(c[20] in ign) || c[4] == "1791590554") print }')
      if [ -n "$nuevos" ]; then
        res=$(echo "$nuevos" | ruido_apt "$(apt_disparos)")
        napt=$(echo "$res" | sed -n 's/^#APT //p'); nuevos=$(echo "$res" | grep -v '^#APT ')
        [ "${napt:-0}" -gt 0 ] && dmz="apt($napt)"
      fi
      if [ -n "$nuevos" ]; then
        dmz="ALERTA($(echo "$nuevos" | wc -l))"
        alerta "DMZ: $(echo "$nuevos" | wc -l) bloqueos nuevos de Debian" "$(echo "$nuevos" | formato | tail -10)"
      fi
    else ciego=1; fi

    if [ "$ciego" = 1 ]; then fciego=$((fciego + 1)); else fciego=0; fi
    [ "$fciego" -eq 3 ] && alerta "CIEGO: 3 rondas sin poder leer Debian o pfSense (Pi 5 o VMs caidas?)"

    log "$([ "$nal" -gt 0 ] && echo "alerta($nal)" || echo ok) web=$code archivos=$arch dmz=$dmz ciego=$fciego feed=$([ -f "$WEB" ] && echo "ok($ffeed)" || echo off)"
    nal=0
  fi
  ronda=$((ronda + 1))
  sleep "$TICK"
done
log "FIN de turno: $HORAS h sin novedad"
echo "FIN: $HORAS h sin novedad"
pausa
