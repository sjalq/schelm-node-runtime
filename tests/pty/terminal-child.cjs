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
const app = require(`../../build/runtime-${artifact}.js`).Elm.Main.init({ flags: `pty-${mode}` });
app.ports.report.subscribe(line => {
  if (line === 'RAW' || line === 'POISON' || line === 'RECOVERED') process.stdout.write(`${line}\n`);
  if (mode === 'release' && line === 'RAW') setTimeout(() => process.exit(0), 50);
  if (mode === 'backstop' && line === 'RAW') process.exit(0);
  if (mode === 'restore-failed' && line === 'RECOVERED') process.exit(0);
});
setTimeout(() => process.exit(92), 3000);
