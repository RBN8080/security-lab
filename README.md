# Security Lab

*[Leer en español](README.es.md)*

Hands-on security projects: network security monitoring, hardening, detection and SOC operations. Each folder is a self-contained project with its own README.

| Project | What |
|---|---|
| [`dmz-web-nsm/`](dmz-web-nsm/) | A hardened web service exposed to the Internet from a contained pfSense DMZ through a VPS tunnel, watched by Security Onion, a Raspberry Pi 5 network sensor (Suricata + Zeek) and a live log watcher |

The scripts target one specific lab (hard-coded addresses and hostnames) and several change firewall or server configuration: read them before running anything. Comments are in Spanish.
