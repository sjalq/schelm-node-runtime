/*
import Elm.Kernel.Scheduler exposing (binding, rawSpawn, succeed)
*/
var $crypto = require('node:crypto');

var _RuntimeFeasibility_snapshot = __Scheduler_binding(function(callback) {
  callback(__Scheduler_succeed({
    __$nowMs: Date.now(),
    __$randomHex: $crypto.randomBytes(8).toString('hex'),
    __$envPresent: Object.prototype.hasOwnProperty.call(process.env, 'SCHELM_FEASIBILITY_ENV'),
    __$isTty: !!(process.stdin.isTTY && process.stdout.isTTY),
    __$columns: Number.isSafeInteger(process.stdout.columns) ? process.stdout.columns : 0,
    __$rows: Number.isSafeInteger(process.stdout.rows) ? process.stdout.rows : 0
  }));
});

var _RuntimeFeasibility_write = function(text) {
  return __Scheduler_binding(function(callback) {
    try {
      process.stdout.write(text, function(error) {
        callback(__Scheduler_succeed(!error));
      });
    } catch (_) {
      callback(__Scheduler_succeed(false));
    }
  });
};

var _RuntimeFeasibility_exit = function(code) {
  return __Scheduler_binding(function(_callback) {
    process.exit(code);
  });
};

var _RuntimeFeasibility_listen = function(sendToSelf) {
  return __Scheduler_binding(function(_callback) {
    var listener = function(value) { __Scheduler_rawSpawn(sendToSelf(String(value))); };
    process.on('schelm-runtime-feasibility', listener);
    return function() { process.off('schelm-runtime-feasibility', listener); };
  });
};
