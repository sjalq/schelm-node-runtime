'use strict';
const assert = require('node:assert/strict');
const cp = require('node:child_process');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
for (const mode of ['debug', 'optimize']) {
  const signal = cp.execFileSync(process.execPath, ['tests/run-replay-child.cjs', mode, 'signal'], { cwd: root, encoding: 'utf8', timeout: 5000 });
  assert.ok(JSON.parse(signal.slice(signal.indexOf('['))).includes('signal'), mode);
  const ticker = cp.execFileSync(process.execPath, ['tests/run-replay-child.cjs', mode, 'ticker'], { cwd: root, encoding: 'utf8', timeout: 5000 });
  assert.ok(JSON.parse(ticker.slice(ticker.indexOf('['))).some(x => /^\d+$/.test(x)), mode);
  const input = cp.spawnSync('python3', ['tests/pty/pty-runner.py', 'input-replay', mode], { cwd: root, input: Buffer.from([0xff]), encoding: 'utf8', timeout: 10000 });
  assert.equal(input.status, 0, input.stdout + input.stderr);
  assert.match(input.stdout, /input:�:1:malformed/);
}
console.log('compiled signal/input/ticker replay pass');
