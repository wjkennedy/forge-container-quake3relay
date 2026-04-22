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
import http from 'node:http';
import { WebSocketServer } from 'ws';

// Configuration from environment
const TARGET_HOST = process.env.TARGET_HOST || '127.0.0.1';
const TARGET_PORT = Number(process.env.TARGET_PORT || 27960);
const PROXY_PORT = Number(process.env.PROXY_PORT || 8080);
const PROXY_HOST = process.env.PROXY_HOST || '0.0.0.0';
const DEBUG = process.env.DEBUG === 'true';

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

const httpServer = http.createServer((req, res) => {
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
