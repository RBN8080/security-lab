#!/usr/bin/env bash
# Emite el certificado Let's Encrypt para sitio-ejemplo.duckdns.org por DNS-01 (DuckDNS).
# NO contiene credenciales: la clave sudo entra por stdin y el token como argumento.
# Lo corre el responsable (la salida de internet de la DMZ debe estar ABIERTA):
#   ! echo 'CLAVE_SUDO' | bash "D:/VMware_LAB/_lab/https/obtener_cert.sh" <DuckDNS_Token>
set -uo pipefail
TOKEN="${1:?Uso: ... obtener_cert.sh <DuckDNS_Token>}"
S="-o BatchMode=yes"
read -r PW   # clave sudo de Debian (primera linea de stdin; no se guarda)
{
  printf '%s\n' "$PW"
  cat <<REMOTE
export LC_ALL=C
export DuckDNS_Token="$TOKEN"
echo "salida a internet: \$(curl -s -o /dev/null -w %{http_code} --max-time 8 https://acme-v02.api.letsencrypt.org/directory)"
if [ ! -f /root/.acme.sh/acme.sh ]; then echo "instalando acme.sh..."; curl -s https://get.acme.sh | sh >/dev/null 2>&1; fi
echo "emitiendo certificado (puede tardar por el DNS)..."
/root/.acme.sh/acme.sh --issue --dns dns_duckdns -d sitio-ejemplo.duckdns.org --server letsencrypt --keylength ec-256 2>&1 | tail -15
mkdir -p /etc/ssl/sitio-ejemplo
/root/.acme.sh/acme.sh --install-cert -d sitio-ejemplo.duckdns.org --ecc \\
  --key-file /etc/ssl/sitio-ejemplo/privkey.pem \\
  --fullchain-file /etc/ssl/sitio-ejemplo/fullchain.pem \\
  --reloadcmd "systemctl reload apache2" 2>&1 | tail -5
echo "--- archivos del certificado:"; ls -l /etc/ssl/sitio-ejemplo/ 2>&1
REMOTE
} | ssh $S rpi5 "ssh $S debian 'sudo -S -p \"\" bash -s'"
