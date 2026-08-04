# Runtime v1 five-principle self-audit

Status: PM self-audit, not the required independent package audit or harness approval.

## 1. User mental model

Pass with caveats. The surface teaches shared `Runtime`, explicit interactive
`Terminal`, sole `InputReader`, and bounded `Ticker`/console operations. No Node
handles leak. `recover` exists only for the uncommon poisoned-terminal path.

## 2. Right path obvious; wrong path unrepresentable

Pass on the main distinctions: wall/monotonic/elapsed/timer types differ; no exit
API; one opaque reader; bounded constructors; headless acquisition is typed.
Limit: runtime/terminal values are cooperative tokens, not security authority.
Stale persistent Elm values are checked at the kernel lease id boundary.

## 3. Tiny orthogonal core plus recipes

Pass. `text` + `line` + `write`, one entropy primitive with hex helper, one
ticker mechanism, and one read owner. No process-title/exit/generic-stream scope.
The callback-Cmd style is less fluent than Tasks but is required for legal Elm
effect-manager ownership.

## 4. Errors teach recovery

Pass with one improvement deferred to review: `RestoreFailed` directs callers to
`recover`; `NotInteractive` directs headless continuation; EPIPE/closed are
closed kinds; malformed input is data-with-fact. `ControlFailed` and
`AcquireFailed` are intentionally coarse because arbitrary Node exceptions do
not cross the boundary.

## 5. Guarantees have executable evidence

Partial pass pending independent audit. Current evidence includes debug/opt
compilation, deterministic replay digests, independent JS oracle/import gate,
mutation kills, PTY cooked restoration/poison recovery/backstop, 200-scale
fixtures, artifact checks, and provenance. The package self-audit fails closed
if any evidence is absent. This PM audit does not substitute for an independent
review, and harness integration remains blocked.

## Conclusion

The public API is coherent and substantially smaller/more truthful than design
01. No ergonomic concern justifies weakening bounds, adding ambient exit, or
moving policy into JavaScript. Independent package audit is still required
before any harness work.
