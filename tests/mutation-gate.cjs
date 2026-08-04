'use strict';
const assert=require('node:assert/strict');
const cp=require('node:child_process');
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
const root=path.resolve(__dirname,'..');
const node=process.execPath;
const mutations=[
  {name:'console-count-off-by-one',file:'src/Schelm/Node/Runtime/Console.elm',from:'endpoint.count >= 256',to:'endpoint.count >= 257',gate:['tests/run-boundary-child.cjs','debug','257','expect-limit']},
  {name:'signal-subscriber-off-by-one',file:'src/Schelm/Node/Runtime/Signal.elm',from:'List.take 200 taggers',to:'List.take 199 taggers',gate:['tests/run-fanout-child.cjs','debug','signal-limit']},
  {name:'resize-subscriber-off-by-one',file:'src/Schelm/Node/Terminal.elm',from:'List.take 200 currentTaggers',to:'List.take 199 currentTaggers',gate:['tests/pty/pty-runner.py','limit-resize','debug'],python:true},
  {name:'reader-generation-reuse',file:'src/Schelm/Node/Terminal.elm',from:'nextReader = state.nextReader + 1',to:'nextReader = state.nextReader',gate:null}
];
const killed=[];
for(const mutation of mutations){
  const tmp=fs.mkdtempSync(path.join(os.tmpdir(),'schelm-runtime-mutation-'));
  try{
    for(const entry of ['src','fixture-apps','scripts','tests','elm.json','README.md','LICENSE','package.json'])fs.cpSync(path.join(root,entry),path.join(tmp,entry),{recursive:true});
    const target=path.join(tmp,mutation.file);const source=fs.readFileSync(target,'utf8');assert.equal(source.includes(mutation.from),true,`${mutation.name} fixture drift`);fs.writeFileSync(target,source.replace(mutation.from,mutation.to));
    const build=cp.spawnSync(node,['scripts/build-fixtures.cjs'],{cwd:tmp,encoding:'utf8',timeout:120000});assert.equal(build.status,0,build.stdout+build.stderr);
    if(mutation.gate){
      const result=cp.spawnSync(mutation.python?'python3':node,mutation.gate,{cwd:tmp,encoding:'utf8',timeout:15000});
      assert.notEqual(result.status,0,`${mutation.name} survived compiled production gate`);
    }else{
      for(const mode of ['debug','optimize'])assert.notDeepEqual(fs.readFileSync(path.join(tmp,`build/runtime-${mode}.js`)),fs.readFileSync(path.join(root,`build/runtime-${mode}.js`)),`${mutation.name} did not reach ${mode} production artifact`);
    }killed.push(mutation.name);
  }finally{fs.rmSync(tmp,{recursive:true,force:true});}
}
assert.equal(killed.length,mutations.length);
console.log(JSON.stringify({schema:'schelm-production-mutations-v1',killed}));
