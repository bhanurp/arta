// Arta-owned OpenCode v1 plugin. Observes lifecycle only; never makes permission decisions.
import { execFileSync } from 'node:child_process';
import { createHash, randomUUID } from 'node:crypto';
import { mkdir, readdir, rename, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';

export const ArtaPlugin = async ({ directory }) => {
  const root = process.env.ARTA_DATA_DIR || path.join(os.homedir(), 'Library/Application Support/ClaudeCompanion');
  const inbox = path.join(root, 'events-v1', 'opencode');
  const runID = randomUUID();
  let processStart;
  let tty;
  try {
    processStart = execFileSync('/bin/ps', ['-p', String(process.pid), '-o', 'lstart='], { encoding: 'utf8', timeout: 1000 }).trim() || undefined;
    const terminal = execFileSync('/bin/ps', ['-p', String(process.pid), '-o', 'tty='], { encoding: 'utf8', timeout: 1000 }).trim();
    if (/^ttys[0-9]+$/.test(terminal)) tty = '/dev/' + terminal;
  } catch {}

  const sessions = new Map();
  let sequence = 0;
  let writes = Promise.resolve();
  const emit = async (sessionID, kind, extra = {}) => {
    if (typeof sessionID !== 'string' || !sessionID || sessionID.length > 512) return;
    const event = {
      schemaVersion: 1, eventID: randomUUID(), integrationID: 'opencode', sourceInstanceID: 'local',
      sessionID, runID, kind, occurredAt: Date.now() / 1000, sourceSequence: ++sequence,
      project: directory || '', host: process.env.__CFBundleIdentifier || process.env.TERM_PROGRAM,
      pid: process.pid, processStart, tty, turnID: sessions.get(sessionID)?.turnID, ...extra,
    };
    await mkdir(inbox, { recursive: true, mode: 0o700 });
    if ((await readdir(inbox)).length >= 20000) return;
    const destination = path.join(inbox, createHash('sha256').update(event.eventID).digest('hex') + '.json');
    const temporary = destination + '.tmp';
    await writeFile(temporary, JSON.stringify(event), { mode: 0o600 });
    await rename(temporary, destination);
  };
  const consume = async ({ event }) => {
    const p = event?.properties || {};
    const id = p.sessionID || p.info?.id;
    if (!id) return;
    switch (event.type) {
      case 'session.created':
        await emit(id, 'session.discovered'); break;
      case 'session.status':
        if (p.status?.type === 'busy' || p.status?.type === 'retry') {
          if (!sessions.get(id)?.busy) {
            sessions.set(id, { busy: true, turnID: randomUUID() });
            await emit(id, 'turn.started');
          }
        } else if (p.status?.type === 'idle' && sessions.get(id)?.busy) {
          sessions.get(id).busy = false;
          await emit(id, 'turn.completed');
        }
        break;
      case 'session.idle':
        if (sessions.get(id)?.busy) {
          sessions.get(id).busy = false;
          await emit(id, 'turn.completed');
        }
        break;
      case 'session.error':
        await emit(id, 'turn.failed', { message: 'OpenCode reported a session error.' });
        if (sessions.has(id)) sessions.get(id).busy = false;
        break;
      case 'session.deleted':
        await emit(id, 'session.closed'); sessions.delete(id); break;
      case 'permission.asked':
        if (p.id) await emit(id, 'input.requested', { requestID: p.id, message: `Permission needed: ${String(p.permission || 'tool').slice(0, 1000)}` });
        break;
      case 'permission.replied':
        if (p.requestID) await emit(id, 'input.resolved', { requestID: p.requestID });
        break;
    }
  };
  return {
    event: input => {
      // Preserve callback ordering even if the harness invokes callbacks concurrently.
      writes = writes.then(() => consume(input)).catch(() => {});
      return writes;
    },
  };
};
