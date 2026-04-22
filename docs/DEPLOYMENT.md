# Quake 3 Relay Server - Deployment Guide

This guide covers deploying the Quake 3 WebSocket-to-UDP relay server to production environments.

## Deployment Architecture

```
                    Internet
                       ↑
          ┌────────────┼────────────┐
          │            │            │
      Client 1     Client 2     Client 3
    (Browser)     (Browser)     (Browser)
          │            │            │
          └────────────┼────────────┘
                       ↓
                   Firewall
                       ↓
    ┌──────────────────────────────────────┐
    │   Load Balancer (nginx/HAProxy)      │
    │   Port: 8080 (WebSocket)             │
    └──────────────────────────────────────┘
           │                    │
           ↓                    ↓
    ┌─────────────┐      ┌─────────────┐
    │ Relay #1    │      │ Relay #2    │
    │ Port: 9001  │      │ Port: 9002  │
    └─────────────┘      └─────────────┘
           │                    │
           └────────────┬───────┘
                        ↓
          ┌─────────────────────────┐
          │  UDP Firewall (port fwd)│
          └─────────────────────────┘
                        ↓
          ┌─────────────────────────┐
          │  Game Server Network    │
          │  (ioquake3 server)      │
          │  Port: 27960 (UDP)      │
          └─────────────────────────┘
```

## Single Relay Deployment

### Option 1: VPS with systemd

#### Prerequisites
- Ubuntu 20.04+ or similar
- Node.js 18+ installed
- Git
- Basic firewall (ufw)

#### Setup

1. **Create application directory**
```bash
sudo mkdir -p /opt/quake3-relay
sudo chown $USER:$USER /opt/quake3-relay
cd /opt/quake3-relay
```

2. **Clone/copy relay code**
```bash
# Clone your repo (update with your actual repo)
git clone https://github.com/yourorg/quake3-relay .
npm install
npm run build
```

3. **Create systemd service**
```bash
sudo tee /etc/systemd/system/quake3-relay.service > /dev/null <<EOF
[Unit]
Description=Quake 3 WebSocket Relay Server
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=/opt/quake3-relay
ExecStart=/usr/bin/node scripts/relay-server.ts

Environment="RELAY_WS_PORT=8080"
Environment="RELAY_HOST=0.0.0.0"
Environment="GAME_SERVER_HOST=game-server-ip"
Environment="GAME_SERVER_PORT=27960"
Environment="MAX_CLIENTS=64"
Environment="DEBUG=false"

Restart=always
RestartSec=10

# Resource limits
LimitNOFILE=65536
LimitNPROC=32768

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable quake3-relay
sudo systemctl start quake3-relay
```

4. **Configure firewall**
```bash
sudo ufw allow 8080/tcp
sudo ufw allow 8080/udp
sudo ufw status
```

5. **Monitor service**
```bash
# View logs
sudo journalctl -u quake3-relay -f

# Check status
sudo systemctl status quake3-relay

# Restart if needed
sudo systemctl restart quake3-relay
```

### Option 2: Docker on VPS

#### Prerequisites
- Docker and Docker Compose installed
- firewall configured

#### Setup

1. **Create application directory**
```bash
mkdir -p /opt/quake3-relay
cd /opt/quake3-relay
```

2. **Copy files**
```bash
# Copy Dockerfile, docker-compose.yml, lib/, scripts/
cp -r /path/to/repo/* .
```

3. **Create .env file**
```bash
cat > .env <<EOF
RELAY_WS_PORT=8080
RELAY_HOST=0.0.0.0
GAME_SERVER_HOST=game-server-ip
GAME_SERVER_PORT=27960
MAX_CLIENTS=64
DEBUG=false
EOF
```

4. **Start with Docker Compose**
```bash
docker-compose up -d

# View logs
docker-compose logs -f relay

# Stop services
docker-compose down
```

5. **Configure firewall**
```bash
sudo ufw allow 8080/tcp
sudo ufw allow 8080/udp
```

### Option 3: Kubernetes

#### Prerequisites
- Kubernetes cluster (k3s, EKS, GKE, etc.)
- kubectl configured
- Container registry (DockerHub, ECR, etc.)

#### Setup

1. **Create Docker image and push to registry**
```bash
docker build -t your-registry/quake3-relay:latest .
docker push your-registry/quake3-relay:latest
```

2. **Create Kubernetes deployment**
```bash
cat > relay-deployment.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: relay-config
data:
  RELAY_WS_PORT: "8080"
  RELAY_HOST: "0.0.0.0"
  GAME_SERVER_HOST: "game-server-ip"
  GAME_SERVER_PORT: "27960"
  MAX_CLIENTS: "64"
  DEBUG: "false"

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: quake3-relay
spec:
  replicas: 1
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
        image: your-registry/quake3-relay:latest
        ports:
        - containerPort: 8080
          name: websocket
        envFrom:
        - configMapRef:
            name: relay-config
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "1Gi"
            cpu: "1"
        livenessProbe:
          tcpSocket:
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10

---
apiVersion: v1
kind: Service
metadata:
  name: quake3-relay-service
spec:
  selector:
    app: quake3-relay
  ports:
  - protocol: TCP
    port: 80
    targetPort: 8080
    name: websocket
  type: LoadBalancer
EOF

kubectl apply -f relay-deployment.yaml
```

3. **Expose service**
```bash
kubectl get service quake3-relay-service

# Port forward for local testing
kubectl port-forward service/quake3-relay-service 8080:80
```

## Scaling to Multiple Relays

### Load Balancing with nginx

```bash
sudo apt-get install nginx
```

Create `/etc/nginx/sites-available/quake3-relay`:

```nginx
upstream relay_backend {
    server 127.0.0.1:9001;
    server 127.0.0.1:9002;
    server 127.0.0.1:9003;
}

map $http_upgrade $connection_upgrade {
    default upgrade;
    '' close;
}

server {
    listen 8080;
    server_name _;

    location / {
        proxy_pass http://relay_backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
    }
}
```

Enable and start:
```bash
sudo ln -s /etc/nginx/sites-available/quake3-relay /etc/nginx/sites-enabled/
sudo systemctl restart nginx
```

### Running Multiple Relay Instances

```bash
# Start relay instances on different ports
RELAY_WS_PORT=9001 node scripts/relay-server.ts &
RELAY_WS_PORT=9002 node scripts/relay-server.ts &
RELAY_WS_PORT=9003 node scripts/relay-server.ts &
```

Or with systemd for each port:
```bash
# Copy service file for each instance
sudo cp /etc/systemd/system/quake3-relay.service /etc/systemd/system/quake3-relay-1.service
# Edit and change port from 8080 to 9001, etc.
sudo systemctl enable --now quake3-relay-{1,2,3}.service
```

## Database Persistence (Optional)

Track relay metrics and player data:

### Option 1: Redis (Session Storage)

```bash
# Install Redis
sudo apt-get install redis-server

# Or Docker
docker run -d --name redis -p 6379:6379 redis:latest
```

Update relay server to use Redis for session tracking:

```typescript
import redis from 'redis';

const redisClient = redis.createClient();

// Store client session
await redisClient.set(
  `relay:client:${clientId}`,
  JSON.stringify({ connectedAt: Date.now(), stats }),
  'EX',
  3600 // 1 hour expiry
);
```

### Option 2: PostgreSQL (Analytics)

```sql
-- Create database
CREATE DATABASE quake3_relay;

-- Create tables
CREATE TABLE relay_sessions (
  id SERIAL PRIMARY KEY,
  client_id VARCHAR(255) UNIQUE,
  connected_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  disconnected_at TIMESTAMP,
  bytes_sent BIGINT,
  bytes_received BIGINT
);

CREATE TABLE relay_packets (
  id SERIAL PRIMARY KEY,
  client_id VARCHAR(255),
  timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  size_bytes INT,
  direction VARCHAR(10), -- 'send' or 'receive'
  FOREIGN KEY (client_id) REFERENCES relay_sessions(client_id)
);

CREATE INDEX idx_client_id ON relay_sessions(client_id);
CREATE INDEX idx_timestamp ON relay_packets(timestamp);
```

## Monitoring & Logging

### System Monitoring

```bash
# Install monitoring tools
sudo apt-get install htop iotop nethogs

# Monitor relay process
watch -n 1 'ps aux | grep relay-server'

# Monitor network
sudo nethogs

# Monitor disk usage
df -h
```

### Application Logging

Set up centralized logging:

```bash
# Install and configure ELK stack or similar
# Example with rsyslog
sudo apt-get install rsyslog
```

Update systemd service:
```ini
StandardOutput=journal
StandardError=journal
```

View logs:
```bash
journalctl -u quake3-relay -f --lines=100
```

### Prometheus Metrics (Optional)

Add Prometheus middleware to relay server:

```typescript
import prometheus from 'prom-client';

const connectedClients = new prometheus.Gauge({
  name: 'relay_connected_clients',
  help: 'Number of connected clients',
});

const packetsReceived = new prometheus.Counter({
  name: 'relay_packets_received_total',
  help: 'Total packets received',
});

const packetsSent = new prometheus.Counter({
  name: 'relay_packets_sent_total',
  help: 'Total packets sent',
});

// Update metrics in relay server
connectedClients.set(this.clients.size);
packetsReceived.inc();
packetsSent.inc();

// Expose /metrics endpoint
app.get('/metrics', (req, res) => {
  res.set('Content-Type', prometheus.register.contentType);
  res.end(prometheus.register.metrics());
});
```

## SSL/TLS (WSS)

For production, use secure WebSockets (WSS):

### With nginx Reverse Proxy

```nginx
server {
    listen 443 ssl http2;
    server_name relay.yourserver.com;

    ssl_certificate /etc/letsencrypt/live/relay.yourserver.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/relay.yourserver.com/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}

# Redirect HTTP to HTTPS
server {
    listen 80;
    server_name relay.yourserver.com;
    return 301 https://$server_name$request_uri;
}
```

Get SSL certificate with certbot:
```bash
sudo certbot certonly --standalone -d relay.yourserver.com
```

Update client to use WSS:
```typescript
const client = new QuakeRelayClient({
  serverUrl: 'wss://relay.yourserver.com',
});
```

## Backup & Recovery

### Backup Configuration

```bash
# Backup relay configs
tar -czf relay-backup-$(date +%Y%m%d).tar.gz \
  /opt/quake3-relay/.env \
  /etc/systemd/system/quake3-relay*.service

# Backup to S3
aws s3 cp relay-backup-*.tar.gz s3://your-backup-bucket/
```

### Restore Process

```bash
# Download backup
aws s3 cp s3://your-backup-bucket/relay-backup-latest.tar.gz .

# Extract
tar -xzf relay-backup-latest.tar.gz -C /

# Restart services
sudo systemctl restart quake3-relay
```

## Performance Tuning

### System Limits

Increase open file descriptors for many clients:

```bash
# Edit /etc/security/limits.conf
sudo tee -a /etc/security/limits.conf > /dev/null <<EOF
*               soft    nofile          65536
*               hard    nofile          65536
*               soft    nproc           32768
*               hard    nproc           32768
EOF

sudo sysctl -w net.core.somaxconn=4096
sudo sysctl -w net.ipv4.tcp_max_syn_backlog=4096
```

### Network Optimization

```bash
# Increase kernel network buffers
sudo sysctl -w net.core.rmem_max=134217728
sudo sysctl -w net.core.wmem_max=134217728
sudo sysctl -w net.ipv4.tcp_rmem="4096 87380 134217728"
sudo sysctl -w net.ipv4.tcp_wmem="4096 65536 134217728"
```

### Node.js Optimization

```bash
# Run with --max-old-space-size for large heaps
node --max-old-space-size=4096 scripts/relay-server.ts
```

## Troubleshooting Deployment

### Can't connect to relay
1. Check firewall: `sudo ufw status`
2. Check service running: `sudo systemctl status quake3-relay`
3. Check logs: `sudo journalctl -u quake3-relay -n 50`
4. Verify DNS: `nslookup relay.yourserver.com`

### High latency
1. Monitor relay CPU/memory
2. Check number of connected clients
3. Check game server connectivity: `nc -u game-server 27960`
4. Consider scaling to multiple relay instances

### Memory leaks
1. Monitor with `top -p $(pgrep -f relay-server.ts)`
2. Check for connection leaks
3. Restart relay periodically if needed
4. Review logs for errors

## Production Checklist

- [ ] DNS records configured
- [ ] SSL/TLS certificates installed
- [ ] Firewall configured (allow 8080 or 443)
- [ ] Systemd service configured with auto-restart
- [ ] Logging configured (journalctl or ELK)
- [ ] Monitoring set up (CPU, memory, connections)
- [ ] Regular backups configured
- [ ] Load balancer configured (if using multiple instances)
- [ ] System limits increased for file descriptors
- [ ] Network tuning applied
- [ ] Health checks configured
- [ ] Alerting configured for errors/failures
- [ ] Documentation updated with server addresses
- [ ] Team trained on restart/recovery procedures

## Next Steps

1. Deploy relay server following one of the options above
2. Configure SSL/TLS for production
3. Set up monitoring and alerting
4. Test failover and recovery procedures
5. Document your deployment for your team
