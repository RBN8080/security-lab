# dmz-web-nsm

*[Leer en español](README.es.md)*

Contained web exposure with network security monitoring: a WordPress instance deliberately published to the Internet —hardened and confined to a pfSense DMZ— and the NSM stack that records who connects and what they request. Part of [Security Lab](../README.md).

## How a visit travels

```
Internet ──► VPS 203.0.113.10 (24/7)
               nginx stream :80/:443 — raw TCP, no filtering, PROXY protocol
               ufw: 22, 80, 443, 51820/udp
                  │  WireGuard 10.9.0.0/24, opened FROM the DMZ host
                  ▼
             pfSense VM ── DMZ 10.10.20.0/24
                  ▼
             Debian 13 VM 10.10.20.40
               Apache :8080/:8443 + RemoteIPProxyProtocol → real client IP in the log
               TLS terminates here (Let's Encrypt, DNS-01)
               WordPress · PHP 8.4 · MariaDB
```

Why a VPS: the upstream link sits behind carrier-grade NAT, so inbound port forwarding is impossible. The tunnel is initiated outbound from the DMZ, so no inbound port is opened on the local network.

## Containment

DMZ rules on pfSense, in order:

1. DNS and NTP to pfSense — allowed.
2. Anything to RFC 1918 (internal LAN, lab segments, storage) — **blocked and logged**. A hit means someone inside the DMZ is trying to move.
3. Internet 80/443 — disabled; opened briefly only to patch.
4. UDP 51820 to the VPS — allowed (the tunnel).
5. Everything else — blocked.

A compromised site stays boxed in: it can answer visitors and nothing more.

Approach: lock everything down before opening, then remove locks one at a time to observe. Admin panel only from local addresses, xmlrpc off, no user enumeration, no PHP in uploads, security headers, PHP `disable_functions`; ModSecurity + OWASP CRS in detection-only mode; fail2ban. Each layer ships with its revert.

## Watching

- **Security Onion** (VM) sees the DMZ through a capture interface and receives pfSense block events by syslog.
- **Raspberry Pi 5** runs Suricata + Zeek on a managed switch mirror (SPAN) port and ships to Security Onion with Elastic Agent. It only runs while the SOC answers (`10_SENSOR_PI5/auto/`).
- **`monitoreo/`** — one command, `monitor.sh`: live panel, watcher, containment alarm, pre-flight check. Together they stream Apache's access log live and alert on bursts, POSTs, 5xx, odd `.php` 200s, file changes under the web root, DMZ egress attempts, outages and loss of visibility; repeated campaigns are grouped. Each line shows city, country and network owner (ASN) from a local DB-IP Lite database —no address is sent to third parties— and whether the address is new or returning; when a source goes quiet after a burst, a one-line plain-language summary says what it was after and whether it got anything. Blind spots are written down per detection, Palantir ADS style (`monitoreo/puntos_ciegos.md`).

## First full day, in aggregate

- About 5,100 requests from 119 IPs in 8 hours of live watch; 15 alerts; **no intrusion** (no sensitive 200, no file change, no unexplained egress).
- What bots want: forgotten secrets — `.env`, `.git`, cloud and mail credentials, `docker-compose` — in bursts of seconds. Not the site itself.
- Also: webshell hunting; exploitation attempts by the RedTail mining botnet (PHP-CGI CVE-2024-4577, PHPUnit CVE-2017-9841, Apache traversal CVE-2021-41773, Docker API); AndroxGh0st-like mail-credential hunting; probes for AI gateway configs (LiteLLM, Bedrock) and SSRF to cloud metadata.
- VPS door, 6 hours: 545 IPs, ~1,000 firewall blocks (Telnet first), 99 invented SSH users, 0 logins.

## Repository map

| Path | What |
|---|---|
| `10_SENSOR_PI5/` | Pi 5 network sensor: Suricata/Zeek config, provisioning, Fleet policy, on/off by SOC health |
| `20_WEB_DMZ/costura3/` | Publishing the DMZ: pfSense NAT, egress lockdown |
| `20_WEB_DMZ/https/` | Certificate by DNS-01 |
| `20_WEB_DMZ/edge/` | VPS: WireGuard + nginx stream + ufw; Apache vhost with PROXY protocol |
| `20_WEB_DMZ/debian_endurecer/` · `blindaje_fuerte/` · `waf_fail2ban/` | Hardening layers, each with apply and revert |
| `20_WEB_DMZ/wordpress/` | Host-header allowlist |
| `20_WEB_DMZ/monitoreo/` | `monitor.sh`: live panel, watcher, containment alarm, pre-flight check, GeoIP update; blind spots |

## Before running anything

These scripts were written for one specific lab: addresses, hostnames and SSH aliases are hard-coded, and several change firewall or web-server configuration. Read them first. Comments are in Spanish. References such as `D-14` or `§7.16` point to the private design log. `203.0.113.10` and `sitio-ejemplo.duckdns.org` are example values.
