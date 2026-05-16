# Syncing fuse-swift with fuse.js

How to port a new fuse.js release into fuse-swift. This is a runbook —
something to follow without re-deriving every time — not background
reading. Each step explains *why* it exists so future-me can deviate
deliberately rather than by accident.

## The mental model

fuse-swift always tracks **one specific fuse-js version** at a time.
The README's version-mapping table is the source of truth for which
version that is. A "sync" is the operation that advances that pointer:
take fuse-swift from "in parity with fuse-js X" to "in parity with
fuse-js Y." It is mechanically symmetric — code, tests, and fixtures
all advance together — and parity is verified by the release-gate
harness (`make release`).

Two non-negotiable invariants:

1. **No new 1.x tags ever.** The `legacy` / frozen-`master` branch
   contract (see [`MIGRATION.md`](MIGRATION.md)) reserves the entire
   1.x version space against the archived code. Every sync ships under
   the v2.x line.
2. **Parity is the bar.** A sync PR that breaks the cross-runtime
   parity check does not merge. Scoring divergences are bugs in the
   port, not differences-of-opinion to be documented.

## When to sync

Trigger: every upstream tag, regardless of size. Patch releases get
mechanical syncs the same day or next day; minor / major upstream
releases gate on the scope decisions below.

In practice, watch `../fuse-js/CHANGELOG.md` for new entries.

## Scope rules

What lands in the sync PR depends on the kind of upstream change.
Defaults below; deviating is fine when there's a reason, but the
deviation should be visible in the sync PR description.

| Upstream change | Default fuse-swift response | Notes |
|---|---|---|
| Bug fix (patch) | Port to the corresponding fuse-swift file in the same sync PR. | Includes any new regression tests upstream added. |
| Scoring formula change | Port immediately, even if it changes existing scores. | Parity is the bar. Update any in-tree XCTest oracle scores. |
| New `FuseOptions` flag | Add to the public surface in the same sync PR, with the upstream default. | Surface stays additive (non-breaking). |
| New helper / internal type | Port if any user-visible behavior depends on it; else skip with a note. | Keep the file map tight — avoid speculative ports. |
| New feature (e.g. a new query operator) | Add the algorithmic skeleton in the sync PR; land the public surface in a follow-up fuse-swift minor unless the upstream feature was already in fuse-swift's plan. | Lets the sync PR stay mechanical. |
| Token / extended / logical search work | Pull into the appropriate v1.1 work branch, not the v1.x sync. | These features land coherently in fuse-swift v1.1; piecemeal porting fragments the v1.1 PR. |
| Fixture JSON change | Re-copy the affected fixture verbatim from `../fuse-js/test/fixtures/`. | Note the change in the sync PR if it affects any golden assertion. |
| Test additions (non-deferred areas) | Port to the corresponding `Tests/FuseTests/` file. | Use existing parity-test patterns. |

## Step-by-step runbook (patch / minor sync)

Assumes a sibling `../fuse-js` checkout at the same level as
fuse-swift. Set `FUSE_JS_PATH` to override if you keep it elsewhere.

1. **Capture the previous synced tag.** Open
   `README.md` and note the current fuse-js version from the
   compatibility table. Call this `$PREV`. Call the new upstream tag
   `$NEXT`.

2. **Diff upstream `CHANGELOG.md`.**

   ```bash
   cd ../fuse-js
   git fetch --tags
   git log --oneline $PREV..$NEXT -- CHANGELOG.md
   git diff $PREV..$NEXT -- CHANGELOG.md
   ```

   This is the high-signal pass. Read the changelog entries; they
   usually tell you which categories above apply.

3. **Diff upstream `src/`.**

   ```bash
   git diff $PREV..$NEXT -- src/
   ```

   The Swift layout mirrors the upstream `src/` tree with a few
   directory renames:

   | upstream `src/` | fuse-swift `Sources/Fuse/` |
   |---|---|
   | `src/search/bitap/*.ts` | `Search/Bitap/*.swift` |
   | `src/tools/FuseIndex.ts` | `Index/FuseIndex.swift` (+ `IndexRecord.swift`, `SerializedIndex.swift`) |
   | `src/tools/KeyStore.ts` | `Index/KeyStore.swift` |
   | `src/tools/FieldNorm.ts` | `Index/FieldNorm.swift` |
   | `src/tools/MaxHeap.ts` | `Utilities/MaxHeap.swift` |
   | `src/core/computeScore.ts` | `Core/ComputeScore.swift` |
   | `src/core/transformMatches.ts` | (inlined into `Fuse.search` formatting) |
   | `src/core/index.ts` | `Fuse.swift` (`Fuse.Search<Element>`) |
   | `src/helpers/get.ts` | `Utilities/ValueAccessor.swift` |
   | `src/helpers/diacritics.ts` | `Utilities/Diacritics.swift` |
   | `src/helpers/typeGuards.ts` | `Utilities/Trim.swift` (subset: `isBlank`, `toString`) |
   | `src/helpers/mergeIndices.ts` | `Utilities/MergeIndices.swift` |
   | `src/types.ts` | `Options.swift` / `Result.swift` (typed structs) |

   If an upstream diff touches a file outside this map (e.g., a new
   helper), decide whether the change is user-visible — internal helpers
   may not need a Swift counterpart at all.

4. **Start the sync branch in fuse-swift.**

   ```bash
   cd ../fuse-swift
   git checkout -b port-update/fuse-js-$NEXT
   ```

5. **Apply code changes file-by-file.** For each touched JS file, edit
   the corresponding Swift file. Keep the PR scoped to the upstream
   diff — refactoring belongs in a separate PR.

6. **Port new tests.** For each test added in `../fuse-js/test/` under
   the non-deferred suites (`fuzzy-search.test.js`, `scoring.test.js`,
   `match.test.js`, `indexing.test.js`, `optimizations.test.js`,
   `cache-invalidation.test.js`), translate to XCTest in the
   corresponding `Tests/FuseTests/*Tests.swift`. Capture oracle scores
   from `../fuse-js/dist/fuse.mjs` for any assertion that asserts a
   specific score.

7. **Re-copy fixtures.** Any `../fuse-js/test/fixtures/*.json` that
   changed: copy verbatim into `Tests/FuseTests/Fixtures/` and into
   `scripts/parity/fixtures/` (the parity harness uses its own copy
   pinned to the synced version).

8. **Extend the parity battery if needed.** If the sync added a new
   option flag or behavior, add a case to `scripts/parity/queries.json`
   that exercises it. The cross-runtime check then locks in parity for
   the new surface from day one.

9. **Run the local gates.**

   ```bash
   make test           # 253+ XCTests
   make strict-test    # strict-concurrency
   make release        # strict-test + cross-runtime parity
   ```

   Everything must be green. A failing parity check almost always
   means an algorithmic step got missed or translated imprecisely
   — investigate before considering whether to weaken the assertion.

10. **Update the version-mapping table.** Edit `README.md` to add a
    row for the new fuse-swift version → fuse-js `$NEXT`. Bump the
    fuse-swift version per semver (patch for behavior-equivalent
    syncs, minor for new public surface).

11. **Update `CHANGELOG.md`.** Add an entry under the new fuse-swift
    version describing what changed (in fuse-swift terms — not just
    "synced to fuse-js X.Y.Z").

12. **Bump the version constant.** `Fuse.version` in
    `Sources/Fuse/Fuse.swift`.

13. **Commit + PR.** Title: `chore(sync): fuse-js vX.Y.Z`. Body should
    link the upstream CHANGELOG entries that drove the changes.

14. **Tag after merge.**

    ```bash
    git checkout main
    git pull
    git tag vX.Y.Z       # the new fuse-swift version, not the upstream
    # Kiro pushes the tag manually; do not push from automation.
    ```

## Worked example: hypothetical sync from 7.4.0-beta.5 → 7.4.0

This is a synthetic walkthrough showing what the first real sync after
v2.0.0 will look like. Replace with the real commands once it happens.

Setup state: fuse-swift is at v2.0.0, README maps to fuse-js 7.4.0-beta.5.
Upstream tags 7.4.0 stable. Assume the only diff between the two is a
bug fix in `src/search/bitap/search.ts` and one new regression test in
`test/fuzzy-search.test.js`.

```bash
# 1. Capture the version pointer.
#    README says: "2.0.0 → 7.4.0-beta.5"  → $PREV = v7.4.0-beta.5

# 2. Diff upstream CHANGELOG.
cd ../fuse-js
git fetch --tags
git log --oneline v7.4.0-beta.5..v7.4.0 -- CHANGELOG.md
# (one entry: "fix: bitap off-by-one in chunked-pattern boundary case")

# 3. Diff src/.
git diff v7.4.0-beta.5..v7.4.0 -- src/
# (touches src/search/bitap/search.ts only)

# 4. Branch.
cd ../fuse-swift
git checkout -b port-update/fuse-js-7.4.0

# 5. Port the change. File map → Sources/Fuse/Search/Bitap/BitapSearch.swift.
#    Apply the equivalent off-by-one fix.

# 6. Port the new regression test to
#    Tests/FuseTests/BitapFuzzyTests.swift (or whichever maps).

# 7. No fixture changes in this hypothetical sync, skip.

# 8. No new options or behaviors, no parity-battery additions needed.

# 9. Run gates.
make release
# expect: ✓ release gate passed

# 10. Update README. Add row:
#     | 2.0.1 | 7.4.0 | Bitap chunk-boundary off-by-one fix (upstream #NNN). |

# 11. Update CHANGELOG.md.

# 12. Bump Fuse.version in Sources/Fuse/Fuse.swift: "2.0.0" → "2.0.1".

# 13. Commit + PR.
git add -A
git commit -m "chore(sync): fuse-js v7.4.0"
gh pr create --title "chore(sync): fuse-js v7.4.0" --body "..."

# 14. After merge, tag.
git checkout main && git pull
git tag v2.0.1
# Push the tag manually.
```

If the same hypothetical sync had also added a new `FuseOptions` flag,
step 8 would have added a parity battery case exercising it, step 10
would have bumped to `2.1.0` (new public surface = minor), and step 11
would have a separate "Added" subsection.

## Common situations

**Upstream renames an internal helper.** Rename the Swift counterpart
too. Don't preserve the old name — sync diffs become harder to read
when the symbol map drifts.

**Upstream adds a new file under `src/`.** Add a corresponding Swift
file in the matching directory (per the file-map table above). If the
new file is user-visible, add a new row to that table so the next
sync's diff is unambiguous; for purely internal helpers, no map update
needed.

**Upstream adds a non-FuseOptions configuration knob** (e.g. via a
private constructor argument). Decide whether it's worth surfacing in
fuse-swift; if yes, add it with the same default; if no, document the
divergence as a comment in the corresponding file.

**Upstream changes the JSON index shape.** This is a parity-breaking
event for any consumer who persisted indexes. Bump fuse-swift's
major version, document the shape change in MIGRATION.md, and update
the golden file in `Tests/FuseTests/Fixtures/`.

**Parity check fails after a sync that you believe is correct.** Don't
weaken the assertion. The most common causes (in rough order):
score-formula port missing a step, integer vs floating-point arithmetic
divergence at a JS / Swift boundary, fixture not re-copied, an
unported test fixture asserting old behavior. The cross-runtime
harness's diff output names the exact case + result index + field that
disagrees — start there.

**fuse-js ships a v1.1 deferred feature** (extended / logical / token
search). Port the algorithmic skeleton in the sync PR but do not
expose the public flag. The full surface lands in a separate
fuse-swift v1.1 PR.

## Test-suite mapping

| upstream `test/` | fuse-swift `Tests/FuseTests/` |
|---|---|
| `fuzzy-search.test.js` (string-array cases) | `BitapFuzzyTests.swift` |
| `fuzzy-search.test.js` (keyed cases) | `KeyedSearchTests.swift` |
| `scoring.test.js` | `ScoringTests.swift` |
| `match.test.js` | `MatchTests.swift` |
| `indexing.test.js` | `IndexingTests.swift` (+ `AccessorSemanticsTests.swift`) |
| `optimizations.test.js` | `OptimizationsTests.swift` (+ `SortingTests.swift`) |
| `cache-invalidation.test.js` | `CacheInvalidationTests.swift` |
| `extended-search.test.js` | not yet ported (extended search not in v1) |
| `logical-search.test.js` | not yet ported (logical search not in v1) |
| `token-search*.test.js`, `internals.test.ts` (token-internal) | not yet ported (token search not in v1) |
| `workers.test.js`, `feature-flags.test.js`, `typings.test.ts` | not ported (n/a in Swift) |

Within ported suites, the explicit skip list (cases that are
intentionally `XCTSkip`-ed):

- BigInt scalar / array cases — Swift has no native `BigInt`.
- `useTokenSearch` cases — token search not in v1 surface.
- `Fuse.use()` cases — fuse-swift exposes no plugin-registration
  mechanism.
- `indexing.test.js` key-scoped object-query assertions (e.g.
  `fuse.search({ title: 'old man' })`) — query parser is not in v1
  surface.

Any new skip introduced by a sync requires a sentence in the sync PR
description explaining why.

## References

- [`MIGRATION.md`](MIGRATION.md) — branch story and SPM consumer
  migration paths for the v1.x → v2 cut.
- [`scripts/parity/README.md`](../scripts/parity/README.md) — internals
  of the cross-runtime parity harness.
- [`README.md`](../README.md) — version-mapping table is the canonical
  pointer to the currently-synced fuse-js version.
