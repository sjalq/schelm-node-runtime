# 03 — Design revision A

Status: PM response to independent adversarial review A. This document
**supersedes `01-design.md`** where they differ. **Production implementation remains forbidden** pending independent review B, final revision, and the property-test plan.

## 1. Revision verdict and narrowed v1

Review A is accepted in full. Revision A makes these decisive changes:

1. **Process exit is removed from package v1.** A publicly mintable
   `Standalone` did not establish authority. The harness keeps its current host
   one-shot exit verb and daemon-mode swallow/backstop.
2. **Process title is deferred.** No milestone consumer earns its surface.
3. Four compiler-legal effect managers own console, interactive terminal,
   signals, and target-based tickers. State-free snapshots/clock reads/entropy
   remain direct kernel Tasks.
4. Terminal input is one-piece pull/ack with stdin paused while Elm owns a piece;
   there is no package queue and no silent overflow policy.
5. Raw-mode restoration has one synchronous, idempotent kernel backstop because
   asynchronous Elm cleanup cannot satisfy Node's process-exit boundary.
6. Console text, per-write bytes, pending bytes, environment selection, process
   snapshot, entropy, ticker count, and interval are all explicitly bounded.
7. Timers use target-based coalescing and elapsed/deadline values. Tick consumers
   are classified before migration.

The coherent v1 is now: selected immutable runtime facts, wall/monotonic clocks,
bounded secure entropy, bounded acknowledged stdout/stderr, SIGINT/SIGTERM
subscriptions, one interactive stdin/stdout terminal lease, and bounded
coalescing tickers.

Non-goals now additionally include process exit, process title, before-exit,
generic streams, arbitrary signals, line editing, ANSI policy, and graceful
shutdown policy.

## 2. Exact legal implementation topology

Elm 0.19.2 effect managers receive `Cmd` and/or `Sub`; kernel Tasks do not enter
`onEffects`. Revision A no longer claims otherwise.

| Public module | Compiler form | Public effects | Elm-owned state | Minimal kernel ownership |
|---|---|---|---|---|
| `Schelm.Node.Runtime` | normal module | direct Tasks only | none | immutable snapshot construction |
| `Schelm.Node.Runtime.Clock` | normal module | direct `wallNow`/`monotonicNow` Tasks and pure values | none | one clock read per Task |
| `Schelm.Node.Runtime.Entropy` | normal module | direct bounded Task | none | one crypto request per Task |
| `Schelm.Node.Runtime.Console` | `effect module ... where { command = ConsoleCmd }` | callback `Cmd` | endpoint queues, byte totals, terminal settlements | Node stdout/stderr writes and error-listener cancellation handles |
| `Schelm.Node.Runtime.Signal` | `effect module ... where { subscription = SignalSub }` | `Sub` | current taggers, listener generations | one listener/cancellation handle per live signal |
| `Schelm.Node.Terminal` | `effect module ... where { command = TerminalCmd, subscription = TerminalSub }` | acquisition/control callback `Cmd`, input/resize `Sub` | logical lease, taggers, outstanding input piece, generation | live stdin/stdout lease handle, sync raw restore, decoder, listeners |
| `Schelm.Node.Runtime.Ticker` | `effect module ... where { command = TickerCmd, subscription = TickerSub }` | start/stop callback `Cmd`, tick `Sub` | ≤64 ticker records, targets, taggers, one timer generation | at most one physical timeout/cancel handle |

Each effect module declares and compiles the required `init`, `onEffects`,
`onSelfMsg`, and appropriate `cmdMap`/`subMap`. Public commands are constructed
inside that manager by Elm's special `command` function; public subscriptions by
`subscription`. No normal facade pretends it can inject a kernel Task into a
manager.

Direct Task kernels are state-free: invocation owns one callback and returns a
cancellation function that only abandons Elm delivery. Manager kernels expose narrow Tasks such as `writePhysical`, `attachSignal`, `acquireLease`, `readOnePiece`, and `armTimeout`. `onEffects` never blocks while a long physical operation runs: it validates/enqueues the command, spawns the kernel Task with `Process.spawn`, and routes completion through `Platform.sendToSelf`; manager state retains that `Process.Id`, operation id, and generation. Persistent listener bindings are likewise spawned and canceled with the exact retained process id. `onSelfMsg` alone claims a current completion and calls `Platform.sendToApp`. JavaScript does not choose queue order, subscriber policy, timer coalescing, or error recovery.

### Necessary kernel exception: terminal restoration registry

A synchronous Node `exit` handler cannot round-trip through Elm. The terminal
kernel therefore owns exactly one nullable physical lease record:

```text
Absent | PhysicalLease { id, stdin, stdout, raw, restored, exitHandler }
```

It provides synchronous idempotent `restoreCooked(id)` and `releasePhysical(id)`
verbs. Elm owns whether an operation is logically legal; the kernel record is a
backstop for physical restoration and stale-id rejection. It contains no
application/session policy. This exception is narrower than moving the terminal
state machine into JavaScript.

## 3. Revised total public API

All snippets below are intended to be legal Elm signatures. Every error used in
a callback is exposed as a closed union. Opaque validated values have total
constructors and accessors.

### 3.1 Runtime snapshot and selected environment

```elm
module Schelm.Node.Runtime exposing
    ( Runtime, Selection, SelectionError(..), selection, emptySelection, oneEnvironment
    , EnvironmentName, NameError(..), environmentName, environmentNameString
    , InitError(..), RuntimeField(..), initialize
    , ProcessInfo, OperatingSystem(..), Architecture(..)
    , processInfo, environment
    )

type Runtime

type EnvironmentName
type NameError
    = EmptyEnvironmentName
    | EnvironmentNameContainsNul
    | EnvironmentNameContainsEquals
    | EnvironmentNameTooLong

environmentName : String -> Result NameError EnvironmentName
environmentNameString : EnvironmentName -> String

type Selection
type SelectionError
    = TooManyEnvironmentNames
    | EnvironmentSelectionTooLarge

selection : List EnvironmentName -> Result SelectionError Selection
emptySelection : Selection
oneEnvironment : EnvironmentName -> Selection

type InitError
    = UnsupportedRuntime
    | TooManyArguments
    | ArgumentTooLarge
    | ArgumentsTooLarge
    | ExecutablePathTooLarge
    | EnvironmentValueTooLarge EnvironmentName
    | SelectedEnvironmentTooLarge
    | InvalidHostText RuntimeField

type RuntimeField
    = HostArgument
    | HostExecutable
    | HostEnvironmentValue EnvironmentName

initialize : Selection -> Task InitError Runtime
processInfo : Runtime -> ProcessInfo
environment : Runtime -> EnvironmentName -> Maybe String

type alias ProcessInfo =
    { operatingSystem : OperatingSystem
    , architecture : Architecture
    , processId : Int
    , arguments : Array String
    , executable : String
    }

type OperatingSystem
    = Linux | Darwin | Windows | FreeBsd | OpenBsd | SunOs | Aix
    | OtherOperatingSystem String

type Architecture
    = X64 | Arm64 | Arm | Ia32 | Mips | MipsEl | Ppc | Ppc64 | S390 | S390x
    | OtherArchitecture String
```

Bounds are measured after strict UTF-8 validation:

| Item | Bound |
|---|---:|
| one environment name | 1..256 UTF-8 bytes; no NUL or `=` |
| selected unique names | 128 |
| total selected-name bytes | 16 KiB |
| one selected value | 64 KiB |
| total selected-value bytes | 1 MiB |
| argv count | 1,024 |
| one argument | 64 KiB |
| all arguments | 1 MiB |
| executable string | 4 KiB |

`selection` deduplicates by exact string using a `Set`; first occurrence order is
preserved in the one cold construction pass. Only selected names cross the
kernel snapshot boundary. `initialize` is repeatable and returns equivalent
immutable facts at that instant; `Runtime` remains an honestly cooperative
handle, not security authority.

Unknown platform/architecture strings are bounded to 64 ASCII bytes before
constructing `Other...`; otherwise initialization returns `UnsupportedRuntime`.
Node strings containing unpaired UTF-16 surrogates fail as `InvalidHostText`.

`emptySelection` and `oneEnvironment` are pure recipes over `selection` (with impossible failure removed internally), not second snapshot authorities.

### 3.2 Wall time, monotonic time, elapsed time, and deadlines

```elm
module Schelm.Node.Runtime.Clock exposing
    ( WallTime, MonotonicTime, Duration, Deadline
    , wallNow, monotonicNow
    , elapsed, duration, DurationError(..), durationMilliseconds
    , deadlineAfter, deadlineReached, remaining
    , wallMilliseconds
    )

wallNow : Runtime -> Task Never WallTime
monotonicNow : Runtime -> Task Never MonotonicTime
elapsed : MonotonicTime -> MonotonicTime -> Duration

type Duration
type DurationError = NegativeDuration | DurationTooLarge
duration : Int -> Result DurationError Duration
durationMilliseconds : Duration -> Int

type Deadline
deadlineAfter : MonotonicTime -> Duration -> Deadline
deadlineReached : MonotonicTime -> Deadline -> Bool
remaining : MonotonicTime -> Deadline -> Duration

wallMilliseconds : WallTime -> Int
```

`Duration` is integer milliseconds 0..86,400,000 (24 hours) in v1. `elapsed`
saturates at zero only as a fail-safe; fixture instrumentation records a host
monotonic regression as a test failure. `Deadline` and `MonotonicTime` are
process-local opaque values and have no encoder. Wall time is for persisted
calendar/metadata facts only. Deadlines and elapsed operational time use
monotonic values.

### 3.3 Bounded entropy

```elm
module Schelm.Node.Runtime.Entropy exposing
    ( ByteCount, CountError(..), byteCount, byteCountInt
    , Error(..), bytes, hex
    )

type ByteCount
type CountError = NonPositiveCount | CountTooLarge
byteCount : Int -> Result CountError ByteCount
byteCountInt : ByteCount -> Int

type Error = EntropyUnavailable
bytes : Runtime -> ByteCount -> Task Error Bytes
hex : Runtime -> ByteCount -> Task Error String
```

`ByteCount` is 1..65,536. `bytes` returns exactly that width or fails. `hex`
returns exactly `2 * count` lowercase ASCII characters, maximum 131,072 bytes;
it derives from the same bytes primitive and checks width in debug/fixture
assembly. No fallback uses `Math.random`.

### 3.4 Bounded console commands

```elm
module Schelm.Node.Runtime.Console exposing
    ( Console, stdout, stderr
    , Text, TextError(..), text, line, textString, textBytes
    , WriteError(..), write
    )

type Console
type Text

type TextError
    = InvalidText
    | WriteTooLarge

text : String -> Result TextError Text
line : Text -> Result TextError Text
textString : Text -> String
textBytes : Text -> Int

stdout : Runtime -> Console
stderr : Runtime -> Console

type WriteError
    = BackpressureLimit
    | BrokenPipe
    | Closed
    | InvalidHostState
    | WriteFailed

write : Console -> Text -> (Result WriteError () -> msg) -> Cmd msg
```

`Text` contains valid Unicode scalar text with strict UTF-8 width 0..65,536 bytes. Kernel code revalidates UTF-16 well-formedness and byte width before physical dispatch so an optimized ABI accident cannot bypass the bound. `line value` appends one LF only when `textBytes value <= 65,535`; otherwise it returns `WriteTooLarge`. A higher helper is simply `line value |> Result.map (\withLf -> write console withLf callback)`. There is one write mechanism.

Per endpoint:

- maximum one accepted write: 65,536 UTF-8 bytes;
- maximum pending bytes including the physically in-flight write: 1,048,576;
- FIFO uses a two-list queue (amortized O(1)), never end-appending to an accumulated list;
- stdout and stderr have independent queues/budgets;
- immediately before the first package write to an endpoint, one physical Node `error` listener is installed and then retained for that endpoint's package lifetime, regardless of 200 callers; this deliberately owns package-write errors and prevents a late post-callback EPIPE from becoming unhandled; writes performed outside this package remain outside its guarantee;
- success means the Node write callback acknowledged without error—nothing
  stronger;
- accepted writes cannot be canceled through public API because physical writes
  are generally not retractable;
- killing the Elm process waiting for a callback abandons that consumer but does
  not undo bytes; the manager still removes the queue entry on callback;
- callback EPIPE or endpoint `error` EPIPE transitions endpoint to `Broken`,
  settles in-flight and every queued callback exactly once with `BrokenPipe`,
  zeroes pending bytes, and rejects later writes with `BrokenPipe`;
- close settles all pending as `Closed`;
- any late callback carries endpoint generation + write id and is ignored;
- unknown exceptions become `WriteFailed`/`InvalidHostState`; no message or stack
  crosses the boundary.

The manager command contains the Elm callback. `cmdMap` composes it; no Task API
misrepresents manager ownership.

### 3.5 Signal subscriptions

```elm
module Schelm.Node.Runtime.Signal exposing
    ( Signal(..), onSignal )

type Signal = Interrupt | Terminate
onSignal : Runtime -> Signal -> msg -> Sub msg
```

Each signal has one manager record:

```text
DefaultDisposition
  -- 0 -> positive taggers --> Listening(generation, taggers, physical owner)
Listening
  -- positive -> positive --> same generation/owner, replace taggers
  -- positive -> 0 --------> detach exact owner -> DefaultDisposition
```

The physical callback sends `(signal, generation)` to the manager. A mismatch or
zero taggers drops it. With zero subscribers the package has no listener, so
Node/OS default disposition remains intact. With subscribers, the application
has deliberately replaced default disposition and must decide whether to exit.

If an interactive terminal lease is raw when SIGINT/SIGTERM arrives, the kernel
synchronously calls idempotent `restoreCooked(leaseId)` **before** queueing the
signal self-message; Terminal manager state is notified and becomes logically
Cooked before another raw request can succeed. A signal can race unsubscribe:
only a callback with the still-live generation can fan out. Fan-out to 200
taggers uses cons/reverse or `Array`, never end-append.

### 3.6 Interactive terminal lease and one-piece input

```elm
module Schelm.Node.Terminal exposing
    ( Terminal, Configuration, Size, ColorSupport(..)
    , AcquireError(..), acquire, configuration
    , RawMode(..), ControlError(..), setRawMode, release
    , Input(..), InputPiece, inputText, inputBytes, inputHadMalformedUtf8
    , onInput, acknowledge, stopInput
    , onResize
    )

type Terminal

type alias Configuration =
    { size : Size
    , colorSupport : ColorSupport
    }

type alias Size = { columns : Int, rows : Int }
type ColorSupport = NoColor | BasicColor | Color256 | TrueColor

type AcquireError
    = NotInteractive
    | Busy
    | AcquireFailed

acquire : Runtime -> (Result AcquireError Terminal -> msg) -> Cmd msg
configuration : Terminal -> Configuration

type RawMode = Cooked | Raw
type ControlError
    = Released
    | RawModeUnsupported
    | ControlFailed

setRawMode : Terminal -> RawMode -> (Result ControlError () -> msg) -> Cmd msg
release : Terminal -> (Result ControlError () -> msg) -> Cmd msg

type Input
    = InputPieceReady InputPiece
    | InputEnded { hadMalformedUtf8 : Bool }
    | InputFailed

type InputPiece
inputText : InputPiece -> String
inputBytes : InputPiece -> Int
inputHadMalformedUtf8 : InputPiece -> Bool

onInput : Terminal -> (Input -> msg) -> Sub msg
acknowledge : Terminal -> InputPiece -> Cmd msg
stopInput : Terminal -> InputPiece -> Cmd msg
onResize : Terminal -> (Size -> msg) -> Sub msg
```

The lease is called **interactive terminal** only because acquisition requires:

- `stdin.isTTY == true` (input/raw authority);
- `stdout.isTTY == true` (resize/display dimensions);
- `stdin.setRawMode` present; and
- positive integer stdout columns/rows.

Otherwise acquisition reports `NotInteractive`; it never fabricates 80×24.
Console output remains independent and works through pipes.

There is one physical lease process-wide. `release` is physically idempotent and
logically idempotent: the first call performs cleanup; duplicate/reordered calls
join the same release acknowledgement; calls after settled release report
`Released`. `setRawMode` is serialized with release.

#### Input pull/ack contract

When there is at least one `onInput` tagger and no outstanding piece:

1. kernel uses readable mode and requests at most 16,384 bytes;
2. immediately after obtaining bytes it pauses stdin before scheduling Elm;
3. one `InputPiece` with lease id + monotonically increasing piece id is stored;
4. manager fans the same opaque piece to current taggers (up to 200);
5. only `acknowledge terminal exactPiece` consumes it and permits the next read;
6. `stopInput` consumes it, keeps stdin paused, and detaches input ownership.

There is never more than one package-retained 16 KiB physical piece and one Elm
piece. Node/OS may have its own documented stream/TTY buffer while paused; the
package does not claim to prevent external terminal-driver loss under an
indefinitely stalled application. It neither silently drops nor allocates an
unbounded package queue. Wrong/stale acknowledgements are no-ops.

Multiple subscribers all receive the piece, but acknowledgement is lease-wide:
applications needing independent consumers must nominate one owner and fan out
ordinary Elm data. This avoids N acknowledgements controlling one stdin stream.
The API documentation marks multiple subscribers as observation, not multiple
pull owners.

UTF-8 uses one streaming decoder per lease with replacement semantics:

- valid scalars split across physical reads are reconstructed;
- malformed byte sequences produce U+FFFD and set `hadMalformedUtf8 = True`;
- valid text before a malformed sequence may be delivered in the same piece;
- at EOF, an incomplete sequence produces one final replacement-marked piece;
  after that piece is acknowledged, exactly one `InputEnded` is delivered;
- clean EOF with no bytes delivers `InputEnded { hadMalformedUtf8 = False }`;
- EOF is terminal for input and removes the listener/read owner;
- after release acknowledgement, no input/resize message can be constructed;
  stale generation callbacks are dropped.

Resize emits only changed positive integer sizes, updates the stored
configuration before fan-out, and uses one stdout listener for up to 200 taggers.

#### Synchronous cooked restoration

The physical lease stores whether this package successfully set raw mode.
`restoreCooked(id)` performs:

```text
if live id and raw and not restored:
    mark restoration attempted
    call stdin.setRawMode(false) synchronously
    mark raw false on success; retain failure fact on throw
else:
    no-op
```

It is called before ordinary release detaches listeners and before release
callback; from the kernel's synchronous process `exit` handler; before a
subscribed SIGINT/SIGTERM is queued; and from manager binding cancellation. The
exit handler performs no async work and writes no logs. Repeated calls are safe.
Release continues detach/absence even if restore throws, and reports
`ControlFailed`. SIGKILL, abort/native crash, JS runtime corruption, and power
loss remain outside the guarantee.

### 3.7 Target-based ticker manager

```elm
module Schelm.Node.Runtime.Ticker exposing
    ( Interval, IntervalError(..), interval
    , Ticker, StartError(..), start, stop
    , Tick, tickWallTime, tickMonotonicTime, tickElapsed, skippedIntervals
    , onTick
    )

type Interval
type IntervalError = IntervalTooShort | IntervalTooLong
interval : Int -> Result IntervalError Interval

type Ticker
type StartError = TooManyTickers | TickerStartFailed
start : Runtime -> Interval -> (Result StartError Ticker -> msg) -> Cmd msg
stop : Ticker -> Cmd msg

type Tick
tickWallTime : Tick -> Clock.WallTime
tickMonotonicTime : Tick -> Clock.MonotonicTime
tickElapsed : Tick -> Clock.Duration
skippedIntervals : Tick -> Int
onTick : Ticker -> (Tick -> msg) -> Sub msg
```

Interval is 10..86,400,000 integer ms. At most 64 live tickers exist. Any number
of subscriptions may share one ticker; 200 taggers still use one logical ticker.
The manager owns **at most one physical `setTimeout` total**, armed for the
earliest ticker target.

For each ticker:

```text
start at monotonic now N:
    previousActual = N
    target = N + interval

physical wake at actual A for all target <= A:
    emit exactly one Tick per due ticker
    elapsed = A - previousActual
    skipped = floor((A - target) / interval), minimum 0
    nextTarget = target + (skipped + 1) * interval
    previousActual = A
    re-arm one timeout for global earliest nextTarget
```

No delayed callback replays a backlog. Scheduling is target-based, so callback
runtime does not accumulate drift by setting `next = actual + interval`.
Stopping/removing the earliest ticker cancels/re-arms the one physical owner.
Physical callbacks include a timer generation; stale wakes are ignored.

Starting/stopping is a manager command because limits and ownership are manager
state. `onTick` is a manager subscription. Clock reads used to form `Tick` are
kernel facts sampled once at the physical wake.

## 4. Audit of current harness Tick consumers

The accepted harness uses one host `Date.now()` interval every 100 ms, broadcasts
the resulting `Tick` to every live session, and currently increments each
session's approximate `model.nowMs` by a fixed 100. Audit results:

| Consumer | Current clock/use | Correct revised source |
|---|---|---|
| cron next-fire, missed-fire grace, scheduled/started/completed timestamps | server `nowMs` from host epoch | `Tick.wallTime` |
| session metadata, child id wall component, observations, port-link probe timestamps | `wallMs`/server epoch | `Tick.wallTime` |
| HostJob waiter timeout | approximate callback count `model.nowMs += 100` | monotonic `Deadline` / `tickMonotonicTime` |
| embed call timeout | approximate callback count | monotonic `Deadline` |
| idle eviction | server epoch fallback/session wall | monotonic idle-start + deadline while process lives; wall only for persisted display |
| stale ESC/CSI flush | two Tick counts | monotonic elapsed threshold (~200 ms), not count |
| dice animation/frame/redraw | Tick wake count/frame | ticker wake; visual frame may coalesce |
| streaming spinner/repaint | Tick wake | ticker wake; delayed wakes never replay |
| nonce/id mixing in media/child/exec | approximate counter | dedicated monotonically increasing sequence plus wall fact; clock is not randomness |

Migration therefore cannot mechanically replace `Date.now()` while preserving
`model.nowMs += 100`. The integration branch first introduces typed
`WallTime`/`MonotonicTime`/`Deadline` ordinary Elm fields and converts consumers
by row above. One server-owned 100 ms `Ticker` subscription is then broadcast as
a typed application Tick. Sessions do not start tickers.

The hot-path cost remains O(live sessions) because broadcast already has that
cost; the package adds no per-session timer and no conversation/history scan.
Idle server work keeps existing cheap early exits. Long event-loop stalls
advance deadline truth by actual monotonic elapsed time and produce one repaint,
not hundreds of catch-up messages.

## 5. Executable transition models

Implementation must place pure executable models in ordinary Elm modules used by
both property tests and effect-manager decisions. A toy model with different
ownership is forbidden.

### 5.1 Console model

```text
Endpoint = Open { generation, queue, pendingBytes, physical }
         | Broken generation
         | Closed generation
Physical = Idle | Writing writeId byteCount
```

Transitions cover enqueue/reject, dispatch, callback success/error, stream
error, close, stale callback, and consumer abandonment. Invariants: pending
bytes equals physical + queue sum; never exceeds 1 MiB; each accepted write id
settles at most once; queue order is FIFO.

### 5.2 Terminal/input model

```text
Terminal = Absent
         | Live { id, mode, input, resizeGeneration }
         | Releasing { id, restoreResult, pendingJoiners }
Input = NoSubscribers | PausedReady | Reading | Outstanding pieceId
      | FinalPiece pieceId | Ended | Failed
```

Transitions cover acquisition gates, duplicate acquire, tagger changes, read,
malformed decode, EOF/final-piece acknowledgement, normal acknowledgement,
stop, raw change, signal restore, release join, stale callback, and restore
failure.

### 5.3 Signal model

```text
SignalSlot = DefaultDisposition | Listening generation taggerCount
```

Generated tagger counts 0..200 and callbacks from old/current generations prove
listener conservation and stale drop.

### 5.4 Ticker model

```text
TickerState = Dict TickerId { interval, target, previousActual, taggerCount }
PhysicalTimer = Absent | Armed generation earliestTarget
```

Generated starts/stops, arbitrary monotonic jumps, simultaneous targets, stale
wakes, and 200 taggers compare model emissions and re-arm decisions against the
production manager boundary.

## 6. Scale, boundedness, and executable gates

Blocking gates now include:

1. 200 signal subscribers per signal with exactly one physical listener;
2. 200 resize subscribers with exactly one listener;
3. 200 input observers receiving one shared piece, with exactly one physical
   read and no next read before the exact acknowledgement;
4. 200 ticker subscribers sharing one ticker and one physical timeout;
5. 64 live tickers with one physical timeout, then deterministic
   `TooManyTickers` for ticker 65;
6. console writes that fill exactly 1 MiB pending, rejection of the next byte,
   delayed callbacks, callback EPIPE, stream EPIPE, close, stale callback, and
   abandonment;
7. every partition of representative 1–4-byte UTF-8 scalars, malformed leading/
   continuation bytes, overlong encodings, surrogate encodings, and incomplete
   EOF;
8. raw restore on release, process exit fixture, SIGINT, SIGTERM, duplicate
   cleanup, and injected `setRawMode(false)` throw;
9. target ticker jumps of 0, one interval, many intervals, and simultaneous due
   targets with no replay storm;
10. selected-name duplicate/count/byte boundaries and host value/snapshot
    boundaries;
11. entropy counts 0, 1, 65,536, 65,537, injected failure, and exact hex width;
12. Cmd/Sub map identity and composition for all four managers;
13. debug and optimized real application execution with normalized differential
    traces;
14. pure model versus production boundary generated traces with fixed seeds and
    replay output;
15. old-host/new-package differential fixtures for each selected harness slice;
16. hard per-process timeout, maximum generated command count, and bounded
    aggregate output;
17. cold/warm isolated compiler cache, pinned compiler/Node hashes, deterministic
    archive, and final-commit provenance; and
18. artifact grep proving fixture hooks/observers, absolute paths, credentials,
    and source maps are absent from production artifacts.

Fixture hooks mark physical dispatch, physical callback, error event, pause,
read, scheduler send, Elm delivery acknowledgement, restoration, detach,
generation drop, timer target/re-arm, and settlement. One canonical transition
source feeds production and fixture wrappers; fixture hooks are mechanically
stripped from production assembly.

## 7. Integration authority matrix

“Package” below means the reviewed implementation, not the feasibility fixture.
Dual execution is allowed only in differential tests.

| Mechanism | Before | Differential test | After selected cutover |
|---|---|---|---|
| wall fact + 100 ms wake | `host/serve.js startOnTick` + `Ports.onTick` | old host trace compared with one package Ticker trace | package Ticker is sole runtime timer/wall source; old `startOnTick` path removed for migrated server |
| monotonic waits/deadlines | fixed `model.nowMs += 100` | old count behavior compared for no-stall traces; stall fixtures prove intentional difference | typed package monotonic Tick/deadlines; approximate counter removed |
| one-shot standalone process exit | host `terminal.js`/`serve.js` | unchanged host tests | **host remains authority in v1**; package exposes no exit |
| daemon session close | Elm `Server.routeIo` -> `CloseSession`; host daemon swallow backstop | daemon survival test | same Elm authority and host backstop remain |
| stdout/stderr | `elm-pkg-js/terminal.js` ports | byte/callback/error differential fixture | Console manager sole migrated Elm-worker authority; old subscriptions removed for that app |
| interactive acquire/raw/input/resize | `terminal.js` setup/listeners/ports | old/new TTY PTY fixture | Terminal manager sole worker authority; old terminal listeners removed for migrated mode |
| attach client terminal | `host/attach.js` | out of first slice | unchanged separate client-process authority |
| SIGINT/SIGTERM | `terminal.js` host handler/default Node behavior | PTY/subprocess signal fixture | Signal + Terminal restoration own migrated worker listeners; host duplicate handler removed only in that mode |
| selected environment | host bootstrap/flags and `tool-env.js` policy | selected values compared | package may own selected fact read; host still owns dotenv loading and secret/scrub policy |
| secure entropy | scattered Node crypto callers | package fixture only until one concrete consumer selected | no cutover claim; existing subsystem callers remain until individually migrated |
| daemon state/env paths | `daemon-state.js` | none | unchanged host facts/policy |

The daemon host exit swallow/backstop remains because package v1 intentionally
provides no process-exit authority and because a bare legacy port must never kill
siblings. No design text claims types alone secure linked malicious code.

## 8. Complexity budgets

- runtime initialization: O(selected names log names + selected/argv UTF-8 bytes)
  once, all bounded;
- wall/monotonic read and entropy bookkeeping: O(1) plus O(requested entropy
  bytes), bounded 64 KiB;
- console enqueue/dequeue: amortized O(1), encoding O(new text bytes), live state
  ≤1 MiB per endpoint;
- signal/resize/input/ticker fan-out: O(current taggers), explicitly tested at
  200; no history traversal;
- input: O(new physical bytes), ≤16 KiB retained package piece;
- terminal acquire/control/release: O(1);
- ticker start/stop/re-arm: with ≤64 tickers, a bounded scan is O(64), never
  O(conversation/sessions/history); physical timers ≤1;
- server Tick migration: one physical wake then existing O(live sessions)
  broadcast with cheap idle exits.

Fold/recursive accumulators must cons then reverse (or use `Array`), never append at the end. Accumulator dedupe must use a `Set`, never a linear list scan. Subscriber dedupe is identity-free because Elm functions cannot be compared—each active `Sub` occurrence is a tagger by definition.

## 9. Error and recovery ergonomics

Errors are operation-local closed unions. No raw code/message/stack is public.
Common recovery remains short:

```elm
case result of
    Err Terminal.NotInteractive ->
        -- continue headlessly with Console

    Err Console.BrokenPipe ->
        -- stop producing output; app decides whether to close

    Err Ticker.TooManyTickers ->
        -- share an existing ticker

    Err Runtime.EnvironmentValueTooLarge name ->
        -- reject startup configuration naming only the validated key
```

Input malformed UTF-8 is data-with-a-fact (`hadMalformedUtf8`), not an exception
that discards already valid bytes. EOF is a distinct terminal event. Raw restore
failure is `ControlFailed`; release still removes ownership to keep recovery
possible. Entropy failure never suggests weak fallback.

## 10. Ergonomic recipes over the strict core

### Initialize with selected environment

```elm
case Runtime.environmentName "NO_COLOR" of
    Ok noColor ->
        case Runtime.selection [ noColor ] of
            Ok wanted ->
                Runtime.initialize wanted |> Task.attempt RuntimeReady

            Err selectionError ->
                -- configuration bug

    Err nameError ->
        -- constant/configuration bug
```

Application helper modules may validate known constant names once. There is no
ambient whole-environment helper.

### Headless-safe output

```elm
case Console.text "ready\n" of
    Ok output ->
        Console.write (Console.stdout runtime) output Wrote

    Err _ ->
        Cmd.none
```

### Interactive input owner

```elm
Terminal.acquire runtime TerminalAcquired

subscriptions model =
    case model.terminal of
        Just terminal ->
            Terminal.onInput terminal InputArrived

        Nothing ->
            Sub.none

update (InputArrived (Terminal.InputPieceReady piece)) model =
    ( consume (Terminal.inputText piece) model
    , Terminal.acknowledge terminal piece
    )
```

### Shared ticker

```elm
Ticker.start runtime interval TickerStarted

subscriptions model =
    Maybe.map (\ticker -> Ticker.onTick ticker Woke) model.ticker
        |> Maybe.withDefault Sub.none

update (Woke tick) model =
    if Clock.deadlineReached (Ticker.tickMonotonicTime tick) model.deadline then
        finish model
    else
        repaintOnce model
```

These recipes add no second mechanism or authority.

## 11. Closed decisions and remaining review questions

Closed by revision A:

- no process exit or process title in package v1;
- four legal effect managers; direct Tasks are state-free;
- one-piece 16 KiB input pull/ack, explicit replacement-marked UTF-8;
- real stdin+stdout interactive gate;
- synchronous idempotent cooked restoration backstop;
- signal generations and true zero-subscriber default disposition;
- 64 KiB per console write, 1 MiB pending per endpoint, no public cancellation;
- target-based coalescing ticker, ≤64 logical tickers, one physical timeout;
- monotonic operational deadlines versus wall persisted facts;
- selected environment and entropy bounds;
- executable production-owned models and 200-subscriber gates; and
- explicit integration authority, retaining daemon host exit backstop.

Questions for independent review B:

1. Should `InputPiece` fan out to multiple observers when only one owner can
   acknowledge, or should the manager allow exactly one input tagger and report
   `Busy` through a prior input-session acquisition?
2. Is replacement-marked UTF-8 preferable to terminating input on malformed
   bytes for terminal key protocols?
3. Should console endpoint error listeners be installed lazily on first write
   and retained for process lifetime, or attached/detached with nonempty queues?
4. Is 64 logical tickers/one physical timer a good broadly useful bound, or
   should v1 expose only one shared scheduler obtained at initialization?
5. Does synchronous raw restore before **subscribed** SIGINT/SIGTERM surprise an
   application that intended to remain raw after handling the signal, and is an
   explicit re-enable recipe sufficient?
6. Should repeated settled `release` report `Released` or succeed to maximize
   cleanup idempotence at the public level?
7. Is a 24-hour maximum `Duration` too narrow for broadly useful monotonic idle
   deadlines, even though v1 tickers need no longer interval?
8. Must runtime initialization reject oversize argv/env facts, or may it omit
   unrequested process arguments to keep selected environment initialization
   usable under an unusual launcher?

No answer authorizes production implementation before the remaining process
gates.
