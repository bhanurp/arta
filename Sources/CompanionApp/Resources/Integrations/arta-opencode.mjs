// Arta-owned OpenCode v1 plugin. Observes lifecycle only; never makes permission decisions.
import { execFileSync } from 'node:child_process';
import { createHash, randomUUID } from 'node:crypto';
import { mkdirSync, readdirSync, renameSync, writeFileSync } from 'node:fs';
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
  const invocations = new Map();
  const observe = (input, args, output, starting) => {
    if (input.tool !== 'bash' || typeof input.callID !== 'string' || typeof input.sessionID !== 'string') return;
    const prior = invocations.get(input.callID);
    const command = starting ? args?.command : prior?.command || args?.command;
    if (typeof command !== 'string' || command.length > 48000 || !/^(?:\S*\/)?(?:swift\s+(?:test|build|format\s+lint)|pytest(?:\s|$)|python3\s+-m\s+pytest|cargo\s+test|go\s+test)/.test(command)) return;
    if (starting) invocations.set(input.callID, { command, turnID: sessions.get(input.sessionID)?.busy ? sessions.get(input.sessionID).turnID : undefined });
    const value = {
      schemaVersion: 1, eventID: randomUUID(), integrationID: 'opencode', sourceInstanceID: 'local',
      sessionID: input.sessionID, producerEpoch: runID,
      kind: starting ? 'tool.started' : 'tool.finished', occurredAt: Date.now() / 1000,
      turnID: starting ? (sessions.get(input.sessionID)?.busy ? sessions.get(input.sessionID).turnID : undefined) : prior?.turnID,
      invocationID: input.callID, workspace: directory || '', command,
    };
    // Completion alone is not a successful exit. Only preserve explicit typed tool metadata.
    if (!starting && Number.isInteger(output?.metadata?.exit)) value.exitCode = output.metadata.exit;
    const destination = path.join(root, 'observations-v1', 'opencode');
    mkdirSync(destination, {recursive:true,mode:0o700});
    if (readdirSync(destination).length < 20000) {
      const file = path.join(destination, createHash('sha256').update('opencode:' + value.eventID).digest('hex') + '.json');
      writeFileSync(file + '.tmp', JSON.stringify(value), {mode:0o600}); renameSync(file + '.tmp', file);
    }
    if (!starting) invocations.delete(input.callID);
  };
  let sequence = 0;
  const emit = (sessionID, kind, extra = {}) => {
    if (typeof sessionID !== 'string' || !sessionID || sessionID.length > 512) return;
    const event = {
      schemaVersion: 1, eventID: randomUUID(), integrationID: 'opencode', sourceInstanceID: 'local',
      sessionID, runID, kind, occurredAt: Date.now() / 1000, sourceSequence: ++sequence,
      project: directory || '', host: process.env.__CFBundleIdentifier || process.env.TERM_PROGRAM,
      pid: process.pid, processStart, tty, turnID: sessions.get(sessionID)?.turnID, ...extra,
    };
    mkdirSync(inbox, { recursive: true, mode: 0o700 });
    if (readdirSync(inbox).length >= 20000) return;
    const destination = path.join(inbox, createHash('sha256').update(event.eventID).digest('hex') + '.json');
    const temporary = destination + '.tmp';
    writeFileSync(temporary, JSON.stringify(event), { mode: 0o600 });
    renameSync(temporary, destination);
  };
  const consume = ({ event }) => {
    const p = event?.properties || {};
    const id = p.sessionID || p.info?.id;
    if (!id) return;
    switch (event.type) {
      case 'session.created':
        emit(id, 'session.discovered', { sessionName: p.info?.title }); break;
      case 'session.updated':
        emit(id, 'session.updated', { sessionName: p.info?.title }); break;
      case 'session.status':
        if (p.status?.type === 'busy' || p.status?.type === 'retry') {
          if (!sessions.get(id)?.busy) {
            sessions.set(id, { busy: true, turnID: randomUUID() });
            emit(id, 'turn.started');
          }
        } else if (p.status?.type === 'idle' && sessions.get(id)?.busy) {
          sessions.get(id).busy = false;
          emit(id, 'turn.completed');
        }
        break;
      case 'session.idle':
        if (sessions.get(id)?.busy) {
          sessions.get(id).busy = false;
          emit(id, 'turn.completed');
        }
        break;
      case 'session.error':
        emit(id, 'turn.failed', { message: 'OpenCode reported a session error.' });
        if (sessions.has(id)) sessions.get(id).busy = false;
        break;
      case 'session.deleted':
        emit(id, 'session.closed'); sessions.delete(id); break;
      case 'permission.asked':
        if (p.id) emit(id, 'input.requested', { requestID: p.id, message: `Permission needed: ${String(p.permission || 'tool').slice(0, 1000)}` });
        break;
      case 'permission.replied':
        if (p.requestID) emit(id, 'input.resolved', { requestID: p.requestID });
        break;
    }
  };
  return {
    'tool.execute.before': async (input, output) => { try { observe(input, output.args, undefined, true); } catch {} },
    'tool.execute.after': async (input, output) => { try { observe(input, input.args, output, false); } catch {} },
    event: input => {
      // OpenCode may exit immediately after this callback without awaiting its promise.
      // Publish the small local event atomically before returning; never lose terminal events.
      try { consume(input); } catch {}
    },
  };
};
