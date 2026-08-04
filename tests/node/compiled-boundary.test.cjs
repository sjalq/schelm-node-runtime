'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const cp = require('node:child_process');
const path = require('node:path');
const { consoleOracle } = require('../oracle/oracle.cjs');
const root = path.resolve(__dirname, '../..');

function compiled(mode, count) {
  const raw = cp.execFileSync(process.execPath, ['tests/run-boundary-child.cjs', mode, String(count)], {
    cwd: root,
    encoding: 'utf8',
    timeout: 5000
  });
  const start = raw.indexOf('[');
  assert.notEqual(start, -1, raw);
  return JSON.parse(raw.slice(start));
}

function expected(count) {
  const trace = Array.from({ length: count }, (_, id) => ({ op: 'write', id: count - id - 1, bytes: 0 }));
  const decisions = consoleOracle(trace).events;
  const rejected = decisions
    .filter(event => event[0] === 'reject')
    .map(event => ({ kind: 'settle', id: event[1], outcome: event[2] }));
  const accepted = decisions
    .filter(event => event[0] === 'accept')
    .map(event => ({ kind: 'settle', id: event[1], outcome: 'ok' }));
  return rejected.concat(accepted);
}

for (const mode of ['debug', 'optimize']) {
  test(`compiled ${mode} production manager preserves unsorted FIFO`, () => {
    const got = compiled(mode, 3);
    assert.deepEqual(got, expected(3));
    assert.deepEqual(got.map(x => x.id), [2, 1, 0], 'comparison must not sort production output');
  });

  test(`compiled ${mode} production manager enforces zero-byte count bound`, () => {
    const got = compiled(mode, 257);
    assert.deepEqual(got, expected(257));
    assert.deepEqual(got[0], { kind: 'settle', id: 0, outcome: 'count' });
    assert.deepEqual(got[1], { kind: 'settle', id: 256, outcome: 'ok' });
  });
}
