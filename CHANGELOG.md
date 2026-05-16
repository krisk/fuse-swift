# Changelog

All notable changes to fuse-swift are documented here. The format
loosely follows [Keep a Changelog](https://keepachangelog.com/); commit
messages follow [Conventional Commits](https://www.conventionalcommits.org/).

The 1.x line (top tag `1.4.0`) is preserved on the `legacy` branch and
the frozen `master` branch — see [`docs/MIGRATION.md`](docs/MIGRATION.md)
for the branch story. This changelog covers the v2.x line only.

## [Unreleased]

_(nothing since the most recent tag)_

## [2.0.0-rc.1] - Pending

First release candidate of the official Swift port of
[fuse.js](https://github.com/krisk/fuse). fuse-swift v2 is a rewrite,
not an evolution of the archived 1.x line: it tracks fuse.js's
algorithm byte-for-byte (within floating-point tolerance on scores),
ships a Swift-idiomatic API surface (generic `Fuse.Search<Element>`,
typed `FuseKey`, throwing initializers, `Sendable` where possible), and
lives above the frozen 1.4.0 tag tree on the same repo so existing SPM
pins continue to resolve to the artifacts they always did.

Targets fuse.js `7.4.0-beta.5`.

### Added

- **`Fuse.Search<Element>`** — generic searcher for both string-list
  (`Fuse.Search<String>`) and keyed object collections, with the
  mutation surface (`add`, `remove(predicate:)`, `removeAt`,
  `setCollection`, `getIndex`).
- **`FuseKey<Element>`** — typed key declaration with four constructor
  forms:
  - `.keyPath` — `KeyPath<Element, String>` / `KeyPath<Element, String?>`,
    compile-time checked, no `Encodable` requirement.
  - `.path(String)` — dotted-string path resolved against the encoded
    JSON of the element (requires `Element: Encodable` or a top-level
    `options.getFn`).
  - `.path([String])` — segmented path preserving literal-dot segments.
  - `.closure` — `@Sendable (Element) -> String | String? | [String]`
    for non-Encodable types or computed fields.
  All initializers `throw` on `weight <= 0`.
- **`FuseOptions<Element>`** — 16 flags matching fuse.js defaults
  exactly: `isCaseSensitive`, `ignoreDiacritics`, `includeMatches`,
  `includeScore`, `keys`, `shouldSort`, `sortFn`, `location`,
  `threshold`, `distance`, `findAllMatches`, `minMatchCharLength`,
  `ignoreLocation`, `ignoreFieldNorm`, `fieldNormWeight`, `getFn`.
- **`Fuse.match(_:in:options:)`** — one-shot pattern-vs-text fuzzy
  match, mirroring upstream's `Fuse.match` static.
- **Index persistence** — `Fuse.createIndex` / `Fuse.parseIndex` /
  `FuseIndex.toJSON()` with upstream-compatible JSON shape
  (`{records, keys}` with `{v, i, n}` for string records and
  `{i, $: {...}}` for object records). An index built by fuse.js can
  be loaded by fuse-swift and vice versa.
- **Top-K via `limit`** — positive `limit` routes through a `MaxHeap`
  even when `shouldSort: false`. The heap selects candidates by score
  only; a custom `sortFn` re-orders the extracted N without affecting
  which N are admitted (parity with upstream).
- **Searcher cache** — identical-pattern re-queries reuse the
  `BitapSearch` instance; mutations invalidate, except `remove`
  predicates with zero matches (load-bearing invariant ported from
  upstream).
- **Literal port of fuse.js's three-step diacritic folder** (NFD +
  scalar-range filter + 12-entry `NON_DECOMPOSABLE_MAP`). Foundation's
  `String.folding(options: .diacriticInsensitive)` is intentionally
  *not* used — it diverges from fuse.js on real inputs.
- **JS-style stringification for terminal non-scalars** inside array
  traversal: objects become `"[object Object]"`, nested arrays
  comma-join their elements, matching fuse.js's `value + ''` semantics.
- **Cross-runtime parity harness** at `scripts/parity-check.sh` —
  shared query battery (`scripts/parity/queries.json`) drives both a
  fuse.js oracle (Node) and a fuse-swift oracle (standalone SwiftPM
  package), then diffs the canonicalized results with relative
  tolerance on scores. Gates `make release`.
- **`Examples/CLI/`** — standalone SwiftPM package demonstrating both
  string-list and keyed object search.

### Platforms

iOS 15+, macOS 12+, tvOS 15+, watchOS 8+, visionOS 1+, Linux. Builds
clean on Swift 5.9 and Swift 6.x under
`-strict-concurrency=complete -warnings-as-errors`.

### Compatibility

Tracks fuse.js `7.4.0-beta.5`. The cross-runtime parity check covers
25 query cases / 138 result records spanning string-list search,
keyed object search, weighted keys (including weights not summing to
one), threshold and location options, case-sensitive and
ignore-location modes, and `includeMatches` shape.

### Not in v1 — landing in v1.1

- Extended search (`useExtendedSearch`) — token operators (`'foo`,
  `^foo`, `!foo`, `foo$`, etc.).
- Logical search (`$and` / `$or` query trees) — comes with the query
  parser.
- Token search (`useTokenSearch` / TF-IDF) — tracks upstream's May 2026
  configurable-tokenizer surface.

### Known limitations

- **Unicode case-folding edge cases.** The Swift port currently uses
  `String.lowercased()` for case-insensitive matching, which diverges
  from JS `toLowerCase()` on a small set of code points (Turkish dotted
  `İ`, Greek final sigma at word boundaries, German `ẞ`). A
  source-aware `jsLowercased` helper ports the JS table directly and
  is on the v1.x roadmap. Inputs that don't hit those scalars are
  unaffected.
- **`BigInt` scalar coercion is out of scope.** Swift has no native
  `BigInt`; upstream tests that exercise `BigInt` are explicitly
  skipped in the parity oracle.
- **Match indices are in transformed-text UTF-16 space.** When
  `ignoreDiacritics` and/or case-folding apply, indices refer to the
  post-transform string, not the original. Same as fuse.js. No
  `Range<String.Index>` round-trip back to the original text in v1; a
  helper for the case-sensitive / no-diacritics combination can land
  later without breaking the offset contract.
- **`Fuse.Search` is not `Sendable`.** Mutable index state + sync API.
  Wrap in an actor or a `Task` if needed for cross-isolation use.
  Result types and `FuseOptions<Element>` (when `Element: Sendable`)
  are `Sendable`.

### Notes for users of `krisk/fuse-swift` 1.x

Existing 1.x SPM pins continue to resolve to 1.4.0 unchanged. Migration
to v2 is opt-in. See [`docs/MIGRATION.md`](docs/MIGRATION.md) for the
branch story and the three SPM consumer migration paths. No new 1.x
tags will ever ship.

---

[Unreleased]: https://github.com/krisk/fuse-swift/compare/v2.0.0-rc.1...HEAD
[2.0.0-rc.1]: https://github.com/krisk/fuse-swift/releases/tag/v2.0.0-rc.1
