// Runs the steerpin script against a temp project and inbox. Usage: node test/run-tests.mjs
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const script = path.resolve(import.meta.dirname, '../scripts/steerpin.mjs');
let home, project, userHome;

function reset() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'steerpin-test-'));
  home = path.join(root, 'home');
  project = path.join(root, 'project');
  userHome = path.join(root, 'user');
  fs.mkdirSync(project);
  fs.mkdirSync(userHome);
}

function run(args, input = '') {
  try {
    return execFileSync('node', [script, ...args], {
      input,
      env: { ...process.env, HOME: userHome, STEERPIN_HOME: home, CLAUDE_PROJECT_DIR: project },
      encoding: 'utf8',
      stdio: ['pipe', 'pipe', 'pipe'],
    });
  } catch (err) {
    if (args[0] === 'hook' || args[0] === 'session-start') throw err; // hooks must always exit 0
    return err.stdout;
  }
}

const hook = () => {
  const out = run(['hook'], JSON.stringify({ hook_event_name: 'UserPromptSubmit', cwd: project }));
  return out ? JSON.parse(out) : null;
};
const context = (out) => out?.hookSpecificOutput?.additionalContext ?? '';

function inbox(...items) {
  fs.mkdirSync(home, { recursive: true });
  const lines = items.map((i) => (typeof i === 'string' ? i : JSON.stringify({ timestamp: '2026-09-30T12:00:00Z', source_app: 'iTerm2', ...i })));
  fs.appendFileSync(path.join(home, 'inbox.jsonl'), lines.join('\n') + '\n');
}

const read = (rel) => fs.readFileSync(path.join(project, rel), 'utf8');
const tests = [];
const test = (name, fn) => tests.push([name, fn]);

test('missing inbox and no marks: no output', () => {
  assert.equal(hook(), null);
  fs.mkdirSync(home, { recursive: true });
  fs.writeFileSync(path.join(home, 'inbox.jsonl'), '');
  assert.equal(hook(), null);
});

test('priority and wrong marks reach the context', () => {
  inbox({ type: 'priority', text: 'Tokens must stay platform-agnostic' }, { type: 'wrong', text: "Style Dictionary can't handle composite tokens" });
  const out = hook();
  const ctx = context(out);
  assert.match(ctx, /Priority, keep these/);
  assert.match(ctx, /\[1\] Tokens must stay platform-agnostic/);
  assert.match(ctx, /\[2\] "Style Dictionary can't handle composite tokens"/);
  assert.match(ctx, /New since last message: \[1\] \[2\]/);
  assert.match(ctx, /Noted, \[2\] was wrong/);
  assert.match(out.systemMessage, /new marks \[1\] \[2\]/);
  assert.equal(fs.existsSync(path.join(home, 'inbox.jsonl')), false);
});

test('marks persist on later messages, without "new"', () => {
  inbox({ type: 'priority', text: 'Keep it fast' });
  hook();
  const out = hook();
  assert.match(context(out), /\[1\] Keep it fast/);
  assert.doesNotMatch(context(out), /New since/);
  assert.equal(out.systemMessage, undefined);
});

test('roadmap and later go to files, not context', () => {
  inbox({ type: 'roadmap', text: 'Export to Figma variables' }, { type: 'later', text: 'Try Raycast\nsecond line' });
  const out = hook();
  assert.equal(context(out), '');
  assert.match(out.systemMessage, /1 saved to .claude\/steerpin\/roadmap.md; 1 saved to .claude\/steerpin\/later.md/);
  const roadmap = read('.claude/steerpin/roadmap.md');
  assert.match(roadmap, /^# Roadmap/);
  assert.match(roadmap, /- Export to Figma variables\n  _2026-09-30 \d\d:\d\d · marked in iTerm2_/);
  assert.match(read('.claude/steerpin/later.md'), /- Try Raycast\n  second line\n/);
});

test('exact duplicates are skipped', () => {
  inbox({ type: 'wrong', text: 'A is B' }, { type: 'wrong', text: '  A is  B ' }, { type: 'roadmap', text: 'Idea' });
  hook();
  inbox({ type: 'roadmap', text: 'Idea' });
  hook();
  assert.equal((read('.claude/steerpin/marks.md').match(/## \[/g) || []).length, 1);
  assert.equal((read('.claude/steerpin/roadmap.md').match(/- Idea/g) || []).length, 1);
});

test('re-marking text as another type replaces it', () => {
  inbox({ type: 'priority', text: 'X' });
  hook();
  inbox({ type: 'wrong', text: 'X' });
  const ctx = context(hook());
  assert.doesNotMatch(ctx, /Priority/);
  assert.match(ctx, /\[2\] "X"/);
});

test('long marks are truncated in context but kept in marks.md', () => {
  const long = 'word '.repeat(200).trim();
  inbox({ type: 'priority', text: long });
  const out = hook();
  assert.match(context(out), /… \[truncated, full text in \.claude\/steerpin\/marks\.md\]/);
  assert.match(out.systemMessage, /\[1\] truncated in context/);
  assert.ok(read('.claude/steerpin/marks.md').includes(long));
});

test('maxActiveMarks caps the context', () => {
  fs.mkdirSync(path.join(project, '.claude/steerpin'), { recursive: true });
  fs.writeFileSync(path.join(project, '.claude/steerpin/config.json'), JSON.stringify({ maxActiveMarks: 2 }));
  inbox({ type: 'priority', text: 'one' }, { type: 'priority', text: 'two' }, { type: 'priority', text: 'three' });
  const ctx = context(hook());
  assert.doesNotMatch(ctx, /one/);
  assert.match(ctx, /\[3\] three/);
  assert.match(ctx, /1 older mark not shown \(limit 2\)/);
});

test('config paths are respected', () => {
  fs.mkdirSync(path.join(project, '.claude/steerpin'), { recursive: true });
  fs.writeFileSync(path.join(project, '.claude/steerpin/config.json'), JSON.stringify({ roadmap: 'ROADMAP.md' }));
  inbox({ type: 'roadmap', text: 'Custom path' });
  hook();
  assert.match(read('ROADMAP.md'), /- Custom path/);
});

test('malformed inbox lines are ignored', () => {
  inbox('not json', { type: 'bogus', text: 'x' }, { type: 'wrong', text: '' }, { type: 'wrong', text: 'valid' });
  const ctx = context(hook());
  assert.match(ctx, /\[1\] "valid"/);
});

test('corrupt marks.md does not break the hook', () => {
  fs.mkdirSync(path.join(project, '.claude/steerpin'), { recursive: true });
  fs.writeFileSync(path.join(project, '.claude/steerpin/marks.md'), 'garbage\n## [x] nope\n');
  assert.equal(hook(), null);
});

test('text containing a mark header round-trips', () => {
  inbox({ type: 'priority', text: 'line one\n## [9] wrong\nline three' });
  hook();
  const ctx = context(hook());
  assert.match(ctx, /\[1\] line one\n    ## \[9\] wrong\n    line three/);
  assert.doesNotMatch(ctx, /\[9\]\s*"/);
});

test('stale claim files are recovered, fresh ones left alone', () => {
  fs.mkdirSync(home, { recursive: true });
  const line = (t) => JSON.stringify({ type: 'priority', text: t }) + '\n';
  fs.writeFileSync(path.join(home, `inbox.jsonl.claim-${Date.now() - 60_000}-1-0`), line('stale'));
  fs.writeFileSync(path.join(home, `inbox.jsonl.claim-${Date.now()}-2-0`), line('fresh'));
  const ctx = context(hook());
  assert.match(ctx, /stale/);
  assert.doesNotMatch(ctx, /fresh/);
});

test('unmark, list and clear', () => {
  inbox({ type: 'priority', text: 'p1' }, { type: 'wrong', text: 'w1' }, { type: 'roadmap', text: 'r1' });
  const listed = run(['list']);
  assert.match(listed, /1 saved to .claude\/steerpin\/roadmap.md/);
  assert.match(listed, /Priority:\n  \[1\] p1/);
  assert.match(listed, /Wrong:\n  \[2\] w1/);
  assert.match(run(['unmark', '[1]', '7']), /Removed \[1\] priority: p1\nNo active mark with id 7/);
  assert.match(run(['unmark', 'abc']), /Usage/);
  assert.match(run(['list']), /\[2\] w1/);
  inbox({ type: 'priority', text: 'p2' });
  hook();
  assert.match(context(hook()), /\[3\] p2/); // ids are not reused
  assert.match(run(['clear']), /Removed 2 marks/);
  assert.equal(hook(), null);
  assert.match(read('.claude/steerpin/roadmap.md'), /r1/);
  assert.match(run(['list']), /No active marks/);
});

test('add writes directly; capture writes to the inbox', () => {
  assert.match(run(['add', 'wrong'], 'it\'s "quoted" $HOME `x`\n'), /Added \[1\] wrong/);
  assert.match(context(hook()), /\[1\] "it's "quoted" \$HOME `x`"/);
  assert.match(run(['add', 'roadmap', 'from', 'args']), /Saved to .claude\/steerpin\/roadmap.md/);
  assert.match(run(['add', 'nope', 'x']), /Usage/);
  run(['capture', 'priority', 'captured']);
  assert.match(fs.readFileSync(path.join(home, 'inbox.jsonl'), 'utf8'), /"type":"priority","text":"captured"/);
  assert.match(context(hook()), /\[2\] captured/);
});

test('session-start uses the SessionStart event name', () => {
  inbox({ type: 'priority', text: 'p' });
  const out = JSON.parse(run(['session-start'], JSON.stringify({ source: 'compact' })));
  assert.equal(out.hookSpecificOutput.hookEventName, 'SessionStart');
});

test('.claude/steerpin/ is added to .gitignore once, only in git repos', () => {
  inbox({ type: 'priority', text: 'p' });
  hook();
  assert.equal(fs.existsSync(path.join(project, '.gitignore')), false); // not a git repo

  fs.mkdirSync(path.join(project, '.git'));
  fs.writeFileSync(path.join(project, '.gitignore'), 'node_modules/');
  inbox({ type: 'roadmap', text: 'r' });
  assert.match(hook().systemMessage, /added \.claude\/steerpin\/ to \.gitignore/);
  assert.equal(read('.gitignore'), 'node_modules/\n.claude/steerpin/\n');

  inbox({ type: 'wrong', text: 'w' });
  assert.doesNotMatch(hook().systemMessage, /gitignore/);
  assert.equal(read('.gitignore'), 'node_modules/\n.claude/steerpin/\n');
});

test('an existing .claude ignore rule is respected', () => {
  fs.mkdirSync(path.join(project, '.git'));
  fs.writeFileSync(path.join(project, '.gitignore'), '/.claude/*\n');
  inbox({ type: 'priority', text: 'p' });
  hook();
  assert.equal(read('.gitignore'), '/.claude/*\n');
});

test('undo takes back the last delivery only', () => {
  inbox({ type: 'priority', text: 'keep' });
  hook();
  inbox({ type: 'wrong', text: 'oops' }, { type: 'roadmap', text: 'idea' });
  hook();
  const out = run(['undo']);
  assert.match(out, /Removed \[2\] wrong: oops/);
  assert.match(out, /Removed from \.claude\/steerpin\/roadmap\.md: idea/);
  assert.doesNotMatch(read('.claude/steerpin/roadmap.md'), /idea/);
  assert.match(context(hook()), /\[1\] keep/);
  assert.doesNotMatch(context(hook()), /oops/);
  assert.match(run(['undo']), /Nothing to undo/);
});

test('undo restores a mark that was re-marked as another type', () => {
  inbox({ type: 'priority', text: 'X' });
  hook();
  inbox({ type: 'wrong', text: 'X' });
  hook();
  assert.match(run(['undo']), /Restored \[1\] priority/);
  assert.match(context(hook()), /Priority[\s\S]*\[1\] X/);
});

test('undo works for /steerpin:mark', () => {
  run(['add', 'later'], 'try biome');
  assert.match(run(['undo']), /Removed from \.claude\/steerpin\/later\.md: try biome/);
});

test('a new chat mentions marks carried over; resume and compact stay quiet', () => {
  inbox({ type: 'priority', text: 'p' }, { type: 'wrong', text: 'w' });
  hook();
  const start = (source) => {
    const out = run(['session-start'], JSON.stringify({ source }));
    return out ? JSON.parse(out).systemMessage ?? '' : '';
  };
  assert.equal(start('startup'), 'steerpin: 2 marks carried over from an earlier chat (1 priority, 1 wrong). Keep going, or run /steerpin:clear-marks to start fresh.');
  assert.match(start('clear'), /carried over/);
  assert.doesNotMatch(start('resume'), /carried over/);
  assert.doesNotMatch(start('compact'), /carried over/);
  run(['clear']);
  assert.doesNotMatch(start('startup'), /carried over/);
});

test('each message moves its project to the top of the recent list', () => {
  const other = path.join(path.dirname(project), 'other');
  fs.mkdirSync(other);
  const hookIn = (dir) => execFileSync('node', [script, 'hook'], {
    input: '{}',
    env: { ...process.env, HOME: userHome, STEERPIN_HOME: home, CLAUDE_PROJECT_DIR: dir },
  });
  hookIn(project);
  hookIn(other);
  hookIn(project);
  const list = JSON.parse(fs.readFileSync(path.join(home, 'projects.json'), 'utf8'));
  assert.deepEqual(list.map((p) => p.project), [project, other]);
  assert.equal(list[0].marks, path.join(project, '.claude/steerpin/marks.md'));
  assert.equal(list[0].roadmap, path.join(project, '.claude/steerpin/roadmap.md'));
  assert.equal(list[0].later, path.join(project, '.claude/steerpin/later.md'));
  assert.ok(!Number.isNaN(Date.parse(list[0].lastUsed)));
});

test('unwritable project fails silently with exit 0', () => {
  inbox({ type: 'priority', text: 'p' });
  fs.mkdirSync(path.join(project, '.claude'));
  fs.writeFileSync(path.join(project, '.claude/steerpin'), 'a file, not a dir');
  assert.doesNotThrow(() => run(['hook'], '{}'));
});

test('config paths outside the project and bad limits are ignored and reported', () => {
  const victim = path.join(path.dirname(project), 'victim.md');
  fs.writeFileSync(victim, '# untouched\n');
  fs.mkdirSync(path.join(project, '.claude/steerpin'), { recursive: true });
  fs.writeFileSync(path.join(project, '.claude/steerpin/config.json'), JSON.stringify({
    roadmap: '../victim.md', later: victim, maxActiveMarks: 'lots', maxMarkLength: -1,
  }));
  inbox({ type: 'roadmap', text: 'r' }, { type: 'later', text: 'l' }, { type: 'priority', text: 'p' });
  const out = hook();
  assert.equal(fs.readFileSync(victim, 'utf8'), '# untouched\n');
  assert.match(read('.claude/steerpin/roadmap.md'), /- r/);
  assert.match(read('.claude/steerpin/later.md'), /- l/);
  assert.match(context(out), /\[1\] p/);
  assert.match(out.systemMessage, /config\.json: ignoring roadmap \(must be a path inside the project\), later \(.*\), maxActiveMarks \(must be a positive whole number\), maxMarkLength/);
  const projects = JSON.parse(fs.readFileSync(path.join(home, 'projects.json'), 'utf8'));
  assert.equal(projects[0].later, path.join(project, '.claude/steerpin/later.md'));
});

test('a config file that is not JSON is reported, marks still arrive', () => {
  fs.mkdirSync(path.join(project, '.claude/steerpin'), { recursive: true });
  fs.writeFileSync(path.join(project, '.claude/steerpin/config.json'), '{oops');
  inbox({ type: 'priority', text: 'p' });
  const out = hook();
  assert.match(context(out), /\[1\] p/);
  assert.match(out.systemMessage, /config\.json: ignoring the whole file, it is not valid JSON/);
});

test('a list file that is a symlink is refused; other marks still arrive', () => {
  const victim = path.join(path.dirname(project), 'profile');
  fs.writeFileSync(victim, '# dotfile\n');
  fs.mkdirSync(path.join(project, '.claude/steerpin'), { recursive: true });
  fs.symlinkSync(victim, path.join(project, '.claude/steerpin/later.md'));
  inbox({ type: 'later', text: 'via symlink' }, { type: 'priority', text: 'still delivered' });
  const out = hook();
  assert.equal(fs.readFileSync(victim, 'utf8'), '# dotfile\n');
  assert.match(out.systemMessage, /not saved: \.claude\/steerpin\/later\.md is a symlink/);
  assert.match(context(out), /\[1\] still delivered/);
  assert.equal(fs.existsSync(path.join(home, 'inbox.jsonl')), false); // dropped, not retried forever
  assert.match(run(['add', 'later', 'x']), /Not saved: .*later\.md is a symlink/);
});

test('a steerpin folder linked outside the project blocks delivery and keeps the marks', () => {
  const outside = path.join(path.dirname(project), 'elsewhere');
  fs.mkdirSync(outside);
  fs.mkdirSync(path.join(project, '.claude'));
  fs.symlinkSync(outside, path.join(project, '.claude/steerpin'));
  inbox({ type: 'priority', text: 'p' });
  const out = hook();
  assert.match(out.systemMessage, /not saved: \.claude\/steerpin\/marks\.md points outside the project, new marks are waiting/);
  assert.equal(fs.readdirSync(outside).length, 0);
  assert.ok(fs.readdirSync(home).some((n) => n.startsWith('inbox.jsonl.claim-'))); // retried once stale
});

test('undo only touches files inside the project', () => {
  const victim = path.join(path.dirname(project), 'victim.md');
  const before = 'a\n\n- x\n  _m_\nb\n';
  fs.writeFileSync(victim, before);
  fs.mkdirSync(path.join(project, '.claude/steerpin'), { recursive: true });
  fs.writeFileSync(path.join(project, '.claude/steerpin/last-delivery.json'),
    JSON.stringify([{ kind: 'list', type: 'roadmap', file: '../victim.md', entry: '- x\n  _m_' }]));
  assert.match(run(['undo']), /Nothing to undo: those marks were already removed/);
  assert.equal(fs.readFileSync(victim, 'utf8'), before);
});

test('appending never truncates, and home files are owner-only', () => {
  fs.mkdirSync(path.join(project, '.git'));
  fs.writeFileSync(path.join(project, '.gitignore'), 'dist/\n');
  fs.mkdirSync(path.join(project, '.claude/steerpin'), { recursive: true });
  fs.writeFileSync(path.join(project, '.claude/steerpin/roadmap.md'), '# Mine\n\n- kept');
  inbox({ type: 'roadmap', text: 'new' }, { type: 'priority', text: 'p' });
  hook();
  run(['capture', 'later', 'x']);
  assert.equal(read('.gitignore'), 'dist/\n.claude/steerpin/\n');
  assert.match(read('.claude/steerpin/roadmap.md'), /^# Mine\n\n- kept\n\n- new\n/);
  if (process.platform === 'win32') return;
  const mode = (p) => fs.statSync(p).mode & 0o777;
  assert.equal(mode(home), 0o700);
  assert.equal(mode(path.join(home, 'projects.json')), 0o600);
  assert.equal(mode(path.join(home, 'inbox.jsonl')), 0o600);
  assert.equal(mode(path.join(project, '.claude/steerpin/marks.md')), 0o600);
  assert.equal(mode(path.join(project, '.claude/steerpin/last-delivery.json')), 0o600);
});

let failed = 0;
for (const [name, fn] of tests) {
  reset();
  try {
    fn();
    console.log(`ok   ${name}`);
  } catch (err) {
    failed++;
    console.log(`FAIL ${name}\n${err.stack}`);
  }
}

reset();
const t0 = performance.now();
for (let i = 0; i < 10; i++) hook();
console.log(`\nempty-inbox hook: ${((performance.now() - t0) / 10).toFixed(0)} ms per run`);
process.exit(failed ? 1 : 0);
