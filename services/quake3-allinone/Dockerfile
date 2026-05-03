# Experimental Forge Containers image that runs both ioquake3 dedicated server
# and the WebSocket-to-UDP relay in a single container service.
FROM node:22-bookworm-slim

WORKDIR /opt/forge-q3

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    ioquake3-server \
    netcat-openbsd \
    tini \
    && rm -rf /var/lib/apt/lists/*

RUN npm init -y \
    && npm install --omit=dev ws@8.17.1 rcon@1.1.0 \
    && npm cache clean --force

RUN mkdir -p /opt/ioquake3/baseq3 /opt/ioquake3/demoq3

COPY scripts/relay-server-enhanced.mjs ./scripts/relay-server-enhanced.mjs
COPY scripts/q3-mock-server.mjs ./scripts/q3-mock-server.mjs
COPY scripts/rcon-client.mjs ./scripts/rcon-client.mjs
COPY baseq3/ /opt/ioquake3/baseq3/
COPY demoq3/ /opt/ioquake3/demoq3/
COPY server.cfg /opt/ioquake3/demoq3/server.cfg
COPY scripts/forge-allinone-entrypoint.sh /usr/local/bin/forge-allinone-entrypoint.sh

RUN chmod 0555 /usr/local/bin/forge-allinone-entrypoint.sh \
    && chmod -R a+rX /opt/forge-q3 /opt/ioquake3

ENV NODE_ENV=production \
    PROXY_HOST=0.0.0.0 \
    TARGET_HOST=127.0.0.1 \
    TARGET_PORT=27960 \
    GAME_PORT=27960 \
    DEBUG=false

EXPOSE 8080

USER node

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/forge-allinone-entrypoint.sh"]
