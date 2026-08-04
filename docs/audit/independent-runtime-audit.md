# Independent runtime v1.0.1 adversarial audit

Auditor: runtime-integration agent, separate from the package implementation passes
Date: 2026-08-05
Reviewed baseline: `5a33868ab8fea01c2949ef19039f455d3175b546`
Disposition: **PASS after provenance repair**

## Method

This was a read-only adversarial review of the public Elm API, effect managers,
Node kernel boundary, compiled fixture drivers, oracle/mutation gates, PTY tests,
and release/audit scripts. The only implementation change requested by this
audit is the deterministic provenance repair described below; no runtime
semantics were changed.

The review traced each public operation from `elm.json` exposed modules through
its effect manager and kernel primitive, then challenged ownership, settlement,
stale-generation, resource-bound, and restoration claims against executable
tests in both generated modes. The canonical suite was run independently after
the repair and completed all 41 behavioral tests before the evidence gates.

## Findings

### Blocking finding repaired: provenance hashed the wrong tree

`provenance.cjs` recorded `implementationCommit = HEAD` but built
`sourceDigest` by reading the current worktree after the evidence commit. The
audit recomputation therefore mixed two identities and failed after the 41
behavioral tests (`36b1…` recorded versus canonical implementation digest
`879d…`). Both generation and verification now enumerate the declared
implementation commit with `git ls-tree` and hash each blob with `git show`, in
sorted path order. This makes evidence-only files unable to alter the claimed
implementation digest.

### Console: PASS

The compiled manager owns bounded FIFO settlement. Accepted work is bounded by
count and UTF-8 bytes; zero-byte writes consume count; callbacks, EPIPE, close,
and stale generations settle at most once. The retained endpoint listener is a
Node-boundary fact, while acceptance and ordering remain Elm decisions.

### Terminal and PTY: PASS

One lease, one reader, one outstanding read, and generation checks prevent ABA
reuse. Release, signal, and process-exit backstops attempt cooked restoration.
A failed restore poisons the lease until explicit recovery. PTY evidence covers
raw/cooked release, restore failure and recovery, input replay/EOF, reader ABA,
subscriber limits, and current/released/stale resize ownership in debug and
optimized artifacts. SIGKILL restoration remains correctly excluded.

### Clock, ticker, environment, and signals: PASS

Wall and monotonic facts are distinct. Tickers advance from prior targets,
coalesce delayed wakes, cap skipped counts, and share one physical timeout under
bounded logical ownership. Environment capture is explicit selection rather
than an ambient secret snapshot. SIGINT/SIGTERM listeners detach at zero
subscribers and stale generations are dropped.

### Exit authority: PASS

No public or kernel package API calls `process.exit`. The package reports runtime
facts and events; once-mode process exit versus daemon per-session close remains
an application/harness policy decision.

### Bounds and hot paths: PASS

The reviewed diff contains no accumulated `++ [ x ]` or `List.member`
prohibition. Console queues use two-list FIFO structure; subscriber and joiner
limits bound fan-out. Scale tests exercise compiled production managers rather
than fixture-only reducers.

## Evidence and non-claims

The canonical command is `npm test` (`node scripts/canonical-test.cjs`). It
validates formatting, API and production compilation, 41 Node/PTY behavioral
tests, isolated package diagnostics, oracle import separation, mutation kills,
deterministic replay, compiled replay, provenance, artifact hashes, and a clean
worktree.

This audit does not claim compiler or Node bit-reproducibility, an independent
oracle for console/signal compiled traces, restoration after SIGKILL, or security
capability semantics for cooperative Elm tokens. Those limitations match the
package design and provenance non-claim.

## Conclusion

No independent runtime blocker remains after binding provenance to the declared
implementation commit. Runtime v1.0.1 is suitable for immutable publication and
exact harness pinning.
