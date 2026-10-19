# Vigilante: puntos ciegos y supuestos

Siguiendo el marco ADS de Palantir: cómo puede no disparar cada detección y cómo la burlaría un adversario. Revisado 2026-10-17 (v3).

## Supuestos
- El host está encendido, despierto y con la sesión abierta. Si se suspende o reinicia, se paran el vigilante y el despertador, y **nadie avisa** (no hay latido fuera de banda).
- La Pi 5 está arriba: todas las lecturas pasan por ella. Si cae, CIEGO avisa a los 15 min.
- `panel_bots.sh` (o `transmitir_vivo.sh`) sigue abierto alimentando `logs/access_vivo.log`. Si cae, FEED avisa a los 10 min.
- La hora de pfSense (UTC) y la de Debian están sincronizadas por NTP; la regla de apt compara ambas.

## WEB (access.log de Apache en vivo)
| No dispara si... | Cómo lo aprovecha un adversario |
|---|---|
| Hay menos de 10 respuestas 4xx en una tanda de 30 s | Escaneo lento (1 petición por minuto) |
| La ráfaga tiene 10–49 respuestas 4xx y nada más (sin POST, 5xx ni 200 en .php): se anota en ataques_auto.log pero NO alerta (desde 17:25) | Partir un escaneo en tandas de menos de 50; solo se ve en la revisión diaria |
| La ráfaga repite ≥ 90 % de las rutas de una campaña ya vista (`reportes/campanas/`), sin POST, 5xx ni 200 fuera de portada/estáticos/index.php vacíos: se anota sin alertar (desde 19:00) | Reusar una lista conocida y esconder el hallazgo en un 404/403 o en un estático; solo se ve en la revisión diaria |
| Un 200 en un `index.php` vacío de wp-content no cuenta como ".php raro" | Ninguno mientras no cambien: ARCHIVOS los vigila por hash |
| El tráfico llega por Cloudflare (dominio ajeno): la IP del log es de Cloudflare | Atribuir: el origen real solo queda en ModSecurity (CF-Connecting-IP), y este no registra 404 |
| Los 4xx son a `/favicon.ico` o `/apple-touch-icon*.png` (no cuentan desde 14:57; los pide cualquier navegador) | Ninguno útil: esas rutas no exponen nada |
| Solo pide rutas que existen (200/301) | Reconocimiento de páginas reales, enumeración por la portada |
| El ataque entra por `/index.php` con 200 (excluido) o por GET con parámetros | Inyección en endpoints válidos de WP (`?rest_route=`, `?s=`) |
| La conexión se rompe antes de la petición (sale como 10.9.0.1, excluida) | Ataques al TLS o peticiones malformadas |
| El tráfico no llega a Apache | Ataques al nginx stream o al SSH del droplet (no los mira WEB) |
| ModSecurity detecta pero el vigilante no lee `modsec_audit.log` | Carga útil en una petición que da 200 |

## ARCHIVOS (huellas de /var/www/html cada 5 min)
| No dispara si... | Cómo lo aprovecha un adversario |
|---|---|
| El cambio está fuera de /var/www/html | Webshell o binario en /tmp, /var/tmp, /dev/shm, cron |
| El cambio va en la base de datos | Defacement o JS malicioso inyectado en posts u opciones de WP |
| El archivo vive menos de 5 min | Crear, ejecutar y borrar entre dos rondas |
| El archivo es NOLEGIBLE (solo se lista, no se hashea) | Modificar un archivo que el usuario de lectura no puede leer |

## DMZ (bloqueos de pfSense en em2)
| No dispara si... | Cómo lo aprovecha un adversario |
|---|---|
| El tráfico está PERMITIDO: DNS y NTP a pfSense, UDP 51820 al droplet | **Exfiltración por túnel DNS** (el mayor hueco) |
| El destino está en `vigilante_ignorar.txt` | C2 alojado en esas IPs (api.wordpress.org, Let's Encrypt): improbable |
| tcp/80 a Fastly dentro de los 20 min tras un disparo de apt | Baliza a un dominio en Fastly sincronizada con apt (dos ventanas al día) |
| Hay más de 500 bloqueos en una ronda | Se pierde el detalle (la alerta sí salta) |

## CAIDA / CIEGO / despertador
- CAIDA tarda 15 min (3 rondas) y solo mira el código de la portada: un defacement que sigue dando 200 no la dispara.
- El despertador solo detecta que el vigilante calla; si sigue escribiendo pero lee datos viejos, no avisa.
- CORREGIDO 21:30: la ronda completa (ARCHIVOS, DMZ, CAIDA) se contaba por vueltas del bucle. Una ráfaga web retiene hasta 5 min esperando a que acabe y valía una sola vuelta, así que un ataque largo aplazaba ARCHIVOS/DMZ (21:14–21:28 sin revisar: el ruido tapaba justo lo importante). Ahora va por reloj: como mucho ~5.5 min entre rondas aunque haya ráfagas seguidas. El hueco de 21:14–21:28 se revisó a mano y estaba limpio.

## Qué cerraría los huecos mayores (sin aplicar)
1. Túnel DNS: registrar consultas en el resolver de pfSense y alertar por volumen o longitud de nombre desde 10.10.20.40.
2. Escaneo lento: contar 4xx por IP en ventana de 1 h, no por tanda.
3. Base de datos: huella de `wp_posts`/`wp_options` (necesita sudo) o mirar cambios de contenido en la portada.
4. Latido fuera de banda: un chequeo desde el droplet que avise si el host deja de responder.
