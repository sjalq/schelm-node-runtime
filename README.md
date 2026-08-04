# schelm-node-runtime

Private Schelm Elm 0.19.2 kernel package for bounded Node runtime primitives:
selected process facts/environment, wall and monotonic clocks, cryptographic
entropy, acknowledged console writes, SIGINT/SIGTERM subscriptions, coalescing
tickers, and an interactive terminal lease with one input reader.

Process exit and daemon session close are deliberately not package APIs. See
`docs/design/05-design-revision-b.md` for the final contract and
`06-property-test-plan.md` for evidence requirements.

```sh
node scripts/build-fixtures.cjs
node --test --test-timeout=60000 tests/node/*.test.cjs
node tests/audit.cjs
```

Harness integration is blocked until package audit evidence is committed.
