'use strict';
const { EventEmitter } = require('node:events');
const mode = process.argv[2];
const scenario = process.argv[3];
const writes = [];
const stream = new EventEmitter();
stream.isTTY = false;
stream.write = (text, callback) => { writes.push(callback); return false; };
stream.columns = 80; stream.rows = 24;
Object.defineProperty(process, 'stdout', { value: stream });
const app = require(`../build/runtime-${mode}.js`).Elm.Main.init({ flags: 'console-suite' });
const events = [];
app.ports.report.subscribe(event => {
  if (!event.startsWith('console:')) return;
  events.push(event);
  if (events.length === 3) {
    process.stderr.write(JSON.stringify(events));
    process.exit(0);
  }
});
setTimeout(() => {
  if (scenario === 'emit-close') stream.emit('close');
  else if (scenario === 'emit-pipe') stream.emit('error', Object.assign(new Error('pipe'), { code: 'EPIPE' }));
  else if (scenario === 'callback-pipe') writes[0](Object.assign(new Error('pipe'), { code: 'EPIPE' }));
  else throw new Error('bad scenario');
  setTimeout(() => { if (writes[0]) writes[0](null); }, 20);
}, 100);
setTimeout(() => process.exit(90), 3000);
