#!/usr/bin/env node

import dns from 'node:dns/promises';
import { execFile as execFileCallback } from 'node:child_process';
import { promisify } from 'node:util';
import { WebSocket } from 'ws';

const RELAY_URL = process.env.RELAY_URL || 'wss://q3a.a9group.net';
const TIMEOUT_MS = Number(process.env.TIMEOUT_MS || 15000);
const execFile = promisify(execFileCallback);

async function main() {
  const url = new URL(RELAY_URL);
  const port = Number(url.port || (url.protocol === 'wss:' ? 443 : 80));
  const host = url.hostname;
  const path = `${url.pathname || '/'}${url.search || ''}`;

  let candidates = await resolveWithNode(host);

  if (candidates.length === 0) {
    candidates = await resolveWithDig(host);
  }

  if (candidates.length === 0) {
    throw new Error(`public DNS did not resolve ${host} via 1.1.1.1`);
  }

  let lastError = null;
  for (const ip of candidates) {
    try {
      const result = await probeIp({
        ip,
        host,
        path,
        port,
        secure: url.protocol === 'wss:',
      });
      console.log(`WebSocket check passed via ${ip}`);
      console.log(result.slice(0, 200));
      return;
    } catch (error) {
      lastError = error;
    }
  }

  throw lastError || new Error('websocket probe failed');
}

async function resolveWithNode(host) {
  for (const server of ['1.1.1.1', '1.0.0.1']) {
    const resolver = new dns.Resolver();
    resolver.setServers([server]);

    const ipv4 = await resolver.resolve4(host).catch(() => []);
    const ipv6 = await resolver.resolve6(host).catch(() => []);
    const candidates = [...ipv4, ...ipv6];
    if (candidates.length > 0) {
      return candidates;
    }
  }

  return [];
}

async function resolveWithDig(host) {
  for (const args of [
    ['@1.1.1.1', '+short', host],
    ['@1.0.0.1', '+short', host],
    ['+short', host],
  ]) {
    try {
      const { stdout } = await execFile('dig', args, {
        timeout: TIMEOUT_MS,
      });
      const candidates = stdout
        .split(/\r?\n/)
        .map(line => line.trim())
        .filter(Boolean);
      if (candidates.length > 0) {
        return candidates;
      }
    } catch {
      // Try the next resolver path.
    }
  }

  try {
    const { stdout } = await execFile('getent', ['hosts', host], {
      timeout: TIMEOUT_MS,
    });
    return stdout
      .split(/\r?\n/)
      .flatMap(line => line.trim().split(/\s+/).slice(0, 1))
      .filter(Boolean);
  } catch {
    return [];
  }
}

function probeIp({ ip, host, path, port, secure }) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(`${secure ? 'wss' : 'ws'}://${ip}:${port}${path}`, {
      servername: secure ? host : undefined,
      headers: { Host: host },
      rejectUnauthorized: true,
    });

    const timer = setTimeout(() => {
      ws.terminate();
      reject(new Error(`timeout waiting for relay response via ${ip}`));
    }, TIMEOUT_MS);

    const hdr = Buffer.from([0xff, 0xff, 0xff, 0xff]);
    const pkt = Buffer.concat([hdr, Buffer.from('getinfo\n', 'ascii')]);

    ws.on('open', () => {
      ws.send(pkt);
    });

    ws.on('message', (data) => {
      clearTimeout(timer);
      const text = Buffer.from(data).toString('utf8');
      ws.close();
      if (!/infoResponse|statusResponse|print/i.test(text)) {
        reject(new Error(`unexpected relay response via ${ip}: ${text.slice(0, 120)}`));
        return;
      }
      resolve(text);
    });

    ws.on('error', (error) => {
      clearTimeout(timer);
      reject(error);
    });
  });
}

main().catch((error) => {
  console.error(`WebSocket check failed: ${error.message}`);
  process.exit(1);
});
