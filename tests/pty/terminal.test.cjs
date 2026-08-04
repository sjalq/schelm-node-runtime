'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),cp=require('node:child_process'),path=require('node:path');
const root=path.resolve(__dirname,'../..');
for(const artifact of ['debug','optimize']) for(const mode of ['release','backstop','restore-failed','share','fanout-resize']) test(`compiled ${artifact} PTY ${mode} restores cooked`,()=>{
  const out=cp.execFileSync('python3',['tests/pty/pty-runner.py',mode,artifact],{cwd:root,encoding:'utf8',timeout:10000});
  assert.match(out,mode==='share'?/SHARE=/:mode==='fanout-resize'?/RESIZE_200/:/RAW/);
  assert.match(out,/COOKED_STATE=True/);
  if(mode==='restore-failed'){assert.match(out,/POISON/);assert.match(out,/RECOVERED/);}
});
for(const artifact of ['debug','optimize']) for(const mode of ['input-replay','input-aba','limit-resize']) test(`compiled ${artifact} PTY ${mode} evidence`,()=>{
  const out=cp.execFileSync('python3',['tests/pty/pty-runner.py',mode,artifact],{cwd:root,encoding:'utf8',timeout:10000});
  if(mode==='input-replay'||mode==='input-aba'){assert.match(out,/input:�:1:malformed/);assert.match(out,/input-end:malformed/);}
  if(mode==='input-aba')assert.doesNotMatch(out,/stale-read-delivered/);
  if(mode==='limit-resize'){assert.match(out,/RESIZE_LIMIT/);assert.match(out,/RESIZE_200/);}
  assert.match(out,/COOKED_STATE=True/);
});
for(const artifact of ['debug','optimize']) for(const mode of ['resize-current','resize-released','resize-stale']) test(`compiled ${artifact} PTY ${mode} subscription ownership`,()=>{
  const out=cp.execFileSync('python3',['tests/pty/pty-runner.py',mode,artifact],{cwd:root,encoding:'utf8',timeout:10000});
  assert.match(out,/RESIZE_READY/);
  if(mode==='resize-current')assert.match(out,/RESIZE_DELIVERED/);else assert.doesNotMatch(out,/RESIZE_DELIVERED/);
  assert.match(out,/COOKED_STATE=True/);
});
