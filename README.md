# Forge Quake 3 Relay Container

This repo is a Forge Containers wrapper for the working Quake 3 WebSocket-to-UDP relay from `../forge-quake3-relay`.

The active service runs both processes in one Forge-compatible container:

- `ioq3ded` listens on `127.0.0.1:27960/udp`.
- `scripts/relay-server-enhanced.mjs` listens on `SERVER_PORT`, default `8080`.
- Browser clients connect over WebSocket to the relay.
- The relay forwards binary WebSocket frames to the local UDP game server.

The Forge manifest exposes the service as `q3-relay` with container key `quake3-allinone`.

## Requirements

- Docker with Compose
- Node.js 20, 22, or 24
- Forge CLI 12.10.0 or newer for Forge deployment

Install Node dependencies:

```bash
npm install
```

## Local Container

Build the image:

```bash
npm run container:build
```

Run it directly:

```bash
npm run container:run
```

Or run through Docker Compose:

```bash
npm run container:up
```

If port `8080` is already in use:

```bash
HOST_PORT=18080 npm run container:up
```

Run an RCON command through the running container:

```bash
npm run container:rcon -- status
npm run container:rcon -- 'say server admin connected'
```

The helper uses the existing server defaults: `127.0.0.1:27960`, UDP, no challenge handshake, and password `sphere`. Override them with `RCON_HOST`, `RCON_PORT`, `RCON_PASSWORD`, `RCON_TCP`, or `RCON_CHALLENGE` if you need different values.

Health check:

```bash
curl http://127.0.0.1:8080/healthz
```

Run the local container E2E test:

```bash
npm test
```

The test starts `q3-relay`, waits for `/healthz`, sends Quake 3 `getstatus` packets through WebSocket, and tears the container down.

## LAN Party Start/Stop

For the persistent Cloudflare tunnel on `q3a.a9group.net`, use the wrapper
scripts in the repo root:

```bash
./start-lan-party.sh
./stop-lan-party.sh
```

`start-lan-party.sh` starts the relay, brings up the persistent tunnel, waits
for the local relay health check, validates the public hostname, and prints the
stable relay URL `wss://q3a.a9group.net`.

By default it uses `TUNNEL_MODE=auto`:

- it prepares Cloudflare runtime files via `scripts/prepare-cloudflared-tunnel.sh`
- it resolves the named tunnel from `CLOUDFLARED_TUNNEL_NAME` when possible
- it validates the credentials JSON contents instead of trusting a hardcoded
  filename or UUID
- it can ensure the DNS route with `cloudflared tunnel route dns`
- it prefers the locally managed tunnel when credentials are available
- otherwise it falls back to the dashboard-token tunnel using
  `CLOUDFLARED_TOKEN`

If name resolution through local `cloudflared` auth is broken, you can pin the
expected tunnel directly with `CLOUDFLARED_TUNNEL_ID`.

You can force a mode explicitly:

```bash
TUNNEL_MODE=local-managed ./start-lan-party.sh
TUNNEL_MODE=token ./start-lan-party.sh
```

Prepare the runtime tunnel files without starting Docker:

```bash
npm run tunnel:prepare
```

If you want DNS route creation to be enforced during prep, set:

```bash
CLOUDFLARED_ROUTE_DNS=always
```

## Cloudflare Quick Tunnel

Start the relay and a temporary Cloudflare tunnel:

```bash
npm run tunnel:up
```

Watch the `cloudflared` logs for the generated `https://*.trycloudflare.com` URL. That URL should route to the relay HTTP/WebSocket service.

Stop the tunnel and relay:

```bash
npm run tunnel:down
```

For a persistent tunnel on `q3a.a9group.net`, use
[docs/CLOUDFLARE_TUNNEL.md](docs/CLOUDFLARE_TUNNEL.md).

## Forge Deployment

The active Forge config is in `manifest.yml`:

- service key: `q3-relay`
- container key: `quake3-allinone`
- health route: `/healthz`
- runtime: `nodejs22.x`

The helper script builds, pushes, and deploys the all-in-one image:

```bash
APP_ID=<registered-app-uuid> \
TAG=q3-allinone-test-20260421 \
scripts/prepare-quake3-container-test.sh
```

Useful Forge checks after deploy:

```bash
forge show containers -e development
forge show services -e development
forge webtrigger -e development
```

## Ported Parity Content

This repo includes the working relay docs, E2E tests, and Quake assets from `../forge-quake3-relay`:

- `docs/`
- `QUICKSTART.md`
- `README_RELAY.md`
- `RELAY_COMPARISON.md`
- `tests/e2e/`
- `services/quake3-allinone/baseq3/`
- `services/quake3-allinone/demoq3/`

The full browser client and Next.js UI remain in `../forge-quake3-relay`.

## Known Risk

Cloudflare quick tunnels support WebSocket traffic. Forge Containers endpoint routing may not support browser WebSocket upgrade traffic in the same way. If Forge does not pass WebSocket upgrades through to the container, the all-in-one image can still prove container health and HTTP reachability, but playable browser multiplayer will need an external relay endpoint such as the Cloudflare tunnel.
