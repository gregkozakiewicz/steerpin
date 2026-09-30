#!/usr/bin/env node
// Steerpin: moves marks from the global inbox into the project and into Claude's context.
//
//   steerpin.mjs hook             UserPromptSubmit hook (reads hook JSON on stdin)
//   steerpin.mjs session-start    SessionStart hook (reads hook JSON on stdin)
//   steerpin.mjs list             process the inbox, then print active marks
//   steerpin.mjs unmark <id...>   remove marks by id
//   steerpin.mjs clear            remove all priority and wrong marks
//   steerpin.mjs undo             take back what the last message delivered
//   steerpin.mjs add <type> [text]      mark text directly (text from args or stdin)
//   steerpin.mjs capture <type> [text]  append to the global inbox (for other hotkey tools)

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const TYPES = ['priority', 'wrong', 'roadmap', 'later'];
const ACTIVE_TYPES = ['priority', 'wrong'];
const HOME = process.env.STEERPIN_HOME || path.join(os.homedir(), '.steerpin');
const INBOX = path.join(HOME, 'inbox.jsonl');
const PROJECTS = path.join(HOME, 'projects.json');
const MAX_PROJECTS = 20;
const CLAIM_PREFIX = 'inbox.jsonl.claim-';
const STALE_CLAIM_MS = 30_000;
const MARKS_REL = '.claude/steerpin/marks.md';
const CONFIG_REL = '.claude/steerpin/config.json';
const UNDO_REL = '.claude/steerpin/last-delivery.json';
const IGNORE_LINE = '.claude/steerpin/';
const MAX_CONTEXT_CHARS = 9000;
const DEFAULTS = {
  roadmap: '.claude/steerpin/roadmap.md',
  later: '.claude/steerpin/later.md',
  maxActiveMarks: 15,
  maxMarkLength: 500,
};
const FILE_HEADINGS = { roadmap: '# Roadmap', later: '# Later' };

// ---------- project + config ----------

function projectDir(input) {
  return process.env.CLAUDE_PROJECT_DIR || input?.cwd || process.cwd();
}

// Reads .claude/steerpin/config.json. Bad settings fall back to the defaults and are named in
// `problems`, so the user hears about them instead of the hook failing quietly. List paths must
// stay inside the project: a cloned repo could otherwise point them at a dotfile.
function loadConfig(dir) {
  const cfg = { ...DEFAULTS };
  const problems = [];
  let raw;
  try {
    raw = fs.readFileSync(path.join(dir, CONFIG_REL), 'utf8');
  } catch {
    return { cfg, problems };
  }
  let user;
  try {
    user = JSON.parse(raw);
  } catch {
    return { cfg, problems: ['the whole file, it is not valid JSON'] };
  }
  if (!user || typeof user !== 'object' || Array.isArray(user)) {
    return { cfg, problems: ['the whole file, it is not a JSON object'] };
  }
  for (const key of ['roadmap', 'later']) {
    if (!(key in user)) continue;
    if (typeof user[key] === 'string' && insideProject(dir, user[key])) cfg[key] = user[key];
    else problems.push(`${key} (must be a path inside the project)`);
  }
  for (const key of ['maxActiveMarks', 'maxMarkLength']) {
    if (!(key in user)) continue;
    if (Number.isInteger(user[key]) && user[key] > 0) cfg[key] = user[key];
    else problems.push(`${key} (must be a positive whole number)`);
  }
  return { cfg, problems };
}

// True when `rel` names a file below `dir`. Lexical only; symlinks are checked at write time.
function insideProject(dir, rel) {
  const relative = path.relative(dir, path.resolve(dir, rel));
  return relative !== '' && !isOutside(relative);
}

const isOutside = (relative) =>
  relative === '..' || relative.startsWith(`..${path.sep}`) || path.isAbsolute(relative);

// ---------- inbox ----------

// Claims the inbox by renaming it, so hotkeys writing at the same moment start a fresh file.
// Claims left behind by a crashed run are picked up once they are stale.
function takeInbox() {
  let names;
  try {
    names = fs.readdirSync(HOME);
  } catch {
    return { items: [], claims: [] };
  }
  const now = Date.now();
  const claims = [];
  for (const name of names) {
    if (name !== 'inbox.jsonl') {
      if (!name.startsWith(CLAIM_PREFIX)) continue;
      const claimedAt = Number(name.slice(CLAIM_PREFIX.length).split('-')[0]);
      if (!(now - claimedAt > STALE_CLAIM_MS)) continue;
    }
    const target = path.join(HOME, `${CLAIM_PREFIX}${now}-${process.pid}-${claims.length}`);
    try {
      fs.renameSync(path.join(HOME, name), target);
      claims.push(target);
    } catch {
      // another session claimed it first
    }
  }

  const items = [];
  for (const file of claims) {
    const lines = fs.readFileSync(file, 'utf8').split('\n');
    for (const line of lines) {
      if (!line.trim()) continue;
      try {
        const item = normalizeItem(JSON.parse(line));
        if (item) items.push(item);
      } catch {
        // skip malformed lines
      }
    }
  }
  return { items, claims };
}

function releaseClaims(claims) {
  for (const file of claims) fs.rmSync(file, { force: true });
}

function normalizeItem(raw) {
  if (!raw || !TYPES.includes(raw.type) || typeof raw.text !== 'string') return null;
  const text = cleanText(raw.text);
  if (!text) return null;
  return {
    type: raw.type,
    text,
    timestamp: raw.timestamp || new Date().toISOString(),
    source: raw.source_app || raw.source || '',
  };
}

function cleanText(text) {
  return text
    .replace(/\r\n?/g, '\n')
    .split('\n')
    .map((l) => l.replace(/\s+$/, ''))
    .join('\n')
    .replace(/^\n+|\n+$/g, '')
    .trim();
}

const sameText = (a, b) => a.replace(/\s+/g, ' ').trim() === b.replace(/\s+/g, ' ').trim();

// ---------- marks.md ----------

function marksPath(dir) {
  return path.join(dir, MARKS_REL);
}

function readMarks(dir) {
  let content;
  try {
    content = fs.readFileSync(marksPath(dir), 'utf8');
  } catch {
    return { nextId: 1, marks: [] };
  }
  const marks = [];
  const header = /^## \[(\d+)\] (priority|wrong)[ \t]*$/gm;
  const found = [...content.matchAll(header)];
  found.forEach((m, i) => {
    const bodyStart = m.index + m[0].length;
    const bodyEnd = i + 1 < found.length ? found[i + 1].index : content.length;
    const lines = content.slice(bodyStart, bodyEnd).split('\n');
    while (lines.length && !lines[0].trim()) lines.shift();
    let meta = '';
    if (lines.length && /^_.*_$/.test(lines[0].trim())) meta = lines.shift().trim().slice(1, -1);
    const text = lines.map((l) => l.replace(/^\\(## \[)/, '$1')).join('\n').trim();
    if (text) marks.push({ id: Number(m[1]), type: m[2], meta, text });
  });
  const stored = content.match(/steerpin: next-id=(\d+)/);
  const maxId = marks.reduce((max, m) => Math.max(max, m.id), 0);
  return { nextId: Math.max(stored ? Number(stored[1]) : 1, maxId + 1), marks };
}

function writeMarks(dir, state) {
  const file = marksPath(dir);
  const parts = [
    '# Steerpin marks',
    '',
    `<!-- steerpin: next-id=${state.nextId}. Managed by the steerpin plugin. Remove marks with /steerpin:unmark <id>, or delete a section by hand. -->`,
  ];
  for (const m of state.marks) {
    parts.push('', `## [${m.id}] ${m.type}`);
    if (m.meta) parts.push(`_${m.meta}_`);
    parts.push('', m.text.replace(/^## \[/gm, '\\## ['));
  }
  writeAtomic(safeTarget(dir, file), parts.join('\n') + '\n', PRIVATE);
}

// ---------- writing files ----------

const PRIVATE = 0o600;
const O_NOFOLLOW = fs.constants.O_NOFOLLOW ?? 0;

class UnsafePathError extends Error {}

// The real path to write to, once `file` is known to sit inside `root` with no symlink in the way.
// A repo can commit `.claude/steerpin/later.md` as a symlink to a dotfile, so writes never follow one.
function safeTarget(root, file) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const parent = fs.realpathSync(path.dirname(file));
  const shown = path.relative(root, file);
  if (isOutside(path.relative(fs.realpathSync(root), parent))) {
    throw new UnsafePathError(`${shown} points outside the project`);
  }
  let stat;
  try {
    stat = fs.lstatSync(file);
  } catch {
    // new file
  }
  if (stat?.isSymbolicLink()) throw new UnsafePathError(`${shown} is a symlink`);
  return path.join(parent, path.basename(file));
}

// Appends without ever truncating, so a crash mid-write cannot empty the user's file.
function appendFile(file, text, mode) {
  const flags = fs.constants.O_WRONLY | fs.constants.O_APPEND | fs.constants.O_CREAT | O_NOFOLLOW;
  const fd = fs.openSync(file, flags, mode);
  try {
    const buf = Buffer.from(text);
    let done = 0;
    while (done < buf.length) done += fs.writeSync(fd, buf, done, buf.length - done);
  } finally {
    fs.closeSync(fd);
  }
}

function writeAtomic(file, content, mode) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const tmp = `${file}.${process.pid}.tmp`;
  fs.writeFileSync(tmp, content, { mode });
  fs.renameSync(tmp, file);
}

function metaLine(item) {
  const d = new Date(item.timestamp);
  const valid = !Number.isNaN(d.getTime());
  const pad = (n) => String(n).padStart(2, '0');
  const date = valid
    ? `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`
    : String(item.timestamp);
  return item.source ? `${date} · marked in ${item.source}` : date;
}

// ---------- processing ----------

const emptyResult = () => ({ newIds: [], saved: {}, skipped: 0, refused: [] });

// Applies inbox items to the project. Returns what changed, for the context block and user message.
function applyItems(dir, cfg, items) {
  const result = emptyResult();
  if (!items.length) return result;

  const state = readMarks(dir);
  let marksChanged = false;
  const undo = [];

  for (const item of items) {
    if (ACTIVE_TYPES.includes(item.type)) {
      const existing = state.marks.find((m) => sameText(m.text, item.text));
      if (existing && existing.type === item.type) {
        result.skipped++;
        continue;
      }
      if (existing) state.marks = state.marks.filter((m) => m !== existing); // re-marked as the other type
      const mark = { id: state.nextId++, type: item.type, meta: metaLine(item), text: item.text };
      state.marks.push(mark);
      result.newIds.push(mark.id);
      undo.push({ kind: 'mark', id: mark.id, replaced: existing ?? null });
      marksChanged = true;
    } else {
      const rel = cfg[item.type];
      let entry;
      try {
        entry = appendToList(dir, rel, item);
      } catch (err) {
        if (!(err instanceof UnsafePathError)) throw err;
        result.refused.push(err.message); // the item is dropped, and the user is told why
        continue;
      }
      if (entry) {
        result.saved[rel] = (result.saved[rel] || 0) + 1;
        undo.push({ kind: 'list', type: item.type, file: rel, entry });
      } else {
        result.skipped++;
      }
    }
  }

  if (marksChanged) writeMarks(dir, state);
  if (undo.length) {
    writeAtomic(safeTarget(dir, path.join(dir, UNDO_REL)), JSON.stringify(undo, null, 2) + '\n', PRIVATE);
  }
  if (marksChanged || Object.keys(result.saved).length) result.gitignored = ensureGitignore(dir);
  return result;
}

// Keeps steerpin's files out of git: adds .claude/steerpin/ to the repo's .gitignore once.
function ensureGitignore(dir) {
  if (!fs.existsSync(path.join(dir, '.git'))) return false;
  const file = path.join(dir, '.gitignore');
  let content = '';
  try {
    content = fs.readFileSync(file, 'utf8');
  } catch {
    // no .gitignore yet
  }
  const covered = content
    .split('\n')
    .map((l) => l.trim().replace(/^\//, '').replace(/\/?\*{0,2}$/, ''))
    .some((l) => l === '.claude' || l === '.claude/steerpin');
  if (covered) return false;
  let target;
  try {
    target = safeTarget(dir, file);
  } catch (err) {
    if (err instanceof UnsafePathError) return false;
    throw err;
  }
  const sep = content && !content.endsWith('\n') ? '\n' : '';
  appendFile(target, `${sep}${IGNORE_LINE}\n`);
  return true;
}

function appendToList(dir, relPath, item) {
  const file = safeTarget(dir, path.resolve(dir, relPath));
  let content = '';
  try {
    content = fs.readFileSync(file, 'utf8');
  } catch {
    // new file
  }
  const [first, ...rest] = item.text.split('\n');
  const entry = [`- ${first}`, ...rest.map((l) => (l ? `  ${l}` : '')), `  _${metaLine(item)}_`].join('\n');
  const body = entry.slice(0, entry.lastIndexOf('\n  _'));
  if (content.includes(body)) return null;
  let head = `${FILE_HEADINGS[item.type]}\n\nItems saved with steerpin.\n`;
  if (content) head = content.endsWith('\n') ? '' : '\n';
  appendFile(file, `${head}\n${entry}\n`);
  return entry;
}

function processInbox(dir, cfg) {
  const inbox = takeInbox();
  const result = applyItems(dir, cfg, inbox.items);
  releaseClaims(inbox.claims);
  return result;
}

// ---------- context ----------

function renderContext(marks, result, cfg) {
  if (!marks.length) return { text: '', truncated: [] };
  const shown = marks.slice(-cfg.maxActiveMarks);
  const hidden = marks.length - shown.length;
  const truncated = [];
  let budget = MAX_CONTEXT_CHARS;

  const line = (m) => {
    let t = m.text;
    if (t.length > cfg.maxMarkLength) {
      t = `${t.slice(0, cfg.maxMarkLength).trimEnd()} … [truncated, full text in ${MARKS_REL}]`;
      truncated.push(m.id);
    }
    const body = m.type === 'wrong' ? `"${t}"` : t;
    return `[${m.id}] ${body.replace(/\n/g, '\n    ')}`;
  };

  const out = ['USER MARKS (set by the user by highlighting text in this chat)'];
  const priority = shown.filter((m) => m.type === 'priority');
  const wrong = shown.filter((m) => m.type === 'wrong');
  const section = (title, list) => {
    if (!list.length) return;
    out.push('', title);
    for (const m of list) {
      const l = line(m);
      if (l.length > budget) continue;
      budget -= l.length;
      out.push(l);
    }
  };
  section('Priority, keep these at the top of your attention:', priority);
  section(
    'Flagged as wrong, do not rely on or repeat these. If anything\nyou said or built depends on them, say so briefly and correct it:',
    wrong,
  );

  const notes = [];
  if (result.newIds.length) {
    notes.push(`New since last message: ${result.newIds.map((id) => `[${id}]`).join(' ')}`);
    const newWrong = shown.filter((m) => m.type === 'wrong' && result.newIds.includes(m.id));
    if (newWrong.length) {
      notes.push(
        `Start your reply with one short line per new wrong mark, e.g. "Noted, [${newWrong[0].id}] was wrong: <what is actually true>". Then answer the message.`,
      );
    }
  }
  if (hidden > 0) notes.push(`${hidden} older mark${hidden === 1 ? '' : 's'} not shown (limit ${cfg.maxActiveMarks}), see ${MARKS_REL}`);
  if (notes.length) out.push('', ...notes);
  out.push('', 'The user can list marks with /steerpin:marks and remove them with /steerpin:unmark <id>.');
  return { text: out.join('\n'), truncated };
}

function userMessage(result, truncated, configProblems = []) {
  const parts = [];
  if (result.newIds.length) parts.push(`new mark${result.newIds.length === 1 ? '' : 's'} ${result.newIds.map((id) => `[${id}]`).join(' ')}`);
  for (const [rel, n] of Object.entries(result.saved)) parts.push(`${n} saved to ${rel}`);
  for (const why of result.refused) parts.push(`not saved: ${why}`);
  const newTruncated = truncated.filter((id) => result.newIds.includes(id));
  if (newTruncated.length) parts.push(`${newTruncated.map((id) => `[${id}]`).join(' ')} truncated in context (long selection)`);
  if (result.gitignored) parts.push(`added ${IGNORE_LINE} to .gitignore`);
  if (configProblems.length) parts.push(`${CONFIG_REL}: ignoring ${configProblems.join(', ')}`);
  return parts.length ? `steerpin: ${parts.join('; ')}` : '';
}

// Keeps the Steerpin app's list of recent projects, newest first, so its menu can show them by name.
function rememberProject(dir, cfg) {
  let projects = [];
  try {
    projects = JSON.parse(fs.readFileSync(PROJECTS, 'utf8'));
  } catch {
    // first project
  }
  const entry = {
    project: dir,
    marks: marksPath(dir),
    roadmap: path.resolve(dir, cfg.roadmap),
    later: path.resolve(dir, cfg.later),
    lastUsed: new Date().toISOString(),
  };
  projects = [entry, ...projects.filter((p) => p.project !== dir)].slice(0, MAX_PROJECTS);
  privateHome();
  writeAtomic(PROJECTS, JSON.stringify(projects, null, 2) + '\n', PRIVATE);
  fs.rmSync(path.join(HOME, 'last-project.json'), { force: true }); // replaced by projects.json
}

// Marked text can hold anything the user selected, secrets included, so ~/.steerpin is owner-only.
function privateHome() {
  fs.mkdirSync(HOME, { recursive: true, mode: 0o700 });
  try {
    fs.chmodSync(HOME, 0o700);
  } catch {
    // not ours to change (or Windows)
  }
}

// Marks belong to the project, so a brand-new chat inherits them. Say so, so the user can start fresh.
// Resumed and compacted chats are continuations and stay quiet.
function carriedOverNotice(source, marks, result) {
  if (source !== 'startup' && source !== 'clear') return '';
  const old = marks.filter((m) => !result.newIds.includes(m.id));
  if (!old.length) return '';
  const count = (type) => old.filter((m) => m.type === type).length;
  const parts = [];
  if (count('priority')) parts.push(`${count('priority')} priority`);
  if (count('wrong')) parts.push(`${count('wrong')} wrong`);
  const n = old.length;
  return `steerpin: ${n} mark${n === 1 ? '' : 's'} carried over from an earlier chat (${parts.join(', ')}). Keep going, or run /steerpin:clear-marks to start fresh.`;
}

// ---------- commands ----------

function readStdin() {
  try {
    return fs.readFileSync(0, 'utf8');
  } catch {
    return '';
  }
}

function runHook(eventName) {
  let input = {};
  try {
    input = JSON.parse(readStdin() || '{}');
  } catch {
    // no usable input; fall back to cwd
  }
  const dir = projectDir(input);
  const { cfg, problems } = loadConfig(dir);
  rememberProject(dir, cfg);
  let result;
  try {
    result = processInbox(dir, cfg);
  } catch (err) {
    if (!(err instanceof UnsafePathError)) throw err;
    // marks.md itself is unsafe to write. The claimed inbox stays and is retried once stale.
    result = emptyResult();
    result.refused.push(`${err.message}, new marks are waiting`);
  }
  const { marks } = readMarks(dir);
  const { text, truncated } = renderContext(marks, result, cfg);
  const carried = eventName === 'SessionStart' ? carriedOverNotice(input.source, marks, result) : '';
  const message = [userMessage(result, truncated, problems), carried]
    .filter(Boolean)
    .join('\n');
  if (!text && !message) return;
  const output = {};
  if (text) output.hookSpecificOutput = { hookEventName: eventName, additionalContext: text };
  if (message) output.systemMessage = message;
  process.stdout.write(JSON.stringify(output));
}

function list() {
  const dir = projectDir();
  const { cfg, problems } = loadConfig(dir);
  const result = processInbox(dir, cfg);
  const { marks } = readMarks(dir);
  const message = userMessage(result, [], problems);
  if (message) console.log(`${message}\n`);
  if (!marks.length) {
    console.log('No active marks.');
    return;
  }
  for (const type of ACTIVE_TYPES) {
    const ofType = marks.filter((m) => m.type === type);
    if (!ofType.length) continue;
    console.log(type === 'priority' ? 'Priority:' : 'Wrong:');
    for (const m of ofType) {
      console.log(`  [${m.id}] ${m.text.replace(/\n/g, '\n      ')}${m.meta ? `  (${m.meta})` : ''}`);
    }
  }
  if (marks.length > cfg.maxActiveMarks) {
    console.log(`\nOnly the newest ${cfg.maxActiveMarks} are sent to Claude (maxActiveMarks).`);
  }
}

function unmark(args) {
  const ids = args.join(' ').split(/[\s,]+/).filter(Boolean).map((s) => Number(s.replace(/^\[|\]$/g, '')));
  if (!ids.length || ids.some((id) => !Number.isInteger(id))) {
    console.log('Usage: /steerpin:unmark <id> [id...]  (see /steerpin:marks for ids)');
    process.exitCode = 1;
    return;
  }
  const dir = projectDir();
  const state = readMarks(dir);
  const removed = state.marks.filter((m) => ids.includes(m.id));
  const missing = ids.filter((id) => !removed.some((m) => m.id === id));
  if (removed.length) {
    state.marks = state.marks.filter((m) => !ids.includes(m.id));
    writeMarks(dir, state);
  }
  for (const m of removed) console.log(`Removed [${m.id}] ${m.type}: ${m.text.split('\n')[0]}`);
  if (missing.length) console.log(`No active mark with id ${missing.join(', ')}.`);
}

function clear() {
  const dir = projectDir();
  const state = readMarks(dir);
  const n = state.marks.length;
  state.marks = [];
  writeMarks(dir, state);
  console.log(n ? `Removed ${n} mark${n === 1 ? '' : 's'}. Roadmap and later files are untouched.` : 'No active marks.');
}

function undo() {
  const dir = projectDir();
  const file = path.join(dir, UNDO_REL);
  let steps;
  try {
    steps = JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch {
    console.log('Nothing to undo.');
    return;
  }
  const state = readMarks(dir);
  const done = [];
  for (const step of steps) {
    if (step.kind === 'mark') {
      const mark = state.marks.find((m) => m.id === step.id);
      if (!mark) continue;
      state.marks = state.marks.filter((m) => m !== mark);
      if (step.replaced) state.marks.push(step.replaced);
      done.push(`Removed [${mark.id}] ${mark.type}: ${mark.text.split('\n')[0]}`);
      if (step.replaced) done.push(`Restored [${step.replaced.id}] ${step.replaced.type}`);
    } else {
      if (typeof step.file !== 'string' || typeof step.entry !== 'string' || !insideProject(dir, step.file)) continue;
      let listFile, content;
      try {
        listFile = safeTarget(dir, path.resolve(dir, step.file));
        content = fs.readFileSync(listFile, 'utf8');
      } catch {
        continue;
      }
      const at = content.lastIndexOf(`\n${step.entry}\n`);
      if (at === -1) continue;
      writeAtomic(listFile, content.slice(0, at) + content.slice(at + step.entry.length + 1));
      done.push(`Removed from ${step.file}: ${step.entry.slice(2).split('\n')[0]}`);
    }
  }
  state.marks.sort((a, b) => a.id - b.id);
  writeMarks(dir, state);
  fs.rmSync(file, { force: true });
  console.log(done.length ? done.join('\n') : 'Nothing to undo: those marks were already removed.');
}

function parseTypedText(args, usage) {
  const [type, ...rest] = args;
  if (!TYPES.includes(type)) {
    console.log(usage);
    process.exitCode = 1;
    return null;
  }
  const text = cleanText(rest.length ? rest.join(' ') : process.stdin.isTTY ? '' : readStdin());
  if (!text) {
    console.log(usage);
    process.exitCode = 1;
    return null;
  }
  return { type, text };
}

function add(args) {
  const parsed = parseTypedText(args, 'Usage: /steerpin:mark <priority|wrong|roadmap|later> <text>');
  if (!parsed) return;
  const dir = projectDir();
  const { cfg, problems } = loadConfig(dir);
  if (problems.length) console.log(`${CONFIG_REL}: ignoring ${problems.join(', ')}.`);
  const item = { ...parsed, timestamp: new Date().toISOString(), source: '/steerpin:mark' };
  const result = applyItems(dir, cfg, [item]);
  if (result.gitignored) console.log(`Added ${IGNORE_LINE} to .gitignore.`);
  if (result.newIds.length) console.log(`Added [${result.newIds[0]}] ${item.type}. It will be sent with every message until removed.`);
  else if (Object.keys(result.saved).length) console.log(`Saved to ${cfg[item.type]}.`);
  else if (result.refused.length) console.log(`Not saved: ${result.refused.join('; ')}.`);
  else console.log('Already marked, nothing changed.');
}

function capture(args) {
  const parsed = parseTypedText(args, 'Usage: steerpin.mjs capture <priority|wrong|roadmap|later> <text>');
  if (!parsed) return;
  privateHome();
  const line = { ...parsed, timestamp: new Date().toISOString(), source_app: process.env.STEERPIN_SOURCE || 'cli' };
  fs.appendFileSync(INBOX, JSON.stringify(line) + '\n', { mode: PRIVATE });
  console.log(`Marked as ${parsed.type}.`);
}

const [command, ...args] = process.argv.slice(2);
try {
  switch (command) {
    case 'hook':
      runHook('UserPromptSubmit');
      break;
    case 'session-start':
      runHook('SessionStart');
      break;
    case 'list':
      list();
      break;
    case 'unmark':
      unmark(args);
      break;
    case 'clear':
      clear();
      break;
    case 'undo':
      undo();
      break;
    case 'add':
      add(args);
      break;
    case 'capture':
      capture(args);
      break;
    default:
      console.log('Usage: steerpin.mjs <hook|session-start|list|unmark|clear|undo|add|capture> ...');
      process.exitCode = 1;
  }
} catch (err) {
  // Hooks must never block a message: report and exit 0.
  if (command === 'hook' || command === 'session-start') {
    process.stderr.write(`steerpin: ${err.message}\n`);
    process.exitCode = 0;
  } else {
    console.error(`steerpin: ${err.message}`);
    process.exitCode = 1;
  }
}
