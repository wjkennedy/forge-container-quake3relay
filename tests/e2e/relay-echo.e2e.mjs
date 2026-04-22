#!/usr/bin/env node
// End-to-end test: WebSocket -> relay -> UDP echo -> relay -> WebSocket

import { WebSocket } from 'ws';

const RELAY_HOST = process.env.RELAY_HOST || '127.0.0.1';
const RELAY_PORT = Number(process.env.RELAY_PORT || 8080);
const RELAY_SCHEME = process.env.RELAY_SCHEME || 'ws';
const RELAY_URL = process.env.RELAY_URL || `${RELAY_SCHEME}://${RELAY_HOST}:${RELAY_PORT}`;
const RELAY_HEALTH_URL = process.env.RELAY_HEALTH_URL || (() => {
  if (!process.env.RELAY_URL) return `http://${RELAY_HOST}:${RELAY_PORT}/healthz`;
  const url = new URL(RELAY_URL);
  url.protocol = url.protocol === 'wss:' ? 'https:' : 'http:';
  url.pathname = '/healthz';
  url.search = '';
  url.hash = '';
  return url.toString();
})();
const TIMEOUT_MS = Number(process.env.TIMEOUT_MS || 10000);

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

async function waitForHealthz(url, timeoutMs) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    try {
      const res = await fetch(url);
      if (res.ok) return true;
    } catch {}
    await sleep(300);
  }
  throw new Error(`Relay healthz not ready at ${url}`);
}

async function main() {
  await waitForHealthz(RELAY_HEALTH_URL, TIMEOUT_MS);

  const ws = new WebSocket(RELAY_URL);
  const payloadText = `hello-${Math.random().toString(36).slice(2)}`;
  const payload = Buffer.from(payloadText);

  const result = await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('timeout waiting for echo')), TIMEOUT_MS);

    ws.on('error', (err) => {
      clearTimeout(timer);
      reject(err);
    });

    ws.on('open', () => {
      ws.send(payload);
    });

    ws.on('message', (data) => {
      clearTimeout(timer);
      const buf = Buffer.isBuffer(data) ? data : Buffer.from(data);
      resolve(buf);
      ws.close();
    });
  });

  const text = result.toString('utf8');
  if (!text.includes(`echo:${payloadText}`)) {
    console.error('Unexpected echo:', text);
    process.exit(2);
  }
  console.log('E2E relay echo passed');
}

main().catch((err) => {
  console.error('E2E failed:', err.message);
  process.exit(1);
});
