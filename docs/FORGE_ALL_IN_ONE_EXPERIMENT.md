# Forge All-In-One Quake 3 Experiment

This is an experimental Forge Containers shape for running both processes in one
container:

- `ioq3ded` listens on `127.0.0.1:27960/udp`.
- `scripts/relay-server-enhanced.mjs` listens on Forge's `SERVER_PORT`.
- The relay forwards WebSocket binary frames to the local UDP game server.
- The demo data is expected at `demoq3/pak0.pk3`.

## Why This Shape

Forge Containers currently allow one containerised service with one defined
container in EAP. The existing Docker Compose topology has separate `relay` and
`ioquake3` services, so the Forge experiment must run both processes in one
image.

## Build

```bash
docker build -f Dockerfile.forge-allinone \
  --platform linux/amd64 \
  -t forge-q3-allinone:local \
  -t forge-q3-allinone:q3-allinone-test-20260421 \
  .
```

## Local Smoke Test

Real Quake 3 demo gameplay requires `demoq3/pak0.pk3` in the image.

```bash
docker run --rm --platform linux/amd64 -p 8090:8080 \
  -e SERVER_PORT=8080 \
  --name forge-q3-allinone-real \
  forge-q3-allinone:local
```

Then:

```bash
curl http://127.0.0.1:8090/healthz
env Q3_SKIP_ASSET_CHECK=1 RELAY_PORT=8090 node tests/e2e/quake3-status.e2e.mjs
docker stop forge-q3-allinone-real
```

For startup testing without game data, set `ALLOW_START_WITHOUT_PAK0=1`. The
entrypoint will run the local UDP mock instead of `ioq3ded`.

## Forge Test Prep

The companion Forge app manifest in `../jira-quake3/manifest.yml` references:

```text
service key: q3-relay
container key: quake3-allinone
tag: q3-allinone-test-20260421
health webtrigger: q3-relay-health-trigger
```

The expected Forge-side sequence is:

```bash
cd ../jira-quake3
forge containers create -k quake3-allinone
forge containers docker-login

# Tag/push forge-q3-allinone:q3-allinone-test-20260421 to the registry URL
# provided by Forge for the quake3-allinone container.

forge deploy -e development
forge webtrigger -e development
```

## Forge Gating Risks

The container process can fit Forge's single-container model, but browser
gameplay still depends on whether Forge's endpoint routing supports WebSocket
upgrade traffic to a container service. The documented `invokeService` frontend
path is request/response HTTP, not a persistent WebSocket stream.

If WebSocket upgrades are not supported, this image can still prove that the
combined process runs, but it cannot deliver playable browser multiplayer
without an external WebSocket relay.
