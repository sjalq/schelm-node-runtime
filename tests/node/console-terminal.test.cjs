'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),cp=require('node:child_process'),path=require('node:path');
const root=path.resolve(__dirname,'../..');
for(const mode of ['debug','optimize']) for(const scenario of ['emit-close','emit-pipe','callback-pipe']) test(`compiled ${mode} console ${scenario} settles FIFO once`,()=>{
  const r=cp.spawnSync(process.execPath,['tests/run-console-child.cjs',mode,scenario],{cwd:root,encoding:'utf8',timeout:5000});
  assert.equal(r.status,0,r.stdout+r.stderr);
  const start=r.stderr.indexOf('[');assert.notEqual(start,-1,r.stderr);
  const events=JSON.parse(r.stderr.slice(start));
  const outcome=scenario==='emit-close'?'closed':'pipe';
  assert.deepEqual(events,[`console:2:${outcome}`,`console:1:${outcome}`,`console:0:${outcome}`]);
  assert.equal(new Set(events.map(x=>x.split(':')[1])).size,3);
});
