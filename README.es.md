# Security Lab

*[Read in English](README.md)*

Proyectos prácticos de seguridad de un laboratorio casero de una sola persona: monitoreo de red, endurecimiento, detección y trabajo de SOC. Cada carpeta es un proyecto independiente con su propio README.

| Proyecto | Qué |
|---|---|
| [`home-network-monitoring/`](home-network-monitoring/) | Un servicio web endurecido, expuesto a Internet desde una DMZ contenida de pfSense a través de un túnel a un VPS, vigilado por Security Onion, un sensor de red en una Raspberry Pi 5 (Suricata + Zeek) y un vigilante de logs en vivo |

Los scripts apuntan a un laboratorio concreto (direcciones y nombres de equipo fijos) y varios cambian reglas de firewall o la configuración del servidor: léelos antes de ejecutar nada. Los comentarios están en español.
