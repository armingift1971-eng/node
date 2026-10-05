# PasarGuard Node with a TLS multiplexer for Sliplane TCP services.
ARG PASARGUARD_NODE_IMAGE=pasarguard/node:v0.5.4
FROM ${PASARGUARD_NODE_IMAGE}

USER root
RUN apk add --no-cache nginx openssl gettext \
    && mkdir -p /run/nginx /var/log/nginx

COPY nginx.conf.template /etc/nginx/nginx.conf.template
COPY entrypoint.sh /entrypoint.sh
RUN chmod 0755 /entrypoint.sh

ENV PORT=62050 \
    SERVICE_PORT=62051 \
    NODE_WS_PORT=10001 \
    NODE_WS_PATH=/xws \
    NODE_HOST=0.0.0.0 \
    SSL_CERT_FILE=/var/lib/pg-node/certs/ssl_cert.pem \
    SSL_KEY_FILE=/var/lib/pg-node/certs/ssl_key.pem \
    GENERATED_CONFIG_PATH=/var/lib/pg-node/generated \
    SERVICE_PROTOCOL=grpc

EXPOSE 62050
ENTRYPOINT ["/entrypoint.sh"]
