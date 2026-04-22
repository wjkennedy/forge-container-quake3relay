# Cloudflare Tunnel for q3a.a9group.net

This repo supports two tunnel modes:

- quick tunnel: random `https://*.trycloudflare.com` URL for short local testing
- named tunnel: persistent Cloudflare Tunnel routed from `q3a.a9group.net`

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

3. Copy the Docker tunnel token and export it locally:

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

## Locally Managed q3a Tunnel

This repo also includes a Docker-ready locally-managed tunnel config:

```text
cloudflared-q3a.docker.yml
```

It routes:

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

The credentials file mounted by `docker-compose.cloudflare-local.yml` lives
under `~/.cloudflared` and must not be committed.

## Notes

Cloudflare routes public HTTPS and WebSocket traffic to the local HTTP service.
The relay itself still speaks WebSocket to clients and UDP to the local
`ioq3ded` process inside the same container.
