import Foundation

/// `Fuse` is a namespace enum holding both the generic searcher type
/// (`Fuse.Search<Element>`) and the static helpers (`Fuse.version`, etc.).
/// See plan section "Public API namespace shape" for the rationale (Swift
/// generic classes can't host both an instance API and statics without
/// forcing callers to specialize a type parameter the statics don't use).
public enum Fuse {
    public static let version: String = "2.0.0-dev"
}

extension Fuse {
    /// Generic searcher. v1 supports `Fuse.Search<String>` for string-array
    /// search (this phase) and `Fuse.Search<Element>` for keyed object search
    /// (lands in phase 8). The class is intentionally non-`Sendable`; it owns
    /// mutable state and uses synchronous methods. See plan section
    /// "Sendable scope".
    public final class Search<Element> {
        private let docs: [Element]
        private let options: FuseOptions<Element>
        // Per-doc field-length norm for the string-array path; nil entries
        // correspond to blank docs that are excluded from indexed records.
        private let stringNorms: [Double?]

        public init(_ docs: [Element], options: FuseOptions<Element>) throws {
            self.docs = docs
            self.options = options

            if Element.self == String.self {
                let normer = FieldNorm(weight: options.fieldNormWeight)
                self.stringNorms = docs.map { doc -> Double? in
                    let s = doc as! String
                    return Trim.isBlank(s) ? nil : normer.get(s)
                }
            } else {
                // Phase 8 will populate this branch via FuseIndex.
                self.stringNorms = Array(repeating: nil, count: docs.count)
            }
        }

        /// Search for `pattern` across the collection.
        ///
        /// Per the plan's empty-query contract: blank / whitespace queries
        /// return one `FuseResult` per doc in `refIndex` order with
        /// `score = nil` and `matches = nil` (regardless of `includeScore` /
        /// `includeMatches`). `limit > 0` slices the result.
        public func search(_ pattern: String, limit: Int? = nil) -> [FuseResult<Element>] {
            if Trim.isBlank(pattern) {
                var results = docs.enumerated().map { idx, item in
                    FuseResult<Element>(item: item, refIndex: idx, score: nil, matches: nil)
                }
                if let lim = limit, lim > 0 {
                    results = Array(results.prefix(lim))
                }
                return results
            }

            guard Element.self == String.self else {
                // Object collections are not supported until phase 8.
                return []
            }

            let bitapOptions = BitapSearchOptions(
                location: options.location,
                distance: options.distance,
                threshold: options.threshold,
                findAllMatches: options.findAllMatches,
                minMatchCharLength: options.minMatchCharLength,
                includeMatches: options.includeMatches,
                ignoreLocation: options.ignoreLocation,
                isCaseSensitive: options.isCaseSensitive,
                ignoreDiacritics: options.ignoreDiacritics
            )
            let searcher = BitapSearch(pattern: pattern, options: bitapOptions)

            // Internal collection of pre-format results.
            var internalResults: [InternalStringResult<Element>] = []
            for (idx, doc) in docs.enumerated() {
                let text = doc as! String
                if Trim.isBlank(text) { continue }
                let bitapResult = searcher.searchIn(text: text)
                if !bitapResult.isMatch { continue }

                let norm = stringNorms[idx] ?? 1.0
                let finalScore = ComputeScore.compute(
                    matches: [.init(score: bitapResult.score, norm: norm, weight: 1.0)],
                    ignoreFieldNorm: options.ignoreFieldNorm
                )

                internalResults.append(InternalStringResult(
                    item: doc,
                    refIndex: idx,
                    finalScore: finalScore,
                    bitapScore: bitapResult.score,
                    norm: norm,
                    value: text,
                    indices: bitapResult.indices
                ))
            }

            if options.shouldSort {
                if let sortFn = options.sortFn {
                    internalResults.sort { a, b in
                        sortFn(a.sortItem(), b.sortItem()) == .orderedAscending
                    }
                } else {
                    internalResults.sort { a, b in
                        if a.finalScore != b.finalScore { return a.finalScore < b.finalScore }
                        return a.refIndex < b.refIndex
                    }
                }
            }

            if let lim = limit, lim > 0, internalResults.count > lim {
                internalResults = Array(internalResults.prefix(lim))
            }

            return internalResults.map { r in
                var matches: [FuseMatch]? = nil
                if options.includeMatches {
                    matches = [FuseMatch(
                        indices: r.indices ?? [],
                        key: nil,
                        refIndex: nil,
                        value: r.value
                    )]
                }
                return FuseResult<Element>(
                    item: r.item,
                    refIndex: r.refIndex,
                    score: options.includeScore ? r.finalScore : nil,
                    matches: matches
                )
            }
        }
    }
}

/// Internal pre-format record for a string-list match. Phase 7+ will replace
/// this with `FuseIndex<Element>` + a generic `InternalResult`.
private struct InternalStringResult<Element> {
    let item: Element
    let refIndex: Int
    let finalScore: Double
    let bitapScore: Double
    let norm: Double
    let value: String
    let indices: [FuseRange]?

    func sortItem() -> FuseSortItem<Element> {
        let m = FuseSortMatch(
            key: nil,
            value: value,
            score: bitapScore,
            indices: indices
        )
        return FuseSortItem(
            item: item,
            refIndex: refIndex,
            score: finalScore,
            matches: [m]
        )
    }
}
