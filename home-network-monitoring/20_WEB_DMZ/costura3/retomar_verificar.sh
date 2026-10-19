#!/usr/bin/env bash
# Costura 3 - Verificacion al RETOMAR. SOLO LECTURA: no cambia nada.
# Antes, encender: pfSense -> Debian -> Security Onion (SO tarda 5-10 min en estar listo).
# La Pi 5 entra sola por WireGuard en cuanto pfSense arranca.
# Uso (Git Bash en el host):  bash "D:/VMware_LAB/_lab/costura3/retomar_verificar.sh"
ok(){ echo "  [OK]  $*"; }; mal(){ echo "  [!!]  $*"; }
S="-o BatchMode=yes -o ConnectTimeout=8"

echo "=== 1. Host (Fase 2)"
grep -q '^80 = 192.168.85.128:80' /c/ProgramData/VMware/vmnetnat.conf \
  && ok "NAT de VMware: TCP 80 -> pfSense 192.168.85.128" || mal "NAT de VMware SIN la linea del 80"
R=$(powershell.exe -NoProfile -Command "\$r = Get-NetFirewallRule -DisplayName 'Costura3 HTTP (TCP 80 -> pfSense)' -ErrorAction SilentlyContinue; if (\$r -and \$r.Enabled -eq 'True') {'si'} else {'no'}" | tr -d '\r')
[ "$R" = si ] && ok "Firewall de Windows: regla 'Costura3 HTTP' activa" || mal "Falta o esta apagada la regla 'Costura3 HTTP'"

echo "=== 2. Pi 5 y tunel"
ssh $S rpi5 true 2>/dev/null && ok "Pi 5 accesible (ssh rpi5)" || { mal "Pi 5 no responde: no se puede seguir"; exit 1; }
ssh $S rpi5 'ping -c1 -W3 10.10.10.1 >/dev/null' && ok "Tunel WireGuard al lab" || mal "Tunel caido (pfSense apagado o arrancando?)"

echo "=== 3. pfSense (Fase 1, contencion y salida cerrada)"
P=$(ssh $S rpi5 "ssh $S pfsense 'pfctl -sn; echo ===; pfctl -sr'" 2>/dev/null)
echo "$P" | grep -q 'port = http -> 10.10.20.40' && ok "Port-forward WAN tcp/80 -> 10.10.20.40" || mal "No esta el port-forward de la Fase 1"
echo "$P" | grep -q 'ridentifier 1791590554' && ok "Regla de CONTENCION DMZ -> redes privadas activa" || mal "NO esta la regla de contencion (grave)"
N=$(echo "$P" | grep 'on em2' | grep -cE 'port = (http|https)')
[ "$N" = 0 ] && ok "Salida de la DMZ a internet CERRADA" || mal "La DMZ puede salir a internet ($N reglas pass http/https)"

echo "=== 4. Web"
C1=$(ssh $S rpi5 'curl -s -o /dev/null -w %{http_code} --max-time 6 http://10.10.20.40/')
[ "$C1" = 200 ] && ok "WordPress directo (10.10.20.40) = 200" || mal "WordPress directo = $C1"
C2=$(ssh $S rpi5 'curl -s -o /dev/null -w %{http_code} --max-time 6 http://192.168.1.23/')
[ "$C2" = 200 ] && ok "WordPress por el host (192.168.1.23) = 200" || mal "WordPress por el host = $C2"
C3=$(ssh $S rpi5 "ssh $S debian 'curl -s -o /dev/null -w %{http_code} --max-time 6 http://deb.debian.org/'" 2>/dev/null)
[ "$C3" = 000 ] && ok "Debian NO sale a internet" || mal "Debian SALE a internet (codigo $C3)"

echo "=== 5. Security Onion"
B=$(ssh $S soc 'cat /sys/class/net/bond0/bonding/slaves' 2>/dev/null)
echo "$B" | grep -q ens35 && ok "SO captura la DMZ (ens35 en bond0: $B)" || mal "SO no responde o no captura la DMZ"
W=$(curl -k -s -o /dev/null -w %{http_code} --max-time 8 https://192.168.1.200/)
case "$W" in 200|30*) ok "Consola web de SO responde ($W)";; *) mal "Consola web de SO = $W (si acaba de arrancar, esperar)";; esac

echo "=== 6. Para la Fase 3"
IP=$(ssh $S rpi5 'curl -4 -s --max-time 8 https://api.ipify.org')
echo "  IP publica actual: ${IP:-desconocida}  (comparar con la IPv4 WAN del ZTE; si difiere o es 100.x = CGNAT)"
echo "  ZTE: la regla TCP 80 -> 192.168.1.23 NO existe aun (Fase 3 pendiente). Revisar a mano."
