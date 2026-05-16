import Fuse
import Foundation

// fuse-swift CLI demo. Two scenarios:
//   1. String-list search (Fuse.Search<String>) with includeScore.
//   2. Keyed object search (Fuse.Search<Book>) with includeMatches.
//
// Run from this directory:
//   swift run FuseCLI            # default queries below
//   swift run FuseCLI <query>    # run that query against both fixtures

let userQuery = CommandLine.arguments.dropFirst().first

// ── 1. String-list search ─────────────────────────────────────────────

let fruits = ["apple", "orange", "banana", "pear", "grape", "kiwi", "mango", "plum"]
let stringOptions = try FuseOptions<String>(includeScore: true)
let stringSearcher = try Fuse.Search<String>(fruits, options: stringOptions)

let stringQuery = userQuery ?? "ange"
print("== String-list search ==")
print("Query: \"\(stringQuery)\"  (corpus: \(fruits.count) fruits)")
let stringResults = stringSearcher.search(stringQuery, limit: 5)
if stringResults.isEmpty {
    print("  (no matches)")
} else {
    for r in stringResults {
        let score = r.score.map { String(format: "%.4f", $0) } ?? "—"
        print("  [\(r.refIndex)] \(r.item)  score=\(score)")
    }
}

// ── 2. Keyed object search ────────────────────────────────────────────

struct Book: Codable, Sendable {
    let title: String
    let author: Author
}
struct Author: Codable, Sendable {
    let firstName: String
    let lastName: String
}

let books: [Book] = [
    Book(title: "Old Man's War", author: .init(firstName: "John", lastName: "Scalzi")),
    Book(title: "The Lock Artist", author: .init(firstName: "Steve", lastName: "Hamilton")),
    Book(title: "The Great Gatsby", author: .init(firstName: "F. Scott", lastName: "Fitzgerald")),
    Book(title: "Pride and Prejudice", author: .init(firstName: "Jane", lastName: "Austen")),
    Book(title: "Animal Farm", author: .init(firstName: "George", lastName: "Orwell")),
]

// Mixed-form keys: `.keyPath` for `title`, `.path` (dotted JSON path) for
// `author.firstName` — the latter exercises the default Encodable walker
// and is the form most users will reach for first.
let bookKeys = [
    try FuseKey<Book>("title", keyPath: \Book.title, weight: 0.7),
    try FuseKey<Book>(path: "author.firstName", weight: 0.3),
]
let bookOptions = try FuseOptions<Book>(
    includeMatches: true,
    includeScore: true,
    keys: bookKeys
)
let bookSearcher = try Fuse.Search<Book>(books, options: bookOptions)

let bookQuery = userQuery ?? "stve"
print("\n== Keyed object search ==")
print("Query: \"\(bookQuery)\"  (corpus: \(books.count) books)")
let bookResults = bookSearcher.search(bookQuery, limit: 3)
if bookResults.isEmpty {
    print("  (no matches)")
} else {
    for r in bookResults {
        let score = r.score.map { String(format: "%.4f", $0) } ?? "—"
        print("  [\(r.refIndex)] \(r.item.title) / \(r.item.author.firstName) \(r.item.author.lastName)  score=\(score)")
        if let matches = r.matches {
            for m in matches {
                let keyDesc = m.key.map(describeKey) ?? "—"
                let value = m.value ?? "(nil)"
                print("       match key=\(keyDesc) value=\"\(value)\" ranges=\(m.indices.map { "[\($0.start)-\($0.end)]" }.joined(separator: ", "))")
            }
        }
    }
}

func describeKey(_ key: KeySource) -> String {
    switch key {
    case .string(let s): return s
    case .array(let a): return "[\(a.joined(separator: ", "))]"
    }
}
