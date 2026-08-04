'use strict';
const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');
const root = path.resolve(__dirname, '..');
const overlay = path.join(root, 'build/package-diagnostic');
const compiler = '/home/s.dormehl/git/elm-compiler/.worktrees/schelm-kernel-author/result/bin/elm';
fs.rmSync(overlay, { recursive: true, force: true });
fs.mkdirSync(overlay, { recursive: true });
for (const entry of ['src', 'elm.json', 'README.md', 'LICENSE']) fs.cpSync(path.join(root, entry), path.join(overlay, entry), { recursive: true });
for (const module of ['src/Schelm/Node/Runtime/Ticker.elm', 'src/Schelm/Node/Terminal.elm']) {
  cp.execFileSync(compiler, ['make', module, '--output=/dev/null', '--report=json'], {
    cwd: overlay,
    stdio: 'inherit',
    env: { ...process.env, ELM_HOME: path.join(root, 'build/elm-home') }
  });
}
console.log('isolated package diagnostic pass');
