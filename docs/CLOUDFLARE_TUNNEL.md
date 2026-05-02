# Cloudflare Tunnel for q3a.a9group.net

This repo supports two persistent tunnel modes behind one preparation step:

- quick tunnel: random `https://*.trycloudflare.com` URL for short local testing
- named tunnel: persistent Cloudflare Tunnel routed from `q3a.a9group.net`

## Runtime Preparation

Before Docker starts either persistent tunnel mode, this repo now runs:

```bash
scripts/prepare-cloudflared-tunnel.sh
```

That script:

- resolves the tunnel by `CLOUDFLARED_TUNNEL_NAME` when `cloudflared` and
  `cert.pem` are available
- supports `CLOUDFLARED_TUNNEL_ID` as an explicit fallback when local
  name-resolution auth is stale
- validates that the credentials JSON matches the resolved tunnel ID
- generates `.cloudflared/config.yml` and `.cloudflared/credentials.json` for
  Docker
- can run `cloudflared tunnel route dns <tunnel> <hostname>` as part of prep
- optionally refreshes the token for token mode and writes
  `.cloudflared/token.txt`

The runtime files are ignored by git and should not be edited by hand.

## Quick Tunnel

```bash
npm run tunnel:quick
```

Read the generated URL from the `cloudflared` logs. Stop it with:

```bash
npm run tunnel:quick:down
```

Quick tunnels are development-only. They are not stable hostnames.

## Persistent Tunnel With Dashboard Token

This is the simplest persistent setup for Docker Compose.

1. In Cloudflare Zero Trust, create a tunnel for the `a9group.net` account.
2. Add a public hostname:

```text
Hostname: q3a.a9group.net
Service:  http://q3-relay:8080
```

3. Copy the Docker tunnel token and export it locally, or let the prepare
   script refresh it by tunnel name when `cert.pem` is available:

```bash
export CLOUDFLARED_TOKEN='<cloudflare tunnel token>'
```

4. Start the relay and tunnel:

```bash
npm run tunnel:named
```

5. Test:

```bash
curl https://q3a.a9group.net/healthz
RELAY_URL=wss://q3a.a9group.net Q3_SKIP_ASSET_CHECK=1 node tests/e2e/quake3-status.e2e.mjs
```

Stop it with:

```bash
npm run tunnel:named:down
```

## Persistent Tunnel With CNAME

Cloudflare gives every named tunnel a target like:

```text
<TUNNEL_UUID>.cfargotunnel.com
```

For `q3a.a9group.net`, create this proxied DNS record in the same Cloudflare
account as the tunnel:

```text
Type:    CNAME
Name:    q3a
Target:  <TUNNEL_UUID>.cfargotunnel.com
Proxy:   enabled
```

If you have a local Cloudflare origin cert from `cloudflared tunnel login`, the
CLI can create the route:

```bash
cloudflared tunnel route dns <TUNNEL_UUID_OR_NAME> q3a.a9group.net
```

The CLI route path requires `~/.cloudflared/cert.pem`, created by:

```bash
cloudflared tunnel login
```

To make DNS routing part of bringup, set:

```bash
CLOUDFLARED_ROUTE_DNS=always
```

Then `scripts/prepare-cloudflared-tunnel.sh` will run:

```bash
cloudflared tunnel route dns q3-websocket q3a.a9group.net
```

## Locally Managed q3a Tunnel

This repo also includes a Docker-ready locally-managed tunnel path.

```text
scripts/prepare-cloudflared-tunnel.sh
```

The generated runtime config routes:

```text
q3a.a9group.net -> http://q3-relay:8080
```

Start the relay and detached local tunnel:

```bash
npm run tunnel:local-managed
```

Stop it with:

```bash
npm run tunnel:local-managed:down
```

The source credentials JSON still lives under `~/.cloudflared`, but Docker now
mounts the validated runtime copy from `.cloudflared/credentials.json`.

## Notes

Cloudflare routes public HTTPS and WebSocket traffic to the local HTTP service.
The relay itself still speaks WebSocket to clients and UDP to the local
`ioq3ded` process inside the same container.
