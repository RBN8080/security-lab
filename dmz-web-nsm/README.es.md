# dmz-web-nsm

*[Read in English](README.md)*

Exposición web contenida con monitoreo de seguridad de red: un WordPress publicado a Internet a propósito —endurecido y confinado en una DMZ de pfSense— y el stack NSM que registra quién se conecta y qué pide. Parte de [Security Lab](../README.es.md).

## Recorrido de una visita

```
Internet ──► VPS 203.0.113.10 (24/7)
               nginx stream :80/:443 — TCP crudo, sin filtrar, PROXY protocol
               ufw: 22, 80, 443, 51820/udp
                  │  WireGuard 10.9.0.0/24, lo ABRE el servidor de la DMZ
                  ▼
             VM pfSense ── DMZ 10.10.20.0/24
                  ▼
             VM Debian 13 10.10.20.40
               Apache :8080/:8443 + RemoteIPProxyProtocol → IP real del visitante en el log
               TLS termina aquí (Let's Encrypt, DNS-01)
               WordPress · PHP 8.4 · MariaDB
```

Por qué un VPS: el enlace de salida está detrás de CGNAT y el reenvío de puertos entrante es imposible. El túnel se inicia desde la DMZ hacia afuera, así que no se abre ningún puerto entrante en la red local.

## Contención

Reglas de la DMZ en pfSense, en orden:

1. DNS y NTP a pfSense — permitido.
2. Cualquier cosa hacia RFC 1918 (LAN interna, segmentos del laboratorio, almacenamiento) — **bloqueado y registrado**. Un registro aquí significa que alguien dentro de la DMZ intenta moverse.
3. Internet 80/443 — desactivado; se abre un rato solo para parchar.
4. UDP 51820 al VPS — permitido (el túnel).
5. Todo lo demás — bloqueado.

Si toman el sitio, queda encajonado: puede contestar visitas y nada más.

Enfoque: cerrar todo antes de abrir y luego quitar candados uno a uno para observar. Panel solo desde direcciones locales, xmlrpc apagado, sin enumeración de usuarios, sin PHP en uploads, cabeceras de seguridad, `disable_functions` de PHP; ModSecurity + OWASP CRS en modo solo detección; fail2ban. Cada capa trae su forma de revertir.

## Vigilancia

- **Security Onion** (VM) ve la DMZ por una interfaz de captura y recibe por syslog los bloqueos de pfSense.
- **Raspberry Pi 5** corre Suricata + Zeek sobre el puerto espejo (SPAN) de un switch administrado y envía a Security Onion con Elastic Agent. Solo corre mientras el SOC responde (`10_SENSOR_PI5/auto/`).
- **`panel_bots/`** — vigilante en shell en el host. Lee en vivo el log de Apache y alerta por ráfagas, POST, 5xx, 200 en `.php` raros, cambios de archivos en la raíz web, intentos de salida de la DMZ, caídas y pérdida de visibilidad; agrupa campañas repetidas. Cada línea muestra ciudad, país y dueño de la red (ASN) desde una base local DB-IP Lite, así que ninguna dirección se envía a terceros. Sus puntos ciegos están escritos por detección, al estilo ADS de Palantir (`panel_bots/puntos_ciegos.md`).

## Primer día completo, en agregado

- Unas 5 100 peticiones de 119 IPs en 8 horas de vigilancia en vivo; 15 alertas; **ninguna intrusión** (ningún 200 sensible, ningún archivo cambiado, ninguna salida sin explicar).
- Lo que buscan los bots: secretos olvidados —`.env`, `.git`, credenciales de nube y de correo, `docker-compose`— en ráfagas de segundos. No el sitio en sí.
- También: búsqueda de webshells; intentos de explotación de la botnet minera RedTail (PHP-CGI CVE-2024-4577, PHPUnit CVE-2017-9841, traversal de Apache CVE-2021-41773, API de Docker); búsqueda de credenciales de correo al estilo AndroxGh0st; sondeos de configuraciones de pasarelas de IA (LiteLLM, Bedrock) y SSRF a metadatos de nube.
- Puerta del VPS, 6 horas: 545 IPs, ~1 000 bloqueos del firewall (Telnet primero), 99 usuarios SSH inventados, 0 entradas.

## Mapa del repositorio

| Ruta | Qué |
|---|---|
| `10_SENSOR_PI5/` | Sensor de red en la Pi 5: config de Suricata/Zeek, aprovisionamiento, política de Fleet, encendido según el SOC |
| `20_WEB_DMZ/costura3/` | Publicar la DMZ: NAT de pfSense, cierre de salida, verificación previa, alarma de contención |
| `20_WEB_DMZ/https/` | Certificado por DNS-01 |
| `20_WEB_DMZ/edge/` | VPS: WireGuard + nginx stream + ufw; vhost de Apache con PROXY protocol |
| `20_WEB_DMZ/debian_endurecer/` · `blindaje_fuerte/` · `waf_fail2ban/` | Capas de endurecimiento, cada una con aplicar y revertir |
| `20_WEB_DMZ/wordpress/` | Lista blanca de cabecera Host |
| `20_WEB_DMZ/panel_bots/` | Vigilante en vivo y sus puntos ciegos |

## Antes de ejecutar nada

Estos scripts se escribieron para un laboratorio concreto: direcciones, nombres de equipo y alias SSH van fijos, y varios cambian reglas de firewall o la configuración del servidor web. Léelos primero. Referencias como `D-14` o `§7.16` apuntan al registro de diseño privado. `203.0.113.10` y `sitio-ejemplo.duckdns.org` son valores de ejemplo.
