/*
import Elm.Kernel.List exposing (fromArray, toArray)
import Elm.Kernel.Scheduler exposing (binding, succeed, fail, rawSpawn)
*/
var $crypto = require('node:crypto');
var $perf = require('node:perf_hooks').performance;
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
var $consoleState=[{terminal:null},{terminal:null}];
function $console(which){return {stream:which===0?process.stdout:process.stderr,state:$consoleState[which]};}
var _SchelmRuntime_attachConsole = function(which) { return function(send) { return __Scheduler_binding(function(_cb){
  var endpoint=$console(which), active=true;
  function publish(kind){if(!active||endpoint.state.terminal)return;endpoint.state.terminal=kind;__Scheduler_rawSpawn(send(kind));}
  function error(e){publish(e&&e.code==='EPIPE'?'pipe':'closed');}
  function close(){publish('closed');}
  endpoint.stream.on('error',error); endpoint.stream.on('close',close);
  if(endpoint.state.terminal)__Scheduler_rawSpawn(send(endpoint.state.terminal));
  return function(){active=false;endpoint.stream.off('error',error);endpoint.stream.off('close',close);};
}); }; };
var _SchelmRuntime_write = function(which) { return function(text) { return __Scheduler_binding(function(cb){ var endpoint=$console(which); if(endpoint.state.terminal){cb(__Scheduler_succeed(endpoint.state.terminal));return;} try { endpoint.stream.write(text,function(e){ if(e&&e.code==='EPIPE')endpoint.state.terminal='pipe';cb(__Scheduler_succeed(e?(e.code==='EPIPE'?'pipe':'failed'):(endpoint.state.terminal||'ok'))); }); } catch(e) { if(e&&e.code==='EPIPE')endpoint.state.terminal='pipe';cb(__Scheduler_succeed(e&&e.code==='EPIPE'?'pipe':'failed')); } }); }; };
var _SchelmRuntime_attachSignal = function(signal) { return function(send) { return __Scheduler_binding(function(_cb){ var name=signal===0?'SIGINT':'SIGTERM'; var listener=function(){ if($terminalLease)$restore($terminalLease.id); __Scheduler_rawSpawn(send({})); }; process.on(name,listener); return function(){process.off(name,listener);}; }); }; };
var _SchelmRuntime_delayUntil = function(target) { return __Scheduler_binding(function(cb){ var ms=Math.max(0,target-$perf.now()); var id=setTimeout(function(){cb(__Scheduler_succeed({__$wall:Date.now(),__$mono:$perf.now()}));},ms); return function(){clearTimeout(id);}; }); };
function $restore(id) { if(!$terminalLease||$terminalLease.id!==id)return 'released'; if(!$terminalLease.raw && !$terminalLease.poison)return 'ok'; try { process.stdin.setRawMode(false); $terminalLease.raw=false; $terminalLease.poison=false; return 'ok'; } catch(_){ $terminalLease.poison=true; return 'restore'; } }
var _SchelmRuntime_acquireTerminal = __Scheduler_binding(function(cb){
  if($terminalLease){cb(__Scheduler_succeed({__$kind:$terminalLease.poison?'restore':'busy'}));return;}
  if(!process.stdin.isTTY||!process.stdout.isTTY||typeof process.stdin.setRawMode!=='function'||!(process.stdout.columns>0)||!(process.stdout.rows>0)){cb(__Scheduler_succeed({__$kind:'not'}));return;}
  var lease={id:$nextLease++,raw:false,poison:false,decoder:new TextDecoder('utf-8',{fatal:false}),strictDecoder:new TextDecoder('utf-8',{fatal:true}),remainder:Buffer.alloc(0),ended:false,eofFlushed:false}; $terminalLease=lease; var back=function(){$restore(lease.id);}; var ended=function(){lease.ended=true;}; lease.back=back;lease.endedListener=ended;process.on('exit',back);process.stdin.on('end',ended);
  cb(__Scheduler_succeed({__$kind:'ok',__$id:lease.id,__$columns:process.stdout.columns,__$rows:process.stdout.rows,__$depth:process.stdout.getColorDepth?process.stdout.getColorDepth():0}));
});
var _SchelmRuntime_setRaw = function(id){return function(raw){return __Scheduler_binding(function(cb){if(!$terminalLease||$terminalLease.id!==id){cb(__Scheduler_succeed('released'));return;}if($terminalLease.poison){cb(__Scheduler_succeed('restore'));return;}try{process.stdin.setRawMode(raw);$terminalLease.raw=raw;cb(__Scheduler_succeed('ok'));}catch(_){if(!raw)$terminalLease.poison=true;cb(__Scheduler_succeed(raw?'failed':'restore'));}});};};
var _SchelmRuntime_release = function(id){return __Scheduler_binding(function(cb){if(!$terminalLease||$terminalLease.id!==id){cb(__Scheduler_succeed('released'));return;}var r=$restore(id);if(r==='restore'){cb(__Scheduler_succeed('restore'));return;}process.off('exit',$terminalLease.back);process.stdin.off('end',$terminalLease.endedListener);$terminalLease=null;cb(__Scheduler_succeed('ok'));});};
var _SchelmRuntime_recover = __Scheduler_binding(function(cb){if(!$terminalLease||!$terminalLease.poison){cb(__Scheduler_succeed('released'));return;}var r=$restore($terminalLease.id);if(r==='ok'){process.off('exit',$terminalLease.back);$terminalLease=null;}cb(__Scheduler_succeed(r));});
var _SchelmRuntime_read = function(id){return __Scheduler_binding(function(cb){
  if(!$terminalLease||$terminalLease.id!==id){cb(__Scheduler_succeed({__$kind:'closed'}));return;}
  var lease=$terminalLease,done=false;
  function cleanup(){process.stdin.off('data',data);process.stdin.off('end',end);process.stdin.pause();}
  function finish(value){if(done)return;done=true;cleanup();cb(__Scheduler_succeed(value));}
  function malformed(bytes,stream){try{lease.strictDecoder.decode(bytes,{stream:stream});return false;}catch(_){lease.strictDecoder=new TextDecoder('utf-8',{fatal:true});return true;}}
  function deliver(bytes){var take=bytes.subarray(0,16384);lease.remainder=bytes.subarray(take.length);var bad=malformed(take,true);var text=lease.decoder.decode(take,{stream:true});finish({__$kind:'piece',__$text:text,__$bytes:take.length,__$malformed:bad});}
  function flush(){if(lease.eofFlushed){finish({__$kind:'end',__$malformed:false});return;}lease.eofFlushed=true;var bad=malformed(new Uint8Array(0),false),text=lease.decoder.decode();lease.decoder=new TextDecoder('utf-8',{fatal:false});lease.strictDecoder=new TextDecoder('utf-8',{fatal:true});if(text||bad)finish({__$kind:'piece',__$text:text,__$bytes:0,__$malformed:bad});else finish({__$kind:'end',__$malformed:false});}
  function data(buf){deliver(Buffer.concat([lease.remainder,Buffer.from(buf)]));}
  function end(){lease.ended=true;if(lease.remainder.length)deliver(lease.remainder);else flush();}
  if(lease.remainder.length){deliver(lease.remainder);return function(){};}
  if(lease.ended||process.stdin.readableEnded){lease.ended=true;flush();return function(){};}
  process.stdin.once('data',data);process.stdin.once('end',end);process.stdin.resume();return cleanup;
});};
var _SchelmRuntime_attachResize = function(send){return __Scheduler_binding(function(_cb){var listener=function(){if(process.stdout.columns>0&&process.stdout.rows>0)__Scheduler_rawSpawn(send({__$columns:process.stdout.columns,__$rows:process.stdout.rows}));};process.stdout.on('resize',listener);return function(){process.stdout.off('resize',listener);};});};
