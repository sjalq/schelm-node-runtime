'use strict';
const path = require('node:path');
const mode = process.argv[2];
const elm = require(path.resolve(__dirname, `../build/feasibility-${mode}.js`));
const app = elm.Elm.Main.init({ flags: null });
const events = [];
app.ports.report.subscribe((value) => {
  events.push(value);
  process.stderr.write(`REPORT ${JSON.stringify(value)}\n`);
});
setTimeout(() => process.emit('schelm-runtime-feasibility', 'first'), 30);
setTimeout(() => app.ports.control.send('unsubscribe'), 60);
setTimeout(() => process.emit('schelm-runtime-feasibility', 'after-unsubscribe'), 90);
setTimeout(() => {
  const kinds = events.map((x) => x.kind);
  if (!kinds.includes('snapshot') || !kinds.includes('written') || !kinds.includes('probe') || kinds.filter((x) => x === 'probe').length !== 1) process.exit(91);
  app.ports.control.send('exit7');
}, 130);
setTimeout(() => process.exit(92), 500);
