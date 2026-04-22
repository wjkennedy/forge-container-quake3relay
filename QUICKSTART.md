# Quick Start Guide

Get the Quake 3 relay server running locally in minutes.

## Prerequisites

- Docker and Docker Compose installed (for Option 1)
- Node.js 18+ (for local development)
- ~2GB free disk space (for ioquake3 build in Docker)

## Option 1: Docker Compose (Easiest - Full Stack)

```bash
# Clone the project and navigate to it
cd /path/to/quake3-relay

# Start both relay and ioquake3 server
docker-compose up --build

# Output shows relay running on ws://localhost:8080
```

The relay is now running at `ws://localhost:8080` with ioquake3 server at `localhost:27960`.

## Option 2: Minimal Relay (Standalone - No Docker)

Fast setup using the production-proven minimal relay from q3js.

### 2a. UDP Relay (Quake 3)
```bash
# Install ws dependency
npm install

# Run minimal UDP relay
TARGET_HOST=127.0.0.1 TARGET_PORT=27960 PROXY_PORT=8080 npm run relay:udp
```

### 2b. Enhanced Relay (with metrics)
```bash
# Install ws dependency
npm install

# Run with debug logging
npm run relay:dev

# Run production (clean output)
npm run relay:enhanced
```

Both expose `/healthz` endpoint:
```bash
curl http://localhost:8080/healthz
# Returns active connections, bytes in/out, target info
```

## Option 3: Local Node.js Development (Full TypeScript)

```bash
# Install dependencies
npm install
npm install -D ts-node

# Set environment variables
export GAME_SERVER_HOST=localhost
export GAME_SERVER_PORT=27960
export RELAY_WS_PORT=8080

# Start relay server
npx ts-node scripts/relay-server.ts
```

## Test the Connection

### Option A: Browser Console

Open browser DevTools console:

```javascript
// Create relay client
const client = new WebSocket('ws://localhost:8080');

// Handle connection
client.onopen = () => {
  console.log('Connected to relay!');
  
  // Send test message
  const message = {
    type: 'data',
    data: 'AAAAAAAAAA==', // Base64 dummy data
    clientId: 'test-client'
  };
  client.send(JSON.stringify(message));
};

// Receive messages
client.onmessage = (event) => {
  console.log('Received:', event.data);
};

client.onerror = (error) => {
  console.error('Error:', error);
};

client.onclose = () => {
  console.log('Disconnected');
};
```

### Option B: Using the Example Component

1. Open http://localhost:3000 in your browser
2. You should see the Quake Game Client interface
3. The client should auto-connect to `ws://localhost:8080`
4. Check console for debug messages

### Option C: CLI Testing with wscat

```bash
# Install wscat
npm install -g wscat

# Connect to relay
wscat -c ws://localhost:8080

# Type JSON messages
> {"type":"data","data":"AAAAAAAAAA==","clientId":"test"}

# You should see messages flowing
< {"type":"connect","clientId":"abc12345",...}
```

## Project Structure

```
├── lib/
│   ├── relay-server.ts           # Main relay server
│   ├── quake-protocol.ts         # Q3 protocol utilities
│   └── quake-ws-client.ts        # WebSocket client library
├── hooks/
│   └── useQuakeRelay.ts          # React hook
├── components/
│   └── QuakeGameClient.tsx       # Example component
├── scripts/
│   └── relay-server.ts           # Entry point
├── docker/
│   └── ioquake3/                 # Game server container
│       ├── Dockerfile
│       └── server.cfg
├── docker-compose.yml            # Full stack orchestration
├── Dockerfile                    # Relay container
├── docs/
│   ├── RELAY_INTEGRATION.md      # Detailed integration guide
│   └── DEPLOYMENT.md             # Production deployment
└── README_RELAY.md               # Relay server documentation
```

## Environment Variables

Create a `.env.local` file:

```env
# WebSocket configuration
NEXT_PUBLIC_RELAY_SERVER_URL=ws://localhost:8080

# Server-side configuration
RELAY_WS_PORT=8080
RELAY_HOST=0.0.0.0
GAME_SERVER_HOST=localhost
GAME_SERVER_PORT=27960
MAX_CLIENTS=64
DEBUG=true
```

## Next Steps

1. **Understand the Architecture**
   - Read `README_RELAY.md` for overview
   - Check `docs/RELAY_INTEGRATION.md` for protocol details

2. **Integrate Your WASM Client**
   - Use `QuakeRelayClient` class to send/receive packets
   - Wire to your WASM Quake 3 module
   - See `components/QuakeGameClient.tsx` for example

3. **Deploy to Production**
   - Follow `docs/DEPLOYMENT.md`
   - Choose VPS, Docker, or Kubernetes deployment
   - Configure SSL/TLS for security

4. **Scale Multiplayer**
   - Run multiple relay instances with load balancer
   - Monitor with logging/metrics
   - Add database for session tracking

## Debugging

### View Relay Logs

```bash
# With Docker
docker-compose logs -f relay

# With Node.js
# Logs appear in terminal

# Enable debug mode
DEBUG=true node scripts/relay-server.ts
```

### Monitor Connections

```bash
# Check relay is listening
netstat -an | grep 8080

# Check game server is reachable
nc -u localhost 27960

# Monitor relay memory/CPU
top -p $(pgrep -f relay-server.ts)
```

### Test Packet Flow

1. Enable `DEBUG=true` in relay server
2. Enable `debug: true` in client library
3. Open browser DevTools console
4. Send packets and watch the logs
5. Look for `[v0] ...` debug messages in client
6. Look for `[relay] ...` debug messages in server

## Common Issues

**"Connection refused"**
- Relay not running: `docker-compose up` or `npx ts-node scripts/relay-server.ts`
- Check port 8080 is free: `lsof -i :8080`

**"Can't connect to game server"**
- Game server not running
- Wrong `GAME_SERVER_HOST` or `GAME_SERVER_PORT`
- Firewall blocking UDP port 27960

**"WebSocket handshake failed"**
- Browser security issue
- Check WSS is properly configured (if using HTTPS)
- Verify CORS headers if behind proxy

**High latency**
- Too many clients on one relay (>100)
- Network latency to game server
- Game server is overloaded

## Need Help?

1. Check the logs: `docker-compose logs -f`
2. Enable debug mode: `DEBUG=true`
3. Read `docs/RELAY_INTEGRATION.md` troubleshooting section
4. Test with wscat: `wscat -c ws://localhost:8080`
5. Verify game server: `nc -u localhost 27960`

## Production Deployment

When ready for production, follow `docs/DEPLOYMENT.md` which covers:
- VPS setup with systemd
- Docker deployment
- Kubernetes setup
- Load balancing multiple relays
- SSL/TLS configuration
- Monitoring and logging
- Performance tuning
- Backup and recovery

---

**Happy gaming! 🎮**
