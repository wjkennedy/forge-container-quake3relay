# Experimental Forge Containers image that runs ioquake3, the WebSocket-to-UDP
# relay, and optionally cloudflared in a single container service.
FROM cloudflare/cloudflared:latest AS cloudflared

FROM node:22-bookworm-slim

WORKDIR /opt/forge-q3

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    ioquake3-server \
    netcat-openbsd \
    tini \
    && rm -rf /var/lib/apt/lists/*

RUN npm init -y \
    && npm install --omit=dev ws@8.17.1 rcon@1.1.0 \
    && npm cache clean --force

RUN mkdir -p /opt/ioquake3/baseq3 /opt/ioquake3/demoq3

COPY services/quake3-allinone/scripts/relay-server-enhanced.mjs ./scripts/relay-server-enhanced.mjs
COPY services/quake3-allinone/scripts/q3-mock-server.mjs ./scripts/q3-mock-server.mjs
COPY services/quake3-allinone/scripts/rcon-client.mjs ./scripts/rcon-client.mjs
COPY services/quake3-allinone/baseq3/ /opt/ioquake3/baseq3/
COPY services/quake3-allinone/demoq3/ /opt/ioquake3/demoq3/
COPY services/quake3-allinone/server.cfg /opt/ioquake3/demoq3/server.cfg
COPY --from=cloudflared /usr/local/bin/cloudflared /usr/local/bin/cloudflared
COPY scripts/forge-allinone-entrypoint.sh /usr/local/bin/forge-allinone-entrypoint.sh

RUN chmod 0555 /usr/local/bin/forge-allinone-entrypoint.sh \
    && chmod 0555 /usr/local/bin/cloudflared \
    && chmod -R a+rX /opt/forge-q3 /opt/ioquake3

ENV NODE_ENV=production \
    PROXY_HOST=0.0.0.0 \
    TARGET_HOST=127.0.0.1 \
    TARGET_PORT=27960 \
    GAME_PORT=27960 \
    DEBUG=false \
    ENABLE_CLOUDFLARED=false \
    CLOUDFLARED_PROTOCOL=http2 \
    CLOUDFLARED_RESTART_DELAY_SECONDS=5

EXPOSE 8080

USER node

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/forge-allinone-entrypoint.sh"]
