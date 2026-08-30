#!/usr/bin/env bash
# Attach the already-deployed game (/var/www/back-of-dreams) to the existing
# HTTPS site on this server as /dream/, satisfying Godot 4's Secure Context
# requirement. Idempotent. Usage: bash attach-https.sh [domain]
set -euo pipefail

DEST=/var/www/back-of-dreams
DOMAIN="${1:-}"

if [ ! -f "$DEST/index.html" ]; then
  echo "ERROR: $DEST/index.html not found — run deploy-do.sh first." >&2
  exit 1
fi

# find the nginx config that terminates TLS (a server block with 'listen ... 443')
if [ -n "$DOMAIN" ]; then
  CONF=$(grep -rslE "server_name[^;]*${DOMAIN}" /etc/nginx/sites-enabled/ /etc/nginx/conf.d/ 2>/dev/null | head -1 || true)
else
  CONF=$(grep -rslE 'listen[^;]*443' /etc/nginx/sites-enabled/ /etc/nginx/conf.d/ 2>/dev/null | head -1 || true)
fi
if [ -z "$CONF" ]; then
  echo "ERROR: no HTTPS server block found under sites-enabled/ or conf.d/." >&2
  exit 1
fi
echo "==> Using site config: $CONF"

mkdir -p /etc/nginx/snippets
cat > /etc/nginx/snippets/back-of-dreams.conf <<'SNIP'
location = /dream { return 301 /dream/; }
location /dream/ {
    alias /var/www/back-of-dreams/;
    index index.html;
}
SNIP

if ! grep -q "back-of-dreams.conf" "$CONF"; then
  cp "$CONF" "${CONF}.bak.back-of-dreams"
  sed -i '0,/listen[^;]*443[^;]*;/s//&\n    include snippets\/back-of-dreams.conf;/' "$CONF"
  echo "==> Included snippet in $CONF (backup: ${CONF}.bak.back-of-dreams)"
else
  echo "==> Snippet already included"
fi

nginx -t
systemctl reload nginx
sleep 1

HOST=$(grep -m1 -oE 'server_name[^;]+' "$CONF" | awk '{print $2}')
echo ""
echo "==> Local check:"
curl -skI "https://127.0.0.1/dream/" -H "Host: ${HOST}" | head -1
echo "======================================================"
echo "  Play at:  https://${HOST}/dream/"
echo "======================================================"
