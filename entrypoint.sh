
#!/bin/sh
set -eu

DATA_DIR=${DATA_DIR:-/var/lib/pg-node}
CERT_DIR=${CERT_DIR:-$DATA_DIR/certs}
DEFAULT_CERT=$CERT_DIR/ssl_cert.pem
DEFAULT_KEY=$CERT_DIR/ssl_key.pem
CERT=${SSL_CERT_FILE:-$DEFAULT_CERT}
KEY=${SSL_KEY_FILE:-$DEFAULT_KEY}
API_KEY_FILE=${API_KEY_FILE:-$DATA_DIR/api_key.txt}
CERT_HOST_FILE=${CERT_HOST_FILE:-$DATA_DIR/.certificate-host}
SETUP_INFO_FILE=${SETUP_INFO_FILE:-$DATA_DIR/connection-info.txt}

PUBLIC_PORT=${PORT:-62050}
NODE_GRPC_PORT=${SERVICE_PORT:-62051}
NODE_WS_PORT=${NODE_WS_PORT:-10001}
NODE_WS_PATH=${NODE_WS_PATH:-/xws}
export PORT="$PUBLIC_PORT" SERVICE_PORT="$NODE_GRPC_PORT" NODE_WS_PORT NODE_WS_PATH
export NODE_HOST=${NODE_HOST:-0.0.0.0}
export SERVICE_PROTOCOL=${SERVICE_PROTOCOL:-grpc}

fail() { echo "[pasarguard-node] ERROR: $*" >&2; exit 1; }
is_uuid() { printf '%s' "$1" | grep -Eq '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'; }
is_hostname_or_ipv4() { printf '%s' "$1" | grep -Eq '^([A-Za-z0-9][A-Za-z0-9.-]*|([0-9]{1,3}\.){3}[0-9]{1,3})$'; }

CERT_HOST=${NODE_PUBLIC_HOST:-${SLIPLANE_DOMAIN:-${RAILWAY_PUBLIC_DOMAIN:-node}}}
is_hostname_or_ipv4 "$CERT_HOST" || fail "NODE_PUBLIC_HOST must be a bare hostname or IPv4: $CERT_HOST"
printf '%s' "$NODE_GRPC_PORT" | grep -Eq '^[0-9]+$' || fail "SERVICE_PORT must be numeric"
printf '%s' "$PUBLIC_PORT" | grep -Eq '^[0-9]+$' || fail "PORT must be numeric"
[ "$NODE_GRPC_PORT" != "$PUBLIC_PORT" ] || fail "SERVICE_PORT and PORT must differ"

umask 077
mkdir -p "$DATA_DIR" "$CERT_DIR" "$(dirname "$CERT")" "$(dirname "$KEY")" /run/nginx /var/log/nginx
chmod 0700 "$DATA_DIR" "$CERT_DIR" 2>/dev/null || true

if [ -n "${API_KEY:-}" ]; then
  is_uuid "$API_KEY" || fail "API_KEY must be a valid UUID"
elif [ -s "$API_KEY_FILE" ]; then
  API_KEY=$(tr -d '\r\n' < "$API_KEY_FILE")
  is_uuid "$API_KEY" || fail "stored API key is not a valid UUID"
else
  API_KEY=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || true)
  is_uuid "$API_KEY" || fail "could not generate a valid API key"
  printf '%s\n' "$API_KEY" > "$API_KEY_FILE"
  chmod 0600 "$API_KEY_FILE" 2>/dev/null || true
fi
export API_KEY

cert_host_changed=false
if [ -f "$CERT_HOST_FILE" ] && [ "$(cat "$CERT_HOST_FILE" 2>/dev/null || true)" != "$CERT_HOST" ]; then cert_host_changed=true; fi
if [ "${AUTO_GENERATE_CERT:-true}" = "true" ] && [ "$cert_host_changed" = "true" ] && [ "${REGENERATE_CERT_ON_HOST_CHANGE:-true}" = "true" ] && [ -f "$DATA_DIR/.generated-certificate" ]; then
  rm -f "$CERT" "$KEY"
fi

if [ "${AUTO_GENERATE_CERT:-true}" = "true" ] && { [ ! -s "$CERT" ] || [ ! -s "$KEY" ]; }; then
  echo "[pasarguard-node] generating certificate for $CERT_HOST"
  cfg=/tmp/node-openssl.cnf
  {
    echo '[req]'
    echo 'distinguished_name = req_distinguished_name'
    echo 'x509_extensions = v3_req'
    echo 'prompt = no'
    echo '[req_distinguished_name]'
    printf 'CN = %s\n' "$CERT_HOST"
    echo '[v3_req]'
    echo 'subjectAltName = @alt_names'
    echo '[alt_names]'
    if printf '%s' "$CERT_HOST" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then printf 'IP.1 = %s\n' "$CERT_HOST"; else printf 'DNS.1 = %s\n' "$CERT_HOST"; fi
  } > "$cfg"
  openssl req -x509 -newkey rsa:2048 -nodes -days "${CERT_VALIDITY_DAYS:-825}" -keyout "$KEY" -out "$CERT" -config "$cfg" -extensions v3_req 2>/dev/null || fail "failed to generate TLS certificate"
  rm -f "$cfg"
  printf '%s\n' "$CERT_HOST" > "$CERT_HOST_FILE"
  touch "$DATA_DIR/.generated-certificate"
  chmod 0600 "$KEY" "$CERT_HOST_FILE" "$DATA_DIR/.generated-certificate" 2>/dev/null || true
  chmod 0644 "$CERT" 2>/dev/null || true
fi
[ -s "$CERT" ] || fail "TLS certificate not found: $CERT"
[ -s "$KEY" ] || fail "TLS private key not found: $KEY"

{
  echo '# PasarGuard Node connection details'
  echo "Address: $CERT_HOST"
  echo "Public/container port: $PUBLIC_PORT"
  echo "Internal gRPC port: $NODE_GRPC_PORT"
  echo "Protocol: $SERVICE_PROTOCOL"
  echo "API Key: $API_KEY"
  echo "WebSocket path: $NODE_WS_PATH"
  echo 'Certificate:'
  cat "$CERT"
} > "$SETUP_INFO_FILE"
chmod 0600 "$SETUP_INFO_FILE" 2>/dev/null || true

envsubst '${PORT} ${SERVICE_PORT} ${NODE_WS_PORT} ${NODE_WS_PATH} ${SSL_CERT_FILE} ${SSL_KEY_FILE}' \
  < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf
nginx -t
nginx
NGINX_PID=$!
trap 'kill "$NGINX_PID" 2>/dev/null || true' EXIT INT TERM

echo "[pasarguard-node] public TLS/gRPC on :${PUBLIC_PORT}; WebSocket ${NODE_WS_PATH} -> :${NODE_WS_PORT}; Node gRPC internal :${NODE_GRPC_PORT}"
exec ./main
