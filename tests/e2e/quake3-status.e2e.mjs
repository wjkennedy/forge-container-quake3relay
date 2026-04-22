#!/usr/bin/env node
// E2E test against a real Quake 3 server via relay
// Requires ioquake3 to be running with pak0.pk3 present.

import { WebSocket } from 'ws';
import fs from 'node:fs';

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
const TIMEOUT_MS = Number(process.env.TIMEOUT_MS || 12000);

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

async function waitForHealthz(url, timeoutMs) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    try {
      const res = await fetch(url);
      if (res.ok) return true;
    } catch {}
    await sleep(500);
  }
  throw new Error(`Relay healthz not ready at ${url}`);
}

async function main() {
  // Skip if pak0.pk3 not present locally (required to boot ioq3)
  const hasGameData =
    fs.existsSync('baseq3/pak0.pk3') ||
    fs.existsSync('demoq3/pak0.pk3') ||
    fs.existsSync('services/quake3-allinone/baseq3/pak0.pk3') ||
    fs.existsSync('services/quake3-allinone/demoq3/pak0.pk3');

  if (!process.env.Q3_SKIP_ASSET_CHECK && !hasGameData) {
    console.log('SKIP: pak0.pk3 not found; real Q3 E2E requires game assets');
    process.exit(0);
  }

  await waitForHealthz(RELAY_HEALTH_URL, TIMEOUT_MS);

  const hdr = Buffer.from([0xFF, 0xFF, 0xFF, 0xFF]);
  const pktStatus = Buffer.concat([hdr, Buffer.from('getstatus\n', 'ascii')]);
  const pktStatusNoNl = Buffer.concat([hdr, Buffer.from('getstatus', 'ascii')]);
  const pktInfo = Buffer.concat([hdr, Buffer.from('getinfo\n', 'ascii')]);

  const ws = new WebSocket(RELAY_URL);

  const result = await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('timeout waiting for status response')), TIMEOUT_MS);

    ws.on('error', (err) => { clearTimeout(timer); reject(err); });
    ws.on('open', () => {
      // Retry sending getstatus every 500ms until response
      const seq = [pktStatus, pktStatusNoNl, pktInfo];
      let idx = 0;
      const iv = setInterval(() => {
        try { ws.send(seq[idx % seq.length]); idx++; } catch {}
      }, 500);
      ws.once('message', (data) => {
        clearTimeout(timer);
        clearInterval(iv);
        resolve(Buffer.isBuffer(data) ? data : Buffer.from(data));
        ws.close();
      });
    });
  });

  const txt = result.toString('utf8');
  if (!/statusResponse|infoResponse|print/i.test(txt)) {
    console.error('Unexpected server reply:', txt.slice(0, 200));
    process.exit(2);
  }
  console.log('E2E quake3 status passed');
}

main().catch((err) => {
  console.error('E2E Q3 failed:', err.message);
  process.exit(1);
});
