# Minimal WebSocket↔UDP Relay Guide

This guide covers the production-proven minimal relay implementations extracted from the q3js project, optimized for simplicity, performance, and reliability.

## Three Relay Options

### 1. **ws-udp-relay-minimal.js** (Recommended for Quake 3)
- **Purpose**: WebSocket ↔ UDP bridging
- **Best for**: Game servers (Quake 3, etc.)
- **Binary forwarding**: Direct binary frame ↔ UDP packet translation
- **File**: `scripts/ws-udp-relay-minimal.js`

```bash
# Run standalone
TARGET_HOST=127.0.0.1 TARGET_PORT=27960 PROXY_PORT=8080 node scripts/ws-udp-relay-minimal.js
```

### 2. **ws-tcp-relay-minimal.js** (For TCP protocols)
- **Purpose**: WebSocket ↔ TCP bridging
- **Best for**: RDP, SSH, or other TCP services
- **Connection model**: 1 WebSocket client = 1 TCP connection
- **Backpressure handling**: Automatic flow control
- **File**: `scripts/ws-tcp-relay-minimal.js`

```bash
# Run standalone (e.g., for RDP)
TARGET_HOST=rdp.internal TARGET_PORT=3389 PROXY_PORT=8080 node scripts/ws-tcp-relay-minimal.js
```

### 3. **relay-server-enhanced.mjs** (Production with metrics)
- **Purpose**: Enhanced UDP relay with monitoring
- **Best for**: Production deployments, monitoring
- **Features**: Healthz endpoint, metrics, CORS, debug logging
- **File**: `scripts/relay-server-enhanced.mjs`

```bash
# Run with debug logging
DEBUG=true node scripts/relay-server-enhanced.mjs

# Run production (clean logs)
node scripts/relay-server-enhanced.mjs
```

## Environment Variables

### UDP Relay
```bash
TARGET_HOST=127.0.0.1      # Server address
TARGET_PORT=27960          # Server port
PROXY_PORT=8080            # WebSocket listen port
DEBUG=false                # Enable debug logging
```

### TCP Relay (Additional)
```bash
WS_BACKPRESSURE_THRESHOLD=1048576  # 1MB - tunable for performance
```

## Architecture

```
WebSocket Client (Browser)
    ↓ Binary frames
[Relay Server]
    ↓ Raw UDP/TCP packets
[Game Server / Service]
```

## Usage in Docker Compose

The default `docker-compose.yml` is configured to run the enhanced relay with the ioquake3 server:

```bash
# Start both services
docker-compose up --build

# View logs
docker-compose logs -f relay

# Stop services
docker-compose down
```

## Health Checks

All relays expose a `/healthz` endpoint for monitoring:

```bash
# UDP/Enhanced relays
curl http://localhost:8080/healthz

# Response
{
  "ok": true,
  "activeConnections": 2,
  "totalConnections": 5,
  "totalBytesIn": 102400,
  "totalBytesOut": 204800,
  "targetHost": "127.0.0.1",
  "targetPort": 27960
}
```

## Client Integration

### JavaScript/Browser
```javascript
// Connect to relay
const ws = new WebSocket('ws://localhost:8080');

// Send binary data (raw Quake 3 packet)
const packet = new Uint8Array([0xff, 0xff, 0xff, 0xff, 'c', 'o', 'n', 'n', 'e', 'c', 't']);
ws.send(packet);

// Receive binary responses
ws.addEventListener('message', (event) => {
  const data = event.data; // ArrayBuffer
  console.log('Received packet:', new Uint8Array(data));
});
```

### With React Hook (useQuakeRelay)
```typescript
import { useQuakeRelay } from '@/hooks/useQuakeRelay';

function GameClient() {
  const { connected, sendPacket } = useQuakeRelay('ws://localhost:8080', {
    debug: true,
  });

  const handleConnect = () => {
    const packet = new Uint8Array([0xff, 0xff, 0xff, 0xff, 'c', 'o', 'n', 'n']);
    sendPacket(packet);
  };

  return (
    <div>
      {connected ? 'Connected' : 'Disconnected'}
      <button onClick={handleConnect}>Connect to Game</button>
    </div>
  );
}
```

## Performance Tuning

### TCP Relay Backpressure (ws-tcp-relay-minimal.js)
```bash
# Default: 1MB threshold
WS_BACKPRESSURE_THRESHOLD=2097152 node scripts/ws-tcp-relay-minimal.js
# Increase for high-throughput scenarios, decrease for low-memory environments
```

### UDP Socket Options
The UDP relay uses default socket settings. For specialized needs:
- Modify `dgram.createSocket('udp4')` options in source
- Consider `SO_RCVBUF` and `SO_SNDBUF` for tuning

## Debugging

### Enable Debug Logging
```bash
# UDP relay
DEBUG=true TARGET_HOST=127.0.0.1 TARGET_PORT=27960 PROXY_PORT=8080 node scripts/ws-udp-relay-minimal.js

# Enhanced relay
DEBUG=true node scripts/relay-server-enhanced.mjs
```

### Monitor Connections
```bash
# Watch active connections in real-time
watch -n 1 'curl -s http://localhost:8080/healthz | jq'

# Or using nodemon
npx nodemon --exec "node scripts/relay-server-enhanced.mjs"
```

### Packet Inspection
```javascript
// Add this to client to see packets
ws.addEventListener('message', (event) => {
  const bytes = new Uint8Array(event.data);
  console.log('Packet hex:', Array.from(bytes).map(b => b.toString(16).padStart(2, '0')).join(' '));
});
```

## Production Deployment

### Vercel (using external relay)
1. Deploy relay to a persistent host (VPS, Railway, Render)
2. Configure `NEXT_PUBLIC_RELAY_SERVER_URL` in Vercel env vars:
   ```
   NEXT_PUBLIC_RELAY_SERVER_URL=wss://relay.yourdomain.com
   ```
3. Put relay behind a reverse proxy (nginx, Caddy) for TLS/WSS

### Railway / Render
```bash
# railway.toml or render.yaml
[build]
  builder = "nixpacks"

[deploy]
  command = "node scripts/relay-server-enhanced.mjs"
```

### Docker Kubernetes
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: quake3-relay
spec:
  replicas: 2
  selector:
    matchLabels:
      app: quake3-relay
  template:
    metadata:
      labels:
        app: quake3-relay
    spec:
      containers:
      - name: relay
        image: node:20-alpine
        command: ["node", "scripts/relay-server-enhanced.mjs"]
        ports:
        - containerPort: 8080
        env:
        - name: TARGET_HOST
          value: "quake3-service"
        - name: TARGET_PORT
          value: "27960"
        livenessProbe:
          httpGet:
            path: /healthz
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 10
```

## Troubleshooting

### Connection Refused
```bash
# Check if relay is running
curl http://localhost:8080/healthz

# Verify target server is reachable
telnet 127.0.0.1 27960
```

### No Messages Received
- Ensure server sends UDP packets back to client IP
- Check firewall rules (UDP port 27960 outbound)
- Enable debug logging and inspect packet flow

### High Memory Usage
- Check `activeConnections` in healthz endpoint
- Reduce `MAX_CLIENTS` if needed
- Monitor with: `node --max-old-space-size=512 scripts/relay-server-enhanced.mjs`

## References
- [q3js](https://github.com/q3js/proxy) - Original implementation
- [ws npm](https://www.npmjs.com/package/ws) - WebSocket library
- [Node.js dgram](https://nodejs.org/api/dgram.html) - UDP sockets
- [Node.js net](https://nodejs.org/api/net.html) - TCP sockets
