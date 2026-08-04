# 04 — Adversarial review B

Provenance: independent round-two findings supplied to the PM after revision A.
Verdict: **block implementation until one final revision and executable test plan**.

## B1. `Duration` still conflates two domains

Revision A caps `Duration` at 24 hours, then uses it for both timer intervals and
elapsed/deadline arithmetic. A process can run or stall longer than 24 hours.
Use an unbounded opaque `Elapsed` for observed monotonic differences and a
separate bounded `TimerDuration` for requested timers. Deadline addition must
saturate safely and never make a long elapsed observation unrepresentable.

## B2. Input has multiple apparent owners

One `InputPiece` fanned to 200 subscribers but acknowledged lease-wide is not a
single-owner pull protocol. Exactly one opaque `InputReader` must own stdin pulls.
The package must not expose observer subscriptions for input. The application
owner may fan decoded facts to non-authoritative observers in ordinary Elm.

## B3. Restore failure cannot immediately free ownership

Revision A says release removes ownership even when cooked restoration throws.
That permits a new lease over a terminal whose physical mode is unknown. A
restore failure must poison the kernel lease. New acquisition fails
`RestoreFailed` until explicit recovery successfully calls cooked restoration.
The synchronous process-exit and signal backstops remain installed while
poisoned. Recovery may make the lease absent; it may not silently claim success.

## B4. Bounds omit zero-width and event/joiner counts

The final contract must decide whether a zero-byte console write is legal and
whether it consumes queue slots. Byte limits alone do not bound callback/event
memory: zero-byte writes, release joiners, signal taggers, resize taggers, and
pending manager self-events can grow without increasing bytes. Set count and
byte bounds for every live collection. State deterministic rejection behavior.

## B5. Signal/default semantics need one final ordering

State whether the package restores cooked mode for a subscribed signal, when the
application message is delivered, and what happens if the application removes
its last subscription without exiting. With no physical package listener, Node's
default disposition must be restored exactly. A signal observed while no package
listener exists cannot be claimed or replayed. Generations must cover detach and
reattach.

## B6. Reference models risk copying production defects

“Pure executable models used by manager decisions” are production reducers, not
independent oracles. Tests need both:

1. a production reducer shared by the effect manager; and
2. a separately authored declarative oracle that consumes external commands and
   observations without importing production transition helpers.

Differential agreement between two wrappers around one reducer proves little.

## B7. Property plan is not reproducible

Name exact generator distributions, valid/invalid command ratios, trace lengths,
shrink order, fixed seeds, replay format, and digest construction. A failure must
print enough information to replay one trace without relying on fuzz-run order.
Digests must normalize debug/optimized constructor naming and exclude timestamps,
PIDs, random bytes, and paths.

## B8. API feasibility must precede production source

Revision A presents plausible signatures but no compiled final API. Before
production implementation, commit a disposable private package mirroring the
final public modules and compile a representative application in both debug and
optimized modes with the pinned Schelm compiler. Exercise every constructor,
callback, `Cmd.map`, and `Sub.map` shape. This validates topology and imports,
not runtime guarantees.

## B9. Scale gates must include all shared resources

The final plan must execute 200 signal subscribers, 200 resize subscribers, 200
ordinary Elm observers behind one `InputReader`, 200 ticker subscribers, 200
concurrent console writes, and maximum release/recovery joiners. Assert physical
listener/timer/read counts, callback counts, bounds, and no post-terminal events.

## B10. Provenance must cover API fixture and final artifacts

Record source commit, compiler authorization ancestor and binary SHA, Node binary
SHA, public package seed/archive hashes, fixture package hash, generated debug
and optimized hashes, normalized trace digests, OS/architecture, and explicit
non-claims. Final provenance must be regenerated after implementation and tests;
pre-implementation hashes are only design evidence.

## B11. Integration remains blocked until package audit

The authority matrix is acceptable as a plan, but no harness branch may start
merely because package tests pass once. Require a package self-audit covering API
surface, kernel constitution, generated artifact inspection, test independence,
bounds, complexity, debug/opt parity, archive reproducibility, and provenance.
Only then may a separate harness integration branch be created.

## Required final artifacts

`05-design-revision-b.md` must close B1–B11 and freeze the public API.
`06-property-test-plan.md` must define independent oracles, exact generated tests,
shrinkers, digests, 200-scale gates, runtime fixtures, and provenance. Commit and
push all three documents plus the compile-only final-API feasibility fixture
before adding production source.
