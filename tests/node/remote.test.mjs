import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseArgs, buildPayload, remoteCommand } from '../../scripts/remote.mjs';

test('parseArgs splits options from the script invocation', () => {
  const o = parseArgs(['--host', 'sup-a', '--forward-env', 'NIAGARA_PLAT_USER,NIAGARA_PLAT_PASSWORD', '--', 'list-stations.ps1', '-HostAlias', 'local', '-Json']);
  assert.equal(o.host, 'sup-a');
  assert.deepEqual(o.forwardEnv, ['NIAGARA_PLAT_USER', 'NIAGARA_PLAT_PASSWORD']);
  assert.equal(o.script, 'list-stations.ps1');
  assert.deepEqual(o.args, ['-HostAlias', 'local', '-Json']);
});

test('buildPayload ships lib + common + the script and never argv secrets', () => {
  const p = buildPayload('list-stations.ps1', ['-HostAlias', 'local'], { NIAGARA_PLAT_PASSWORD: 'hunter2-secret' });
  const paths = p.files.map(f => f.path);
  assert.ok(paths.includes('lib/plat.ps1'));
  assert.ok(paths.includes('scripts/_common.ps1'));
  assert.ok(paths.includes('scripts/list-stations.ps1'));
  assert.equal(p.env.NIAGARA_PLAT_PASSWORD, 'hunter2-secret');
  assert.ok(!remoteCommand('pwsh').includes('hunter2-secret'), 'secrets stay in the stdin payload');
});

test('remoteCommand is an encoded pwsh invocation', () => {
  assert.match(remoteCommand('pwsh'), /^pwsh -NoProfile -NonInteractive -EncodedCommand [A-Za-z0-9+/=]+$/);
});
