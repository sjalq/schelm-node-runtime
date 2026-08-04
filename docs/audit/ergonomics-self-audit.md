# Runtime v1 five-principle self-audit

Status: historical PM self-audit. The subsequent independent audit is recorded in
`independent-runtime-audit.md`.

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

Pass. Current evidence includes debug/opt
compilation, deterministic replay digests, independent JS oracle/import gate,
mutation kills, PTY cooked restoration/poison recovery/backstop, 200-scale
fixtures, artifact checks, and provenance. The package audit fails closed if
any evidence is absent. This PM audit did not substitute for independent review;
the completed adversarial review is preserved separately.

## Conclusion

The public API is coherent and substantially smaller/more truthful than design
01. No ergonomic concern justifies weakening bounds, adding ambient exit, or
moving policy into JavaScript. The independent audit subsequently passed after
the deterministic provenance repair.
