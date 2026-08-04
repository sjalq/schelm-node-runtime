'use strict';
const mode = process.argv[2];
const subsystem = process.argv[3];
const app = require(`../build/runtime-${mode}.js`).Elm.Main.init({ flags: 'ordinary' });
const events = [];
app.ports.report.subscribe(event => {
  events.push(event);
  if (subsystem === 'signal' && event === 'signal') finish();
  if (subsystem === 'ticker' && /^\d+$/.test(event)) finish();
});
if (subsystem === 'signal') setTimeout(() => process.kill(process.pid, 'SIGINT'), 100);
function finish() {
  process.stdout.write(JSON.stringify(events));
  process.exit(0);
}
setTimeout(() => process.exit(90), 3000);
