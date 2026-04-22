# Configuration Reference

Complete reference for configuring the Quake 3 relay server, client, and related components.

## Environment Variables

### Relay Server Configuration

Set these on the relay server process.

| Variable | Default | Type | Description |
|----------|---------|------|-------------|
| `RELAY_WS_PORT` | `8080` | Integer | WebSocket server listen port |
| `RELAY_HOST` | `0.0.0.0` | String | Bind address (0.0.0.0 for all interfaces, 127.0.0.1 for localhost) |
| `GAME_SERVER_HOST` | `localhost` | String | ioquake3 server address/hostname |
| `GAME_SERVER_PORT` | `27960` | Integer | ioquake3 server UDP port |
| `MAX_CLIENTS` | `64` | Integer | Maximum concurrent WebSocket clients |
| `HEARTBEAT_INTERVAL` | `30000` | Integer | Heartbeat check interval in milliseconds |
| `DEBUG` | `false` | Boolean | Enable debug logging (`true` or `false`) |

### Example .env File

```bash
# Relay Server Configuration
RELAY_WS_PORT=8080
RELAY_HOST=0.0.0.0
GAME_SERVER_HOST=game-server.example.com
GAME_SERVER_PORT=27960
MAX_CLIENTS=128
HEARTBEAT_INTERVAL=30000
DEBUG=true

# Client Configuration (Next.js public vars)
NEXT_PUBLIC_RELAY_SERVER_URL=ws://localhost:8080
NEXT_PUBLIC_DEBUG_MODE=true
```

## Client Configuration

### QuakeRelayClient Options

```typescript
interface QuakeRelayClientConfig {
  // WebSocket server URL (required)
  serverUrl: string;
  
  // Automatically reconnect on disconnect (default: true)
  autoReconnect: boolean;
  
  // Milliseconds to wait before first reconnection attempt (default: 3000)
  reconnectInterval: number;
  
  // Maximum number of reconnection attempts (default: 10)
  // Set to 0 for infinite retries
  reconnectMaxAttempts: number;
  
  // Enable console debug logging (default: false)
  debug: boolean;
  
  // Milliseconds before marking connection as dead (default: 60000)
  heartbeatTimeout: number;
}
```

### Quickstart Examples

```typescript
// Minimal configuration
const client = new QuakeRelayClient({
  serverUrl: 'ws://localhost:8080'
});

// Development with debugging
const client = new QuakeRelayClient({
  serverUrl: 'ws://localhost:8080',
  debug: true,
  autoReconnect: true
});

// Production with custom timeouts
const client = new QuakeRelayClient({
  serverUrl: 'wss://relay.yourdomain.com',
  autoReconnect: true,
  reconnectInterval: 5000,
  reconnectMaxAttempts: 20,
  heartbeatTimeout: 90000,
  debug: false
});

// Aggressive reconnection for unstable networks
const client = new QuakeRelayClient({
  serverUrl: 'ws://relay-server:8080',
  autoReconnect: true,
  reconnectInterval: 1000,  // Retry quickly
  reconnectMaxAttempts: 0,  // Infinite retries
  heartbeatTimeout: 30000   // Quick timeout detection
});
```

### React Hook Configuration

```typescript
const {
  connected,
  clientId,
  error,
  connecting,
  stats,
  connect,
  disconnect,
  sendPacket,
  on,
  isConnected
} = useQuakeRelay(
  'ws://localhost:8080',
  {
    debug: true,
    autoReconnect: true,
    reconnectInterval: 3000,
    heartbeatTimeout: 60000
  }
);
```

## Game Server Configuration

### ioquake3 Server Settings

Located in `docker/ioquake3/server.cfg` or your server configuration file.

| Setting | Default | Description |
|---------|---------|-------------|
| `sv_hostname` | "Quake3 Server" | Server name shown in browser |
| `sv_maxclients` | 64 | Maximum player count |
| `g_gametype` | 0 | Game type (0=FFA, 1=Tournament, 3=Team, 4=CTF) |
| `g_fraglimit` | 20 | Frag limit for match end |
| `g_timelimit` | 0 | Time limit in minutes (0=unlimited) |
| `g_needpass` | 0 | Password required (1=yes, 0=no) |
| `g_password` | "" | Server password |
| `net_port` | 27960 | Server UDP port |
| `sv_pure` | 1 | Enforce pure server files |
| `sv_cheats` | 0 | Allow cheats (1=yes, 0=no) |
| `sv_floodprotect` | 1 | Protect against packet flooding |
| `g_forcerespawn` | 20 | Force respawn after N seconds |
| `sv_privateClients` | 0 | Reserved slots for server admins |

### Basic Configuration

```cfg
// Deathmatch Server
set sv_hostname "My Quake 3 Server"
set sv_maxclients 16
set g_gametype 0          // FFA
set g_fraglimit 20
set g_timelimit 0
set map q3dm1
set net_port 27960

// CTF Server
set sv_hostname "Capture The Flag"
set sv_maxclients 32
set g_gametype 4          // CTF
set g_fraglimit 0
set g_timelimit 30
set map q3ctf1
set net_port 27960

// Tournament Server
set sv_hostname "Tournament Mode"
set sv_maxclients 4
set g_gametype 1          // Tournament
set g_fraglimit 10
set g_timelimit 0
set map q3dm1
set net_port 27960
```

### Advanced Settings

```cfg
// High performance settings
set sv_maxRate 0          // Unlimited rate
set sv_minPing 0
set sv_maxPing 0
set net_maxclients 512    // Higher than sv_maxclients

// Competitive settings
set sv_pure 1             // Pure server
set sv_cheats 0           // No cheats
set g_allowVote 1         // Allow voting
set sv_allowDownload 1    // Allow file downloads

// Anti-cheat
set sv_strictAuth 1       // Strict authentication
set sv_floodprotect 1
set sv_floodprotect_maxlogs 4
set sv_floodprotect_ignoretime 2

// Weapon settings
set g_knockback 1000      // Knockback force
set g_speed 320           // Player speed
set g_gravity 800         // Gravity

// Respawn settings
set g_respawntime 1700    // Spawn in item respawn time (ms)
set g_forcerespawn 20     // Force respawn after N seconds
set g_inactivity 0        // Kick inactive players (ms, 0=disabled)
```

## Docker Configuration

### docker-compose.yml Override

Create `docker-compose.override.yml` for local development:

```yaml
version: '3.8'

services:
  relay:
    environment:
      - DEBUG=true
      - HEARTBEAT_INTERVAL=15000
      - MAX_CLIENTS=16
    ports:
      - "8080:8080"
      - "9229:9229"  # Node.js debug port
    volumes:
      - ./lib:/app/lib  # Live reload code
      - ./scripts:/app/scripts

  ioquake3:
    environment:
      - MAP_ROTATION=q3dm1,q3dm6,q3dm13
      - MAX_PLAYERS=8
    ports:
      - "27960:27960/udp"
```

### Environment Variables in Docker

Set via `environment` in docker-compose or `docker run -e`:

```bash
# Docker run
docker run -e DEBUG=true -e MAX_CLIENTS=100 quake3-relay

# Docker compose
environment:
  - RELAY_WS_PORT=8080
  - DEBUG=true
  - GAME_SERVER_HOST=ioquake3
```

### Resource Limits

```yaml
services:
  relay:
    resources:
      limits:
        cpus: '1'
        memory: 1G
      reservations:
        cpus: '0.5'
        memory: 512M
```

## Network Configuration

### Firewall Rules

#### UFW (Ubuntu)

```bash
# Allow WebSocket traffic
sudo ufw allow 8080/tcp
sudo ufw allow 8080/udp

# Allow SSH (for management)
sudo ufw allow 22/tcp

# Enable firewall
sudo ufw enable

# Check status
sudo ufw status
```

#### iptables

```bash
# Allow WebSocket
sudo iptables -A INPUT -p tcp --dport 8080 -j ACCEPT

# Allow ioquake3 UDP
sudo iptables -A INPUT -p udp --dport 27960 -j ACCEPT

# Save rules
sudo iptables-save > /etc/iptables/rules.v4
```

### Port Mapping

| Port | Protocol | Service | Purpose |
|------|----------|---------|---------|
| 8080 | TCP | Relay Server | WebSocket connections |
| 27960 | UDP | ioquake3 | Game server |
| 27961 | TCP | ioquake3 | Console (optional) |
| 3000 | TCP | Next.js | Development frontend |

## Performance Tuning

### System Limits

```bash
# /etc/security/limits.conf
* soft nofile 65536
* hard nofile 65536
* soft nproc 32768
* hard nproc 32768
```

### Kernel Parameters

```bash
# /etc/sysctl.conf or via sysctl -w
net.core.somaxconn=4096
net.ipv4.tcp_max_syn_backlog=4096
net.core.rmem_max=134217728
net.core.wmem_max=134217728
net.ipv4.tcp_rmem=4096 87380 134217728
net.ipv4.tcp_wmem=4096 65536 134217728
```

Apply changes:
```bash
sudo sysctl -p
```

### Node.js Configuration

```bash
# Increase heap size
node --max-old-space-size=4096 relay-server.ts

# Enable clustering
NODE_CLUSTER=1 node relay-server.ts

# Set thread pool size
UV_THREADPOOL_SIZE=128 node relay-server.ts
```

## SSL/TLS Configuration

### nginx Configuration

```nginx
server {
    listen 443 ssl http2;
    server_name relay.example.com;

    ssl_certificate /etc/letsencrypt/live/relay.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/relay.example.com/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 86400;
    }
}

server {
    listen 80;
    server_name relay.example.com;
    return 301 https://$server_name$request_uri;
}
```

### Let's Encrypt Certificate

```bash
sudo certbot certonly --standalone -d relay.example.com
sudo certbot renew --dry-run  # Test renewal
```

### Client Configuration for WSS

```typescript
const client = new QuakeRelayClient({
  serverUrl: 'wss://relay.example.com',  // Note: wss:// not ws://
  debug: false
});
```

## Logging Configuration

### systemd Journal

```ini
[Service]
StandardOutput=journal
StandardError=journal
SyslogIdentifier=quake3-relay

# Persistent journal
Environment="SYSTEMD_LOG_LEVEL=debug"
```

View logs:
```bash
journalctl -u quake3-relay -f --lines=100
```

### File Logging

Add to relay server or use journalctl redirection:

```bash
journalctl -u quake3-relay > /var/log/quake3-relay.log
```

Rotate logs with logrotate `/etc/logrotate.d/quake3-relay`:

```
/var/log/quake3-relay.log {
    daily
    rotate 7
    compress
    delaycompress
    notifempty
    create 0640 root root
    sharedscripts
    postrotate
        systemctl reload quake3-relay > /dev/null 2>&1 || true
    endscript
}
```

## Monitoring and Alerts

### Prometheus Configuration

Create `prometheus.yml`:

```yaml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'quake3-relay'
    static_configs:
      - targets: ['localhost:9090']
```

### Alertmanager Configuration

Create `alertmanager.yml`:

```yaml
global:
  resolve_timeout: 5m

route:
  receiver: 'default'

receivers:
  - name: 'default'
    webhook_configs:
      - url: 'http://localhost:5001/'
```

## Configuration Best Practices

1. **Development**: Enable `DEBUG=true`, low timeouts, small `MAX_CLIENTS`
2. **Staging**: `DEBUG=false`, realistic timeouts, medium `MAX_CLIENTS`
3. **Production**: `DEBUG=false`, high timeouts, appropriate `MAX_CLIENTS` for your server
4. **High Load**: Increase `MAX_CLIENTS`, tune kernel limits, consider multiple relays
5. **Unstable Networks**: Lower `heartbeatTimeout`, increase `reconnectMaxAttempts`
6. **Competitive**: High `sv_pure`, `sv_cheats=0`, anti-flood protection
7. **Casual**: Lower limits, public server, voting enabled

## Configuration Validation

### Check Environment Variables

```bash
# Linux/Mac
env | grep -i relay
env | grep -i game_server

# Windows
set | findstr /i relay
```

### Test Relay Connection

```bash
# Check relay is listening
netstat -an | grep 8080

# Test game server reachability
nc -u localhost 27960

# Test WebSocket (requires wscat)
wscat -c ws://localhost:8080
```

### Validate Docker Configuration

```bash
# Check docker-compose syntax
docker-compose config

# Validate Dockerfile
docker build --dry-run .

# Check resources
docker stats --no-stream
```

## Troubleshooting Configuration Issues

### Relay not starting
- Check `GAME_SERVER_HOST` is resolvable: `ping $GAME_SERVER_HOST`
- Verify `RELAY_WS_PORT` is not in use: `lsof -i :$RELAY_WS_PORT`
- Check logs: `DEBUG=true node relay-server.ts`

### Clients disconnecting
- Check `heartbeatTimeout` value (may be too aggressive)
- Verify network stability
- Check relay resource usage

### High CPU usage
- Reduce `HEARTBEAT_INTERVAL`
- Limit `MAX_CLIENTS`
- Enable connection pooling

### Memory leaks
- Update Node.js version
- Check for unclosed connections in logs
- Monitor with `node --inspect`

## Next Steps

1. Set up your `.env` file with your specific values
2. Test with the configuration locally
3. Validate connectivity with test tools
4. Monitor the relay in production
5. Adjust settings based on performance metrics

See `docs/DEPLOYMENT.md` for production-specific configurations.
