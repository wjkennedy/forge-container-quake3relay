#!/usr/bin/env node

/**
 * Enhanced Quake 3 WebSocket ↔ UDP Relay Server
 * Based on production-proven q3js relay architecture
 * 
 * Features:
 * - Binary WebSocket ↔ UDP bridging
 * - CORS support
 * - Healthz endpoint
 * - Connection metrics
 * - Proper backpressure handling
 * - Clean error handling
 */

import dgram from 'node:dgram';
import fs from 'node:fs';
import http from 'node:http';
import { WebSocket, WebSocketServer } from 'ws';

// Configuration from environment
const TARGET_HOST = process.env.TARGET_HOST || '127.0.0.1';
const TARGET_PORT = Number(process.env.TARGET_PORT || 27960);
const PROXY_PORT = Number(process.env.PROXY_PORT || 8080);
const PROXY_HOST = process.env.PROXY_HOST || '0.0.0.0';
const DEBUG = process.env.DEBUG === 'true';
const DEFAULT_PUBLIC_RELAY_HEALTH_URL = process.env.PUBLIC_RELAY_HEALTH_URL || 'https://q3a.a9group.net/healthz';
const DEFAULT_PUBLIC_RELAY_WEBSOCKET_URL = process.env.PUBLIC_RELAY_WEBSOCKET_URL || 'wss://q3a.a9group.net';
const DEFAULT_DIAG_TIMEOUT_MS = Number(process.env.PUBLIC_RELAY_DIAG_TIMEOUT_MS || 10000);
const CLOUDFLARED_TUNNEL_LOG = process.env.CLOUDFLARED_TUNNEL_LOG || '/tmp/cloudflared.log';
const GAME_PID_FILE = process.env.GAME_PID_FILE || '/tmp/q3-game.pid';
const RELAY_PID_FILE = process.env.RELAY_PID_FILE || '/tmp/q3-relay.pid';
const CLOUDFLARED_PID_FILE = process.env.CLOUDFLARED_PID_FILE || '/tmp/cloudflared.pid';
const CLOUDFLARED_TUNNEL_NAME = process.env.CLOUDFLARED_TUNNEL_NAME || null;
const CLOUDFLARED_TUNNEL_ID = process.env.CLOUDFLARED_TUNNEL_ID || null;

// Metrics
let activeConnections = 0;
let totalConnections = 0;
let totalBytesIn = 0;
let totalBytesOut = 0;

function setCorsHeaders(res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
}

function sendJson(res, statusCode, payload) {
  setCorsHeaders(res);
  res.writeHead(statusCode, { 'Content-Type': 'application/json; charset=utf-8' });
  res.end(JSON.stringify(payload));
}

function truncate(value, maxLength) {
  if (typeof value !== 'string' || value.length <= maxLength) {
    return value;
  }
  return value.slice(0, maxLength);
}

function rootMessage(error) {
  let current = error;
  while (current?.cause) current = current.cause;
  return current?.message || String(current);
}

function readPidFile(path) {
  try {
    const value = fs.readFileSync(path, 'utf8').trim();
    return value ? Number(value) : null;
  } catch {
    return null;
  }
}

function isPidRunning(pid) {
  if (!pid || !Number.isFinite(pid)) {
    return false;
  }

  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

function tailFile(path, maxLines) {
  try {
    const content = fs.readFileSync(path, 'utf8');
    return content.split(/\r?\n/).filter(Boolean).slice(-maxLines);
  } catch {
    return [];
  }
}

function decodeTunnelIdFromToken(token) {
  if (typeof token !== 'string' || token.length < 20) {
    return null;
  }

  try {
    const payload = JSON.parse(Buffer.from(token, 'base64').toString('utf8'));
    return payload?.t || null;
  } catch {
    return null;
  }
}

async function probeHealth(url, timeoutMs) {
  const startedAt = Date.now();
  try {
    const response = await fetch(url, { method: 'GET', signal: AbortSignal.timeout(timeoutMs) });
    const body = await response.text();
    return {
      ok: response.ok,
      statusCode: response.status,
      latencyMs: Date.now() - startedAt,
      bodySnippet: truncate(body, 400),
    };
  } catch (error) {
    return {
      ok: false,
      latencyMs: Date.now() - startedAt,
      error: rootMessage(error),
    };
  }
}

function probeWebSocket(url, timeoutMs) {
  const startedAt = Date.now();
  return new Promise((resolve) => {
    let settled = false;
    const timer = setTimeout(() => {
      if (settled) return;
      settled = true;
      try { ws.close(); } catch {}
      resolve({
        ok: false,
        latencyMs: Date.now() - startedAt,
        error: `Timed out after ${timeoutMs}ms`,
      });
    }, timeoutMs);

    const ws = new WebSocket(url);

    const finish = (payload) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolve(payload);
    };

    ws.on('open', () => {
      finish({
        ok: true,
        latencyMs: Date.now() - startedAt,
        state: 'opened',
      });
      try { ws.close(1000, 'diagnostic'); } catch {}
    });

    ws.on('error', (error) => {
      finish({
        ok: false,
        latencyMs: Date.now() - startedAt,
        error: rootMessage(error),
      });
    });

    ws.on('close', (code) => {
      if (!settled) {
        finish({
          ok: code === 1000,
          latencyMs: Date.now() - startedAt,
          state: `closed:${code}`,
        });
      }
    });
  });
}

const httpServer = http.createServer(async (req, res) => {
  if (req.method === 'OPTIONS') {
    setCorsHeaders(res);
    res.writeHead(204);
    res.end();
    return;
  }

  const url = new URL(req.url || '/', 'http://127.0.0.1');

  if (req.method === 'GET' && url.pathname === '/healthz') {
    sendJson(res, 200, {
      ok: true,
      activeConnections,
      totalConnections,
      totalBytesIn,
      totalBytesOut,
      targetHost: TARGET_HOST,
      targetPort: TARGET_PORT,
    });
    return;
  }

  if (req.method === 'GET' && url.pathname === '/') {
    sendJson(res, 200, {
      name: 'Quake3 WebSocket↔UDP Relay',
      version: '1.0.0',
      activeConnections,
      totalConnections,
      targetHost: TARGET_HOST,
      targetPort: TARGET_PORT,
      proxyPort: PROXY_PORT,
    });
    return;
  }

  if (req.method === 'GET' && url.pathname === '/diag/public-relay') {
    const healthUrl = url.searchParams.get('healthUrl') || DEFAULT_PUBLIC_RELAY_HEALTH_URL;
    const websocketUrl = url.searchParams.get('websocketUrl') || DEFAULT_PUBLIC_RELAY_WEBSOCKET_URL;
    const timeoutMs = Number(url.searchParams.get('timeoutMs') || DEFAULT_DIAG_TIMEOUT_MS);

    const https = await probeHealth(healthUrl, timeoutMs);
    const websocket = await probeWebSocket(websocketUrl, timeoutMs);

    sendJson(res, 200, {
      timestamp: new Date().toISOString(),
      healthUrl,
      websocketUrl,
      timeoutMs,
      https,
      websocket,
      ok: Boolean(https.ok && websocket.ok),
    });
    return;
  }

  if (req.method === 'GET' && url.pathname === '/diag/runtime') {
    const maxLines = Number(url.searchParams.get('logLines') || 80);
    const gamePid = readPidFile(GAME_PID_FILE);
    const relayPid = readPidFile(RELAY_PID_FILE);
    const cloudflaredPid = readPidFile(CLOUDFLARED_PID_FILE);

    const tokenTunnelId = decodeTunnelIdFromToken(process.env.CLOUDFLARED_TOKEN || '');
    sendJson(res, 200, {
      timestamp: new Date().toISOString(),
      processes: {
        game: { pid: gamePid, running: isPidRunning(gamePid) },
        relay: { pid: relayPid, running: isPidRunning(relayPid) },
        cloudflared: { pid: cloudflaredPid, running: isPidRunning(cloudflaredPid) },
      },
      cloudflared: {
        enabled: process.env.ENABLE_CLOUDFLARED === 'true' || process.env.ENABLE_CLOUDFLARED === '1',
        originUrl: process.env.CLOUDFLARED_ORIGIN_URL || `http://127.0.0.1:${PROXY_PORT}`,
        protocol: process.env.CLOUDFLARED_PROTOCOL || 'http2',
        configuredTunnelName: CLOUDFLARED_TUNNEL_NAME,
        configuredTunnelId: CLOUDFLARED_TUNNEL_ID,
        tokenTunnelId,
        tokenMatchesConfiguredId: tokenTunnelId && CLOUDFLARED_TUNNEL_ID ? tokenTunnelId === CLOUDFLARED_TUNNEL_ID : null,
        logPath: CLOUDFLARED_TUNNEL_LOG,
        recentLogLines: tailFile(CLOUDFLARED_TUNNEL_LOG, maxLines),
      },
    });
    return;
  }

  sendJson(res, 404, { error: 'Not found' });
});

const wss = new WebSocketServer({ server: httpServer });

httpServer.listen(PROXY_PORT, PROXY_HOST, () => {
  console.log(`[Relay] WS↔UDP relay listening on ws://${PROXY_HOST}:${PROXY_PORT}/`);
  console.log(`[Relay] Target: ${TARGET_HOST}:${TARGET_PORT}`);
  console.log(`[Relay] Debug: ${DEBUG}`);
});

wss.on('connection', (ws, req) => {
  const clientIp = req.socket.remoteAddress || 'unknown';
  const connId = Math.random().toString(36).substring(7);
  activeConnections++;
  totalConnections++;

  if (DEBUG) {
    console.log(`[${connId}] Client connected from ${clientIp} | Active: ${activeConnections}`);
  }

  const udp = dgram.createSocket('udp4');

  // Bidirectional forwarding: UDP → WS
  udp.on('message', (msg) => {
    if (ws.readyState === ws.OPEN) {
      totalBytesOut += msg.length;
      ws.send(msg, (err) => {
        if (err && DEBUG) console.warn(`[${connId}] WS send error:`, err.message);
      });
      if (DEBUG) console.log(`[${connId}] UDP→WS: ${msg.length} bytes`);
    }
  });

  udp.on('error', (err) => {
    console.warn(`[${connId}] UDP error:`, err.message);
    try {
      udp.close();
    } catch {}
  });

  // Bidirectional forwarding: WS → UDP
  ws.on('message', (data) => {
    try {
      const buf = Buffer.isBuffer(data) ? data : Buffer.from(data);
      totalBytesIn += buf.length;
      if (DEBUG) console.log(`[${connId}] WS→UDP: ${buf.length} bytes`);

      udp.send(buf, TARGET_PORT, TARGET_HOST, (sendErr) => {
        if (sendErr) {
          console.warn(`[${connId}] UDP send error:`, sendErr.message);
        }
      });
    } catch (e) {
      console.warn(`[${connId}] WS message error:`, e.message);
    }
  });

  // Clean up both connections
  const close = () => {
    if (ws.readyState === ws.OPEN) {
      try {
        ws.close();
      } catch {}
    }
    try {
      udp.close();
    } catch {}
    activeConnections--;
    if (DEBUG) console.log(`[${connId}] Client disconnected | Active: ${activeConnections}`);
  };

  ws.on('close', close);
  ws.on('error', (err) => {
    if (DEBUG) console.warn(`[${connId}] WS error:`, err.message);
    close();
  });
});

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('[Relay] SIGTERM received, shutting down gracefully...');
  wss.close(() => {
    httpServer.close(() => {
      console.log('[Relay] Relay server closed');
      process.exit(0);
    });
  });
});

process.on('SIGINT', () => {
  console.log('[Relay] SIGINT received, shutting down gracefully...');
  wss.close(() => {
    httpServer.close(() => {
      console.log('[Relay] Relay server closed');
      process.exit(0);
    });
  });
});
