#!/usr/bin/env bash
# Configura el Droplet DO (203.0.113.10) como PUENTE publico:
#   WireGuard server + nginx (reenvio TCP crudo, SIN filtrar) + ufw.
# Lo corre el responsable (usa la llave ~/.ssh/id_vps, sin credenciales en el archivo):
#   ! bash "D:/VMware_LAB/_lab/edge/setup_edge_droplet.sh" <DEBIAN_WG_PUB>
set -uo pipefail
DPUB="${1:?Uso: setup_edge_droplet.sh <DEBIAN_WG_PUB>}"
KEY="$HOME/.ssh/id_vps"
ssh -i "$KEY" -o StrictHostKeyChecking=accept-new root@203.0.113.10 "DEBIAN_PUB='$DPUB' bash -s" <<'REMOTE'
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null
apt-get install -y -qq wireguard nginx libnginx-mod-stream >/dev/null
cd /etc/wireguard; umask 077
[ -f server.key ] || wg genkey | tee server.key | wg pubkey > server.pub
cat > /etc/wireguard/wg0.conf <<CONF
[Interface]
Address = 10.9.0.1/24
ListenPort = 51820
PrivateKey = $(cat server.key)

[Peer]
PublicKey = $DEBIAN_PUB
AllowedIPs = 10.9.0.2/32
CONF
systemctl enable wg-quick@wg0 >/dev/null 2>&1
systemctl restart wg-quick@wg0
mkdir -p /etc/nginx/stream.d
grep -q 'stream.d' /etc/nginx/nginx.conf || printf '\nstream {\n    include /etc/nginx/stream.d/*.conf;\n}\n' >> /etc/nginx/nginx.conf
cat > /etc/nginx/stream.d/sitio.conf <<'CONF'
# TCP crudo (no inspecciona HTTP = cero filtrado). PROXY protocol -> IP real del bot.
server { listen 443; proxy_pass 10.9.0.2:8443; proxy_protocol on; }
server { listen 80;  proxy_pass 10.9.0.2:8080; proxy_protocol on; }
CONF
nginx -t && systemctl restart nginx
ufw allow 22/tcp  >/dev/null
ufw allow 80/tcp  >/dev/null
ufw allow 443/tcp >/dev/null
ufw allow 51820/udp >/dev/null
ufw --force enable >/dev/null 2>&1
echo "=========================================="
echo "SERVER_WG_PUB=$(cat server.pub)"
echo "wg:    $(wg show wg0 | head -1)"
echo "nginx: $(systemctl is-active nginx)"
echo "ufw:   $(ufw status | grep -c ALLOW) reglas (22,80,443,51820)"
REMOTE
