# WASM Quake 3 Client Integration Guide

This guide explains how to integrate your WASM Quake 3 client with the relay server to enable WebSocket communication for multiplayer gameplay.

## Overview

Your WASM Quake 3 module currently handles game logic and rendering. To connect to the relay server:

1. Replace direct UDP socket calls with relay client calls
2. Wrap outgoing packets with relay message protocol
3. Handle incoming relay packets in your game loop
4. Manage connection state and reconnection

## Architecture

```
WASM Quake 3 Module
    ↓ (game logic)
Relay Bridge (quake-wasm-bridge.ts)
    ↓ (JSON WebSocket messages)
Relay Client (quake-ws-client.ts)
    ↓ (WebSocket protocol)
Relay Server
    ↓ (UDP translation)
ioquake3 Server
```

## Step 1: Identify WASM Module Interface

First, understand your WASM module's network interface. Your module needs to expose:

```typescript
// Functions your WASM module exports
exports: {
  // Called when client wants to send a packet
  sendClientPacket: (bufferPtr: number, length: number) => void;
  
  // Called when you want to pass server data to game
  handleServerPacket: (packet: Uint8Array) => void;
  
  // Connection state management
  setRelayConnected: (connected: number) => void;
  isNetworkReady: () => number;
  
  // Player configuration
  setPlayerName: (namePtr: number, nameLen: number) => void;
  
  // Game state
  getGameState: () => number;
  
  // Memory management
  memory: WebAssembly.Memory;
  malloc: (size: number) => number;
  free: (ptr: number) => void;
}
```

## Step 2: Load WASM Module

```typescript
import { QuakeWasmRelayBridge } from '@/lib/quake-wasm-bridge';

async function initializeQuakeGame() {
  // Load WASM module
  const wasmModule = await loadQuake3Wasm();
  
  // Create relay bridge
  const bridge = new QuakeWasmRelayBridge(
    wasmModule,
    'ws://relay-server:8080'
  );
  
  // Initialize connection
  await bridge.initialize('YourPlayerName');
  
  // Start game loop
  gameLoop(wasmModule, bridge);
}

async function loadQuake3Wasm() {
  const response = await fetch('/wasm/quake3.wasm');
  const wasmBinary = await response.arrayBuffer();
  
  const wasmModule = await WebAssembly.instantiate(wasmBinary);
  return wasmModule;
}
```

## Step 3: Game Loop Integration

```typescript
function gameLoop(wasmModule: WasmQuake3Module, bridge: QuakeWasmRelayBridge) {
  const canvas = document.getElementById('game-canvas') as HTMLCanvasElement;
  const ctx = canvas.getContext('2d')!;
  
  function tick(timestamp: DOMHighResTimeStamp) {
    // Update WASM game logic
    // This should call into WASM to update game state
    // wasmModule.Instance.exports.update(timestamp);
    
    // Render to canvas
    // wasmModule.Instance.exports.render(canvasPtr);
    
    // Send outgoing packets
    const state = wasmModule.Instance.exports.getGameState();
    if (state & 0x01) { // Has packet to send
      const packet = readPacketFromWasm(wasmModule);
      bridge.sendPacket(packet);
    }
    
    requestAnimationFrame(tick);
  }
  
  requestAnimationFrame(tick);
}

function readPacketFromWasm(wasmModule: WasmQuake3Module): Uint8Array {
  // Read packet buffer from WASM memory
  // Implement based on your WASM module's packet format
  const memory = wasmModule.Instance.exports.memory;
  const view = new Uint8Array(memory.buffer);
  
  // Assuming WASM stores packet at offset 0 with length at offset -4
  const lengthView = new DataView(memory.buffer);
  const length = lengthView.getUint32(0, true);
  const packet = new Uint8Array(view.slice(4, 4 + length));
  
  return packet;
}
```

## Step 4: Handle Incoming Packets

The relay bridge automatically calls `handleServerPacket` in your WASM module when packets arrive from the server. Make sure your WASM module handles this:

```c
// In your WASM Quake 3 C code
void handleServerPacket(uint8_t* packet, int length) {
  // Parse packet according to Q3 protocol
  // Update game state based on packet
  // This is typically where you'd call CL_ParsePacket or similar
  
  // Example:
  memcpy(&net_message.data[net_message.cursize], packet, length);
  net_message.cursize += length;
  // Process with your normal packet handler
}
```

## Step 5: Connection Management

The bridge automatically handles reconnection, but you need to respond to connection state changes:

```typescript
// In your game UI
function GameStatus({ bridge }: { bridge: QuakeWasmRelayBridge }) {
  const stats = bridge.getStats();
  
  return (
    <div>
      {stats.connected ? (
        <>
          <p>Connected to relay</p>
          <p>Client ID: {stats.clientId}</p>
        </>
      ) : (
        <p>Connecting to relay server...</p>
      )}
    </div>
  );
}

// Handle disconnect events
bridge.relayClient.on('disconnect', (reason) => {
  console.log('Disconnected from relay:', reason);
  // Pause game or show reconnection UI
  showReconnectionDialog();
});

bridge.relayClient.on('error', (error) => {
  console.error('Relay error:', error);
  // Show error to player
  showErrorMessage(error);
});
```

## Step 6: React Component Integration

```typescript
import { useQuakeWasmRelay } from '@/lib/quake-wasm-bridge';

function QuakeGameComponent() {
  const [wasmModule, setWasmModule] = React.useState<WasmQuake3Module | null>(null);
  const { connected, error, initialize, sendPacket, disconnect } = 
    useQuakeWasmRelay(wasmModule, 'ws://relay-server:8080');

  // Load WASM module
  React.useEffect(() => {
    (async () => {
      const module = await loadQuake3Wasm();
      setWasmModule(module);
    })();
  }, []);

  // Initialize relay connection
  const handleStartGame = React.useCallback(async () => {
    await initialize('Player_1');
  }, [initialize]);

  return (
    <div>
      <canvas id="game-canvas" width={800} height={600} />
      
      <div>
        Status: {connected ? 'Connected' : 'Connecting...'}
        {error && <p className="error">{error}</p>}
      </div>
      
      <button onClick={handleStartGame} disabled={connected}>
        Start Game
      </button>
    </div>
  );
}
```

## WASM Module Modifications Required

Your WASM Quake 3 module needs to be modified to:

### 1. Accept Relay Packets

Currently your module probably:
```c
// OLD: Direct UDP receive
void NET_GetPacket() {
  while (recvfrom(socket, buffer, ...) > 0) {
    // Process packet
    CL_ParsePacket();
  }
}
```

Should become:
```c
// NEW: Relay-compatible
void handleServerPacket(uint8_t* packet, int length) {
  // JavaScript calls this with relay packets
  
  // Create message from packet
  msg_t msg;
  MSG_InitOOB(&msg, packet, length);
  
  // Parse using existing Q3 parser
  CL_ParsePacket();
}

// JavaScript bridge calls this
void sendClientPacket(uint8_t* buffer, int length) {
  // Send to relay instead of UDP socket
  // Bridge receives this and calls relayClient.sendPacket()
}
```

### 2. Integrate with Game Loop

```c
// In your main loop
void GameLoop() {
  while (1) {
    // ... your game logic ...
    
    // Check if relay is connected
    if (relay_connected) {
      // Process incoming packets
      // These arrive via handleServerPacket() from relay
      
      // Build and send outgoing packets
      // These are sent via sendClientPacket() to relay
    } else {
      // Show connecting screen
    }
  }
}
```

### 3. Handle Connection State

```c
// New functions to integrate with relay state
void setRelayConnected(int connected) {
  relay_connected = connected;
  if (!connected) {
    // Reset connection state
    CL_Disconnect();
  }
}

int isNetworkReady() {
  return relay_connected;
}

int getGameState() {
  // Return flags indicating if there's data to send
  return (output_buffer_has_data ? 0x01 : 0x00);
}
```

## Performance Considerations

### Packet Batching

If your WASM module sends many small packets, consider batching:

```typescript
// Instead of sending each packet individually
for (let packet of packets) {
  bridge.sendPacket(packet); // Inefficient
}

// Batch into one larger packet
const batchedPacket = new Uint8Array(packets.reduce((a, b) => a + b.length, 0));
let offset = 0;
for (let packet of packets) {
  batchedPacket.set(packet, offset);
  offset += packet.length;
}
bridge.sendPacket(batchedPacket); // Better
```

### Memory Management

Be careful with WASM memory allocation:

```typescript
// GOOD: Allocate once, reuse
const bufferPtr = wasmModule.Instance.exports.malloc(65536);
// Reuse bufferPtr for multiple operations
wasmModule.Instance.exports.free(bufferPtr);

// BAD: Allocate on every frame
requestAnimationFrame(() => {
  const ptr = wasmModule.Instance.exports.malloc(100);
  // ... use ...
  // Forgot to free! Memory leak
});
```

### Rendering Performance

Keep relay communication off the main render thread if possible:

```typescript
// Use Web Worker for relay communication
const relayWorker = new Worker('relay-worker.ts');

relayWorker.onmessage = (event) => {
  if (event.data.type === 'packet') {
    // Pass received packet to WASM
    wasmModule.Instance.exports.handleServerPacket(event.data.packet);
  }
};

// Send packet from worker
relayWorker.postMessage({
  type: 'send',
  packet: outgoingPacket
});
```

## Debugging

### Enable Debug Logging

```typescript
// In your bridge initialization
const bridge = new QuakeWasmRelayBridge(wasmModule, 'ws://relay-server:8080');

// The bridge logs to console with [wasm-relay] prefix
// Look for messages like:
// [wasm-relay] Connected with client ID: abc12345
// [wasm-relay] Received packet: 128 bytes
// [wasm-relay] Error handling server packet: ...
```

### Monitor Packet Flow

```typescript
// Intercept packets for debugging
const originalSendPacket = bridge.sendPacket.bind(bridge);
bridge.sendPacket = (packet: Uint8Array) => {
  console.log('[debug] Sending packet:', {
    size: packet.length,
    header: Array.from(packet.slice(0, 8)).map(b => '0x' + b.toString(16).padStart(2, '0')).join(' ')
  });
  originalSendPacket(packet);
};
```

### Browser DevTools

1. Open DevTools → Network tab
2. Filter for WebSocket connections
3. Click on `relay-server` connection
4. View individual frame messages
5. Packets show as JSON with base64 data

## Common Integration Issues

### "WASM memory out of bounds"

```typescript
// Problem: Buffer pointer is invalid
const ptr = 0xFFFFFFFF; // Invalid
wasmModule.Instance.exports.handleServerPacket(ptr); // Crash

// Solution: Use proper allocation
const ptr = wasmModule.Instance.exports.malloc(packet.length);
```

### "Packets not being sent"

```typescript
// Check 1: Bridge is initialized
if (!bridge.isConnected()) {
  console.log('Not connected, queuing packet');
  return;
}

// Check 2: Relay client is connected
console.log('Relay connected:', bridge.relayClient.isConnected());

// Check 3: Enable debug logging
// DEBUG=true in relay server
// debug: true in QuakeRelayClient config
```

### "High latency despite low network latency"

```typescript
// Problem: Too many small packets
// Solution 1: Batch packets
// Solution 2: Reduce packet size
// Solution 3: Increase transmission interval

// Check WASM module isn't doing expensive work on main thread
// Consider using Web Workers for heavy lifting
```

## Next Steps

1. **Modify your WASM module** to support relay communication
2. **Test locally** with `docker-compose up`
3. **Integrate bridge** into your React component
4. **Test multiplayer** with multiple browser instances
5. **Deploy relay** to production following `docs/DEPLOYMENT.md`

## Additional Resources

- [WebAssembly MDN Docs](https://developer.mozilla.org/en-US/docs/WebAssembly)
- [Quake 3 Protocol Specification](https://www.quake3world.com/)
- [Relay Protocol Specification](./RELAY_INTEGRATION.md)
- [Example Bridge Code](../lib/quake-wasm-bridge.ts)

## Support

For issues integrating your WASM client:

1. Ensure WASM module exports all required functions
2. Enable debug logging on both relay and client
3. Check browser console for [wasm-relay] messages
4. Verify relay server is running and game server is reachable
5. Review the example component in `components/QuakeGameClient.tsx`
