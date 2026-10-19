#!/usr/bin/env python3
"""Visor del panel de bots: pinta en columnas cada peticion del access.log de Apache.

Por peticion: hora, IP, VISTA (NUEVA = primera vez que viene; VUELVE = ya vino otro dia;
xN = peticiones de hoy), LUGAR y RED (bases locales DB-IP Lite: ninguna IP sale del equipo),
codigo, ETIQUETA, metodo, ruta y navegador. Cuando una IP deja de pedir RAFAGA_PAUSA segundos
y llevaba RAFAGA_MIN peticiones o mas, escribe un resumen de la rafaga en palabras simples.
Solo lee: no cambia nada en ninguna maquina.

Uso (lo llama panel_bots.sh):
  ... | python -u panel_bots.py --geoip DIR [--historial access_vivo.log] [--mostrar N]
  --historial: log del taller; da el "ya vino otro dia" y las ultimas N lineas de contexto.
Ancho de la ventana: variable COLS. Sin colores: NO_COLOR=1.
En IPs de nube la ciudad es aproximada (donde el proveedor registra el rango); la red es fiable.
IP Geolocation by DB-IP (https://db-ip.com), CC BY 4.0.
"""
import argparse
import collections
import glob
import ipaddress
import os
import queue
import re
import sys
import threading
import time
import unicodedata

RAFAGA_PAUSA = 20   # s sin peticiones de esa IP para dar la rafaga por terminada
RAFAGA_MIN = 10     # peticiones minimas para resumirla
UA_PROPIO = "vigilante-lab"

MESES = {m: i for i, m in enumerate("Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split(), 1)}
LINEA = re.compile(r'^(\S+) \S+ \S+ \[([^\]]+)\] "(.*)" (\d{3}|-) \S+(?: "(.*)" "(.*)")?$')
PETICION = re.compile(r"^([A-Za-z_]+) (\S+)(?: HTTP/[0-9.]+)?$")
ATAQUE = re.compile(r"(\.\./|%2e%2e|%ad|allow_url_include|auto_prepend_file|eval-stdin|invokefunction"
                    r"|pearcmd|/bin/(ba)?sh|cgi-bin|base64_decode|union.+select|<script|\$\{jndi"
                    r"|/containers/json|/images/json|169\.254\.169\.254|=(https?|php|data|file):)")
SONDEO = re.compile(r"(/\.env|/\.git|/\.aws|/\.ssh|/\.docker|/\.ds_store|/\.ht|wp-config|phpmyadmin"
                    r"|/vendor/|\.bak|\.sql|\.old|\.swp|\.zip|\.tar|backup|readme|phpinfo"
                    r"|server-(status|info)|config\.(json|js|php|ya?ml)|composer\.(json|lock)"
                    r"|package(-lock)?\.json|yarn\.lock|credentials|secrets?\.|settings\."
                    r"|docker-compose|\.(map|ya?ml|ini|log|conf|cfg|toml|key|pem)$)")
PORTADA = re.compile(r"^/(index\.php)?$")
VACIOS = re.compile(r"^/wp-content/((themes|plugins|uploads)/)?index\.php$")
SUFIJOS = re.compile(r"[,.]?\s+(inc|llc|l\.l\.c|ltd|limited|corporation|corp|co|gmbh|sarl|s\.a"
                     r"|s\.a\.s|b\.v|srl|plc|pte|pty|ag|oy|ab|s\.a\. de c\.v|sp\. z o\.o)\.?$", re.I)

COLOR = {"ok": "32", "PROPIO": "2", "SONDEO": "33", "WEBSHELL": "33;1", "ATAQUE": "31;1",
         "LOGIN": "35", "XMLRPC": "35", "METODO": "36", "TLS": "2", "ROTA": "2", "BLOQUEADO": "31",
         "NUEVA": "36;1", "VUELVE": "35;1"}
QUE_BUSCABA = {"SONDEO": "secretos y archivos olvidados", "WEBSHELL": "puertas traseras .php",
               "ATAQUE": "intentos de ejecutar codigo", "LOGIN": "panel de WordPress",
               "XMLRPC": "panel de WordPress", "METODO": "metodos raros", "404": "rutas que no existen",
               "BLOQUEADO": "zonas bloqueadas", "ok": "paginas normales", "TLS": "conexiones rotas",
               "ROTA": "conexiones rotas"}
LEYENDA = [
    "ok=visita normal  SONDEO=busca secretos o archivos olvidados  WEBSHELL=busca puertas traseras .php",
    "ATAQUE=intenta ejecutar algo  LOGIN/XMLRPC=panel de WordPress  METODO=metodo raro (OPTIONS, CONNECT...)",
    "TLS/ROTA=conexion rota o en otro idioma  BLOQUEADO=403  PROPIO=latido del vigilante  !!=200 a algo sospechoso: revisar",
    "VISTA: NUEVA=primera vez que viene  VUELVE=ya vino otro dia  xN=peticiones de hoy   >>=resumen de una rafaga",
    "LUGAR=ciudad y pais (aproximado si es una nube)  RED=dueno de la IP (Microsoft, Oracle, Cloudflare...)",
]


def ascii(texto):
    """"Sao Paulo" en vez de "São Paulo": un acento descuadra las columnas."""
    return unicodedata.normalize("NFKD", texto).encode("ascii", "ignore").decode()


def corta(s, n):
    return s if len(s) <= n else s[:n - 1] + "~"


class Geo:
    """Lugar y red de una IP, desde las bases locales; con cache por IP."""

    def __init__(self, carpeta):
        self.ciudad = self.asn = None
        try:
            import maxminddb
            c = sorted(glob.glob(os.path.join(carpeta, "dbip-city-lite-*.mmdb")))
            a = sorted(glob.glob(os.path.join(carpeta, "dbip-asn-lite-*.mmdb")))
            self.ciudad = maxminddb.open_database(c[-1]) if c else None
            self.asn = maxminddb.open_database(a[-1]) if a else None
        except ImportError:
            pass
        self.cache = {}

    def ok(self):
        return bool(self.ciudad and self.asn)

    def __call__(self, ip):
        if ip in self.cache:
            return self.cache[ip]
        lugar = red = "-"
        try:
            dir_ip = ipaddress.ip_address(ip)
            if ip == "10.9.0.1":
                lugar = "(tunel)"
            elif dir_ip.is_private or dir_ip.is_loopback:
                lugar = "(interna)"
            else:
                r = (self.ciudad.get(ip) if self.ciudad else None) or {}
                nombre = ((r.get("city") or {}).get("names") or {}).get("en") or ""
                nombre = re.sub(r"\s*\(.*?\)", "", nombre)  # "Navi Mumbai (Rabale)" -> "Navi Mumbai"
                pais = (r.get("country") or {}).get("iso_code") or ""
                lugar = ", ".join(x for x in (nombre, pais) if x) or "-"
                s = (self.asn.get(ip) if self.asn else None) or {}
                org = s.get("autonomous_system_organization") or ""
                for _ in range(2):  # "Amazon.com, Inc." -> "Amazon.com"
                    org = SUFIJOS.sub("", org.strip())
                red = org or "-"
        except ValueError:
            pass
        self.cache[ip] = (ascii(lugar), ascii(red))
        return self.cache[ip]


def etiqueta(m, p, code, req, ua):
    lp = p.lower()
    if UA_PROPIO in ua:
        return "PROPIO"
    if m == "-":
        return "TLS" if req.startswith("\\x16\\x03") else "ROTA"
    if m not in ("GET", "HEAD", "POST"):
        return "METODO"
    if ATAQUE.search(lp):
        return "ATAQUE"
    if "wp-login.php" in lp:
        return "LOGIN"
    if "xmlrpc.php" in lp:
        return "XMLRPC"
    if SONDEO.search(lp):
        return "SONDEO"
    if ".php" in lp and code == "404":
        return "WEBSHELL"
    if code in ("403", "401"):
        return "BLOQUEADO"
    if code == "404":
        return "404"
    if code[:1] in ("2", "3"):
        return "ok"
    return code


def analizar(linea, geo):
    """Una linea del log -> dict, o None si no tiene el formato combinado."""
    x = LINEA.match(linea)
    if not x:
        return None
    ip, ts, req, code, ua = x.group(1), x.group(2), x.group(3), x.group(4), x.group(6) or ""
    try:  # "19/Oct/2026:10:19:43 -0600"
        dia, hms = ts.split(":", 1)[0], ts.split(":", 1)[1].split(" ")[0]
        d, mes, a = dia.split("/")
        h, mi, s = (int(v) for v in hms.split(":"))
        seg = time.mktime((int(a), MESES[mes], int(d), h, mi, s, 0, 0, -1))
    except (ValueError, KeyError, IndexError):
        dia, hms, seg = "?", "?", 0
    y = PETICION.match(req)
    m, p = (y.group(1), y.group(2)) if y else ("-", "(" + req + ")")
    tag = etiqueta(m, p, code, req, ua)
    base = p.split("?", 1)[0]
    alerta = (code.startswith("2") and tag in ("SONDEO", "WEBSHELL", "ATAQUE")
              and not PORTADA.match(base) and not VACIOS.match(base))
    lugar, red = geo(ip)
    return {"ip": ip, "dia": dia, "hora": hms, "seg": seg, "m": m, "p": p, "code": code, "ua": ua,
            "tag": tag, "alerta": alerta, "lugar": lugar, "red": red}


class Memoria:
    """Que IPs vinieron, cuantas veces hoy y en que otros dias."""

    def __init__(self):
        self.dias = collections.defaultdict(set)
        self.hoy = collections.Counter()

    def vista(self, d):
        ip, dia = d["ip"], d["dia"]
        otros = self.dias[ip] - {dia}
        self.hoy[(ip, dia)] += 1
        n = self.hoy[(ip, dia)]
        self.dias[ip].add(dia)
        d["otros_dias"] = len(otros)
        if n == 1:
            d["vista"] = "VUELVE" if otros else "NUEVA"
        else:
            d["vista"] = "x%d" % n
        return d


class Pantalla:
    def __init__(self, cols, color):
        self.color = color
        self.wl = 26 if cols >= 110 else 0     # LUGAR
        self.wr = 16 if cols >= 130 else 0     # RED
        self.wua = 24 if cols >= 165 else 0    # NAVEGADOR
        fijo = 8 + 2 + 15 + 1 + 6 + 1 + 3 + 2 + 9 + 1 + 7 + 1   # hasta METODO; 4 de reserva para " !!"
        self.wp = max(20, cols - fijo - (self.wl + 1 if self.wl else 0) - (self.wr + 1 if self.wr else 0)
                      - (self.wua + 3 if self.wua else 0) - 4)
        self.filas = 0

    def pinta(self, txt, c):
        return "\033[%sm%s\033[0m" % (c, txt) if (self.color and c) else txt

    def escribe(self, texto):
        try:
            print(texto, flush=True)
        except OSError:  # la ventana se cerro (en Windows llega como EINVAL)
            os._exit(0)

    def cabecera(self):
        t = "%-8s  %-15s %-6s " % ("HORA", "IP", "VISTA")
        if self.wl:
            t += "%-*s " % (self.wl, "LUGAR")
        if self.wr:
            t += "%-*s " % (self.wr, "RED")
        t += "%-3s  %-9s %-7s %-*s" % ("COD", "ETIQUETA", "METODO", self.wp, "RUTA")
        if self.wua:
            t += " | NAVEGADOR"
        self.escribe(self.pinta(t, "1"))

    def inicio(self):
        for linea in LEYENDA:
            self.escribe(self.pinta(linea, "2"))
        self.cabecera()

    def nota(self, texto):
        self.escribe(self.pinta(texto, "2"))

    def fila(self, d):
        v = d["vista"]
        t = "%-8s  %-15s " % (d["hora"], d["ip"]) + self.pinta("%-6s" % v, COLOR.get(v, "2")) + " "
        if self.wl:
            t += "%-*s " % (self.wl, corta(d["lugar"], self.wl))
        if self.wr:
            t += "%-*s " % (self.wr, corta(d["red"], self.wr))
        t += "%-3s  " % d["code"] + self.pinta("%-9s" % d["tag"], COLOR.get(d["tag"], ""))
        t += " %-7s %-*s" % (corta(d["m"], 7), self.wp, corta(d["p"], self.wp))
        if self.wua:
            t += " | " + corta(d["ua"] if d["ua"] not in ("", "-") else "(sin navegador)", self.wua)
        if d["alerta"]:
            t += " " + self.pinta("!!", "31;1")
        self.escribe(t)
        self.filas += 1
        if self.filas % 40 == 0:
            self.cabecera()


class Rafagas:
    """Junta las peticiones seguidas de una misma IP y las resume cuando termina la rafaga.
    Lo que llega por Cloudflare (otro dominio apuntando al VPS) se junta como una sola fuente."""

    def __init__(self, pantalla):
        self.pantalla = pantalla
        self.abiertas = {}

    @staticmethod
    def clave(d):
        if d["tag"] == "PROPIO" or d["lugar"] in ("(tunel)", "(interna)"):
            return None
        return "cloudflare" if d["red"].startswith("Cloudflare") else d["ip"]

    def agrega(self, d):
        k = self.clave(d)
        if k is None:
            return
        r = self.abiertas.get(k)
        if r and d["seg"] - r["fin"] > RAFAGA_PAUSA:
            self.cierra(k)
            r = None
        if r is None:
            r = self.abiertas[k] = {"ini": d["seg"], "fin": d["seg"], "hora_ini": d["hora"], "n": 0,
                                    "ips": set(), "tags": collections.Counter(), "codes": collections.Counter(),
                                    "ejemplos": collections.defaultdict(list), "alertas": 0,
                                    "lugar": d["lugar"], "red": d["red"], "vista": d["vista"],
                                    "otros_dias": d["otros_dias"]}
        r["fin"], r["hora_fin"], r["reloj"] = d["seg"], d["hora"], time.time()
        r["n"] += 1
        r["ips"].add(d["ip"])
        r["tags"][d["tag"]] += 1
        r["codes"][d["code"]] += 1
        r["alertas"] += d["alerta"]
        ej = r["ejemplos"][d["tag"]]
        if len(ej) < 2 and d["p"] not in ej:
            ej.append(d["p"])

    def vence(self, ahora):
        for k in [k for k, r in self.abiertas.items() if ahora - r["reloj"] > RAFAGA_PAUSA]:
            self.cierra(k)

    def cierra_todas(self):
        for k in list(self.abiertas):
            self.cierra(k)

    def cierra(self, k):
        r = self.abiertas.pop(k)
        if r["n"] < RAFAGA_MIN:
            return
        if k == "cloudflare":
            quien, donde = "%d IPs de Cloudflare (otro dominio que apunta al VPS)" % len(r["ips"]), ""
        else:
            quien = k
            donde = " - ".join(x for x in (r["red"], r["lugar"]) if x and x != "-")
        if r["otros_dias"]:
            historia = "ya vino %d dia%s antes" % (r["otros_dias"], "" if r["otros_dias"] == 1 else "s")
        else:
            historia = "primera vez" if r["vista"] == "NUEVA" else "ya habia venido hoy"
        top = r["tags"].most_common(3)
        buscaba = ", ".join("%s %d" % (QUE_BUSCABA.get(t, t), n) for t, n in top)
        ejemplos = ", ".join(corta(e, 50) for e in r["ejemplos"][top[0][0]])
        codigos = ", ".join("%sx%d" % (c, n) for c, n in r["codes"].most_common(3))
        if r["alertas"]:
            resultado, c = "OJO: %d respuestas 200 sospechosas, revisar" % r["alertas"], "31;1"
        elif any(k.startswith("2") for k in r["codes"]):
            resultado, c = "no consiguio nada (sus 200 fueron paginas normales)", "33;1"
        else:
            resultado, c = "no consiguio nada", "33;1"
        dur = int(r["fin"] - r["ini"])
        p = self.pantalla
        p.escribe(p.pinta(">> RAFAGA %s-%s  %s  %s  (%s)" % (r["hora_ini"], r["hora_fin"], quien, donde,
                                                              historia), c))
        p.escribe(p.pinta("   %d peticiones en %d s: %s. Ej: %s. Resultado: %s (%s)"
                          % (r["n"], dur, buscaba, ejemplos, resultado, codigos), c))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--geoip", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "geoip"))
    ap.add_argument("--historial")
    ap.add_argument("--mostrar", type=int, default=40)
    args = ap.parse_args()
    sys.stdin.reconfigure(encoding="utf-8", errors="replace")
    sys.stdout.reconfigure(encoding="utf-8", errors="replace", newline="\n")
    try:
        cols = int(os.environ.get("COLS", "120"))
    except ValueError:
        cols = 120

    geo, memoria = Geo(args.geoip), Memoria()
    pantalla = Pantalla(max(cols, 60), not os.environ.get("NO_COLOR"))
    rafagas = Rafagas(pantalla)
    pantalla.inicio()
    if not geo.ok():
        pantalla.nota("AVISO: sin bases GeoIP (pip install --user maxminddb; bash geoip_actualizar.sh)")

    # El historial solo alimenta la memoria; de el se muestran las ultimas N lineas como contexto
    if args.historial and os.path.isfile(args.historial):
        ultimas = collections.deque(maxlen=max(args.mostrar, 0))
        with open(args.historial, encoding="utf-8", errors="replace") as f:
            for linea in f:
                d = analizar(linea.rstrip("\r\n"), geo)
                if d:
                    ultimas.append(memoria.vista(d))
        if ultimas:
            pantalla.nota("--- ultimas %d del historial ---" % len(ultimas))
            for d in ultimas:
                pantalla.fila(d)
        pantalla.nota("--- en vivo ---")

    cola = queue.Queue()

    def lector():
        for linea in iter(sys.stdin.readline, ""):
            cola.put(linea)
        cola.put(None)

    threading.Thread(target=lector, daemon=True).start()
    while True:
        try:
            linea = cola.get(timeout=1)
        except queue.Empty:
            rafagas.vence(time.time())
            continue
        if linea is None:
            break
        d = analizar(linea.rstrip("\r\n"), geo)
        if d is None:
            pantalla.nota(corta("?? " + linea.rstrip("\r\n"), cols - 1))
            continue
        pantalla.fila(memoria.vista(d))
        rafagas.agrega(d)
        rafagas.vence(time.time())
    rafagas.cierra_todas()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
