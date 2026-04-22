#!/usr/bin/env node
// Simple UDP echo server for relay E2E tests
import dgram from 'node:dgram';

const HOST = process.env.ECHO_HOST || '0.0.0.0';
const PORT = Number(process.env.ECHO_PORT || process.env.TARGET_PORT || 27960);

const socket = dgram.createSocket('udp4');

socket.on('error', (err) => {
  console.error('[udp-echo] socket error:', err);
  process.exit(1);
});

socket.on('message', (msg, rinfo) => {
  // Echo payload back unchanged; prefix for visibility if text
  let out = msg;
  try {
    const asText = msg.toString('utf8');
    if (/^[\x20-\x7E\r\n\t]*$/.test(asText)) {
      out = Buffer.from(`echo:${asText}`);
    }
  } catch {}
  socket.send(out, rinfo.port, rinfo.address);
});

socket.bind(PORT, HOST, () => {
  console.log(`[udp-echo] listening on udp://${HOST}:${PORT}`);
});

