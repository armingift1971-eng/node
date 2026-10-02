# Pin the upstream node version for reproducible Railway/VPS deployments.
# Override at build time when upgrading: --build-arg PASARGUARD_NODE_IMAGE=pasarguard/node:vX.Y.Z
ARG PASARGUARD_NODE_IMAGE=pasarguard/node:v0.5.4
FROM ${PASARGUARD_NODE_IMAGE}

# The upstream image contains the node binary and runtime dependencies.
# OpenSSL is used only by the portable bootstrap to create a self-signed cert.
RUN apk add --no-cache openssl

COPY entrypoint.sh /entrypoint.sh
RUN chmod 0755 /entrypoint.sh

# Keep upstream defaults portable. entrypoint.sh uses Railway's PORT only when
# SERVICE_PORT is not explicitly supplied; VPS deployments fall back to 62050.
ENV NODE_HOST=0.0.0.0 \
    SSL_CERT_FILE=/var/lib/pg-node/certs/ssl_cert.pem \
    SSL_KEY_FILE=/var/lib/pg-node/certs/ssl_key.pem \
    GENERATED_CONFIG_PATH=/var/lib/pg-node/generated \
    SERVICE_PROTOCOL=grpc

ENTRYPOINT ["/entrypoint.sh"]
