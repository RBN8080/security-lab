#!/usr/bin/env python3
"""Agrega lugar (ciudad, pais) y red (dueno del ASN) a cada linea del access.log de Apache.

Lee lineas por stdin y escribe: linea original + TAB + lugar + TAB + red. Consulta SOLO las
bases locales DB-IP Lite de geoip/ (geoip_actualizar.sh): ninguna IP sale del equipo.
Sin la libreria maxminddb o sin las bases, escribe "-" y avisa una vez por stderr.
En IPs de nube la ciudad es aproximada (donde el proveedor registra el rango); la red es fiable.
IP Geolocation by DB-IP (https://db-ip.com), CC BY 4.0.
Uso: ... | python -u geo.py [carpeta_geoip] | ...   (lo llama panel_bots.sh con la del taller)
"""
import glob
import ipaddress
import os
import re
import sys
import unicodedata

DIR = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "geoip")
SUFIJOS = re.compile(r"[,.]?\s+(inc|llc|l\.l\.c|ltd|limited|corporation|corp|co|gmbh|sarl|s\.a|"
                     r"s\.a\.s|b\.v|srl|plc|pte|pty|ag|oy|ab|s\.a\. de c\.v|sp\. z o\.o)\.?$", re.I)


def abrir(patron):
    try:
        import maxminddb
    except ImportError:
        return None
    archivos = sorted(glob.glob(os.path.join(DIR, patron)))
    return maxminddb.open_database(archivos[-1]) if archivos else None


def ascii(texto):
    """"Sao Paulo" en vez de "São Paulo": un acento descuadra las columnas del visor."""
    return unicodedata.normalize("NFKD", texto).encode("ascii", "ignore").decode()


def corto(org):
    for _ in range(2):  # "Amazon.com, Inc." -> "Amazon.com"; "Foo Co., Ltd." -> "Foo"
        org = SUFIJOS.sub("", org.strip())
    return org


def buscar(ip, ciudad, asn, cache):
    if ip in cache:
        return cache[ip]
    lugar = red = "-"
    try:
        dir_ip = ipaddress.ip_address(ip)
        if ip == "10.9.0.1":
            lugar = "(tunel)"
        elif dir_ip.is_private or dir_ip.is_loopback:
            lugar = "(interna)"
        else:
            r = (ciudad.get(ip) if ciudad else None) or {}
            nombre = ((r.get("city") or {}).get("names") or {}).get("en") or ""
            nombre = re.sub(r"\s*\(.*?\)", "", nombre)  # "Navi Mumbai (Rabale)" -> "Navi Mumbai"
            pais = (r.get("country") or {}).get("iso_code") or ""
            lugar = ", ".join(x for x in (nombre, pais) if x) or "-"
            s = (asn.get(ip) if asn else None) or {}
            if s.get("autonomous_system_organization"):
                red = corto(s["autonomous_system_organization"])
    except ValueError:
        pass
    cache[ip] = (ascii(lugar), ascii(red))
    return cache[ip]


def main():
    sys.stdin.reconfigure(encoding="utf-8", errors="replace")
    sys.stdout.reconfigure(encoding="utf-8", errors="replace", newline="\n")
    ciudad, asn = abrir("dbip-city-lite-*.mmdb"), abrir("dbip-asn-lite-*.mmdb")
    if not (ciudad and asn):
        print("AVISO: sin bases GeoIP (pip install --user maxminddb; bash geoip_actualizar.sh)",
              file=sys.stderr, flush=True)
    cache = {}
    while True:
        linea = sys.stdin.readline()
        if not linea:
            break
        linea = linea.rstrip("\r\n")
        lugar, red = buscar(linea.split(" ", 1)[0], ciudad, asn, cache)
        try:
            print(f"{linea}\t{lugar}\t{red}", flush=True)
        except OSError:  # el visor se cerro; en Windows llega como EINVAL, no como BrokenPipe
            os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())
            break


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
