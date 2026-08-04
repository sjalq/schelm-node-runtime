# 00 — `schelm-node-runtime` v1 feasibility

Status: completed compiler/runtime spike; design evidence, not production implementation.

## 1. Question and verdict

Before choosing a public API, this spike asked whether the pinned Schelm toolchain can actually support the mechanisms a Node runtime package needs:

1. a private `sjalq` package containing an Elm effect manager with both commands and subscriptions;
2. kernel `Task` facts for wall time, cryptographic entropy, an environment-presence probe, and terminal facts;
3. acknowledgement of a physical stdout write before an Elm message;
4. one shared Node listener while subscribed, and listener removal when the Elm subscription disappears;
5. a terminal standalone exit which does not pretend to return; and
6. execution—not merely compilation—of both debug and optimized Elm artifacts.

**Verdict: feasible, with important constraints.** All six mechanisms ran under Node 24.4.1 in both compiler modes. Effect managers are suitable for listener ownership and callback routing. Kernel Tasks are suitable for one-shot facts and acknowledged writes. Direct `process.exit` is technically possible but is only valid for an explicitly standalone program; it cannot implement a daemon session close. Elm 0.19.2 has no privileged initialization phase equivalent to Gren `Init.Task`, so any public runtime/terminal handle is cooperative authority, not a security boundary.

No production module or kernel was implemented. The committed `feasibility/` package and application are disposable evidence fixtures and deliberately use the name `sjalq/schelm-node-runtime-feasibility`.

## 2. Toolchain and provenance

Evidence was produced on 2026-08-04 UTC from package base commit:

- package base: `29d7bc181983977ae64d7a71d69a9115260d0dce`
- compiler repository HEAD: `bb9bad307c369004751e840f9a50d0f97bdcff1b`
- kernel-authorization ancestor: `76bbe44424106c96f915cb24cd7f50d69f5cee0e`
- compiler binary SHA-256: `69987adf7062562b6e6dfd60b6709be3a06feeb90b096b9c84f673f2b97d8654`
- compiler language version: Elm 0.19.2, based on upstream `48befde1`
- Node: v24.4.1, linux-x64
- Node binary SHA-256: `82e1a4da51b1870fc16495482f47c9bbb634dd02559f80ab5385090123cb034a`
- host: Linux 6.8 x86_64

The build gate accepts a compiler repository descendant of the authorization commit, then pins the compiler **binary** hash. This matters because the repository HEAD contains later authorization tests while the tested binary is unchanged. Provenance does not claim bit-reproducibility of either compiler or Node.

## 3. Committed fixture

`feasibility/package/src/Feasibility/Runtime.elm` is a combined command/subscription effect manager. Its state owns at most one Node listener process and the current Elm taggers. `feasibility/package/src/Elm/Kernel/RuntimeFeasibility.js` supplies only the spike verbs. `feasibility/app/src/Main.elm` exercises them. `feasibility/run.cjs` is bounded by a 500 ms fail timer and expects exit code 7.

Build and run:

```sh
node feasibility/scripts/build.cjs
SCHELM_FEASIBILITY_ENV=present node feasibility/run.cjs debug
SCHELM_FEASIBILITY_ENV=present node feasibility/run.cjs optimize
```

The build script creates an isolated Elm 0.19.2 package overlay, installs the fixture package, adds its private registry entry, and compiles the same application in debug and optimize modes. Generated `build/` artifacts are intentionally ignored; the source, runner, and exact gates are committed.

## 4. Observed results

Both modes produced the same semantic trace:

```text
WRITE_ACK
REPORT {"kind":"snapshot","randomHexLength":16,"envPresent":true,
        "isTty":false,"columns":0,"rows":0,...}
REPORT {"kind":"written","ok":true}
REPORT {"kind":"probe","value":"first"}
REPORT {"kind":"unsubscribed","ok":true}
EXIT 7
```

A second synthetic process event after `unsubscribe` produced no second `probe`, proving the effect-manager cancellation function removed the listener in this bounded run. `written` arrived only from Node's `stdout.write` callback. The fixture then requested standalone exit and the OS-observed process status was 7.

Artifact facts from this run:

| Mode | Bytes | SHA-256 |
|---|---:|---|
| debug | 76,719 | `4211cd1aba1ee991f6e4b2f0a7c17fbf6337d7346cb191842e8e14c4db43fbe1` |
| optimize | 75,516 | `c62c99fc9603c41d23d7ef245c6224b2b9ddf4861dde18d816728f10080cf5d2` |

These artifact hashes are evidence for this source state, not permanent release hashes; final implementation provenance must be regenerated from its final commit.

## 5. Failed attempt and lesson

The first build reached private package dependency verification and failed. The disposable effect manager had encoded Elm `Result` constructors manually in kernel JavaScript and included an unnecessary impossible self-message. The corrected spike sends a primitive `Bool` across the kernel boundary and constructs public error algebra in Elm where practical.

That failure establishes a design rule: **kernel output shapes must be minimal, documented ABI facts; JavaScript must not guess optimized Elm constructor representations.** Production kernels may use generated/canonical adapters, but debug/optimize execution and artifact inspection are mandatory.

## 6. Capability conclusions

| Mechanism | Result | Consequence for design |
|---|---|---|
| private effect manager | Works in debug/optimize | Use for signal, resize, and input listener ownership. |
| kernel one-shot Task | Works | Use for snapshots, clocks, entropy, and acknowledged writes. |
| cancellation function on binding | Works in bounded listener test | Treat as cooperative cleanup; inject races and stale callbacks in property/runtime tests. |
| direct standalone exit | Works; callback never settles | Expose only behind a `Standalone` token. Never use for daemon session closure. |
| terminal discovery without TTY | Works, returned non-interactive facts | Model `NotInteractive`, not fabricated 80×24 terminal capability. |
| environment presence probe | Works | Reading ambient env is authority; production design must cross only explicit selected names and classify them honestly. |
| cryptographic random bytes | Works | Keep separate from deterministic `elm/random`; bound every request. |
| wall clock | Works | Separate wall time from monotonic elapsed time; do not use wall time for deadlines. |
| Gren-style privileged `Init.Task` | Not available in Elm | Initialization handles are cooperative tokens, not security capabilities. |

## 7. What remains unproven

The spike does **not** prove:

- raw-mode restore after signals, crashes, or forced termination;
- partial/backpressured stdout writes, EPIPE, closed stdin, or malformed UTF-8 behavior;
- ordering among signal, resize, input, write callback, release, and exit races;
- uniqueness under concurrent initialization/acquisition;
- monotonic-clock behavior across long sleeps or platform peculiarities;
- entropy failure mapping or maximum-size enforcement;
- Windows/macOS behavior;
- old harness versus package differential behavior; or
- that daemon session closure is safe (the design intentionally keeps it outside process exit).

Those are implementation-phase obligations after the mandated adversarial design reviews and property-test plan. The spike proves the compiler/runtime shape is viable, not that the final guarantees already exist.

## 8. Design constraints carried forward

1. Runtime effects must have one effect-manager owner per global listener/resource.
2. Callback queued, Elm message delivered, and application settlement are distinct states.
3. Standalone process exit and embedded/daemon session close are different types and authorities.
4. Terminal dimensions exist only for an interactive lease; headless output is console I/O, not a fake terminal.
5. Environment access is selected and snapshotted, never an ambient global `Dict` helper.
6. Wall and monotonic clocks are distinct opaque values.
7. Secure entropy is bounded and explicitly non-deterministic; simulations use `elm/random` instead.
8. Every final runtime fixture runs in debug and optimize, with generated provenance and bounded timeouts.
9. Fixture hooks live in a separate fixture package/kernel and are mechanically absent from production artifacts.
10. The first harness milestone may be smaller than the coherent public v1, but it may not distort the public API around `terminal.js` ports.
