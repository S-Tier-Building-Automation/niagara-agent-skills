#!/usr/bin/env node
// CI gate: the repo must stay generic. Fails on anything that looks like a credential, a vault
// reference, a private hostname/IP outside documentation examples, or a real-looking plat password.
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';

const root = new URL('..', import.meta.url).pathname;
const SKIP_DIRS = new Set(['.git', 'node_modules']);
const RULES = [
  { name: 'vault reference', re: /op:\/\/[^\s"'`]+/g, allow: (f, m) => /op\.example\.ps1$/.test(f) && /op:\/\/Vault\//.test(m) },
  { name: 'plat password on argv', re: /-pwd:(?!\*|\$|<)[^\s"'`)]+/g, allow: (f, m) => /tests\/|docs\//.test(f) && /-pwd:(x|y|secret|hunter2|pw)\b/.test(m) },
  { name: 'private IPv4', re: /\b(10\.\d{1,3}\.\d{1,3}\.\d{1,3}|172\.(1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3}|192\.168\.\d{1,3}\.\d{1,3})\b/g, allow: () => false },
  { name: 'bearer / api key', re: /\b(sk-[A-Za-z0-9]{16,}|ghp_[A-Za-z0-9]{20,}|xox[abp]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16})\b/g, allow: () => false },
  { name: 'private key block', re: /-----BEGIN [A-Z ]*PRIVATE KEY-----/g, allow: () => false },
  { name: 'password literal', re: /password\s*[:=]\s*["'](?!\$|<|\{)[^"'\s]{4,}["']/gi, allow: (f, m) => /tests\//.test(f) || /["'](s|pw|x|hunter2|envpass|Sécret|example)["']$/.test(m) },
];

function walk(dir, out) {
  for (const name of readdirSync(dir)) {
    if (SKIP_DIRS.has(name)) continue;
    const p = join(dir, name);
    if (statSync(p).isDirectory()) walk(p, out); else out.push(p);
  }
}
const files = []; walk(root, files);
let bad = 0;
for (const f of files) {
  const rel = relative(root, f);
  if (/\.(png|jpg|ico|jar|zip)$/.test(rel) || rel === 'tests/check-secrets.mjs') continue;
  const text = readFileSync(f, 'utf8');
  for (const rule of RULES) {
    for (const m of text.matchAll(rule.re)) {
      if (/[\\(|]/.test(m[0]) && /lib\/audit\.ps1|tests\//.test(rel)) continue; // regex patterns, not values
      if (rule.allow(rel, m[0])) continue;
      const line = text.slice(0, m.index).split('\n').length;
      console.error(`${rel}:${line}: ${rule.name}: ${m[0].slice(0, 60)}`);
      bad++;
    }
  }
}
if (bad) { console.error(`check-secrets: ${bad} finding(s)`); process.exit(1); }
console.log(`check-secrets: ${files.length} files clean`);
