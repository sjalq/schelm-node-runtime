'use strict';
const mode=process.argv[2],kind=process.argv[3];
const app=require(`../build/runtime-${mode}.js`).Elm.Main.init({flags:`fanout-${kind}`});
const events=[];app.ports.report.subscribe(x=>{if((kind==='signal'&&x==='signal')||(kind==='ticker'&&/^\d+$/.test(x)))events.push(x);if(events.length===200){process.stdout.write(JSON.stringify(events));process.exit(0);}});
if(kind==='signal')setTimeout(()=>process.kill(process.pid,'SIGINT'),100);
setTimeout(()=>process.exit(90),3000);
