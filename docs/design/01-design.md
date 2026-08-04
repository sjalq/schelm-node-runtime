# 01 — `schelm-node-runtime` v1 design

Status: first-turn design only. Production implementation is forbidden until the two independent adversarial reviews, both revisions, and property-test plan are committed.

## 1. Goal and teachable model

V1 is the small Node foundation that ordinary Elm packages can depend on for:

- immutable process facts and selected environment values;
- wall-clock readings, monotonic elapsed time, and bounded secure entropy;
- acknowledged console writes;
- scoped interactive-terminal input/raw mode/resize ownership; and
- explicit standalone-process termination.

The mental model has three values:

1. **`Runtime`** is a snapshot/read handle for process facts and harmlessly composable runtime services.
2. **`Terminal`** is an exclusive lease on an interactive terminal; `Nothing` means the process is headless or the terminal is already leased.
3. **`Standalone`** is explicit authority to terminate this Node process. A daemon does not create or pass one to session code.

```text
bootstrap
  ├─ Runtime (shared cooperative handle)
  ├─ acquireTerminal Runtime ──> NotInteractive | Busy | Acquired Terminal
  └─ standalone Runtime ───────> Standalone       (only standalone composition root)

Terminal: Acquired ── release ──> absent
Standalone: Running ── exit code ──> OS process terminates (no Elm settlement)
Daemon session: Open ── close code ──> SessionClosed (ordinary Elm policy; process lives)
```

This can be taught without explaining Node, ports, file descriptors, or libuv.

## 2. Scope and non-goals

### Coherent broad v1

V1 includes process identity facts, selected environment lookup, both clock kinds, secure bytes, console output, signals, interactive terminal acquisition, UTF-8 input chunks, resize, raw mode, process title, release, and standalone exit-code/exit operations. These mechanisms belong together because they are Node-process-global runtime resources and lifecycle facts.

### Non-goals

V1 does not include filesystem/path operations, child processes, HTTP, sockets, daemon liveness files, argument parsing, dotenv loading, secret classification, credential scrubbing, retries, logging policy, terminal escape-screen/mouse recipes, line editing, ANSI rendering, session lifecycle, session exit codes, upgrade/re-exec, process supervisors, deterministic pseudo-random generation, locale/time-zone conversion, or browser support.

`schelm-node-runtime` does not replace `elm/time` or `elm/random`. It supplies Node wall/monotonic facts and cryptographic entropy. Deterministic application simulations continue to use `elm/random`.

## 3. Proposed modules and public API

Names may be refined during review, but authority and lifecycle boundaries may not collapse.

### 3.1 Runtime facts and environment

```elm
module Schelm.Node.Runtime exposing
    ( Runtime, initialize, RuntimeError, RuntimeOperation(..), runtimeErrorOperation
    , ProcessInfo, OperatingSystem(..), Architecture(..)
    , processInfo
    , EnvironmentName, environmentName, NameError(..)
    , environment
    , ProcessTitle, processTitle, TitleError(..), setProcessTitle
    )

type Runtime                         -- opaque cooperative runtime handle
initialize : List EnvironmentName -> Task Never Runtime

type RuntimeError                    -- opaque, inspected with accessors
type RuntimeOperation
    = SetProcessTitle
    | AcquireTerminal

runtimeErrorOperation : RuntimeError -> RuntimeOperation

type alias ProcessInfo =
    { operatingSystem : OperatingSystem
    , architecture : Architecture
    , processId : Int
    , arguments : List String
    , executable : String
    }

type OperatingSystem
    = Linux | Darwin | Windows | FreeBsd | OpenBsd | SunOs | Aix
    | OtherOperatingSystem String

type Architecture
    = X64 | Arm64 | Arm | Ia32 | Mips | MipsEl | Ppc | Ppc64 | S390 | S390x
    | OtherArchitecture String

processInfo : Runtime -> ProcessInfo

type EnvironmentName                -- non-empty, no NUL or `=`
type NameError = EmptyName | ContainsNul | ContainsEquals
environmentName : String -> Result NameError EnvironmentName
environment : Runtime -> EnvironmentName -> Maybe String

type ProcessTitle                    -- validated UTF-8 text, bounded to 256 bytes
type TitleError = EmptyTitle | TitleTooLong | ContainsControlCharacter
processTitle : String -> Result TitleError ProcessTitle
setProcessTitle : Runtime -> ProcessTitle -> Task RuntimeError ()
```

`initialize requestedNames` snapshots `process.argv`, platform, architecture, pid, executable, and only the requested environment names exactly once. Names are deduplicated before crossing the kernel boundary. `environment` reads that immutable selected snapshot, so later host mutation cannot create time-dependent application behavior and unrequested values never enter Elm memory. Environment values remain sensitive application data. `EnvironmentName` is a **validated value**, not permission. `Runtime` is a **cooperative token**, not a security capability: any linked Elm module can call `initialize` with other names.

There is deliberately no `environmentVariables : Dict String String`; the composition root must name each variable it intends to read. Secret classification and scrubbing belong to application policy (the harness currently owns them in `tool-env.js`), not this package.

`setProcessTitle` is process-global and therefore requires the explicit runtime handle, but the handle does not enforce organizational policy.

### 3.2 Clocks

```elm
module Schelm.Node.Runtime.Clock exposing
    ( WallTime, MonotonicTime, Duration
    , Interval, IntervalError(..), interval
    , wallNow, monotonicNow, elapsed, every
    , wallMilliseconds, durationMilliseconds
    )

type Interval                         -- integer 10..86400000 ms
type IntervalError = IntervalTooShort | IntervalTooLong
interval : Int -> Result IntervalError Interval

wallNow : Runtime -> Task Never WallTime
monotonicNow : Runtime -> Task Never MonotonicTime
elapsed : MonotonicTime -> MonotonicTime -> Duration
every : Runtime -> Interval -> (WallTime -> msg) -> Sub msg
wallMilliseconds : WallTime -> Int
durationMilliseconds : Duration -> Float
```

`WallTime` and `MonotonicTime` are distinct opaque types, making “use civil time to measure a deadline” unrepresentable. `elapsed start end` saturates at zero if a host violation reports `end < start`; implementation tests flag that condition. Wall milliseconds are Unix epoch milliseconds within Elm's safe integer range. Monotonic duration uses Node `performance.now()` (or an equivalently pinned monotonic source) and is process-local: it is not serializable as a cross-process timestamp.

`every` is a periodic wake-up, not a metronome: missed intervals are not replayed, callback time is sampled when the timer fires, and consumers must calculate elapsed time rather than count ticks. The effect manager owns one Node timer per distinct live `Interval`, fans each firing to current taggers, and removes it at zero taggers. No clock promises nanosecond precision, clock synchronization, exact cadence, or progress while the machine is suspended. The API promises only that monotonic readings from one process are suitable for elapsed durations under the supported Node platform preconditions.

### 3.3 Secure entropy

```elm
module Schelm.Node.Runtime.Entropy exposing
    ( ByteCount, ByteCountError(..), byteCount
    , Error(..), bytes, hex
    )

type ByteCount                      -- 1..65536
type ByteCountError = NonPositive | TooLarge
byteCount : Int -> Result ByteCountError ByteCount

type Error = EntropyUnavailable
bytes : Runtime -> ByteCount -> Task Error Bytes
hex : Runtime -> ByteCount -> Task Error String
```

Every request is bounded; no unbounded stream exists. The kernel calls Node `crypto.randomBytes`. `hex` is a recipe over `bytes`, not a second entropy authority. This is operating-system entropy and is intentionally not seedable or reproducible. It is suitable for collision-resistant names/tokens only when the application also handles storage/protocol concerns; the package does not call arbitrary output “secure credentials.” Host exceptions become the single stable `EntropyUnavailable` constructor; no exception text crosses the boundary.

### 3.4 Console output

```elm
module Schelm.Node.Runtime.Console exposing
    ( Console, stdout, stderr
    , WriteError(..), write, writeLine
    )

type Console                        -- opaque stdout or stderr endpoint
type WriteError = Closed | BrokenPipe | BackpressureLimit | WriteFailed
stdout : Runtime -> Console
stderr : Runtime -> Console
write : Console -> String -> Task WriteError ()
writeLine : Console -> String -> Task WriteError ()
```

A successful Task means Node invoked the write callback without error; it does **not** mean bytes reached disk, a terminal emulator painted them, or a remote reader consumed them. `writeLine` is exactly `write console (text ++ "\n")` with one bounded allocation. Writes are serialized per console by one manager queue so invocation order equals callback order. Queue work is O(new write bytes) and O(1) state per pending write; the design must define a maximum pending-byte budget before implementation. Exceeding that budget will be an explicit `BackpressureLimit` error or an acquisition failure after review—not unbounded buffering.

Console output does not require an interactive terminal. This keeps pipes and CI useful and avoids fabricating terminal dimensions.

### 3.5 Signals

```elm
module Schelm.Node.Runtime.Signal exposing
    ( Signal(..), onSignal )

type Signal = Interrupt | Terminate
onSignal : Runtime -> (Signal -> msg) -> Sub msg
```

Subscriptions observe SIGINT/SIGTERM after the manager installs one shared listener per signal. Once installed, Node's default signal action is replaced; therefore applications subscribing assume responsibility for eventual cleanup/exit. The package does not invent graceful-shutdown policy. Multiple Elm taggers may observe one physical signal. Listener registration is process-global and manager-owned; stale callbacks after unsubscribe are ignored by generation/ownership state.

`beforeExit` is excluded from v1: it has subtle event-loop re-entry semantics and no harness milestone need. It may be proposed separately with an executable model.

### 3.6 Interactive terminal

```elm
module Schelm.Node.Terminal exposing
    ( Terminal, AcquireResult(..), acquire, release
    , Configuration, Size, ColorSupport(..), configuration
    , RawMode(..), setRawMode
    , InputError(..), onInput, onResize
    )

type Terminal                        -- opaque exclusive live lease

type AcquireResult
    = Acquired Terminal
    | NotInteractive
    | Busy

acquire : Runtime -> Task RuntimeError AcquireResult
release : Terminal -> Task RuntimeError ()

type alias Configuration =
    { size : Size
    , colorSupport : ColorSupport
    }

type alias Size = { columns : Int, rows : Int }
type ColorSupport = NoColor | BasicColor | Color256 | TrueColor
configuration : Terminal -> Configuration

type RawMode = Cooked | Raw
setRawMode : Terminal -> RawMode -> Task TerminalError ()

type InputError = InputClosed | InputFailed
onInput : Terminal -> (Result InputError String -> msg) -> Sub msg
onResize : Terminal -> (Size -> msg) -> Sub msg
```

Acquisition succeeds only when both stdin and stdout are TTYs and dimensions are positive. One package manager owns at most one terminal lease process-wide. `Busy` represents a cooperative ownership collision. A released token cannot be invalidated at Elm's type level while it may still be stored elsewhere, so every operation also checks a kernel registry lease id; use-after-release becomes `Released`, an external checked failure. This is an honest limit of Elm's persistent values.

Input chunks are strings decoded with Node's streaming UTF-8 decoder; split multi-byte sequences must not produce replacement characters. EOF yields one `InputClosed` event then removes the listener. `onResize` deduplicates identical positive sizes. No event is delivered after release settlement; a physical event already observed may have been queued before release, so the transition model distinguishes these boundaries.

`setRawMode Raw` requires an interactive lease. `release` first restores cooked mode if this lease changed it, then detaches input/resize listeners, then removes the registry entry. Restore failure is returned, but cleanup continues best-effort and ownership becomes absent so reacquisition is possible. Abrupt `SIGKILL`, runtime crash, or host power loss cannot be repaired by any package; applications needing stronger visual cleanup should use a supervising process and idempotent terminal recipes.

Escape sequences for alternate screen, mouse tracking, cursor visibility, and repaint remain ordinary Elm recipes over `Console.write`. The kernel does not gain policy for them.

### 3.7 Standalone process termination

```elm
module Schelm.Node.Runtime.Standalone exposing
    ( Standalone, authorize
    , ExitCode, exitCode, ExitCodeError(..)
    , setExitCode, exit
    )

type Standalone                       -- opaque cooperative termination token
authorize : Runtime -> Standalone

type ExitCode                          -- integer 0..255
type ExitCodeError = ExitCodeOutOfRange
exitCode : Int -> Result ExitCodeError ExitCode
setExitCode : Standalone -> ExitCode -> Task Never ()
exit : Standalone -> ExitCode -> Cmd msg
```

`authorize` is intentionally loud. The value is a **cooperative token**, not a security capability; Elm lacks a privileged composition-root mint. `setExitCode` sets Node's eventual exit code but returns. `exit` invokes `process.exit` and never settles. The supported portable range is 0..255 even though Node accepts broader numbers, because shells and operating systems truncate differently.

A daemon composition root **must not pass `Standalone` to session code**. Session closure is ordinary application state:

```elm
-- harness-owned, not package API
type SessionState = Open Session | Closed SessionResult
closeSession : ExitCode -> SessionState -> ( SessionState, Cmd msg )
```

This preserves the harness invariant: one session can close without killing sibling sessions. The package will not expose a generic “scope exit” abstraction whose implementation could ambiguously mean either process death or session closure.

## 4. Authority classification

| Value/rule | Honest class | What it does and does not guarantee |
|---|---|---|
| `Runtime` | cooperative token + immutable snapshot | Makes dependencies explicit; cannot exclude malicious linked Elm code from initializing another one. |
| `EnvironmentName` | validated value | Proves syntax only; does not grant or hide a secret. |
| `Terminal` | cooperative lease backed by checked registry ownership | Prevents accidental concurrent terminal control through this package; external JS can still mutate the terminal. |
| `Standalone` | cooperative token | Makes process-death authority visible in types; not securely unforgeable because `authorize` is public. |
| `ByteCount`, `ExitCode`, `ProcessTitle` | validated values | Carry bounds/proofs, no ambient authority. |
| environment secret allowlist | application policy | Not owned by this package. |
| daemon/session close routing | application policy | Not process exit and not owned by this package. |

No public documentation may call these tokens a sandbox or security capabilities.

## 5. State machines and transition tables

### 5.1 Terminal lease manager

```text
Absent
  -- acquire, not tty ------------------------------> Absent + NotInteractive
  -- acquire, tty ----------------------------------> Live(id, Cooked, listeners=none)
Live(id,...)
  -- acquire ---------------------------------------> Live + Busy
  -- setRawMode dispatched -------------------------> ChangingMode(id, target)
  -- subscribe first kind --------------------------> Live(listener installed)
  -- release ---------------------------------------> Releasing(id)
ChangingMode
  -- callback success ------------------------------> Live(id, target,...)
  -- callback failure ------------------------------> Live(id, prior,...) + error
Releasing
  -- restore/detach acknowledgements or bounded sync failure -> Absent + result
```

| Current | Input | Physical effect | Elm delivery | Next |
|---|---|---|---|---|
| Absent | acquire on TTY | snapshot facts, allocate id | `Acquired token` | Live |
| Live | duplicate acquire | none | `Busy` | Live |
| Live | raw request | `setRawMode(true)` | only after callback | Live Raw / Live Cooked+error |
| Live | first input sub | attach stream decoder/listener | none | Live listening |
| Live listening | bytes | decoder consumes new bytes | one chunk message per decoded chunk | Live listening |
| Live listening | EOF | detach input listener | one `InputClosed` | Live, input closed |
| Live | release | restore cooked, detach listeners | only after cleanup attempt | Absent |
| Absent/new id | stale old callback | none | ignored | unchanged |

Release is idempotent at the physical boundary: a repeated stale release returns `Released` and performs no effect. There is exactly one live registry entry, not independent `isRaw`, `isReleased`, and listener booleans that can disagree.

### 5.2 Subscription ownership

| Tagger count before/after | Action |
|---|---|
| 0 → positive | install exactly one Node listener and retain its cancellation owner |
| positive → positive | replace tagger collection; do not reinstall listener |
| positive → 0 | detach listener and remove owner |
| 0 → 0 | no-op |
| stale callback generation | drop before constructing an app message |

Signal, resize, and input each use this pattern. Fan-out costs O(number of current taggers), never O(history). No accumulator uses end-append or linear dedupe.

### 5.3 Console write

| State | Event | Next/result |
|---|---|---|
| Idle | enqueue within budget | Writing(head), queue tail |
| Writing | enqueue within budget | Writing, append to queue structure in O(1) |
| Writing | Node callback success | settle head success; start next or Idle |
| Writing | classified callback failure | settle head error; continue next unless stream closed |
| Any | pending-byte limit exceeded | reject new write; existing queue unchanged |

Physical write dispatch, callback acknowledgement, scheduler message, and application settlement are separate evidence points in fixture builds.

### 5.4 Standalone versus daemon

| Context | Request | Allowed effect |
|---|---|---|
| standalone owner has `Standalone` | `exit code` | process exits; no Elm completion |
| standalone owner | `setExitCode code` | process continues; natural eventual exit uses code |
| daemon session | close | journal/session state transition; Node process remains alive |
| daemon session lacks `Standalone` | process exit | cannot be expressed through package API it receives |
| malicious linked code calls `authorize` | exit | possible; cooperative model limitation is documented |

## 6. Error ergonomics

Errors live near the operation that can recover from them; there is no giant Node-error union and no arbitrary exception message.

```elm
type RuntimeError
    = UnsupportedRuntime
    | RuntimeFailure RuntimeOperation

type TerminalError
    = Released
    | NotInteractiveTerminal
    | RawModeUnsupported
    | TerminalFailure TerminalOperation

type WriteError
    = Closed
    | BrokenPipe
    | BackpressureLimit
    | WriteFailed
```

Operations are small stable enums (`AcquireTerminal`, `ChangeRawMode`, `ReleaseTerminal`, `SetProcessTitle`) so users can report context without parsing strings. Kernel code maps an allowlist of Node codes (for example EPIPE) to stable constructors; unknown exceptions become the corresponding operation failure. Exception messages/stacks never cross into typed values or logs.

Recovery guidance:

- `NotInteractive`/`NotInteractiveTerminal`: continue headlessly; use console writes, no resize/raw mode.
- `Busy`: reuse the application's existing lease or coordinate ownership.
- `Released`: stop using the stale token and reacquire deliberately.
- `BrokenPipe`/`Closed`: stop writing that endpoint; commonly exit cleanly for Unix pipelines.
- `BackpressureLimit`: reduce producer rate or chunk size; retry only after application-level pacing.
- `EntropyUnavailable`: fail the operation that needs uniqueness; never substitute `Math.random`.
- `RuntimeFailure`/`TerminalFailure`: report the operation enum and choose app-level degradation or shutdown.

## 7. Gren comparison matrix

Source comparison is against bundled `gren-lang/node` 6.1.3 (`Node`, `Terminal`, and kernels), not memory or documentation summaries.

| Concern | Gren 6.1.3 | Proposed Schelm v1 | Reason for divergence |
|---|---|---|---|
| privileged bootstrap | `Init.Task`, environment supplied to program definition | ordinary `initialize : Task Never Runtime` | Elm has no Gren node platform/bootstrap type; authority is explicitly cooperative. |
| environment | whole `Dict String String` | selected `EnvironmentName -> Maybe String` from immutable snapshot | narrower accidental exposure and stable snapshot semantics. |
| argv/platform/arch | in `Environment` / Tasks | immutable `ProcessInfo` | close semantic match, Elm records/lists. |
| stdin/stdout/stderr | Gren `Stream` handles | console write API plus terminal input subscription | Schelm has no general stream package yet; do not invent one inside runtime. |
| terminal init | `Init.Task (Maybe Configuration)` with `Permission` | exclusive `acquire` yielding `Acquired/NotInteractive/Busy` | honest multi-owner lifecycle and no fake privileged permission. |
| terminal color depth | integer | `ColorSupport` algebra | users choose rendering without interpreting Node bit depth. |
| raw mode | `Permission -> Bool -> Task` | live `Terminal -> RawMode -> Task` | lease ties operation to interactive ownership and release cleanup. |
| resize | permission-gated subscription | lease-gated subscription | same broad mechanism, stronger ownership model. |
| input | available through Gren stream | UTF-8 terminal subscription | coherent terminal recipes without broad stream API. |
| process title | terminal permission | runtime validated title | Node process title is process-global, not inherently interactive terminal authority. |
| signals | SIGINT/SIGTERM subscriptions | same two signals | close match; package owns one listener each. |
| empty event loop | subscription | omitted | subtle re-entry semantics and no v1 need. |
| exit/setExitCode | ambient `Cmd`/Task | explicit `Standalone` token | separates process death from daemon session close. |
| clocks | not in examined Node/Terminal public API | wall and monotonic modules | required broad runtime foundation and harness clock seam. |
| secure entropy | not in examined public API | bounded cryptographic bytes | required runtime primitive; explicitly distinct from deterministic random. |
| Node kernel behavior | direct process APIs, listener Tasks | same class of boundary with generated production/fixture separation | Elm compiler/runtime ABI differs; guarantees require Schelm-specific tests. |

“Close to Gren” means preserving the explicit initialization/permission idea where it fits, not copying APIs that Elm cannot make equally truthful.

## 8. Ergonomic recipes

### Headless-safe startup

```elm
init _ =
    Runtime.initialize []
        |> Task.perform RuntimeReady

update (RuntimeReady runtime) model =
    ( { model | runtime = Just runtime }
    , Console.writeLine (Console.stdout runtime) "ready"
        |> Task.attempt WroteReady
    )
```

### Optional terminal UI

```elm
Terminal.acquire runtime
    |> Task.perform TerminalReady

case result of
    Terminal.Acquired terminal ->
        -- store the lease; subscribe to input/resize

    Terminal.NotInteractive ->
        -- keep working as a pipe/service

    Terminal.Busy ->
        -- coordinate with the existing UI owner
```

### Correct deadline measurement

```elm
Clock.monotonicNow runtime
    |> Task.andThen
        (\started ->
            doWork
                |> Task.andThen
                    (\value ->
                        Clock.monotonicNow runtime
                            |> Task.map (\ended -> ( value, Clock.elapsed started ended ))
                    )
        )
```

### Secure temporary suffix (mechanism only)

```elm
Entropy.byteCount 16
    |> Result.map (Entropy.hex runtime)
```

The filesystem package still owns safe path/root/atomic rules; entropy alone does not make a safe temporary-file protocol.

### Standalone CLI exit

```elm
case Standalone.exitCode 2 of
    Ok code ->
        ( model, Standalone.exit standalone code )

    Err _ ->
        ( model, Cmd.none )
```

Daemon session update code never receives `standalone`; it returns a `CloseSession code` application effect instead.

## 9. Complexity and resource budgets

- snapshots: O(number of requested environment names) once at `initialize`; dedupe is O(k log k), and individual lookup is O(log k) in Elm `Dict`;
- wall/monotonic read: O(1); each periodic firing is O(current taggers for that interval), with one timer per distinct live interval;
- entropy: O(requested bytes), maximum 65,536 bytes per call;
- terminal event: O(new chunk bytes + current tagger count), never O(all prior input/events);
- resize/signal: O(current tagger count);
- acquire/release/raw mode: O(1);
- console enqueue/dequeue: O(1) queue operations; write cost O(new text bytes), never O(total output history);
- no hot operation scans sessions, transcript history, prior clock readings, or prior entropy calls.

The console pending-byte cap must be fixed before implementation (proposed 1 MiB per endpoint) and proven under generated load. Terminal input relies on Node stream backpressure only to the extent the effect manager can pause/resume ownership; the final design revision must set an explicit maximum queued input byte count or prove one-event-at-a-time acknowledgement.

At item 1,000/session 200/chunk 10,000, package work depends only on that new operation, current subscribers, and bounded live queue—not accumulated history or other sessions.

## 10. Non-trivial properties and failure injection obligations

The later `06-property-test-plan.md` must make these executable; example tests are insufficient.

1. **Single terminal owner:** generated acquire/release sequences never produce two live ids.
2. **Exactly one terminal transition:** every write/raw/release request settles at most once; `exit` is explicitly non-settling.
3. **No post-release delivery:** after release callback acknowledgement, any stale input/resize callback is dropped.
4. **Listener conservation:** physical listeners equal 0 when tagger count is 0 and exactly 1 when positive, across arbitrary subscription changes.
5. **Raw restore:** if a lease successfully entered raw mode, every normal release trace attempts cooked restore before ownership disappears, even when detach fails.
6. **UTF-8 chunk invariance:** every partition of the same valid byte sequence yields the same decoded text; malformed terminal input follows one documented replacement/failure rule.
7. **Resize validity/dedupe:** only positive changed sizes reach Elm.
8. **Write ordering:** successful callbacks preserve dispatch order per console under partial, delayed, throwing, EPIPE, and close injections.
9. **Queue bound:** generated producers cannot exceed the configured pending-byte cap; rejected writes do not disturb accepted ordering.
10. **Clock separation/model:** elapsed monotonic duration is non-negative and independent of injected wall-clock jumps.
11. **Entropy shape:** for every valid count, result width is exact; invalid counts cannot call kernel; injected crypto errors never fall back to weak randomness.
12. **Environment selection/snapshot:** only requested deduplicated names cross the kernel boundary, and later mutation of injected host env cannot change lookup results.
13. **Timer conservation/cadence:** each distinct live interval owns exactly one physical timer, zero taggers owns none, stale firings are dropped, and delayed callbacks never replay a backlog.
14. **Exit range:** constructor accepts exactly 0..255; OS-observed debug and optimized fixtures exit with representative 0, 1, 7, 130, and 255.
15. **Cmd/Sub map laws:** identity and composition hold for command callbacks and subscription taggers in generated worker fixtures.
16. **Debug/opt differential:** both modes produce equivalent normalized event traces for all bounded scenarios.
17. **Production provenance:** fixture symbols/hooks are mechanically absent from production generated JS and release archive.
18. **Old/new harness differential:** terminal dimensions, input bytes, resize, write acknowledgement, ticks, env selection, and standalone close behavior match accepted harness fixtures before cutover.
19. **Daemon survival:** generated session close sequences never invoke process exit; sibling sessions continue and receive events.

Fixtures need deterministic phase hooks at dispatch, physical effect/callback, scheduler send, release, stale callback, and settlement. Hooks belong in a separate fixture kernel assembled from one canonical machine; production assembly strips them and an artifact gate greps for their absence.

All runtime tests are bounded by explicit wall time and operation counts. Run focused state-machine tests before full suites. Build cold and warm isolated caches with the pinned compiler and Node, in debug and optimize.

## 11. Harness milestone and migration seam

The first harness milestone is intentionally narrower than v1:

1. replace `onTick.send(Date.now())` with one package `Clock.every` subscription at 100 ms in the single server TEA loop; the manager owns one timer for that interval, never one timer per session;
2. replace terminal discovery, raw-mode transition, stdin chunks, stdout/stderr acknowledgement, and resize listener mechanics currently in `elm-pkg-js/terminal.js` for standalone/TUI ownership;
3. expose selected environment reads needed by ordinary Elm bootstrap only after harness policy supplies validated names;
4. route one-shot `ExitWith` through `Standalone.exit`, while daemon `Server.routeIo` continues converting `ForSessionE sid (ExitWith code)` to `CloseSession`; and
5. leave daemon-state paths/liveness, dotenv loading, secret scrubbing, upgrade re-exec, GUI attach terminal ownership, and session policy where they are.

The accepted harness source establishes two invariants that migration must retain:

- `host/serve.js --once` may terminate the process after session close;
- daemon `Server.routeIo` maps `ExitWith` to a session close, and `terminal.js` swallows any bare process-exit port in daemon mode as a backstop.

During differential migration, old JS and package mechanisms may coexist only behind a test-selected boundary. After cutover there is one production authority; the old listener/exit path is removed rather than retained as fallback. GUI `host/attach.js` controls the client's own terminal and is a separate process boundary; migrating it is not required to prove daemon session safety.

## 12. Debug/opt fixtures, artifact gates, and provenance

Implementation must follow accepted package patterns:

- isolated Elm 0.19.2 private overlay;
- compiler authorization commit plus exact compiler-binary hash;
- pinned Node 24.4.1 archive/binary hashes;
- canonical runtime state machine source generating separate production and fixture kernels;
- debug and optimized application fixtures that actually execute;
- bounded runners with OS-observed exit codes;
- generated source hash embedded in kernels;
- artifact gate rejecting fixture markers, observers, injection branches, absolute worktree paths, credentials, and source maps from production output/archive;
- deterministic package archive built twice from clean staging and compared by SHA-256;
- provenance generated from the final commit, including compiler/Node hashes and explicit non-claims about binary reproducibility.

The committed feasibility fixture is not the production canonical machine and must remain under `feasibility/` or be replaced by reviewed fixtures without being imported by exposed production modules.

## 13. MISI, MITI, and DRY summary

### MISI

- wall and monotonic time cannot be confused;
- byte counts, exit codes, env names, and process titles are validated once;
- interactive operations require a live terminal lease;
- standalone process death requires a distinct token not passed to daemon sessions;
- no fake terminal exists in headless mode;
- one registry entry owns terminal lifecycle and each global listener;
- settled/released ownership is absent; stale ids cannot act;
- every entropy request and live queue is bounded.

### MITI

- external JS can still mutate process/terminal state; checked failures remain explicit;
- publicly mintable `Runtime`/`Standalone` values are cooperative, never called security capabilities;
- process death, SIGKILL, OS crash, and power loss cannot guarantee cleanup;
- write callback acknowledgement is not physical display/durability;
- queued-before-release and delivered-after-release are distinguished and tested;
- Node exceptions are mapped at one boundary and cannot smuggle arbitrary strings.

### DRY

- one Elm effect manager owns each lifecycle/listener rule;
- one canonical machine generates production and fixture kernels;
- `hex`, `writeLine`, and ergonomic recipes derive from strict primitives;
- session close remains one harness-owned policy, not duplicated in runtime;
- environment secret rules remain one harness/application policy, not copied into the package;
- no old/new production fallback remains after differential cutover.

## 14. Open decisions for hostile review

1. Should `initialize` permit multiple equivalent `Runtime` snapshots, or should the manager return one process-wide snapshot id?
2. Is a 1 MiB per-console pending-byte cap appropriate, and should over-cap be immediate error or producer suspension?
3. Can terminal input provide one-chunk acknowledgement/backpressure without making the API cumbersome, or must v1 specify a hard queued-byte cap?
4. Should `release` of an already released token succeed idempotently or return `Released` to expose ownership bugs?
5. Does process title belong in broad v1, or should it wait because it has no first harness milestone need?
6. Is `arguments : List String` acceptable for potentially large argv, or should it be `Array String` despite Elm package ergonomics?
7. Should SIGINT/SIGTERM subscriptions be terminal-lease-scoped when raw mode changes default signal behavior, or remain runtime-scoped as proposed?
8. Is public `Standalone.authorize` valuable enough despite being only cooperative, or should standalone authority be injected by a tiny separate bootstrap package/compiler facility?
9. Should wall-time milliseconds use `Int` given Elm/JS safe integer semantics, or expose an opaque value with only string/float conversion?
10. Does `Clock.every` need a hard cap on the number of distinct live intervals to prevent timer fan-out, and if so what broadly useful bound avoids application policy?

These are review questions, not permission to begin implementation.
