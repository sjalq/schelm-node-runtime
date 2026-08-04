# schelm-node-runtime

Private Schelm Elm 0.19.2 kernel package for bounded Node runtime primitives:
selected process facts/environment, wall and monotonic clocks, cryptographic
entropy, acknowledged console writes, SIGINT/SIGTERM subscriptions, coalescing
tickers, and an interactive terminal lease with one input reader.

Process exit and daemon session close are deliberately not package APIs. See
`docs/design/05-design-revision-b.md` for the final contract and
`06-property-test-plan.md` for evidence requirements.

The canonical package gate is:

```sh
npm test
```

Release 1.0.1 has independent adversarial audit evidence in
`docs/audit/independent-runtime-audit.md`. Immutable release provenance is
recorded in `build/provenance.json`; consumers must pin the release commit,
tree, bundle/archive hashes, and exact version rather than a mutable branch.
