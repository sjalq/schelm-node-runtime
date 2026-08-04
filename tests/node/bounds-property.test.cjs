'use strict';
const test=require('node:test');const assert=require('node:assert/strict');
function consoleOracle(cmds){let count=0,bytes=0,accepted=[];for(const n of cmds){if(count>=256)accepted.push('count');else if(bytes+n>1048576)accepted.push('bytes');else{count++;bytes+=n;accepted.push('ok');}}return{count,bytes,accepted};}
function nextTarget(target,interval,actual){if(actual<target)return{due:false,target};const skipped=Math.max(0,Math.floor((actual-target)/interval));return{due:true,skipped,target:target+(skipped+1)*interval};}
let seed=104729;function rnd(){seed=(seed*48271)%2147483647;return seed;}
test('independent console oracle bounds 200 generated traces',()=>{for(let trace=0;trace<200;trace++){const xs=[];for(let i=0;i<300;i++)xs.push([0,1,65535,65536,rnd()%70000][rnd()%5]);const got=consoleOracle(xs);assert.ok(got.count<=256);assert.ok(got.bytes<=1048576);assert.equal(got.accepted.length,300);}});
test('zero writes consume count independent of bytes',()=>{const got=consoleOracle(Array(257).fill(0));assert.equal(got.count,256);assert.equal(got.bytes,0);assert.equal(got.accepted[256],'count');});
test('target scheduler coalesces without callback-count drift',()=>{for(let i=0;i<2000;i++){const interval=10+rnd()%10000,target=1000+interval,actual=target+(rnd()%100)*interval+(rnd()%interval);const got=nextTarget(target,interval,actual);assert.ok(got.due);assert.ok(got.target>actual);assert.equal(got.target,target+(got.skipped+1)*interval);}});
test('200 fanout is one physical fact and 200 app facts',()=>{const taggers=Array.from({length:200},(_,i)=>x=>[i,x]);const physical={kind:'signal'};const app=taggers.map(f=>f(physical));assert.equal(app.length,200);assert.equal(new Set(app.map(x=>x[1])).size,1);});
