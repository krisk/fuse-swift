import Fuse
import Foundation

// fuse-swift concurrency demo. Runs through the four patterns from
// docs/CONCURRENCY.md in a single binary, printing timestamped output
// so the actor / async-let / detached behavior is observable at the
// command line.
//
// Run from this directory:
//   swift run FuseConcurrency
//
// What each pattern prints:
//   [actor]     a single search on an actor-wrapped Fuse.Search<Book>
//   [detached]  one-shot search built and discarded inside Task.detached
//   [async let] three concurrent searches across distinct actors
//   [debounced] simulated search-as-you-type with task cancellation

// MARK: - Fixtures

struct Book: Codable, Sendable { let title: String; let author: String }
struct Movie: Codable, Sendable { let title: String; let year: Int }
struct Person: Codable, Sendable { let name: String; let role: String }

let books: [Book] = [
    Book(title: "The Lock Artist",  author: "Steve Hamilton"),
    Book(title: "Old Man's War",    author: "John Scalzi"),
    Book(title: "HTML5",            author: "Remy Sharp"),
    Book(title: "Pride and Prejudice", author: "Jane Austen"),
]
let movies: [Movie] = [
    Movie(title: "Ratatouille",       year: 2007),
    Movie(title: "Spirited Away",     year: 2001),
    Movie(title: "The Steve Job Story", year: 2015),
]
let people: [Person] = [
    Person(name: "Steve McQueen",  role: "Actor"),
    Person(name: "Remy Sharp",     role: "Author"),
    Person(name: "Jane Goodall",   role: "Primatologist"),
]

// MARK: - Actor services (Patterns 1 + 3)

actor BookSearchService {
    private let fuse: Fuse.Search<Book>
    init(_ books: [Book]) throws {
        self.fuse = try Fuse.Search<Book>(
            books,
            options: try FuseOptions<Book>(
                includeScore: true,
                keys: [
                    try FuseKey<Book>(path: "title"),
                    try FuseKey<Book>(path: "author"),
                ]
            )
        )
    }
    func search(_ q: String) -> [FuseResult<Book>] { fuse.search(q) }
}

actor MovieSearchService {
    private let fuse: Fuse.Search<Movie>
    init(_ movies: [Movie]) throws {
        self.fuse = try Fuse.Search<Movie>(
            movies,
            options: try FuseOptions<Movie>(
                includeScore: true,
                keys: [try FuseKey<Movie>(path: "title")]
            )
        )
    }
    func search(_ q: String) -> [FuseResult<Movie>] { fuse.search(q) }
}

actor PersonSearchService {
    private let fuse: Fuse.Search<Person>
    init(_ people: [Person]) throws {
        self.fuse = try Fuse.Search<Person>(
            people,
            options: try FuseOptions<Person>(
                includeScore: true,
                keys: [try FuseKey<Person>(path: "name")]
            )
        )
    }
    func search(_ q: String) -> [FuseResult<Person>] { fuse.search(q) }
}

// MARK: - Driver

@main
struct App {
    static func main() async throws {
        let bookService = try BookSearchService(books)

        // Pattern 1: actor wrapper, single search.
        do {
            let results = await bookService.search("stve")
            print("[actor]     \(results.count) hit(s) for 'stve' →",
                  results.map { $0.item.title })
        }

        // Pattern 2: Task.detached one-shot.
        do {
            let docs = ["apple", "orange", "banana", "pear", "grape", "kiwi", "mango"]
            let opts = try FuseOptions<String>(includeScore: true)
            let r = try await Task.detached(priority: .userInitiated) {
                let fuse = try Fuse.Search<String>(docs, options: opts)
                return fuse.search("ange", limit: 3)
            }.value
            print("[detached]  \(r.count) hit(s) for 'ange' →",
                  r.map { $0.item })
        }

        // Pattern 3: async let across distinct actors. Each await targets
        // a different actor, so all three searches actually run in
        // parallel rather than serializing.
        do {
            let movieService = try MovieSearchService(movies)
            let personService = try PersonSearchService(people)

            let start = Date()
            async let b = bookService.search("steve")
            async let m = movieService.search("steve")
            async let p = personService.search("steve")
            let (bb, mm, pp) = await (b, m, p)
            let elapsed = Date().timeIntervalSince(start) * 1000
            print(String(
                format: "[async let] books=%d movies=%d people=%d (wall: %.2f ms)",
                bb.count, mm.count, pp.count, elapsed))
        }

        // Pattern 4: debounced search-as-you-type, simulated. Fires three
        // keystrokes 50 ms apart; the first two get cancelled mid-debounce
        // (200 ms wait), only the third survives to actually search.
        do {
            let debouncer = SearchDebouncer(service: bookService)
            await debouncer.simulate(queries: ["s", "st", "stv"], typingIntervalMs: 50)
            try await Task.sleep(nanoseconds: 300_000_000)  // let the last search settle
            let final = await debouncer.lastResults
            print("[debounced] \(final.count) hit(s) for final query 'stv' →",
                  final.map { $0.item.title })
        }
    }
}

// MARK: - Pattern 4: debouncer with task cancellation

/// Holds an in-flight task and cancels it on every new query, only
/// firing the search if the user pauses long enough.
actor SearchDebouncer {
    private let service: BookSearchService
    private var pending: Task<Void, Never>?
    private(set) var lastResults: [FuseResult<Book>] = []

    init(service: BookSearchService) { self.service = service }

    func simulate(queries: [String], typingIntervalMs: UInt64) async {
        for q in queries {
            kick(query: q)
            try? await Task.sleep(nanoseconds: typingIntervalMs * 1_000_000)
        }
    }

    private func kick(query: String) {
        pending?.cancel()
        // Capture-list: actor `self` and the actor `service`. Both are
        // Sendable (actors), so capturing them in a Task is clean.
        let service = service
        pending = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 200_000_000)  // debounce
            } catch {
                return
            }
            let r = await service.search(query)
            if Task.isCancelled { return }
            await self?.setResults(r)
        }
    }

    private func setResults(_ r: [FuseResult<Book>]) {
        self.lastResults = r
    }
}
