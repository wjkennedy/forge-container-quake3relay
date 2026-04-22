# Quake 3 WebSocket Relay Integration Guide

This guide explains how to integrate the Quake 3 WASM client with the WebSocket relay server to enable multiplayer gameplay over a persistent relay connection.

## Architecture Overview

```
Browser WASM Client (Forge App)
    ↓ WebSocket JSON messages
Node.js Relay Server
    ↓ UDP binary packets
ioquake3 Game Server
```

The relay server translates between:
- **WebSocket**: JSON-formatted messages with base64-encoded binary data
- **UDP**: Raw Quake 3 protocol packets

## Relay Protocol

### Message Format

All WebSocket messages are JSON-formatted:

```typescript
interface RelayMessage {
  type: 'data' | 'connect' | 'disconnect' | 'ping' | 'pong' | 'error';
  data?: string;        // Base64-encoded binary data (for 'data' messages)
  clientId?: string;    // Unique client identifier
  timestamp?: number;   // Unix timestamp in milliseconds
  error?: string;       // Error message (for 'error' type)
}
```

### Message Types

#### Connection Flow

1. **Client connects to WebSocket**
   ```javascript
   ws = new WebSocket('ws://relay-server:8080');
   ```

2. **Server sends connection acknowledgment**
   ```json
   {
     "type": "connect",
     "clientId": "abc12345",
     "timestamp": 1700000000000
   }
   ```

3. **Client registers event handlers and begins sending packets**

#### Data Transfer

**Client → Server (game packet):**
```json
{
  "type": "data",
  "data": "base64encodedpacketdata...",
  "clientId": "abc12345",
  "timestamp": 1700000000000
}
```

**Server → Client (game packet response):**
```json
{
  "type": "data",
  "data": "base64encodedpacketdata...",
  "clientId": "abc12345",
  "timestamp": 1700000000000
}
```

#### Heartbeat

The relay sends periodic ping messages to detect dead connections:

**Server → Client:**
```json
{
  "type": "ping",
  "clientId": "abc12345",
  "timestamp": 1700000000000
}
```

**Client → Server (response):**
```json
{
  "type": "pong",
  "clientId": "abc12345",
  "timestamp": 1700000000000
}
```

#### Disconnection

**Client requests disconnect:**
```json
{
  "type": "disconnect",
  "clientId": "abc12345"
}
```

## Using the Client Library

### Basic Example

```typescript
import { QuakeRelayClient } from '@/lib/quake-ws-client';

// Create client
const client = new QuakeRelayClient({
  serverUrl: 'ws://relay-server:8080',
  autoReconnect: true,
  debug: true,
});

// Register event handlers
client.on('connect', (clientId) => {
  console.log('Connected with ID:', clientId);
});

client.on('data', (packet) => {
  // Pass packet to WASM Quake 3 client
  wasmModule.handleServerPacket(packet);
});

client.on('disconnect', (reason) => {
  console.log('Disconnected:', reason);
});

client.on('error', (error) => {
  console.error('Error:', error);
});

// Connect to relay
await client.connect();

// Send packet from WASM client to server
const packet = new Uint8Array([/* ... */]);
client.sendPacket(packet);

// Disconnect when done
client.disconnect();
```

### React Hook Example

```typescript
import { useQuakeRelay } from '@/hooks/useQuakeRelay';

function QuakeGameComponent() {
  const { connected, clientId, error, sendPacket, on } = useQuakeRelay(
    'ws://relay-server:8080'
  );

  useEffect(() => {
    // Handle incoming packets from server
    on('data', (packet) => {
      console.log('Received packet:', packet);
      // Pass to WASM client
    });

    // Connect when component mounts
    // connect() is called automatically if using the hook
  }, [on]);

  const handleSendPacket = (data) => {
    sendPacket(new Uint8Array(data));
  };

  return (
    <div>
      <div>Status: {connected ? 'Connected' : 'Disconnected'}</div>
      {clientId && <div>Client ID: {clientId}</div>}
      {error && <div className="error">{error}</div>}
      <canvas id="game"></canvas>
    </div>
  );
}
```

## Integrating with WASM Quake 3 Client

Your WASM Quake 3 client needs to:

1. **Listen for socket events** - Replace direct UDP sockets with relay client events
2. **Convert packets** - WASM client sends `Uint8Array` packets to relay
3. **Handle incoming data** - Process relay packets as if they came from server

### Example Integration

```typescript
// In your WASM Quake 3 initialization
import { QuakeRelayClient } from '@/lib/quake-ws-client';

const relayClient = new QuakeRelayClient({
  serverUrl: import.meta.env.VITE_RELAY_SERVER_URL || 'ws://localhost:8080',
});

// Hook up relay events to WASM client
relayClient.on('data', (packet) => {
  // This is what the server sends to your client
  window.wasmModule.Instance.exports.handleNetworkPacket(packet);
});

relayClient.on('connect', (clientId) => {
  console.log('Game relay connected, client ID:', clientId);
  // Signal to WASM that connection is ready
  window.wasmModule.Instance.exports.setRelayConnected(true);
});

relayClient.on('disconnect', () => {
  window.wasmModule.Instance.exports.setRelayConnected(false);
});

relayClient.on('error', (error) => {
  console.error('Relay error:', error);
  window.wasmModule.Instance.exports.onRelayError(error);
});

// Your WASM client calls this to send packets
window.sendGamePacket = (packet) => {
  relayClient.sendPacket(packet);
};

// Connect when ready
await relayClient.connect();
```

## Configuration

### Environment Variables

Set these on the relay server:

```env
# WebSocket server
RELAY_WS_PORT=8080              # WebSocket listen port
RELAY_HOST=0.0.0.0              # Bind address

# Game server connection
GAME_SERVER_HOST=localhost       # ioquake3 server address
GAME_SERVER_PORT=27960           # ioquake3 server port

# Relay settings
MAX_CLIENTS=64                   # Max concurrent WebSocket clients
HEARTBEAT_INTERVAL=30000         # Heartbeat check interval (ms)
DEBUG=false                      # Enable debug logging
```

### Client Configuration

```typescript
const client = new QuakeRelayClient({
  serverUrl: 'ws://relay-server:8080',
  autoReconnect: true,            // Auto-reconnect on disconnect
  reconnectInterval: 3000,        // Wait 3s before first reconnect
  reconnectMaxAttempts: 10,       // Max 10 reconnection attempts
  debug: false,                   // Debug logging
  heartbeatTimeout: 60000,        // 60s inactivity timeout
});
```

## Debugging

### Enable Debug Logging

**Server side:**
```bash
DEBUG=true node relay-server.ts
```

**Client side:**
```typescript
const client = new QuakeRelayClient({
  serverUrl: 'ws://relay-server:8080',
  debug: true,  // Enables console logging
});
```

### Monitor Relay Stats

The relay server logs statistics every 60 seconds:

```
[relay] Stats: 5/64 clients | Sent: 1024000 bytes | Received: 2048000 bytes
```

### WebSocket Debugging

Use browser DevTools Network tab to inspect WebSocket frames:

1. Open DevTools → Network tab
2. Connect your client
3. Look for `relay-server:8080` WebSocket connection
4. Click on it to see individual message frames
5. Messages are JSON, so you can inspect the structure

### Common Issues

#### Connection Timeout
- Check relay server is running: `netstat -an | grep 8080`
- Check firewall allows WebSocket connections
- Verify `GAME_SERVER_HOST` and `GAME_SERVER_PORT` are correct

#### No Packets Received
- Verify game server is running: `netstat -an | grep 27960`
- Enable debug logging to see packet flow
- Check client is sending packets with `sendPacket()`

#### High Latency
- Reduce `HEARTBEAT_INTERVAL` if many clients are idle
- Check network between relay and game server
- Monitor relay CPU/memory with `DEBUG=true`

## Deployment Considerations

### Single Relay Server Capacity

A single relay instance can handle approximately:
- **50-100 concurrent clients** on a 1GB VPS
- **500+ concurrent clients** on a 4GB+ VPS

### Scaling

For more players, consider:

1. **Multiple Relay Instances**
   - Run multiple relay servers pointing to same game server
   - Use load balancer (nginx, HAProxy) on port 8080
   - Clients connect to load balancer

2. **Multiple Game Servers**
   - Run multiple ioquake3 instances on different ports
   - Each relay connects to one game server
   - Client connects to relay matching desired server

3. **Docker Deployment**
   - Scale relay containers with `docker-compose scale relay=3`
   - Put nginx load balancer in front
   - Store relay statistics in Redis for monitoring

### Production Checklist

- [ ] Enable HTTPS/WSS in production (setup reverse proxy with SSL)
- [ ] Set `DEBUG=false` to reduce logging overhead
- [ ] Configure appropriate `MAX_CLIENTS` for your resources
- [ ] Monitor relay metrics (connections, bandwidth, errors)
- [ ] Implement proper error logging/alerting
- [ ] Set up firewall rules (allow 8080/TCP for WebSocket, 27960/UDP for game)
- [ ] Configure auto-restart on crash
- [ ] Regular backup of game server configs

## Troubleshooting Checklist

**Client can't connect:**
1. Verify relay server is running
2. Check firewall isn't blocking port 8080
3. Verify WebSocket URL is correct
4. Check CORS headers (not an issue for WebSocket)
5. Look at browser console for detailed error

**Connection drops frequently:**
1. Increase `heartbeatTimeout` in client config
2. Check network stability
3. Verify relay server isn't out of memory
4. Check game server isn't crashing

**High packet loss:**
1. Verify UDP connection between relay and game server
2. Check network latency
3. Monitor relay CPU usage
4. Consider running relay closer to game server

**Memory leaks:**
1. Ensure clients disconnect properly
2. Check WebSocket connections are closed on disconnect
3. Monitor memory with `free -h` or htop
4. Consider restarting relay periodically

## Additional Resources

- [Quake 3 Network Protocol Documentation](https://www.quake3world.com/)
- [WebSocket Protocol RFC](https://tools.ietf.org/html/rfc6455)
- [ioquake3 Documentation](https://github.com/ioquake/ioq3)
- [Node.js dgram Module](https://nodejs.org/api/dgram.html)
- [WebSocket Client Browser API](https://developer.mozilla.org/en-US/docs/Web/API/WebSocket)
