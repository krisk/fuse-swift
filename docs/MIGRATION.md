# Migrating from `krisk/fuse-swift` 1.x

Short version: **existing 1.x consumers are not broken.** The 1.4.0 codebase is preserved at every commit hash and tag, and SPM pins that resolved against it before the v2 cut continue to resolve to the same artifacts. Migration to the official-port v2 line is **opt-in**.

If you don't intend to upgrade, you can stop reading here.

---

## The branch story

The repo now has three first-class branches:

| Branch | Contents | Default? |
|---|---|---|
| `legacy` | Snapshot of the pre-v2 codebase, top tag `1.4.0`. Frozen — no new commits will land here. | no |
| `master` | Identical to `legacy` content. Kept untouched as a tombstone for SPM consumers who pinned `.branch("master")`. Frozen. | no |
| `main` | The official-port rewrite. Targets fuse-js parity. v2.0.0+ tags live here. | **yes** |

Three points worth knowing:

1. **No history was rewritten.** Every commit hash from the 1.x line is still reachable, on both `legacy` and `master`. Existing clones, forks, and Git URLs continue to work.
2. **No tag was moved or replaced.** `1.4.0` still points at the same commit it always did. There will never be a `1.5.0` or any new `1.x` tag — those are reserved against the frozen line.
3. **`master` is intentionally a tombstone.** GitHub treats default-branch *change* and `master → main` *rename* as distinct operations; this repo did the former. There is no auto-redirect from `master` to `main`. A `git clone` of the bare URL lands on `main`; an explicit `/tree/master` URL or `.branch("master")` SPM dependency continues to resolve to the frozen 1.4.0 content.

---

## SPM consumer migration paths

Find your existing dependency declaration in the table below.

| Your current dependency | What you get today | To opt into v2 |
|---|---|---|
| `.upToNextMajor(from: "1.0.0")` (or any `from: "1.x.x"`) | 1.4.0 forever (no new 1.x tags will ever ship) | change to `.upToNextMajor(from: "2.0.0")` |
| `.exact("1.4.0")` (or any other 1.x exact pin) | exactly that tag, unchanged | change to `.exact("2.0.0")` or `.upToNextMajor(from: "2.0.0")` |
| `.branch("master")` | 1.4.0-era code, frozen — `master` is a tombstone | change to `.upToNextMajor(from: "2.0.0")` (versioned, recommended) or `.branch("main")` (bleeding-edge) |
| No pin yet / `.package(url:...)` only | resolves to the default branch (`main`) → the v2 line | no change, you're already on v2 |

### Concrete example: 1.x version pin → v2 version pin

```swift
// before
dependencies: [
    .package(url: "https://github.com/krisk/fuse-swift.git", from: "1.0.0"),
]

// after
dependencies: [
    .package(url: "https://github.com/krisk/fuse-swift.git", from: "2.0.0"),
]
```

### Concrete example: `.branch("master")` → versioned v2

```swift
// before
dependencies: [
    .package(url: "https://github.com/krisk/fuse-swift.git", .branch("master")),
]

// after — versioned (recommended)
dependencies: [
    .package(url: "https://github.com/krisk/fuse-swift.git", from: "2.0.0"),
]

// alternative — track main directly (bleeding-edge between releases)
dependencies: [
    .package(url: "https://github.com/krisk/fuse-swift.git", .branch("main")),
]
```

After changing the dependency declaration, run `swift package update` (or your Xcode equivalent). Swift Package Manager will pick up v2.0.0+ on the next resolution.

---

## What you're migrating *to*

The v2 line is the official Swift port of [fuse.js](https://github.com/krisk/fuse). v2.0.0 covers the core bitap fuzzy-search pipeline plus keyed object search with per-key weights:

- **Public surface.** `Fuse.Search<Element>` for string-list and keyed object collections, `Fuse.match` for one-shot pattern-vs-text matching, `Fuse.createIndex` / `Fuse.parseIndex` / `FuseIndex.toJSON` for persisted indexes, the full `FuseOptions` surface (16 flags, defaults match fuse.js exactly).
- **Parity.** Results match fuse.js byte-for-byte on match indices / refIndex / ordering, with floating-point tolerance on scores. A cross-runtime parity harness (`make release`) gates the release tag.
- **Platforms.** iOS 15+, macOS 12+, tvOS 15+, watchOS 8+, visionOS 1+, Linux. Requires Swift 6.0 or newer; builds clean under `-strict-concurrency=complete -warnings-as-errors`.

Deferred to v1.1 (additive, non-breaking): extended search (`useExtendedSearch`), logical search (`$and` / `$or` query trees), token search (`useTokenSearch` / TF-IDF).

If your 1.x code uses an API that doesn't appear in the v2 surface, the v2 API is documented in the [README](../README.md). The two surfaces are not source-compatible — v2 is a rewrite, not an evolution — so migrating is a deliberate code change, not a drop-in version bump.

---

## Reporting trouble

If a 1.x consumer pin behaves differently after the branch shuffle, that's a bug — open an issue with the exact dependency declaration that resolves unexpectedly. The contract above is intended to keep every prior SPM pin resolving to the same artifact it did before v2 cut.
