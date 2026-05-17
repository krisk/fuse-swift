import Fuse
import Foundation

// Cross-platform highlighting demo. Wraps each matched UTF-16 range in
// [brackets] so the matched portions are visible at the command line.
//
// `FuseMatch.indices` are UTF-16 offsets in the TRANSFORMED text — the
// string fuse-swift actually fed to bitap after applying case-fold and
// (when enabled) diacritic-strip. For inputs whose transformed length
// equals the original length (ASCII text under default options, or any
// text with `isCaseSensitive: true, ignoreDiacritics: false`), the
// offsets map 1:1 to the original string and the `highlight(_:ranges:)`
// helper below works directly on the source text.
//
// For inputs that change length under the transforms (Turkish dotted İ
// with case-folding; precomposed-vs-decomposed text with
// `ignoreDiacritics: true`; German ẞ getting expanded to "ss" during
// diacritic strip), the offsets refer to the transformed string, not
// the original. Compose your own transform-and-track helper if that
// applies to your inputs.

struct Book: Codable, Sendable {
    let title: String
    let author: String
}

let books = [
    Book(title: "The Lock Artist",      author: "Steve Hamilton"),
    Book(title: "Old Man's War",        author: "John Scalzi"),
    Book(title: "HTML5",                author: "Remy Sharp"),
    Book(title: "Pride and Prejudice",  author: "Jane Austen"),
    Book(title: "Animal Farm",          author: "George Orwell"),
]

let options = try FuseOptions<Book>(
    includeMatches: true,
    includeScore: true,
    keys: [
        try FuseKey<Book>("title",  keyPath: \Book.title),
        try FuseKey<Book>("author", keyPath: \Book.author),
    ]
)
let fuse = try Fuse.Search<Book>(books, options: options)

for query in ["Lock", "stve", "remy", "Old Man"] {
    print("\n== query: \"\(query)\" ==")
    let results = fuse.search(query, limit: 3)
    if results.isEmpty {
        print("  (no matches)")
        continue
    }
    for r in results {
        let score = String(format: "%.4f", r.score!)
        print("  [\(r.refIndex)] \(r.item.title) / \(r.item.author)  (score \(score))")
        for m in r.matches ?? [] {
            let valueString = m.value ?? ""
            let highlighted = highlight(valueString, ranges: m.indices)
            let keyLabel = m.key.map(describeKey) ?? "—"
            print("        \(keyLabel): \(highlighted)")
        }
    }
}

// MARK: - Helpers

/// Wraps each `[start, end]` inclusive UTF-16 range from a `FuseMatch`
/// in `[brackets]` and returns the resulting string.
///
/// `value` is the original matched text. The function operates on the
/// UTF-16 view, so it composes correctly with the offsets fuse-swift
/// emits — but it does NOT account for length-changing transforms (see
/// the file header).
func highlight(_ value: String, ranges: [FuseRange]) -> String {
    guard !ranges.isEmpty else { return value }
    let units = Array(value.utf16)
    var out = ""
    var cursor = 0
    for r in ranges {
        // Skip any range that overlaps a previously-emitted range. The
        // ranges fuse-swift emits are already non-overlapping and sorted
        // (merged via `MergeIndices`), so this is a defensive guard
        // against hand-constructed inputs rather than a real path.
        guard r.start >= cursor else { continue }
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

func describeKey(_ key: KeySource) -> String {
    switch key {
    case .string(let s): return s
    case .array(let a): return "[\(a.joined(separator: ", "))]"
    }
}
