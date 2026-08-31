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
# ^~ stops regex locations (panel static-asset rules) from hijacking
# the index internal redirect; the types block fixes wasm MIME on
# older nginx and must list every extension the export uses.
location ^~ /dream/ {
    alias /var/www/back-of-dreams/;
    index index.html;
    types {
        text/html html;
        application/javascript js;
        application/wasm wasm;
        image/png png;
        application/octet-stream pck;
    }
}
SNIP

if ! grep -q "back-of-dreams.conf" "$CONF"; then
  mkdir -p /root/nginx-backups
  cp "$CONF" "/root/nginx-backups/$(basename "$CONF").bak"
  sed -i '0,/listen[^;]*443[^;]*;/s//&\n    include snippets\/back-of-dreams.conf;/' "$CONF"
  echo "==> Included snippet in $CONF (backup in /root/nginx-backups/)"
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
