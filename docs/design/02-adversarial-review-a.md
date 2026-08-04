# 02 — Adversarial review A

Provenance: independent round-one review findings supplied to the package PM on
2026-08-04. This document records the rejection as review input; it is not the
PM reviewing its own design under another heading.

Verdict: **reject `01-design.md` pending revision**. No production implementation
may begin from design 01.

## A1. `Standalone` is fake authority

`Standalone.authorize : Runtime -> Standalone` is public. Any linked Elm module
can mint it and kill the process, so the type does not establish the daemon
safety property claimed by the design. Passing it carefully is application
convention, not enforced authority.

Either omit process exit from v1, or describe the value only as cooperative and
retain the daemon host backstop that swallows accidental session-level exit.
Never claim that a publicly mintable value makes daemon process death
unrepresentable.

## A2. The proposed Task/manager topology may not be legal

Design 01 gives `Task` APIs for writes, lease acquisition, raw mode, and release
while also claiming that one Elm effect manager owns queues, listeners, leases,
and settlement. It does not show how a normal module's Task enters that effect
manager. Elm effect managers receive `Cmd` and `Sub`; an arbitrary kernel Task
bypasses `onEffects` unless ownership secretly moves into JavaScript.

The revision must specify the exact compiler-legal module topology:

- which one-shot operations are direct kernel Tasks;
- which operations are manager commands with callbacks;
- which listeners are subscriptions;
- which state is Elm-manager state versus a minimal kernel resource handle; and
- how public facade modules can construct each operation.

All shown APIs and error types must be total and compile as written. Do not use
an opaque error while pattern matching it in examples, omit an accessor from an
exposing list, or present a `Task` API that only a fictional manager bridge could
implement.

## A3. Terminal input is unbounded

A push subscription over stdin can outrun Elm. Design 01 names a possible future
byte cap but does not choose pull/acknowledgement semantics, define the Node
stream pause point, or state what happens to a chunk that crosses the cap.

Choose one exact contract:

1. bounded pull/acknowledgement with one outstanding delivery; or
2. a hard queue bound and an explicit overflow/loss event.

Specify byte accounting before UTF-8 decoding, maximum physical chunk handling,
pause/resume, malformed UTF-8, split scalar sequences, EOF with an incomplete
sequence, cancellation/release, and whether any bytes can be delivered after
release acknowledgement.

## A4. Raw-mode restoration needs a synchronous backstop

An asynchronous cleanup Task is insufficient. Node's `stdin.setRawMode` is
synchronous, process `exit` handlers are synchronous, and a user can otherwise
be left with a broken terminal after normal exit or a signal.

The package needs an idempotent synchronous cooked-mode restoration primitive
owned by the live lease and invoked:

- on ordinary release before acknowledgement;
- by a process-exit backstop;
- before signal disposition/delivery; and
- on manager teardown where the runtime permits it.

State the limits honestly: SIGKILL, runtime crash, kernel crash, and power loss
cannot run cleanup. Do not promise restoration there.

## A5. “Terminal” conflates stdin authority with stdout interactivity

Raw mode belongs to stdin. Resize dimensions belong to an interactive stdout.
Console writes work for pipes and are not a terminal lease operation. Either
name the capability for the resources it owns (`stdin`/raw/resize), or require
and document an interactive stdout gate before calling it an interactive
terminal lease. Never return made-up 80×24 dimensions.

## A6. Signal disposition is underspecified

Installing a SIGINT/SIGTERM listener changes Node's default disposition. Removing
the last listener restores the default only if the package really removes its
physical listener. Callback races can otherwise deliver an old signal through
new taggers.

Specify zero-to-one and one-to-zero listener transitions, generation checks,
raw-mode restoration ordering, behavior with zero subscribers, and how default
OS disposition is preserved. A signal observer is not passive on Node.

## A7. Console bounds and failure ownership are incomplete

The design gives a pending-byte idea but no exact per-write UTF-8 bound, pending
bound, queue topology, or behavior when a string's UTF-8 byte width differs from
Elm `String.length`. It also ignores stream `error` events, especially EPIPE,
and does not explain cancellation after physical dispatch.

Specify separately for stdout and stderr:

- maximum UTF-8 bytes per write;
- maximum pending UTF-8 bytes;
- O(1) queue operations;
- one physical `error` listener per endpoint;
- callback error versus stream error classification;
- whether an accepted write may be canceled;
- what success acknowledges; and
- how all pending writes settle after closure/EPIPE.

No arbitrary Node exception message may cross the boundary.

## A8. Clock and timer design precedes the consumer audit

A fixed-interval `every` subscription can drift if implemented as
`setInterval`, can replay or miss assumptions after event-loop stalls, and may
accidentally create one timer per session. Design 01 proposes it before auditing
what harness `Tick` actually means.

Audit all `Tick`, `nowMs`, and `wallMs` consumers. Separate:

- wall timestamps for cron/metadata;
- monotonic elapsed time for waits, idle eviction, input ambiguity, animation,
  and deadlines; and
- repaint/wakeup cadence.

Use target-based scheduling (`nextTarget += interval`) with coalescing rather
than callback-count time. Define delayed-fire behavior and offer elapsed/deadline
helpers so applications do not reconstruct unsafe arithmetic. The harness must
own one subscription in the server TEA loop, not one timer per session.

## A9. Entropy and validated-name bounds are incomplete

Specify exact bounds in UTF-8 bytes or ASCII characters for environment names,
argument/executable snapshots if bounded claims are made, entropy byte counts,
and hex output. Reject NUL and `=` in environment names, but also cap name count
and total name bytes crossing the kernel boundary. Define duplicate-name
behavior. `hex` must prove output-size arithmetic cannot exceed package limits.

## A10. UTF-8 behavior is not executable

“Streaming UTF-8 decoder” is not a contract. State whether malformed bytes are
replaced or fail, whether prior valid text may already have been delivered, how
an incomplete final sequence at EOF settles, and whether Elm strings containing
lone UTF-16 surrogates are accepted for console writes. Debug and optimized
fixtures must exercise every byte partition of representative multi-byte input.

## A11. Scale and state models are too weak

Require executable state models—not prose tables—for terminal lease/input,
console queue/error, signal listener generations, and target timer coalescing.
Run generated traces through both the pure model and production boundary.

At minimum, prove behavior with 200 simultaneous subscribers for each shared
subscription kind and with bounded pending console/input load. Measure physical
listener/timer counts and assert they stay constant where the design claims
sharing. Every process and local fixture needs a hard timeout.

## A12. Harness integration authority remains ambiguous

The revision needs one matrix naming the production authority before, during,
and after each cutover for:

- wall/monotonic facts and Tick wakeups;
- terminal acquisition/raw/input/resize;
- stdout/stderr;
- signals;
- environment selection;
- secure entropy; and
- one-shot process exit versus daemon session close.

Differential dual execution is test-only. After each selected cutover, delete the
old production authority for that mechanism. Keep the daemon host exit backstop
until a real non-public authority boundary exists; package convention is not a
replacement.

## A13. Process title has not earned v1 scope

No first harness milestone consumer was shown. Defer process-title mutation
rather than widening the state/error surface speculatively. A broad coherent v1
means broadly useful, not “bind every nearby `process` property.”

## Required revision

Before implementation, revision A must:

1. omit standalone exit from v1 or narrow all claims to cooperative convention;
2. define a compiler-legal Task/Cmd/Sub topology and total compiling API;
3. choose bounded input delivery and exact UTF-8/EOF/overflow behavior;
4. specify synchronous idempotent cooked restoration and signal ordering;
5. gate the terminal lease on real stdin/stdout interactivity;
6. define signal default-disposition generations;
7. set console per-write/pending UTF-8 bounds and EPIPE/error/cancellation rules;
8. redesign timers as target-based coalescing after auditing every Tick consumer;
9. bound entropy and selected environment names/counts;
10. require executable generated models, debug/optimize parity, 200-subscriber
    scale, provenance, artifact gates, and bounded processes;
11. provide a harness integration authority matrix; and
12. defer process title unless a real v1 consumer appears.

Until revision A survives the second independent review, production source
implementation remains rejected.
