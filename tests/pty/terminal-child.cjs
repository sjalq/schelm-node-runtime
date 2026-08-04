'use strict';
const mode = process.argv[2];
const artifact = process.argv[3] || 'debug';
if (!process.stdin.isTTY) process.exit(90);
if (mode === 'restore-failed') {
  let failed = false;
  const real = process.stdin.setRawMode.bind(process.stdin);
  process.stdin.setRawMode = value => {
    if (value === false && !failed) {
      failed = true;
      throw new Error('injected restore failure');
    }
    return real(value);
  };
}
const flags = mode === 'share' ? 'pty-share' : mode === 'input-replay' ? 'pty-input-replay' : mode === 'input-aba' ? 'pty-input-aba' : mode === 'fanout-resize' ? 'pty-fanout-resize' : mode === 'limit-resize' ? 'pty-limit-resize' : `pty-${mode}`;
const app = require(`../../build/runtime-${artifact}.js`).Elm.Main.init({ flags });
const shared = [];
const inputReplay = [];
let resizeCount = 0;
app.ports.report.subscribe(line => {
  if (line === 'RAW' || line === 'POISON' || line === 'RECOVERED') process.stdout.write(`${line}\n`);
  if (mode === 'release' && line === 'RAW') setTimeout(() => process.exit(0), 50);
  if (mode === 'backstop' && line === 'RAW') process.exit(0);
  if (mode === 'restore-failed' && line === 'RECOVERED') process.exit(0);
  if ((mode === 'fanout-resize' || mode === 'limit-resize') && (line === 'resize' || line === 'resize-limit')) {
    if (line === 'resize') resizeCount++;
    if (line === 'resize-limit') process.stdout.write('RESIZE_LIMIT\n');
    if (resizeCount === 200) { process.stdout.write('RESIZE_200\n'); process.exit(0); }
  }
  if (mode === 'input-aba' && line === 'aba-ready') process.stdout.write('ABA_READY\n');
  if ((mode === 'input-replay' || mode === 'input-aba') && (line.startsWith('input') || line === 'stale-read-delivered')) {
    inputReplay.push(line);
    process.stdout.write(`${line}\n`);
    if (line === 'stale-read-delivered') process.exit(94);
    if (line === 'input-end:malformed' && inputReplay.some(x => /^input:/.test(x))) process.exit(0);
  }
  if (mode === 'share') {
    shared.push(line);
    if (shared.length === 260) {
      const counts = Object.fromEntries([...new Set(shared)].map(value => [value, shared.filter(x => x === value).length]));
      process.stdout.write(`SHARE=${JSON.stringify(counts)}\n`);
      const expected = {
        'acquire-ok': 64,
        'acquire-join-limit': 1,
        'control-ok': 64,
        'control-join-limit': 1,
        'release-ok': 64,
        'release-join-limit': 1,
        'recover-released': 64,
        'recover-join-limit': 1
      };
      process.exit(JSON.stringify(counts) === JSON.stringify(expected) ? 0 : 93);
    }
  }
});
setTimeout(() => process.exit(92), 3000);
