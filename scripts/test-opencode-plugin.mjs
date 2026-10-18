import assert from 'node:assert/strict';
import { mkdtemp, readdir, readFile, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
const root = await mkdtemp(path.join(os.tmpdir(), 'arta-plugin-'));
process.env.ARTA_DATA_DIR = root;
try {
  const { ArtaPlugin } = await import('../Sources/CompanionApp/Resources/Integrations/arta-opencode.mjs');
  const plugin = await ArtaPlugin({ directory: '/tmp/project' });
  await plugin.event({ event: { type: 'session.status', properties: { sessionID: 's', status: { type: 'busy' } } } });
  await plugin.event({ event: { type: 'permission.asked', properties: { sessionID: 's', id: 'q', permission: 'bash' } } });
  await plugin.event({ event: { type: 'permission.replied', properties: { sessionID: 's', requestID: 'q' } } });
  await plugin.event({ event: { type: 'session.idle', properties: { sessionID: 's' } } });
  await plugin.event({ event: { type: 'session.idle', properties: { sessionID: 's' } } });
  const dir = path.join(root, 'events-v1', 'opencode');
  const events = await Promise.all((await readdir(dir)).map(async f => JSON.parse(await readFile(path.join(dir, f), 'utf8'))));
  assert.equal(events.filter(e => e.kind === 'turn.completed').length, 1);
  assert.equal(events.find(e => e.kind === 'input.requested').requestID, 'q');
  assert.equal(events.find(e => e.kind === 'input.resolved').requestID, 'q');
  assert.equal(events.find(e => e.kind === 'turn.started').turnID, events.find(e => e.kind === 'turn.completed').turnID);
  assert(events.every(e => e.integrationID === 'opencode' && e.schemaVersion === 1));
  console.log('OpenCode callback lifecycle and durable spool: passed');
} finally { await rm(root, { recursive: true, force: true }); }
