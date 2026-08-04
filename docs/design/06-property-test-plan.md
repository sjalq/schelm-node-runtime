# 06 — Property and state-machine test plan

Status: blocking implementation and package-audit plan. Commands and seeds are
normative; reducing coverage requires a reviewed design change.

## 1. Layers and entry points

1. `tests/elm/ValueProperties.elm`: constructors/bounds/time/UTF-8 pure tests.
2. `tests/elm/*ReducerProperties.elm`: production reducers under generated
   traces.
3. `tests/oracle/*.elm`: independent declarative oracles; import gate rejects
   production reducer imports.
4. `tests/node/kernel-*.test.cjs`: canonical kernel machines with injected Node
   facts/failures.
5. `fixture-apps/{production,fixture,pty}/`: real Schelm package apps.
6. `tests/run-workers.cjs`: debug/opt normalized trace differential.
7. `tests/pty/*.test.cjs`: raw/signal/EOF real subprocess tests.
8. `tests/scale/*.test.cjs`: 200-subscriber/write and bounded-resource gates.
9. `tests/artifact-gate.cjs`, `archive-repro.cjs`, `toolchain-gate.cjs`,
   `provenance.cjs`.
10. `tests/audit.cjs`: final package-only self-audit aggregator.

`npm test` runs focused bounds/oracles first, then workers/PTY/scale/artifacts.
Every child has 30 s timeout (PTY 60 s), ≤10 MiB captured output, and explicit
cleanup. Full generated suite target ≤10 minutes on recorded linux-x64 Node
24.4.1 host.

## 2. External trace vocabularies

Separate command unions exist for Console, Signal, Terminal, and Ticker. They
contain only public requests plus injected physical observations, e.g.
`Enqueue endpoint id bytes`, `WriteCallback generation id outcome`,
`SignalCallback signal generation`, `Acquire facts`, `Restore outcome`,
`ReadBytes generation bytes eof`, `StartTicker id interval now`, and
`TimerWake generation wall mono`. Production reducer and oracle each adapt this
vocabulary independently.

Observable output is a closed event union: accepted/rejected/settled ids,
delivered public facts, physical verb requests, listener/timer counts, poison
status, and dropped stale ids. Internal queue representation/generation counters
are not compared except through invariants.

## 3. Exact generators

Use `elm-explorations/test` with fixed master seeds `104729`, `130363`,
`155921`, `196613`; 2,000 traces/seed/subsystem in pure suites. Trace length is
biased: 20% 0..8, 50% 9..64, 25% 65..256, 5% 257..1,024. State-aware generator
weights:

- 55% currently valid operation;
- 20% boundary operation (0/max/max+1, last slot, simultaneous target);
- 15% stale/duplicate callback/id/generation;
- 10% injected physical failure/close/restore throw.

Console byte widths draw 30% from `[0,1,65535,65536,65537]`, 40% uniform
0..70,000, 20% queue-bound-completing values, 10% random Unicode strings.
Terminal bytes draw all partitions of fixed UTF-8 corpus plus random arrays
0..16,385; 25% malformed. Subscriber/joiner counts draw 60% boundaries
`[0,1,63,64,65,199,200,201]`, 40% uniform 0..220. Ticker time jumps draw 40%
`[0,i-1,i,i+1,10*i,MAX_SAFE]`, 60% bounded random; interval boundaries
`[9,10,11,86400000,86400001]`. Environment/argv/entropy use every documented
count/byte boundary and random well/ill-formed host text.

## 4. Shrinkers

Shrink in this deterministic order:

1. delete contiguous trace chunks (largest power-of-two first);
2. delete individual commands from end to start;
3. replace ids/generations with 0, then nearest live id;
4. shrink counts toward `[0,1,max-1,max,max+1]`;
5. shrink bytes by removing suffix, then chunks, then scalar width;
6. shrink time toward previous target, target, target+1;
7. replace outcome with success, then each closed failure ordinal;
8. shrink subscriber sets to one offending tagger.

The runner repeats shrink to fixed point or 5,000 candidates/10 s. It writes the
smallest external trace as canonical JSON with schema version, subsystem, seed,
case index, and expected/actual normalized digests.

## 5. Replay and digest

Replay command:

```sh
node tests/replay.cjs build/failures/<subsystem>-<sha256>.json \
  --mode=debug|optimize|oracle|production
```

Canonical trace/event JSON uses recursively sorted object keys, decimal finite
numbers, lowercase enum tokens, ids renumbered by first appearance, and no
whitespace. Normalization replaces wall/mono/PID/random/path values with ordinal
facts while retaining order, deltas, widths, skipped counts, and error kinds.
Digest is SHA-256 over:

```text
schelm-node-runtime-trace-v1\n<canonical-input>\n<canonical-events>\n
```

Debug, optimize, production reducer, fixture boundary, and independent oracle
must match the expected normalized event digest where their observation layer is
equivalent. Failure output always prints seed, case index, pre/post-shrink length,
digest, replay path, compiler/Node hashes.

## 6. Core properties

### Runtime/time/entropy

- selection dedupes exact names, honors all count/byte bounds, and crosses only
  selected keys;
- snapshots reject unpaired surrogates and oversize argv/env facts;
- `Elapsed` is non-negative and accepts observations beyond 24 h;
- `TimerDuration` accepts exactly 10..86,400,000;
- deadline reached/remaining agree with a rational/integer oracle and saturate;
- wall jumps never affect monotonic deadlines;
- entropy validates exactly 1..65,536, returns exact width, hex exact lowercase
  double width, and never invokes fallback after injected failure.

### Console

- pending count ≤256 and bytes ≤1 MiB independently, including zero writes;
- FIFO settlement, exactly once per accepted id;
- 257th zero write rejects even at zero pending bytes;
- EPIPE/close settles all and late callbacks drop;
- callback success means acknowledged only;
- two-list reducer agrees with declarative sequence oracle;
- strict UTF-8 width and lone-surrogate rejection.

### Terminal/input

- at most one Live/Poisoned physical lease and one `InputReader`;
- acquisition requires all interactive facts;
- joiner/event/tagger counts never exceed bounds;
- one read outstanding/piece ≤16,384; no package observer `Sub` exists;
- every valid UTF-8 partition decodes identically;
- malformed and incomplete EOF facts/sequence match TextDecoder oracle;
- release success restores before absence; restore failure yields Poisoned;
- poisoned acquisition fails; failed recovery remains poisoned; successful
  recovery removes registry/backstop;
- duplicate release joins only before settlement; settled stale calls reject;
- no post-close/release event.

### Signals

- physical listener count is zero iff accepted taggers zero, otherwise one;
- generations strictly change on detach/reattach;
- stale callbacks never deliver;
- cooked restore observation precedes subscribed signal delivery;
- last unsubscribe removes listener/default disposition; zero-state signals
  produce no package event;
- 201st tagger receives limit event/no later signals.

### Tickers

- ≤64 logical tickers/≤64 start joiners/≤200 taggers/ticker/≤256 self-events;
- one physical timeout globally;
- earliest target is armed; stale generation drops;
- next target derives from old target; delayed wake emits once/no backlog;
- skipped count/delta agree with independent integer oracle;
- long `Elapsed` remains representable while timer request stays bounded.

## 7. Independent oracle gate

`tests/oracle/import-gate.cjs` fails if any oracle imports a path/module matching
`src/**/Reducer`, generated kernel source, or fixture machine adapter. Oracle
source digest is reported separately. Mutation tests apply at least 12 known
production mutations (off-by-one bounds, stale-generation acceptance, FIFO/LIFO,
actual-based timer target, poison cleared on failure, zero-write count omitted,
listener retained at zero). Every mutation must be killed by oracle/property
tests; otherwise audit fails.

## 8. Real compiler matrix

Build production and fixture apps using compiler binary SHA
`69987adf...8654`, Node binary SHA `82e1a4...034a`, isolated cold and warm
`ELM_HOME`, debug and `--optimize`. Workers cover every public constructor,
manager `Cmd.map` identity/composition, `Sub.map` identity/composition, callback
settlement, `Process.kill` abandonment, and fixture-held physical callbacks.
Compile-only API fixture is rebuilt and hashes compared or deliberately updated
with review.

Normalized worker traces must match across modes. Generated output is scanned for
required production kernels and absence of fixture protocol names in production.

## 9. PTY and synchronous restoration

A Node parent opens a real pseudo-terminal (or records an explicit unsupported
skip outside the normative linux-x64 gate). Scenarios: cooked→raw→release,
SIGINT/SIGTERM with subscriber, last unsubscribe/default signal process status,
normal process exit while raw, duplicate cleanup, injected restore throw→poison,
failed/success recovery, malformed/input EOF. Parent reads termios before/after
and has 60 s kill ladder. SIGKILL test documents no restoration guarantee and
must not be interpreted as package failure.

## 10. 200-scale matrix

Executable fixtures assert:

- 200 SIGINT and 200 SIGTERM taggers: one physical listener each, 200 messages;
- 200 resize taggers: one listener, 200 messages, 201st limit event;
- one `InputReader` result fanned by the fixture application to 200 ordinary Elm
  observers: one physical read, no observer can call package read;
- 200 ticker taggers: one logical ticker/one physical timeout/200 messages;
- 200 concurrent console writes including zero and max widths within byte bound:
  FIFO callbacks, one error listener, no count leak;
- 64 acquire/release/recovery joiners: one physical verb, 64 settlements; 65th
  deterministic rejection;
- 64 tickers: one timeout; 65th rejected.

Instrumentation counts new bytes/events only and records heap before/after forced
GC where available. Blocking complexity assertions are structural counts, not a
flaky absolute latency threshold.

## 11. Artifact, archive, and provenance

Artifact gate rejects `@fixture`, observer globals, injected-failure strings,
absolute repo/worktree paths, credentials, source maps, and duplicate canonical
machine bodies from production JS/archive. Archive staging sets sorted paths,
fixed modes/mtime/uid/gid; two builds compare SHA-256. Toolchain gate verifies
compiler authorization ancestry, exact compiler/Node/public seed hashes, offline
build, and private/public identity collision failure.

`build/provenance.json` schema includes commit/tree/dirty=false, toolchain hashes,
API fixture source/generated hashes, production/fixture generated hashes,
oracle source hash, four master seeds, trace counts, normalized digests, PTY/OS
facts, archive digest, commands, and non-reproducibility claim. Provenance is
generated last and validated against current clean commit.

## 12. Staged release and audit

1. pure values + production reducers + independent oracles/mutation gate;
2. canonical kernels and Node injected tests;
3. real debug/opt workers and PTY;
4. 200-scale and complexity gates;
5. artifact/archive/toolchain/provenance;
6. `tests/audit.cjs` self-audit and clean diff review;
7. commit/push package implementation and audit evidence.

Harness integration is forbidden before stage 7. Any API change returns to API
fixture compilation and design review; any guarantee change updates this plan
before code.
