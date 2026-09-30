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
  fs.mkdirSync(home);
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

test('session-start suggests setting up hotkeys only when needed', () => {
  const hasHammerspoon = process.platform === 'darwin' && fs.existsSync('/Applications/Hammerspoon.app');
  const tip = () => {
    const out = run(['session-start'], '{}');
    return out ? JSON.parse(out).systemMessage ?? '' : '';
  };
  process.env.STEERPIN_APP = path.join(userHome, 'Applications/Steerpin.app'); // app not installed
  if (!hasHammerspoon) {
    assert.equal(tip(), '');
    return;
  }
  assert.match(tip(), /Hammerspoon found\. Run \/steerpin:setup-hotkeys/);
  fs.mkdirSync(path.join(userHome, '.hammerspoon'));
  fs.writeFileSync(path.join(userHome, '.hammerspoon/steerpin.lua'), '-- old');
  assert.match(tip(), /out of date/);
  fs.copyFileSync(path.resolve(import.meta.dirname, '../macos/hammerspoon/steerpin.lua'), path.join(userHome, '.hammerspoon/steerpin.lua'));
  assert.equal(tip(), '');
  inbox({ type: 'priority', text: 'p' });
  assert.equal(JSON.parse(run(['hook'], '{}')).systemMessage, 'steerpin: new mark [1]'); // no tip on normal messages

  fs.rmSync(path.join(userHome, '.hammerspoon'), { recursive: true });
  fs.mkdirSync(process.env.STEERPIN_APP, { recursive: true });
  assert.equal(tip(), ''); // the Steerpin app handles hotkeys
  delete process.env.STEERPIN_APP;
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

test('unwritable project fails silently with exit 0', () => {
  inbox({ type: 'priority', text: 'p' });
  fs.mkdirSync(path.join(project, '.claude'));
  fs.writeFileSync(path.join(project, '.claude/steerpin'), 'a file, not a dir');
  assert.doesNotThrow(() => run(['hook'], '{}'));
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
