'use strict';
const mode=process.argv[2],kind=process.argv[3];
const limit=kind==='signal-limit';
const app=require(`../build/runtime-${mode}.js`).Elm.Main.init({flags:limit?'limit-signal':`fanout-${kind}`});
const events=[];app.ports.report.subscribe(x=>{if(((kind==='signal'||kind==='signal-limit')&&(x==='signal'||x==='signal-limit'))||(kind==='ticker'&&/^\d+$/.test(x)))events.push(x);if((!limit&&events.length===200)||(limit&&events.filter(x=>x==='signal').length===200&&events.filter(x=>x==='signal-limit').length===1)){process.stdout.write(JSON.stringify(events));process.exit(0);}});
if(kind==='signal'||kind==='signal-limit')setTimeout(()=>process.kill(process.pid,'SIGINT'),100);
setTimeout(()=>process.exit(90),3000);
