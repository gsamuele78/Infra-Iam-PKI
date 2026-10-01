# infra-pki/caddy/Dockerfile
# Caddy with the layer4 plugin (TCP proxy + IP allowlist in front of step-ca).
# Both stages and the plugin are pinned (HARD RULE 7). caddy-l4 v0.1.2 requires
# caddy v2.11.x (its go.mod), so the builder and runtime tags follow it: bump all
# three together and run lab tier 0 (docs/testing.md).
ARG CADDY_VERSION=2.11.4

FROM caddy:${CADDY_VERSION}-builder-alpine AS builder
ARG CADDY_VERSION
ARG CADDY_L4_VERSION=v0.1.2
RUN xcaddy build "v${CADDY_VERSION}" \
    --with "github.com/mholt/caddy-l4@${CADDY_L4_VERSION}"

FROM caddy:${CADDY_VERSION}-alpine
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
