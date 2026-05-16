# Cross-runtime parity harness

This directory holds the release-gate parity check. It runs a fixed
query battery on both fuse-js and fuse-swift, canonicalizes the
outputs into a shared comparison shape, and asserts equality. Failure
of this check blocks `make release`.

## Layout

- `queries.json` — battery of `{fixture, options, query}` triples. Both
  oracles consume this file verbatim, so adding parity coverage during a
  sync PR is a one-file edit.
- `fixtures/*.json` — document collections that `queries.json` references
  by name.
- `oracle-js.mjs` — fuse-js side. Imports `../fuse-js/dist/fuse.mjs`,
  emits canonicalized JSON to stdout.
- `SwiftOracle/` — fuse-swift side as a standalone SwiftPM package with a
  path dependency on the parent Fuse package. Same input, same output
  shape.
- `../parity-check.sh` — orchestration: runs both oracles, diffs the
  results, fails non-zero on mismatch.

## Canonical comparison shape

Each query produces a JSON object:

```json
{
  "fixture": "books",
  "query": "Stve",
  "results": [
    {
      "refIndex": 1,
      "score": 0.16758907394754194,
      "matches": [
        {
          "key": "author.firstName",
          "value": "Steve",
          "indices": [[0, 4]],
          "refIndex": null
        }
      ]
    }
  ]
}
```

- `score` is omitted when the query is configured without `includeScore`.
- `matches` is omitted when the query is configured without `includeMatches`.
- `indices` are sorted by `(start, end)` and emitted as `[start, end]`
  tuples (matching fuse-js's `RangeTuple`). fuse-swift's native
  `FuseMatchOutcome` Codable shape is `{"start":N,"end":N}` — the Swift
  oracle re-encodes to tuples before emit.
- `key` carries the user-configured key source (string for dotted form,
  array for segmented form).

## Score tolerance

The wrapper compares scores via relative tolerance `1e-9` (the same
tolerance used by `assertApproxRel` in the XCTests). The compounded
`pow(base, exp)` step routinely produces scores on the order of `1e-23`,
so absolute tolerance is meaningless at the bottom of the magnitude
range.

## Why this isn't a per-PR check

The harness depends on a sibling `../fuse-js` checkout and a Node
runtime. CI infrastructure for the per-PR test matrix doesn't have
either. Per-PR parity is asserted via the byte-equivalent oracle scores
checked into `Tests/FuseTests/KeyedSearchTests.swift`,
`ScoringTests.swift`, and `IndexingTests.swift`. The cross-runtime
script is the release-gate safety net that catches drift the per-PR
oracles can't predict — e.g. a fuse-js refactor that mutates result
shape without changing any individual score.
