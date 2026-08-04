/*
import Elm.Kernel.List exposing (fromArray, toArray)
import Elm.Kernel.Scheduler exposing (binding, succeed, fail, rawSpawn)
*/
var $crypto = require('node:crypto');
var $perf = require('node:perf_hooks').performance;
var $decoder = new TextDecoder('utf-8', { fatal: false });
var $terminalLease = null;
var $nextLease = 1;

function $ok(v) { return { $: 'Ok', a: v }; }
function $err(v) { return { $: 'Err', a: v }; }
function $utf8(s) { return Buffer.byteLength(s, 'utf8'); }
function $wellFormed(s) {
  for (var i=0;i<s.length;i++) { var c=s.charCodeAt(i); if (c>=0xD800&&c<=0xDBFF) { if (++i>=s.length) return false; var d=s.charCodeAt(i); if(d<0xDC00||d>0xDFFF)return false; } else if(c>=0xDC00&&c<=0xDFFF)return false; }
  return true;
}
var _SchelmRuntime_utf8Width = function(s) { return $wellFormed(s) ? $utf8(s) : -1; };
var _SchelmRuntime_snapshot = function(names) { return __Scheduler_binding(function(cb) {
  try {
    var selected=[]; __List_toArray(names).forEach(function(n){ if(Object.prototype.hasOwnProperty.call(process.env,n)) selected.push({__$a:n,__$b:String(process.env[n])}); });
    cb(__Scheduler_succeed({__$platform:process.platform,__$arch:process.arch,__$pid:process.pid,__$args:__List_fromArray(process.argv.slice()),__$exec:process.execPath,__$env:__List_fromArray(selected)}));
  } catch (_) { cb(__Scheduler_fail('unsupported')); }
}); };
var _SchelmRuntime_wallNow = __Scheduler_binding(function(cb){ cb(__Scheduler_succeed(Date.now())); });
var _SchelmRuntime_monotonicNow = __Scheduler_binding(function(cb){ cb(__Scheduler_succeed($perf.now())); });
var _SchelmRuntime_entropy = function(n) { return __Scheduler_binding(function(cb){ $crypto.randomBytes(n,function(e,b){ if(e)cb(__Scheduler_fail({})); else cb(__Scheduler_succeed(new DataView(b.buffer,b.byteOffset,b.byteLength))); }); }); };
var _SchelmRuntime_entropyHex = function(n) { return __Scheduler_binding(function(cb){ $crypto.randomBytes(n,function(e,b){ if(e)cb(__Scheduler_fail({})); else cb(__Scheduler_succeed(b.toString('hex'))); }); }); };
var _SchelmRuntime_write = function(which) { return function(text) { return __Scheduler_binding(function(cb){ var stream=which===0?process.stdout:process.stderr; try { stream.write(text,function(e){ cb(__Scheduler_succeed(e ? 'failed' : 'ok')); }); } catch(e) { cb(__Scheduler_succeed(e&&e.code==='EPIPE'?'pipe':'failed')); } }); }; };
var _SchelmRuntime_attachSignal = function(signal) { return function(send) { return __Scheduler_binding(function(_cb){ var name=signal===0?'SIGINT':'SIGTERM'; var listener=function(){ if($terminalLease)$restore($terminalLease.id); __Scheduler_rawSpawn(send({})); }; process.on(name,listener); return function(){process.off(name,listener);}; }); }; };
var _SchelmRuntime_delay = function(ms) { return __Scheduler_binding(function(cb){ var id=setTimeout(function(){cb(__Scheduler_succeed({__$wall:Date.now(),__$mono:$perf.now()}));},ms); return function(){clearTimeout(id);}; }); };
function $restore(id) { if(!$terminalLease||$terminalLease.id!==id)return 'released'; if(!$terminalLease.raw && !$terminalLease.poison)return 'ok'; try { process.stdin.setRawMode(false); $terminalLease.raw=false; $terminalLease.poison=false; return 'ok'; } catch(_){ $terminalLease.poison=true; return 'restore'; } }
var _SchelmRuntime_acquireTerminal = __Scheduler_binding(function(cb){
  if($terminalLease){cb(__Scheduler_succeed({__$kind:$terminalLease.poison?'restore':'busy'}));return;}
  if(!process.stdin.isTTY||!process.stdout.isTTY||typeof process.stdin.setRawMode!=='function'||!(process.stdout.columns>0)||!(process.stdout.rows>0)){cb(__Scheduler_succeed({__$kind:'not'}));return;}
  var lease={id:$nextLease++,raw:false,poison:false}; $terminalLease=lease; var back=function(){$restore(lease.id);}; lease.back=back; process.on('exit',back);
  cb(__Scheduler_succeed({__$kind:'ok',__$id:lease.id,__$columns:process.stdout.columns,__$rows:process.stdout.rows,__$depth:process.stdout.getColorDepth?process.stdout.getColorDepth():0}));
});
var _SchelmRuntime_setRaw = function(id){return function(raw){return __Scheduler_binding(function(cb){if(!$terminalLease||$terminalLease.id!==id){cb(__Scheduler_succeed('released'));return;}if($terminalLease.poison){cb(__Scheduler_succeed('restore'));return;}try{process.stdin.setRawMode(raw);$terminalLease.raw=raw;cb(__Scheduler_succeed('ok'));}catch(_){if(!raw)$terminalLease.poison=true;cb(__Scheduler_succeed(raw?'failed':'restore'));}});};};
var _SchelmRuntime_release = function(id){return __Scheduler_binding(function(cb){if(!$terminalLease||$terminalLease.id!==id){cb(__Scheduler_succeed('released'));return;}var r=$restore(id);if(r==='restore'){cb(__Scheduler_succeed('restore'));return;}process.off('exit',$terminalLease.back);$terminalLease=null;cb(__Scheduler_succeed('ok'));});};
var _SchelmRuntime_recover = __Scheduler_binding(function(cb){if(!$terminalLease||!$terminalLease.poison){cb(__Scheduler_succeed('released'));return;}var r=$restore($terminalLease.id);if(r==='ok'){process.off('exit',$terminalLease.back);$terminalLease=null;}cb(__Scheduler_succeed(r));});
var _SchelmRuntime_read = function(id){return __Scheduler_binding(function(cb){if(!$terminalLease||$terminalLease.id!==id){cb(__Scheduler_succeed({__$kind:'closed'}));return;}var done=false;function cleanup(){process.stdin.off('data',data);process.stdin.off('end',end);}function data(buf){if(done)return;done=true;cleanup();process.stdin.pause();var b=Buffer.from(buf);var text=$decoder.decode(b,{stream:true});cb(__Scheduler_succeed({__$kind:'piece',__$text:text,__$bytes:b.length,__$malformed:text.indexOf('\uFFFD')>=0}));}function end(){if(done)return;done=true;cleanup();var text=$decoder.decode();cb(__Scheduler_succeed(text?{__$kind:'piece',__$text:text,__$bytes:0,__$malformed:true}:{__$kind:'end',__$malformed:false}));}process.stdin.once('data',data);process.stdin.once('end',end);process.stdin.resume();return cleanup;});};
var _SchelmRuntime_attachResize = function(send){return __Scheduler_binding(function(_cb){var listener=function(){if(process.stdout.columns>0&&process.stdout.rows>0)__Scheduler_rawSpawn(send({__$columns:process.stdout.columns,__$rows:process.stdout.rows}));};process.stdout.on('resize',listener);return function(){process.stdout.off('resize',listener);};});};
