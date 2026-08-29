#!/usr/bin/env bash
# One-shot deploy of "The Back of Dreams" web prototype onto an Ubuntu/Debian
# server with nginx, serving on port 8080 (pass a different port as $1).
# Usage:  bash deploy-do.sh [port]
set -euo pipefail

BRANCH="claude/3d-game-development-yi52wn"
BASE="https://raw.githubusercontent.com/liuzifengxjj1028/browser-use/${BRANCH}/game/dist/web"
PORT="${1:-8080}"
DEST=/var/www/back-of-dreams
SITE=/etc/nginx/sites-available/back-of-dreams

echo "==> Installing nginx (if missing)"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq nginx curl >/dev/null

echo "==> Downloading game files to ${DEST}"
mkdir -p "$DEST"
for f in index.html index.js index.pck index.wasm index.audio.worklet.js \
         index.png index.icon.png index.apple-touch-icon.png; do
  echo "    $f"
  curl -fsSL "$BASE/$f" -o "$DEST/$f"
done

echo "==> Writing nginx site (port ${PORT})"
cat > "$SITE" <<NGINX
server {
    listen ${PORT};
    listen [::]:${PORT};
    server_name _;
    root ${DEST};
    index index.html;

    gzip on;
    gzip_types application/wasm application/javascript text/html image/png;
    gzip_min_length 1024;

    location / {
        try_files \$uri =404;
    }
    location ~ \.wasm\$ {
        types { application/wasm wasm; }
        add_header Cache-Control "public, max-age=86400";
    }
    location ~ \.(pck|js|png)\$ {
        add_header Cache-Control "public, max-age=86400";
    }
}
NGINX
ln -sf "$SITE" /etc/nginx/sites-enabled/back-of-dreams
nginx -t
systemctl reload nginx || systemctl restart nginx

if command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then
  echo "==> Opening firewall port ${PORT}"
  ufw allow "${PORT}/tcp" >/dev/null
fi

IP=$(curl -fsSL -4 https://ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
echo ""
echo "======================================================"
echo "  Deployed. Play at:  http://${IP}:${PORT}/"
echo "======================================================"
echo "If the page doesn't load, also allow port ${PORT} in the"
echo "DigitalOcean cloud firewall (Networking -> Firewalls)."
