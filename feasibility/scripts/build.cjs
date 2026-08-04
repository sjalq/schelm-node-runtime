'use strict';
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const cp = require('node:child_process');
const root = path.resolve(__dirname, '..');
const repo = path.resolve(root, '..');
const compilerRepo = '/home/s.dormehl/git/elm-compiler/.worktrees/schelm-kernel-author';
const compiler = path.join(compilerRepo, 'result/bin/elm');
const authorizationCommit = '76bbe44424106c96f915cb24cd7f50d69f5cee0e';
const expectedBinarySha256 = '69987adf7062562b6e6dfd60b6709be3a06feeb90b096b9c84f673f2b97d8654';
cp.execFileSync('git', ['-C', compilerRepo, 'merge-base', '--is-ancestor', authorizationCommit, 'HEAD']);
const crypto = require('node:crypto');
const actualBinarySha256 = crypto.createHash('sha256').update(fs.readFileSync(compiler)).digest('hex');
if (actualBinarySha256 !== expectedBinarySha256) throw new Error(`compiler binary ${actualBinarySha256}, expected ${expectedBinarySha256}`);
const home = path.join(repo, 'build/elm-home');
const packages = path.join(home, '0.19.2/packages');
fs.rmSync(home, { recursive: true, force: true }); fs.mkdirSync(packages, { recursive: true });
const stock = path.join(os.homedir(), '.elm/0.19.2/packages');
for (const author of fs.readdirSync(stock)) {
  if (author === 'registry.dat' || author === 'lock') continue;
  const source = path.join(stock, author);
  if (fs.statSync(source).isDirectory()) fs.cpSync(source, path.join(packages, author), { recursive: true });
}
const pkg = path.join(root, 'package');
const dest = path.join(packages, 'sjalq/schelm-node-runtime-feasibility/1.0.0');
fs.mkdirSync(dest, { recursive: true });
for (const entry of ['src', 'elm.json', 'README.md', 'LICENSE']) fs.cpSync(path.join(pkg, entry), path.join(dest, entry), { recursive: true });
let registry = fs.readFileSync(path.join(stock, 'registry.dat'));
function entries(buf) { let pos=16,n=Number(buf.readBigUInt64BE(8)),xs=[]; for(let i=0;i<n;i++){let start=pos,la=buf[pos++],author=buf.subarray(pos,pos+la).toString();pos+=la;let lp=buf[pos++],project=buf.subarray(pos,pos+lp).toString();pos+=lp;let major=buf[pos++];if(major===255)throw new Error('large version');pos+=2;let previous=Number(buf.readBigUInt64BE(pos));pos+=8+3*previous;xs.push({author,project,start});} return {n,xs}; }
function add(buf,author,project){let {n,xs}=entries(buf),key=`${author}/${project}`;if(xs.some(x=>`${x.author}/${x.project}`===key))return buf;let index=xs.findIndex(x=>`${x.author}/${x.project}`>key),at=index<0?buf.length:xs[index].start;let entry=Buffer.concat([Buffer.from([author.length]),Buffer.from(author),Buffer.from([project.length]),Buffer.from(project),Buffer.from([1,0,0]),Buffer.alloc(8)]);let out=Buffer.concat([buf.subarray(0,at),entry,buf.subarray(at)]);out.writeBigUInt64BE(buf.readBigUInt64BE(0)+1n,0);out.writeBigUInt64BE(BigInt(n+1),8);return out;}
fs.writeFileSync(path.join(packages, 'registry.dat'), add(registry, 'sjalq', 'schelm-node-runtime-feasibility'));
fs.mkdirSync(path.join(repo, 'build'), { recursive: true });
for (const mode of ['debug', 'optimize']) {
  const args = ['make', 'src/Main.elm', '--output', path.join(repo, `build/feasibility-${mode}.js`)];
  if (mode === 'optimize') args.push('--optimize');
  cp.execFileSync(compiler, args, { cwd: path.join(root, 'app'), stdio: 'inherit', env: {...process.env, ELM_HOME: home} });
}
