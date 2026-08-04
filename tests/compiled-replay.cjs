'use strict';
const assert = require('node:assert/strict');
const cp = require('node:child_process');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const oracle = require('./oracle/oracle.cjs');
const expected = {
  console: ['replay-console:0:too-many', ...Array.from({ length: 256 }, (_, offset) => `replay-console:${256 - offset}:ok`)],
  signal: ['signal'],
  input: ['input:�:1:malformed', 'input-end:malformed']
};
for (const mode of ['debug', 'optimize']) {
  for (const scenario of ['emit-close', 'emit-pipe', 'callback-pipe']) {
    const consoleRun = cp.spawnSync(process.execPath, ['tests/run-console-child.cjs', mode, scenario], { cwd: root, encoding: 'utf8', timeout: 5000 });
    assert.equal(consoleRun.status, 0, consoleRun.stdout + consoleRun.stderr);
  }
  const consoleRaw = cp.execFileSync(process.execPath, ['tests/run-replay-child.cjs', mode, 'console'], { cwd: root, encoding: 'utf8', timeout: 5000 });
  assert.deepEqual(JSON.parse(consoleRaw.slice(consoleRaw.indexOf('['))), expected.console, `${mode} console ordered replay`);
  const signalRaw = cp.execFileSync(process.execPath, ['tests/run-replay-child.cjs', mode, 'signal'], { cwd: root, encoding: 'utf8', timeout: 5000 });
  assert.deepEqual(JSON.parse(signalRaw.slice(signalRaw.indexOf('['))).filter(x => x === 'signal'), expected.signal, `${mode} signal ordered replay`);
  const tickerRaw = cp.execFileSync(process.execPath, ['tests/run-replay-child.cjs', mode, 'ticker'], { cwd: root, encoding: 'utf8', timeout: 5000 });
  const tickerEvents = JSON.parse(tickerRaw.slice(tickerRaw.indexOf('['))).filter(x => /^\d+$/.test(x));
  assert.equal(tickerEvents.length, 1, `${mode} ticker ordered replay`);
  assert.equal(Number(tickerEvents[0]), oracle.tickerOracle(0, 100, Number(tickerEvents[0])).skipped, `${mode} ticker oracle equality`);
  const input = cp.spawnSync('python3', ['tests/pty/pty-runner.py', 'input-replay', mode], { cwd: root, encoding: 'utf8', timeout: 10000 });
  assert.equal(input.status, 0, input.stdout + input.stderr);
  const inputEvents = [...input.stdout.matchAll(/input(?:-end)?:[^\r\n]+/g)].map(match => match[0]);
  assert.deepEqual(inputEvents, expected.input, `${mode} input ordered replay`);
  assert.deepEqual(oracle.inputOracle([[255]], true), { text: '�', malformed: true }, `${mode} input oracle equality`);
}
console.log('compiled console/signal/input/ticker ordered replay and oracle equality pass');
