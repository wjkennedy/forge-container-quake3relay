#!/usr/bin/env node
// Minimal Quake 3 UDP mock for getstatus/getinfo
import dgram from 'node:dgram';

const HOST = process.env.Q3MOCK_HOST || '0.0.0.0';
const PORT = Number(process.env.Q3MOCK_PORT || process.env.TARGET_PORT || 27960);

const sock = dgram.createSocket('udp4');

const HDR = Buffer.from([0xff, 0xff, 0xff, 0xff]);

function respStatus() {
  const info = '\\sv_hostname\\Q3-MOCK\\mapname\\q3dm17\\clients\\0\\sv_maxclients\\8';
  const players = '';
  return Buffer.concat([HDR, Buffer.from('statusResponse\n' + info + '\n' + players, 'ascii')]);
}

function respInfo() {
  const info = '\\sv_hostname\\Q3-MOCK\\mapname\\q3dm17\\clients\\0\\sv_maxclients\\8';
  return Buffer.concat([HDR, Buffer.from('infoResponse\n' + info, 'ascii')]);
}

sock.on('message', (msg, rinfo) => {
  const text = msg.toString('ascii').toLowerCase();
  let out;
  if (text.includes('getstatus')) out = respStatus();
  else if (text.includes('getinfo')) out = respInfo();
  if (out) sock.send(out, rinfo.port, rinfo.address);
});

sock.bind(PORT, HOST, () => {
  console.log(`[q3-mock] listening on udp://${HOST}:${PORT}`);
});

