# Concurrency

`Fuse.Search` is `final class` and intentionally **not `Sendable`** — it
owns mutable index state and uses synchronous methods. `FuseOptions`,
`FuseResult`, and `FuseMatch` *are* `Sendable` (when `Element: Sendable`),
so the input and output sides cross isolation cleanly; only the searcher
instance is single-isolation.

This doc collects the canonical patterns for using fuse-swift in
concurrent contexts. The README has the two most common patterns
inline; everything else lives here.

## Pick your pattern

| Scenario | Pattern |
|---|---|
| Ad-hoc one-shot search; index built on the fly | [`Task.detached`](#task-detached-ad-hoc-one-shot) |
| Repeated searches over a long-lived corpus | [Actor wrapper](#actor-wrapper-repeated-searches) |
| Multiple distinct corpora, search all in parallel | [`async let` across actors](#async-let-parallel-across-corpora) |
| Search-as-you-type with debouncing and cancellation | [Debounced Task](#debounced-search-as-you-type) |
| Small corpus, UI thread can handle it | [Main-actor searcher](#main-actor-searcher-small-corpora) |
| Legacy GCD codebase, caller guarantees serial access | [GCD escape hatch](#legacy-gcd-codebases) |

There is **no useful pattern** for "parallelize many queries against the
same searcher." See [What not to do](#concurrent-batch-against-one-searcher) below.

## Task.detached (ad-hoc one-shot)

Use when the collection changes between calls, or search frequency is
low enough that index construction cost is acceptable.

```swift
let docs: [String] = ["apple", "orange", "banana"]
let opts = try FuseOptions<String>(includeScore: true)
let query = "ange"

let results = try await Task.detached(priority: .userInitiated) {
    let fuse = try Fuse.Search<String>(docs, options: opts)
    return fuse.search(query)
}.value
```

`docs`, `opts`, and `query` must all be `Sendable` to flow into the
detached task. The searcher itself is built inside the task and
discarded when it returns, so no `Sendable` constraint applies to it.

The index is rebuilt per call. For repeated searches over a stable
corpus, the actor pattern below pays for itself after the second call.

## Actor wrapper (repeated searches)

The canonical pattern. The actor's isolation guarantees serial access
to the non-`Sendable` searcher, and callers from any isolation can
`await` the actor's methods.

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

Mutators (`add`, `remove`, `removeAt`, `setCollection`) become actor
methods too — same pattern, same isolation guarantees.

## `async let` parallel across corpora

When the UI shows results from several distinct searchers (books +
movies + people) and you want them to run concurrently. Each `await`
targets a different actor instance, so the calls actually run in
parallel rather than serializing.

```swift
let q = "remy"
async let books  = booksService.search(q)
async let movies = moviesService.search(q)
async let people = peopleService.search(q)

let (b, m, p) = await (books, movies, people)
print("books=\(b.count) movies=\(m.count) people=\(p.count)")
```

The parallelism *only* shows up across distinct actors. Multiple
`async let` calls against the *same* actor serialize on its isolation
and run no faster than a sync loop.

## Debounced search-as-you-type

Most-requested pattern for iOS apps. The user types; we wait briefly,
fire one search, cancel any in-flight search if they type again.

```swift
import Combine
import Fuse

@MainActor
final class SearchViewModel: ObservableObject {
    @Published private(set) var results: [FuseResult<Book>] = []

    private let service: BookSearchService
    private var pendingSearch: Task<Void, Never>?

    init(service: BookSearchService) { self.service = service }

    func queryChanged(to query: String) {
        pendingSearch?.cancel()
        pendingSearch = Task { [service] in
            // Debounce: sleep throws CancellationError if the user types
            // again before this fires.
            do {
                try await Task.sleep(nanoseconds: 200_000_000)  // 200 ms
            } catch {
                return
            }
            let r = await service.search(query)
            // Second cancellation check: the user may have typed again
            // while the actor was working.
            if Task.isCancelled { return }
            self.results = r
        }
    }
}
```

Two cancellation points: the sleep throws on cancel (the debounced
query never fires), and the post-search check drops the result if the
user typed again while the actor was working.

`Task.sleep(nanoseconds:)` works on all platforms fuse-swift supports
(iOS 15+). On iOS 16+ / macOS 13+ you can use
`try await Task.sleep(for: .milliseconds(200))` for readability.

## Main-actor searcher (small corpora)

Sometimes the right answer is "don't hop off main." If the corpus is
small enough that a single search takes well under a frame budget
(roughly: a few hundred docs with simple keys), keeping the searcher on
the main actor avoids the actor-hop overhead and lets SwiftUI bind
directly to the results without `await`.

```swift
@MainActor
final class MainActorSearch {
    private let fuse: Fuse.Search<Book>

    init(books: [Book]) throws {
        self.fuse = try Fuse.Search<Book>(
            books,
            options: try FuseOptions<Book>(
                includeScore: true,
                keys: [try FuseKey<Book>(path: "title")]
            )
        )
    }

    func search(_ q: String) -> [FuseResult<Book>] { fuse.search(q) }
}
```

Tradeoff: the search runs on the main thread and blocks UI for the
duration. Profile before committing to this pattern — see [Profiling
guidance](#profiling-guidance) below.

## Legacy GCD codebases

`Fuse.Search` works behind `DispatchQueue.global().async` as long as
the calling code already guarantees no concurrent access (typically:
the searcher is touched only from one serial queue).

```swift
let searchQueue = DispatchQueue(label: "fuse.search", qos: .userInitiated)
searchQueue.async {
    let r = self.fuse.search(query)
    DispatchQueue.main.async { self.handleResults(r) }
}
```

Under `-strict-concurrency=complete` the compiler will require one of
the actor / Task patterns above instead; the GCD path stays open for
codebases that haven't migrated to Swift Concurrency.

## What not to do

### `@unchecked Sendable` wrappers around `Fuse.Search`

```swift
// Don't do this.
extension Fuse.Search: @unchecked Sendable {}
```

This silences the compiler and lets you share a searcher across actors,
but it doesn't add any synchronization. `Fuse.Search` mutates internal
state during `add` / `remove` / `setCollection` and also touches the
searcher cache on every `search` call. Concurrent access produces
undefined behavior — data races, torn reads, crashes during mutation.
The non-`Sendable` declaration is load-bearing; respect it.

### Sharing one searcher across distinct actors

Even without `@unchecked Sendable`, you can sometimes pass a `Fuse.Search`
into an actor's init and then pass the same instance into another actor
via a `nonisolated` API. Don't. Each actor will assume it has exclusive
access; the next mutation surfaces a race.

If you need multiple search frontends over the same corpus, give each
its own `Fuse.Search` — they can share `docs: [Element]` (which *is*
`Sendable` when `Element: Sendable`) and rebuild their indexes in
parallel via `Task.detached`.

### Concurrent batch against one searcher

`TaskGroup` over many queries against a single actor-wrapped searcher
looks like it should parallelize. It doesn't — all calls serialize on
the actor's isolation, so the observable timeline is identical to a
sync `for` loop. The only thing you gain is async-machinery overhead.

If you genuinely need parallel search across the same corpus (rare —
search is usually fast enough that this isn't a bottleneck), spin up
multiple `Task.detached` instances each building their own
`Fuse.Search`. Memory cost scales with the parallelism factor.

## Profiling guidance

Before pushing search off the main thread, measure. A typical small
keyed search (a few hundred docs, two or three keys, threshold 0.6)
takes a fraction of a millisecond. The main-actor pattern is the right
choice there; an actor hop costs more than the search.

A few heuristics:

- **< 1 ms per search**: main-actor is fine. Actor-hop overhead would
  dominate.
- **1–5 ms per search**: borderline. UI responsiveness depends on how
  often you search (every keystroke vs. on-submit) and what else
  happens on main.
- **> 5 ms per search**: push off-main. Actor wrapper is the default;
  add debouncing if it's search-as-you-type.

Use `os_signpost` (or `OSLog`'s signpost API) to measure under realistic
input loads. The instrumented build will reveal whether the search call
itself or the actor hop dominates the latency budget.

## Examples

[`Examples/Concurrency/`](../Examples/Concurrency/) is a runnable
demo that exercises the actor wrapper, `Task.detached` one-shot,
`async let` across distinct actors, and the debounced search-as-you-
type pattern in a single binary. From a checkout:

```
cd Examples/Concurrency
swift run FuseConcurrency
```

Sample output:

```
[actor]     2 hit(s) for 'stve' → ["The Lock Artist", "Pride and Prejudice"]
[detached]  3 hit(s) for 'ange' → ["orange", "mango", "banana"]
[async let] books=2 movies=1 people=1 (wall: 0.19 ms)
[debounced] 2 hit(s) for final query 'stv' → ["The Lock Artist", "Pride and Prejudice"]
```

## Further reading

- The README's [Concurrency](../README.md#concurrency) section is the
  basics recap.
- [Swift Concurrency book](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/)
  for the underlying primitives (`Task`, actors, `Sendable`, structured
  concurrency).
- [Swift Evolution SE-0337](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0337-async-actor-isolation.md)
  for the actor-hop cost model that informs the [main-actor
  pattern](#main-actor-searcher-small-corpora) above.
