# fuse-swift

<!-- Badges (CI / SPM / platforms) will land once CI is set up post-release. -->

The official Swift port of [fuse.js](https://github.com/krisk/fuse). Byte-equivalent results, idiomatic Swift API, syncs with each upstream release.

## Status

2.0.0-rc.1 is the first release candidate. v1 scope is feature-complete and has 253 unit tests plus a cross-runtime parity check against fuse-js 7.4.0-beta.5 (25 query cases, 138 result records, all match within 1e-9 score tolerance). Promotion to `2.0.0` follows a short feedback window.

## Install

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/krisk/fuse-swift.git", from: "2.0.0"),
]
```

Platforms: iOS 15+, macOS 12+, tvOS 15+, watchOS 8+, visionOS 1+, Linux. Builds clean under Swift 5.9 and Swift 6.x with `-strict-concurrency=complete`.

## Quick start: string array

```swift
import Fuse

let fruits = ["apple", "orange", "banana", "pear", "grape", "kiwi", "mango", "plum"]

let options = try FuseOptions<String>(includeScore: true)
let fuse = try Fuse.Search<String>(fruits, options: options)

for r in fuse.search("ange", limit: 3) {
    print(r.refIndex, r.item, r.score!)
}
// 1 orange 0.02
// 6 mango  0.26
// 2 banana 0.51
```

## Quick start: keyed objects with weighted keys

```swift
import Fuse

struct Book: Codable, Sendable {
    let title: String
    let author: Author
}
struct Author: Codable, Sendable {
    let firstName: String
    let lastName: String
}

let books = [
    Book(title: "Old Man's War",   author: .init(firstName: "John",  lastName: "Scalzi")),
    Book(title: "The Lock Artist", author: .init(firstName: "Steve", lastName: "Hamilton")),
    Book(title: "HTML5",           author: .init(firstName: "Remy",  lastName: "Sharp")),
]

let options = try FuseOptions<Book>(
    includeMatches: true,
    includeScore: true,
    keys: [
        try FuseKey<Book>("title", keyPath: \Book.title, weight: 0.7),
        try FuseKey<Book>(path: "author.firstName", weight: 0.3),
    ]
)
let fuse = try Fuse.Search<Book>(books, options: options)

let results = fuse.search("stve")
print(results[0].item.title)
// "The Lock Artist"

// With `includeMatches: true`, each `FuseResult.matches` entry carries
// the configured key (`.string("title")` or `.string("author.firstName")`),
// the matched sub-record value, sorted UTF-16 indices, and (for array-
// derived keys) the source-array refIndex. See `Examples/CLI/` for a
// runnable walkthrough.
```

`FuseKey` has three accessor forms:

- **`.keyPath`** — type-safe Swift `KeyPath` into a stored property. Compile-time checked; doesn't require `Encodable`.
- **`.path`** (single dotted string or array of segments) — runtime path walked against the encoded JSON of the element. Requires `Element: Encodable` or a custom `getFn`.
- **`.closure`** — `@Sendable (Element) -> String | String? | [String]` for fields that need computation or come from non-Encodable types.

All initializers throw on `weight <= 0`, so call sites use `try`.

## Highlighting matches

With `includeMatches: true`, each `FuseMatch.indices` carries `[FuseRange]` of `(start, end)` UTF-16 offsets covering the matched runs in the matched text. The pattern is the same regardless of whether you render to ANSI, HTML `<mark>`, `AttributedString`, or anything else — slice the original by the ranges and wrap the matched segments.

```swift
func highlight(_ value: String, ranges: [FuseRange]) -> String {
    guard !ranges.isEmpty else { return value }
    let units = Array(value.utf16)
    var out = ""
    var cursor = 0
    for r in ranges {
        if r.start > cursor {
            out += String(decoding: units[cursor..<r.start], as: UTF16.self)
        }
        out += "[" + String(decoding: units[r.start..<(r.end + 1)], as: UTF16.self) + "]"
        cursor = r.end + 1
    }
    if cursor < units.count {
        out += String(decoding: units[cursor..<units.count], as: UTF16.self)
    }
    return out
}

// Given a result `r` from search("Lock", limit: 1):
// for m in r.matches ?? [] {
//     print(highlight(m.value ?? "", ranges: m.indices))
//     // → "The [Lock] Artist"
// }
```

**Transform-space caveat.** Indices are UTF-16 offsets in the *transformed* text (post case-fold + diacritic-strip). For inputs whose length is preserved by the configured transforms (ASCII text under defaults, or any text with `isCaseSensitive: true, ignoreDiacritics: false`), the offsets map 1:1 back to the original and the helper above works directly. Inputs that change length under the transforms (Turkish `İ` lowercased, NFD-decomposed accents with `ignoreDiacritics: true`, German `ẞ` expanded to `ss` during diacritic-strip) need a transform-aware helper that recomputes the original-space offsets.

A runnable demo lives at [`Examples/Highlighting/`](Examples/Highlighting/).

## `FuseOptions` reference

| Option | Default | Notes |
|---|---|---|
| `isCaseSensitive` | `false` | When `false`, pattern and text are JS-equivalent lowercased before bitap. |
| `ignoreDiacritics` | `false` | When `true`, both pattern and text run through a literal port of fuse.js's three-step diacritic strip (NFD + scalar-range filter + `NON_DECOMPOSABLE_MAP`). |
| `includeMatches` | `false` | Populates `FuseResult.matches` with sub-record indices, keys, and values. |
| `includeScore` | `false` | Populates `FuseResult.score`. |
| `keys` | `[]` | Array of `FuseKey<Element>`. Empty for `Fuse.Search<String>`; one or more for keyed object search. |
| `shouldSort` | `true` | Sort by ascending score. Overridden by `limit > 0` (see below). |
| `sortFn` | `nil` | Custom `(FuseSortItem<Element>, FuseSortItem<Element>) -> ComparisonResult`. With `limit > 0`, the heap selects the top-N by score and `sortFn` only re-orders the extracted N. |
| `location` | `0` | Expected match position. |
| `threshold` | `0.6` | Maximum per-text bitap score for `isMatch == true`. `0` requires an exact substring; `1` matches anything. |
| `distance` | `100` | Score penalty applied per character away from `location`. |
| `findAllMatches` | `false` | When `true`, the bitap scan covers the full text length even after a match is found. |
| `minMatchCharLength` | `1` | Minimum run length emitted in `FuseMatch.indices`. |
| `ignoreLocation` | `false` | Drop the position penalty entirely. |
| `ignoreFieldNorm` | `false` | Drop the field-length norm from the score (long and short fields rank by raw bitap score). |
| `fieldNormWeight` | `1.0` | Exponent multiplier on the field norm. |
| `getFn` | `nil` | Top-level `@Sendable (Element, [String]) -> AccessorResult` that overrides the default JSON walker for `.path` keys only. |

*Coming in v1.1:* `useExtendedSearch`, `useTokenSearch`, `tokenize`.

## Index persistence

`Fuse.createIndex` builds an index once; `toJSON()` serializes it to upstream-compatible JSON; `Fuse.parseIndex` reads it back. Useful for warm-starting large collections.

```swift
let books = /* ... */
let keys  = [try FuseKey<Book>("title", keyPath: \Book.title)]

// Build once, persist.
let index = try Fuse.createIndex(keys, books)
let data  = try index.toJSON()
try data.write(to: cacheURL)

// Later: parse, then construct Fuse.Search with the prebuilt index.
let restored: FuseIndex<Book> = try Fuse.parseIndex(try Data(contentsOf: cacheURL))
let fuse = try Fuse.Search<Book>(
    books,
    options: try FuseOptions<Book>(keys: keys),
    index: restored
)
```

The supplied index is copy-on-adopt — `Fuse.Search` never mutates the user's instance. The serialized JSON shape matches fuse.js's (`{records, keys}` with `{v, i, n}` for string records and `{i, $: {...}}` for object records), so an index built by fuse.js can be loaded by fuse-swift and vice versa.

## Coming from fuse.js

The translation is mechanical. The biggest surface change is that fuse-swift puts the element type in the generic (`Fuse.Search<Book>`) rather than the constructor argument, and keys are typed `FuseKey` values rather than strings/dicts.

**Constructor.**

```js
// fuse.js
const fuse = new Fuse(list, { keys: ['title'], includeScore: true })
```

```swift
// fuse-swift
let fuse = try Fuse.Search<Book>(list, options: try FuseOptions<Book>(
    includeScore: true,
    keys: [try FuseKey<Book>("title", keyPath: \Book.title)]
))
```

**String keys → typed key paths.**

```js
// fuse.js
keys: ['title', 'author.firstName']
```

```swift
// fuse-swift
keys: [
    try FuseKey<Book>("title", keyPath: \Book.title),
    try FuseKey<Book>(path: "author.firstName"),
]
```

**Weighted keys.**

```js
// fuse.js
keys: [
    { name: 'title',             weight: 0.7 },
    { name: 'author.firstName',  weight: 0.3 },
]
```

```swift
// fuse-swift
keys: [
    try FuseKey<Book>("title", keyPath: \Book.title, weight: 0.7),
    try FuseKey<Book>(path: "author.firstName",      weight: 0.3),
]
```

**Array-form path (literal-dot segments).**

```js
// fuse.js
keys: [['author', 'first.name']]
```

```swift
// fuse-swift
keys: [try FuseKey<Book>(path: ["author", "first.name"])]
```

**Custom `getFn`.**

```js
// fuse.js
new Fuse(list, { keys: ['author'], getFn: (obj) => obj.author.lastName })
```

```swift
// fuse-swift
try Fuse.Search<Book>(
    list,
    options: try FuseOptions<Book>(
        keys: [try FuseKey<Book>(path: "author")],
        getFn: { book, _ in .single(book.author.lastName) }
    )
)
```

**Search.**

```js
// fuse.js
fuse.search('apple', { limit: 5 })
```

```swift
// fuse-swift
fuse.search("apple", limit: 5)
```

**One-shot `Fuse.match`.**

```js
// fuse.js
Fuse.match('apple', 'apple pie', { includeMatches: true })
```

```swift
// fuse-swift
Fuse.match("apple", in: "apple pie", options: FuseMatchOptions(includeMatches: true))
```

## Limitations vs fuse.js

v1 omits three features. All return as additive (non-breaking) surface in v1.1.

| Feature | Status | Notes |
|---|---|---|
| Extended search (`useExtendedSearch`) | v1.1 | Token operators (`'foo`, `^foo`, `!foo`, `foo$`, etc.). |
| Logical search (`$and` / `$or` trees) | v1.1 | Comes with the query parser. |
| Token search (`useTokenSearch` / TF-IDF) | v1.1 | Configurable tokenizer landed upstream in May 2026; v1.1 will track that surface. |

A few smaller v1 limitations worth knowing:

- **No `BigInt` scalar coercion.** Swift has no native `BigInt`; documented out-of-scope. Upstream tests that hit BigInt paths are explicitly `XCTSkip`-ed in the parity oracle.
- **Match indices are in transformed-text UTF-16 space.** When `ignoreDiacritics` and / or case-folding apply, indices refer to the post-transform string, not the original. fuse.js does the same; the v1 surface does not include a `Range<String.Index>` round-trip back to the original text. A helper for the case-sensitive / no-diacritics combination can land in v1.x without breaking the offset contract.
- **`Fuse.Search` is not `Sendable`.** Mutable index state + synchronous API. The result types and `FuseOptions<Element>` (when `Element: Sendable`) *are* `Sendable`, so input and output cross isolation cleanly; only the searcher instance is single-isolation. See the [Concurrency](#concurrency) section below for the canonical patterns.

## Concurrency

`Fuse.Search` is intentionally non-`Sendable` (mutable index + sync API). `FuseOptions`, `FuseResult`, and `FuseMatch` are `Sendable` (when `Element: Sendable`), so getting data into and out of a searcher across isolation boundaries is fine — only the searcher itself stays put.

**Repeated searches on a long-lived corpus → wrap in an actor.** The canonical pattern. The actor's isolation guarantees serial access to the non-`Sendable` searcher.

```swift
actor BookSearchService {
    private let fuse: Fuse.Search<Book>

    init(books: [Book]) throws {
        self.fuse = try Fuse.Search<Book>(
            books,
            options: try FuseOptions<Book>(
                includeScore: true,
                // .path form avoids capturing a non-Sendable KeyPath
                // across the actor's isolation boundary (Swift 6).
                keys: [try FuseKey<Book>(path: "title")]
            )
        )
    }

    func search(_ query: String) -> [FuseResult<Book>] {
        fuse.search(query)
    }
}

let service = try BookSearchService(books: books)
let results = await service.search("stve")  // hops off the caller's isolation
```

**Ad-hoc one-shot search → build inside `Task.detached`.** Use this when the collection changes between calls or search frequency is low enough that index construction cost is acceptable.

```swift
let docs: [String] = ["apple", "orange", "banana"]
let opts = try FuseOptions<String>(includeScore: true)
let query = "ange"

let results = try await Task.detached(priority: .userInitiated) {
    let fuse = try Fuse.Search<String>(docs, options: opts)
    return fuse.search(query)
}.value
```

The index is rebuilt per call. For repeated searches over a stable corpus, the actor pattern above pays for itself after the second call.

**Legacy GCD codebases.** `Fuse.Search` works behind `DispatchQueue.global().async` as long as the calling code already guarantees no concurrent access (typically: the searcher is touched only from a single serial queue). Under `-strict-concurrency=complete` the compiler will require one of the patterns above instead.

For more patterns (debounced search-as-you-type, `async let` parallel across multiple corpora, main-actor searchers for small corpora, "what not to do" with `@unchecked Sendable`, profiling guidance), see [`docs/CONCURRENCY.md`](docs/CONCURRENCY.md). A runnable demo of these patterns lives at [`Examples/Concurrency/`](Examples/Concurrency/).

## Version compatibility

| fuse-swift | fuse.js | Notes |
|---|---|---|
| 2.0.0-rc.1 | 7.4.0-beta.5 | First release candidate of the official-port line. |

Each fuse.js release triggers a `chore(sync): fuse-js vX.Y.Z` PR. The cross-runtime parity check (`scripts/parity-check.sh`) gates the release tag.

## Migrating from `krisk/fuse-swift` 1.x

The 1.x line is the previous `krisk/fuse-swift` codebase (top tag 1.4.0). It is preserved on the `legacy` branch — every commit hash and tag intact — and the `master` branch is frozen as a tombstone for SPM consumers who pinned `.branch("master")`. The official-port rewrite lives on `main`. See [`docs/MIGRATION.md`](docs/MIGRATION.md) for the upgrade path.

## Examples

Three runnable demos live under `Examples/`:

- [`Examples/CLI/`](Examples/CLI/) — string-list and keyed object search.

  ```
  cd Examples/CLI
  swift run FuseCLI            # default queries
  swift run FuseCLI "stve"     # custom query against both fixtures
  ```

- [`Examples/Concurrency/`](Examples/Concurrency/) — actor wrapper, `Task.detached`, `async let` across distinct actors, and debounced search-as-you-type in one binary.

  ```
  cd Examples/Concurrency
  swift run FuseConcurrency
  ```

- [`Examples/Highlighting/`](Examples/Highlighting/) — slicing `FuseMatch.indices` to wrap matched runs in `[brackets]` (the same pattern works for ANSI, HTML `<mark>`, or `AttributedString`).

  ```
  cd Examples/Highlighting
  swift run FuseHighlighting
  ```

## Syncing with upstream

[`docs/SYNC.md`](docs/SYNC.md) documents the sync procedure with a worked example.

## Release gate

The release gate runs strict-concurrency tests plus the cross-runtime parity check against `../fuse-js`:

```
make release
```

Set `FUSE_JS_PATH` to override the default sibling-checkout location.

## Contributing

`CONTRIBUTING.md` will land in a follow-up. In the meantime, issues and PRs are welcome on [krisk/fuse-swift](https://github.com/krisk/fuse-swift).

## License

[Apache License 2.0](LICENSE). Matches the upstream fuse.js license.
