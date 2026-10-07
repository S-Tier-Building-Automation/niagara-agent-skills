#!/usr/bin/env node
// Run a skill script on a remote host over SSH without copying anything to argv.
// The library + the named script travel in a base64 tar payload over stdin; the remote side
// unpacks into a temp dir, runs the script with the forwarded arguments, prints its output
// (including the NIAGARA_AGENT_RESULT_JSON line) and deletes the temp dir. Exit code is propagated.
//
//   node scripts/remote.mjs --host <ssh-alias> [--shell pwsh|powershell] [--forward-env A,B] [--timeout 900] -- <script.ps1> [args...]
//
// Zero dependencies; Node >= 18. Credentials are resolved on the remote host by its own provider
// unless --forward-env names variables to send INSIDE the stdin payload (never on the command line).
import { spawn, execFileSync } from 'node:child_process';
import { readFileSync, existsSync, readdirSync, statSync } from 'node:fs';
import { join, dirname, basename, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, '..');

function usage(msg) {
  if (msg) console.error(`remote.mjs: ${msg}`);
  console.error('usage: node scripts/remote.mjs --host <ssh-alias> [--shell pwsh|powershell] [--forward-env A,B] [--timeout sec] -- <script.ps1> [args...]');
  process.exit(2);
}

export function parseArgs(argv) {
  const opts = { host: null, shell: 'pwsh', forwardEnv: [], timeout: 900, script: null, args: [] };
  let i = 0;
  for (; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--') { i++; break; }
    if (a === '--host') opts.host = argv[++i];
    else if (a === '--shell') opts.shell = argv[++i];
    else if (a === '--forward-env') opts.forwardEnv = (argv[++i] || '').split(',').map(s => s.trim()).filter(Boolean);
    else if (a === '--timeout') opts.timeout = Number(argv[++i]);
    else usage(`unknown option ${a}`);
  }
  opts.script = argv[i];
  opts.args = argv.slice(i + 1);
  if (!opts.host) usage('--host is required');
  if (!/^[A-Za-z0-9][A-Za-z0-9._@-]{0,127}$/.test(opts.host)) usage('invalid ssh alias');
  if (!['pwsh', 'powershell'].includes(opts.shell)) usage('--shell must be pwsh or powershell');
  if (!opts.script || !/^[A-Za-z0-9_-]+\.ps1$/.test(opts.script)) usage('script must be a bare name like restart-station.ps1');
  for (const v of opts.forwardEnv) if (!/^[A-Z][A-Z0-9_]*$/.test(v)) usage(`invalid env name ${v}`);
  for (const a of opts.args) if (/[\r\n\0]/.test(a)) usage('arguments must not contain newlines');
  return opts;
}

function collectFiles(dir, prefix, out) {
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    const rel = prefix ? `${prefix}/${name}` : name;
    if (statSync(p).isDirectory()) collectFiles(p, rel, out);
    else out.push({ rel, data: readFileSync(p) });
  }
}

export function buildPayload(scriptName, args, env) {
  const files = [];
  collectFiles(join(root, 'lib'), 'lib', files);
  const script = join(root, 'scripts', scriptName);
  if (!existsSync(script)) usage(`script not found: ${script}`);
  files.push({ rel: 'scripts/_common.ps1', data: readFileSync(join(root, 'scripts', '_common.ps1')) });
  files.push({ rel: `scripts/${scriptName}`, data: readFileSync(script) });
  return {
    files: files.map(f => ({ path: f.rel, b64: f.data.toString('base64') })),
    script: scriptName,
    args,
    env,
  };
}

// The remote bootstrap: reads the JSON payload from stdin, writes files under a temp dir,
// sets env vars, runs the script, propagates the exit code and cleans up.
const BOOTSTRAP = String.raw`
$ErrorActionPreference = 'Stop'
$raw = [Console]::In.ReadToEnd()
$p = $raw | ConvertFrom-Json
$dir = Join-Path ([System.IO.Path]::GetTempPath()) ('niagara-agent-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $dir | Out-Null
try {
  foreach ($f in $p.files) {
    $dest = Join-Path $dir $f.path
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
    [System.IO.File]::WriteAllBytes($dest, [Convert]::FromBase64String($f.b64))
  }
  if ($p.env) { foreach ($k in $p.env.PSObject.Properties.Name) { [Environment]::SetEnvironmentVariable($k, [string]$p.env.$k, 'Process') } }
  $script = Join-Path $dir 'scripts' $p.script
  & $script @($p.args)
  $code = $LASTEXITCODE
  if ($null -eq $code) { $code = 0 }
} catch {
  Write-Output ('NIAGARA_AGENT_RESULT_JSON:' + (@{ ok = $false; error = $_.Exception.Message } | ConvertTo-Json -Compress))
  $code = 1
} finally {
  Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
}
exit $code
`;

export function remoteCommand(shell) {
  // -EncodedCommand keeps the bootstrap off the remote shell's quoting rules; stdin carries the payload.
  const enc = Buffer.from(BOOTSTRAP, 'utf16le').toString('base64');
  return `${shell} -NoProfile -NonInteractive -EncodedCommand ${enc}`;
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  const env = {};
  for (const v of opts.forwardEnv) if (process.env[v] !== undefined) env[v] = process.env[v];
  const payload = buildPayload(opts.script, opts.args, env);
  const ssh = spawn('ssh', ['-o', 'BatchMode=yes', opts.host, remoteCommand(opts.shell)], { stdio: ['pipe', 'inherit', 'inherit'] });
  const timer = setTimeout(() => { console.error(`remote.mjs: timeout after ${opts.timeout}s`); ssh.kill('SIGTERM'); process.exitCode = 124; }, opts.timeout * 1000);
  ssh.stdin.end(JSON.stringify(payload));
  ssh.on('exit', (code) => { clearTimeout(timer); if (process.exitCode !== 124) process.exit(code ?? 1); });
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((e) => { console.error(`remote.mjs: ${e.message}`); process.exit(1); });
}
