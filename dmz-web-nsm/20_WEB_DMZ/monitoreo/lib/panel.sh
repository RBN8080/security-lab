#!/usr/bin/env bash
# monitor.sh panel — EN VIVO, una sola ventana. Pide la clave sudo de Debian una vez (la verifica, no la
# guarda), muestra cada peticion con visor.py y ADEMAS guarda el log en el taller para el vigilante.
# Si se cae la conexion, reconecta. Si abres dos paneles, solo uno guarda el log. Ctrl+C para salir.
# visor.py: LUGAR siempre; METODO, RED y NAVEGADOR segun el ancho; al redimensionar redibuja todo.
# LUGAR y RED salen de bases locales DB-IP (monitor.sh geoip): ninguna IP sale del equipo.
. "$(dirname "${BASH_SOURCE[0]}")/comun.sh"
CANDADO="$DATOS/logs/.panel_guarda"
ancho_tty() { local s; s=$(stty size </dev/tty 2>/dev/null) || return 1; echo "${s#* }"; }
COLS=${COLS:-$(ancho_tty || tput cols 2>/dev/null || echo 120)}

limpiar() {
  [ "${CANDADO_MIO:-}" = si ] && { rm -f "$CANDADO/pid"; rmdir "$CANDADO" 2>/dev/null; }
  [ -n "${ANCHO_ARCH:-}" ] && rm -f "$ANCHO_ARCH" "$ANCHO_ARCH.tmp"
  kill $(hijos $$) 2>/dev/null
}
trap limpiar EXIT
trap 'exit 130' INT TERM

command -v python >/dev/null 2>&1 && [ -f "$LIB/visor.py" ] || fallo "falta Python o visor.py"
clave_valida

# Guarda el log un solo panel (candado con su PID)
GUARDA=si
if mkdir "$CANDADO" 2>/dev/null || ! kill -0 "$(cat "$CANDADO/pid" 2>/dev/null)" 2>/dev/null; then
  echo $$ > "$CANDADO/pid"; CANDADO_MIO=si   # libre, o era de un panel que ya no existe
else
  GUARDA=no; echo "Otro panel ya guarda el log: este solo muestra."
fi
guardar() { if [ "$GUARDA" = si ]; then tee -a "$ARCH"; else cat; fi; }

# El access.log de Debian en vivo; si la conexion se cae, reintenta. -F sigue al archivo tras la rotacion
transmitir() {
  while true; do
    printf '%s\n' "$PW" | debian 'read -r P; echo "$P" | sudo -S -p "" tail -n 0 -F /var/log/apache2/access.log'
    echo "$(date +%T) conexion con Debian caida; reintento en 10 s (Ctrl+C para salir)" >&2
    sleep 10
  done
}

# El ancho de la ventana se sigue en vivo: el visor lo lee de este archivo
ANCHO_ARCH=$(mktemp "${TMPDIR:-/tmp}/panel_ancho.XXXXXX"); echo "$COLS" > "$ANCHO_ARCH"
( while sleep 1; do a=$(ancho_tty) && echo "$a" > "$ANCHO_ARCH.tmp" && mv -f "$ANCHO_ARCH.tmp" "$ANCHO_ARCH"; done ) &

echo "== PANEL EN VIVO (Ctrl+C para salir) =="
# El historial se lee hasta el tamano de antes de conectar: lo que guarde el panel no se cuenta dos veces.
# La transmision se arranca desde ESTE shell (fd 3) para que limpiar() la encuentre si el visor muere.
# El visor (Python de Windows) escribe a una tuberia y cat a la ventana: directo a mintty se caia.
TAM=$(stat -c %s "$ARCH" 2>/dev/null || echo 0)
exec 3< <(transmitir | guardar)
COLS="$COLS" python -u "$LIB/visor.py" --geoip "$(win "$DATOS/geoip")" --historial "$(win "$ARCH")" \
  --historial-bytes "$TAM" --mostrar 20 --ancho-archivo "$(win "$ANCHO_ARCH")" <&3 | cat
fallo "el visor se detuvo (codigo ${PIPESTATUS[0]}). Si ves un error arriba, copialo y avisame."
