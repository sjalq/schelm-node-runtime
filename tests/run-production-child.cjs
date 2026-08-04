'use strict';
const mode = process.argv[2];
const scenario = process.argv[3];
const expected = Number(process.argv[4]);
const app = require(`../build/runtime-${mode}.js`).Elm.Main.init({ flags: scenario });
const events = [];
app.ports.report.subscribe(event => {
  events.push(event);
  if (events.length === expected) {
    process.stdout.write(JSON.stringify(events));
    process.exit(0);
  }
});
setTimeout(() => process.exit(90), 3000);
