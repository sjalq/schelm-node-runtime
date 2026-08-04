'use strict';
const mode = process.argv[2];
const count = Number(process.argv[3] || 3);
const app = require(`../build/boundary-${mode}.js`).Elm.Main.init({ flags: count });
const events = [];
app.ports.report.subscribe(event => {
  events.push(event);
  if (events.length === count) {
    process.stdout.write(JSON.stringify(events));
    if (process.argv[4] === 'expect-limit' && events.filter(x => x.outcome === 'count').length !== 1) process.exit(91);
    process.exit(0);
  }
});
setTimeout(() => process.exit(90), 2000);
