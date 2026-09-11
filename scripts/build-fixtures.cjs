'use strict';

const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');

const root = path.resolve(__dirname, '..');
const compiler = process.env.SCHELM_BIN || 'schelm';
const home = process.env.SCHELM_HOME || path.join(root, 'build/schelm-home');

fs.rmSync(home, { recursive: true, force: true });
fs.mkdirSync(path.join(root, 'build'), { recursive: true });

for (const app of ['production', 'boundary']) {
  const cwd = path.join(root, 'fixture-apps', app);
  fs.rmSync(path.join(cwd, 'elm-stuff'), { recursive: true, force: true });

  for (const mode of ['debug', 'optimize']) {
    const stem = app === 'production' ? 'runtime' : 'boundary';
    const args = ['make', 'src/Main.elm', '--output', path.join(root, `build/${stem}-${mode}.js`)];
    if (mode === 'optimize') args.push('--optimize');
    cp.execFileSync(compiler, args, {
      cwd,
      stdio: 'inherit',
      env: { ...process.env, SCHELM_HOME: home }
    });
  }
}
