# 05 — Final design revision B

Status: final pre-implementation contract. This supersedes prior designs where
inconsistent. Production source is authorized only after this document,
`04-adversarial-review-b.md`, `06-property-test-plan.md`, and the API compile
fixture are committed and pushed.

## 1. Frozen v1

V1 contains seven modules exactly as compiled in `api-feasibility/package`:

- `Schelm.Node.Runtime`: bounded immutable process/selected-environment snapshot;
- `Runtime.Clock`: wall/monotonic facts, **unbounded observed `Elapsed`**, bounded
  requested `TimerDuration`, process-local deadlines;
- `Runtime.Entropy`: 1..65,536 cryptographic bytes/lowercase hex;
- `Runtime.Console`: bounded acknowledged stdout/stderr command queue;
- `Runtime.Signal`: SIGINT/SIGTERM subscriptions preserving default disposition
  at zero subscribers;
- `Runtime.Ticker`: ≤64 target-based logical tickers over one physical timeout;
- `Schelm.Node.Terminal`: one interactive lease, one `InputReader`, raw control,
  resize, poison/recovery.

Process exit, session close, process title, generic streams, arbitrary signals,
ANSI/UI policy, parsing, filesystem, network, and harness policy are deferred.
The daemon host exit swallow remains. Tokens are cooperative, not security
capabilities.

## 2. Final public API evidence

The normative signatures are the formatted modules under
`api-feasibility/package/src/`. They are duplicated neither here nor in a second
hand-maintained listing. `api-feasibility/app/src/Main.elm` constructs every
manager command/subscription family and exercises `Cmd.map`/`Sub.map`. It compiled
with the pinned Schelm compiler in debug and optimize before production source:

| Artifact | Bytes | SHA-256 |
|---|---:|---|
| API debug | 92,350 | `b48573dd407ed483f84ea1a2891ec9271ca667c575d4ec0c52da6842f654d30d` |
| API optimize | 89,463 | `4b05af516e65a0c72883dcc0aadc9232b7afaeb970c826e0b15a68ca57def5cc` |

This proves legal topology/types, not runtime semantics. Production must preserve
this exposed surface unless a new review artifact explains and compile-tests a
change.

## 3. Time types and scheduler

`Elapsed` stores a non-negative finite monotonic millisecond `Float`; it has no
application-level maximum and represents arbitrarily long observed process
uptime within JS numeric precision. It cannot construct a timer. `TimerDuration`
is integer 10..86,400,000 ms and only requests bounded waits. `Deadline` is an
opaque process-local monotonic target. Addition saturates at JS
`Number.MAX_SAFE_INTEGER`; `remaining` returns unbounded `Elapsed`. None is
serializable by this package.

Ticker rules from revision A are final: next targets advance from the prior
target, delayed wakes coalesce to one event, skipped count is capped at
`2^31-1`, ≤64 logical tickers share one physical timeout, and timer generations
drop stale callbacks. Count bounds: ≤64 tickers, ≤200 taggers per ticker, ≤64
pending start callbacks globally, and ≤256 queued self-events. Exceeding a
publicly observable bound returns `TooManyTickers`/`TooManyStartJoiners`; extra
subscription taggers receive no events and fixture instrumentation records the
limit (the final `Tick` API remains unchanged).

## 4. Console bounds and settlement

`Text` is strictly well-formed Unicode scalar text and 0..65,536 UTF-8 bytes.
A zero-byte write is legal, consumes one event/write slot, and is acknowledged
without calling Node. Per endpoint: ≤256 accepted unsettled writes and ≤1 MiB
pending UTF-8 bytes, including the in-flight write. FIFO is an amortized-O(1)
two-list queue. The first package write installs one retained endpoint error
listener. Callback/stream EPIPE settles all accepted work once as `BrokenPipe`;
close as `Closed`; stale generations do nothing. No accepted write is publicly
cancelable and success means only Node callback acknowledgement. Endpoint
manager self-events are bounded by accepted-write count plus one error event.

## 5. Signals and default disposition

Each signal allows ≤200 taggers and owns exactly zero physical listener at zero,
one at positive count. 0→positive installs a fresh generation; positive→0
detaches the exact owner before manager acknowledgement and restores Node's
default disposition. A signal occurring with no package listener is not observed
or replayed. Current-generation callback order is:

1. synchronously restore a live/poisoned package terminal toward cooked;
2. record restoration outcome in the physical lease;
3. queue one manager self-event;
4. manager validates signal generation;
5. fan one Elm message to each accepted current tagger.

The package never re-raises a subscribed signal. Application policy decides
exit/re-subscribe/raw re-enable. Detach/reattach always increments generation.

## 6. Terminal, single input owner, and poison recovery

Acquisition requires interactive stdin and stdout, raw support, and positive
size. Limits: ≤64 acquisition joiners, ≤64 control/release/recovery joiners,
≤200 resize taggers, one live lease, one `InputReader`, one read callback, one
≤16,384-byte piece, and ≤256 queued terminal self-events. Deterministic excess
errors are the compiled `TooMany...`/busy errors; resize excess receives
`ResizeSubscriberLimit` and no future sizes.

`InputReader` is the sole stdin owner. There is no input `Sub` and no package
observer fanout. `read reader callback` permits exactly one outstanding read,
pauses stdin before Elm settlement, and requires the next explicit `read` to
consume/advance after the application has processed the prior piece. Ordinary
Elm may fan the resulting immutable text/facts to 200 or more observers; those
observers have no package authority.

UTF-8 replacement semantics are final: streaming decoder reconstructs split
valid scalars; malformed bytes yield U+FFFD and a true malformed fact; incomplete
EOF yields one final replacement-marked piece, then a subsequent read yields
`InputEnded True`; clean EOF yields `InputEnded False`. No event follows closed
reader/released lease settlement.

Raw restoration is synchronous and idempotent. If cooked restoration throws,
the physical registry becomes `Poisoned { leaseId, restoreFailure }`; logical
release detaches listeners/read ownership but **does not make acquisition
available**. `acquire` returns `RestoreFailed`. `recover runtime callback`
retries synchronous cooked restoration: success removes poison and the process
exit/signal backstop; failure remains poisoned and returns
`RestoreFailedControl`. At most 64 recovery joiners share one attempt. The
backstop remains installed while Live or Poisoned. SIGKILL/native crash/runtime
corruption/power loss cannot guarantee restoration.

## 7. Exact topology and reducers

The legal Task/Cmd/Sub topology and minimal terminal physical registry from
revision A are final. Long manager operations are spawned; `onEffects` enqueues
and returns. Completion enters `onSelfMsg` with id+generation. Elm reducers own
policy and bounds; kernels execute facts/verbs and synchronous terminal restore.

Each stateful subsystem has:

1. a production Elm reducer imported by its effect manager; and
2. an independently authored declarative oracle under `tests/oracle/` that does
   not import production reducers or transition helpers.

Both consume a shared external command/observation vocabulary only. Agreement is
checked on normalized observable output and invariants, not internal states.

## 8. Bounds summary

| Resource | Count bound | Byte/time bound |
|---|---:|---:|
| selected env names | 128 | 256/name, 16 KiB names, 64 KiB/value, 1 MiB values |
| argv | 1,024 | 64 KiB/item, 1 MiB total; executable 4 KiB |
| entropy | one Task | 1..65,536 bytes; hex ≤131,072 |
| console/endpoint | 256 unsettled | 65,536/write, 1 MiB pending |
| signal taggers/signal | 200 | one self-event per physical signal |
| terminal acquire/control/recovery joiners | 64 each | no text payload |
| resize taggers | 200 | one current size event/tagger |
| input | one reader/read/piece | 16,384 physical bytes |
| tickers | 64 | interval 10..86,400,000 ms |
| ticker taggers/ticker | 200 | one coalesced event/wake |
| manager self-events | 256/subsystem | bounded facts only |

Zero-byte writes still pay a count slot. Joiners/events are bounded independently
of bytes. At item 1,000/session 200/chunk 10,000, cost depends only on new bounded
work and current accepted taggers—not history, sessions, or total prior bytes.

## 9. Independent oracle and artifact architecture

Canonical production reducers are ordinary Elm. Fixture kernels add phase
observations around the same generated kernel transaction bodies; production
assembly strips fixture markers and artifact tests prove absence. Independent
oracles are separate Elm modules with declarative recomputation over bounded
trace state. Reviewers compare imports mechanically: oracle paths may import
external vocabulary and pure bound modules, never production reducer modules.

Production and fixture packages compile from separate source roots in an isolated
private overlay. Debug and optimize real applications execute under pinned Node.
All runners have wall timeout, operation/output caps, deterministic seeds, and
replay files.

## 10. Provenance contract

Generated provenance records final source commit/tree, compiler repository and
authorization ancestor, compiler binary SHA-256, Node archive/binary SHA-256,
public package seed SHA-256, package/API-fixture source hashes, generated
debug/optimize hashes, normalized trace digests, archive digest, OS/kernel/arch,
and command lines. It states that hashes prove tested artifact identity, not
compiler/Node bit-reproducibility. Final provenance is regenerated after all
implementation/audit commits; design fixture hashes are evidence only.

## 11. Package audit gate and integration

After implementation, a dedicated audit checks exposed API against the compiled
fixture, MISI/MITI claims, JS-kernel doctrine, reducer/oracle independence,
all count/byte bounds, complexity diff grep, debug/opt traces, PTY restoration,
artifact leakage, deterministic archive, toolchain provenance, and clean status.
Failures require package fixes and rerun. **No harness integration worktree or
branch starts until this audit passes and is committed.** The revision-A
integration authority matrix remains the future migration plan, not current
implementation permission.

## 12. Final decisions

All review questions are closed: one input owner; replacement-marked UTF-8;
retained console error listeners; 64 logical tickers/one timeout; subscribed
signals restore cooked before delivery; repeated settled release reports
`Released`; elapsed is unbounded and timer requests bounded; oversize selected
runtime facts fail initialization. This contract now authorizes package-only
implementation after the six design artifacts and API fixture are pushed.
