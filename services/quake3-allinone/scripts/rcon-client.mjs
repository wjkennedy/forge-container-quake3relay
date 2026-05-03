#!/usr/bin/env node

import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const Rcon = require('rcon');

const command = process.argv.slice(2).join(' ').trim();
const host = process.env.RCON_HOST || process.env.TARGET_HOST || '127.0.0.1';
const port = Number(process.env.RCON_PORT || process.env.GAME_PORT || process.env.TARGET_PORT || 27960);
const password = process.env.RCON_PASSWORD || 'sphere';
const timeoutMs = Number(process.env.RCON_TIMEOUT_MS || 5000);
const options = {
  tcp: parseBool(process.env.RCON_TCP, false),
  challenge: parseBool(process.env.RCON_CHALLENGE, false),
};

if (!command) {
  console.error('Usage: node /opt/forge-q3/scripts/rcon-client.mjs <command ...>');
  process.exit(1);
}

const client = new Rcon(host, port, password, options);
const timer = setTimeout(() => {
  console.error(`[rcon] Timed out after ${timeoutMs}ms connecting to ${host}:${port}`);
  process.exit(1);
}, timeoutMs);

client
  .on('auth', () => {
    client.send(command);
  })
  .on('response', (response) => {
    clearTimeout(timer);
    if (response) {
      process.stdout.write(response.endsWith('\n') ? response : `${response}\n`);
    }
    process.exit(0);
  })
  .on('error', (error) => {
    clearTimeout(timer);
    console.error(`[rcon] ${error?.message || error}`);
    process.exit(1);
  })
  .on('end', () => {
    clearTimeout(timer);
  });

client.connect();

function parseBool(value, fallback) {
  if (value == null || value === '') {
    return fallback;
  }

  return value === '1' || value.toLowerCase() === 'true';
}
