import Foundation

/// `Fuse` is a namespace enum holding both the generic searcher type
/// (`Fuse.Search<Element>`) and the static helpers (`Fuse.version`, etc.).
/// See plan section "Public API namespace shape" for the rationale (Swift
/// generic classes can't host both an instance API and statics without
/// forcing callers to specialize a type parameter the statics don't use).
public enum Fuse {
    public static let version: String = "2.0.0-dev"

    /// Build an index from `docs` using the given `keys`. Mirrors
    /// `Fuse.createIndex` at `../fuse-js/src/tools/FuseIndex.ts:251-261`.
    /// The returned `FuseIndex` can be passed to `Fuse.Search(_:options:index:)`
    /// to skip re-indexing on the next searcher construction.
    public static func createIndex<Element>(
        _ keys: [FuseKey<Element>],
        _ docs: [Element],
        options: FuseIndexOptions<Element> = FuseIndexOptions<Element>()
    ) throws -> FuseIndex<Element> {
        let index = FuseIndex<Element>(
            keys: keys,
            getFn: options.getFn,
            fieldNormWeight: options.fieldNormWeight
        )
        index.setSources(docs)
        try index.create()
        return index
    }

    /// Parse a JSON-serialized index back into a `FuseIndex<Element>`.
    /// Mirrors `Fuse.parseIndex` at `../fuse-js/src/tools/FuseIndex.ts:263-275`.
    ///
    /// Live accessors are **not** rebound here — the parsed index has no
    /// accessor binding. Callers pass this index to
    /// `Fuse.Search(_:options:index:)`, which validates keys-shape parity
    /// against the user-supplied `options.keys` per Reviewer Question 1.
    public static func parseIndex<Element>(
        _ data: Data,
        options: FuseIndexOptions<Element> = FuseIndexOptions<Element>()
    ) throws -> FuseIndex<Element> {
        let payload = try JSONDecoder().decode(SerializedIndex.self, from: data)
        let rehydratedKeys = try payload.keys.map { sk -> FuseKey<Element> in
            try FuseKey<Element>(rehydratedFrom: sk)
        }
        let index = FuseIndex<Element>(
            keys: rehydratedKeys,
            getFn: options.getFn,
            fieldNormWeight: options.fieldNormWeight
        )
        index.setRecords(payload.records.map(IndexRecord.init))
        return index
    }
}

extension Fuse {
    /// Generic searcher. v1 supports `Fuse.Search<String>` for string-array
    /// search and `Fuse.Search<Element>` for keyed object search (phase 8).
    /// The class is intentionally non-`Sendable`; it owns mutable index
    /// state and uses synchronous methods. See plan section "Sendable scope".
    public final class Search<Element> {
        private let docs: [Element]
        private let options: FuseOptions<Element>
        private let myIndex: FuseIndex<Element>

        /// Construct a searcher over `docs`. When `index` is supplied, it is
        /// copy-on-adopted (per Reviewer Question 1's contract: the user's
        /// instance is never mutated by the searcher's lifecycle) and used
        /// in place of building a fresh one. `options.keys` shape must match
        /// the supplied index's keys (count + id + src + weight per slot).
        public init(
            _ docs: [Element],
            options: FuseOptions<Element>,
            index: FuseIndex<Element>? = nil
        ) throws {
            self.docs = docs
            self.options = options

            if let provided = index {
                try Search.validateSuppliedIndex(provided, against: options.keys)
                self.myIndex = provided.copy()
            } else {
                let built = FuseIndex<Element>(
                    keys: options.keys,
                    getFn: options.getFn,
                    fieldNormWeight: options.fieldNormWeight
                )
                built.setSources(docs)
                try built.create()
                self.myIndex = built
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

            let searcher = BitapSearch(pattern: pattern, options: bitapOptions())

            var internalResults: [InternalResult<Element>] = []
            for record in myIndex.records {
                switch record.kind {
                case .stringRecord(let value, let norm):
                    if let r = searchStringRecord(
                        value: value,
                        norm: norm,
                        docIndex: record.i,
                        searcher: searcher
                    ) {
                        internalResults.append(r)
                    }
                case .objectRecord(let entries):
                    if let r = searchObjectRecord(
                        entries: entries,
                        docIndex: record.i,
                        searcher: searcher
                    ) {
                        internalResults.append(r)
                    }
                }
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
                    matches = r.matches.compactMap { m in
                        guard let idx = m.indices, !idx.isEmpty else { return nil }
                        return FuseMatch(
                            indices: idx,
                            key: m.key,
                            refIndex: m.refIndex,
                            value: m.value
                        )
                    }
                }
                return FuseResult<Element>(
                    item: r.item,
                    refIndex: r.refIndex,
                    score: options.includeScore ? r.finalScore : nil,
                    matches: matches
                )
            }
        }

        // ── helpers ───────────────────────────────────────────────────────

        private func bitapOptions() -> BitapSearchOptions {
            BitapSearchOptions(
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
        }

        private func searchStringRecord(
            value: String,
            norm: Double,
            docIndex: Int,
            searcher: BitapSearch
        ) -> InternalResult<Element>? {
            let r = searcher.searchIn(text: value)
            if !r.isMatch { return nil }
            let scoreInput = ComputeScore.MatchInput(score: r.score, norm: norm, weight: 1.0)
            let finalScore = ComputeScore.compute(
                matches: [scoreInput],
                ignoreFieldNorm: options.ignoreFieldNorm
            )
            let match = InternalMatch(
                score: r.score,
                value: value,
                indices: r.indices,
                key: nil,
                refIndex: nil,
                norm: norm,
                weight: 1.0
            )
            return InternalResult(
                item: docs[docIndex],
                refIndex: docIndex,
                finalScore: finalScore,
                matches: [match]
            )
        }

        private func searchObjectRecord(
            entries: [Int: IndexEntry],
            docIndex: Int,
            searcher: BitapSearch
        ) -> InternalResult<Element>? {
            var matches: [InternalMatch] = []
            var scoreInputs: [ComputeScore.MatchInput] = []

            for (slot, key) in options.keys.enumerated() {
                guard let entry = entries[slot] else { continue }
                switch entry {
                case .single(let sub):
                    let r = searcher.searchIn(text: sub.value)
                    if !r.isMatch { continue }
                    matches.append(InternalMatch(
                        score: r.score,
                        value: sub.value,
                        indices: r.indices,
                        key: key.source,
                        refIndex: nil,
                        norm: sub.norm,
                        weight: key.weight
                    ))
                    scoreInputs.append(.init(
                        score: r.score,
                        norm: sub.norm,
                        weight: key.weight
                    ))
                case .multiple(let arr):
                    for sub in arr {
                        let r = searcher.searchIn(text: sub.value)
                        if !r.isMatch { continue }
                        matches.append(InternalMatch(
                            score: r.score,
                            value: sub.value,
                            indices: r.indices,
                            key: key.source,
                            refIndex: sub.arrayIndex,
                            norm: sub.norm,
                            weight: key.weight
                        ))
                        scoreInputs.append(.init(
                            score: r.score,
                            norm: sub.norm,
                            weight: key.weight
                        ))
                    }
                }
            }

            if matches.isEmpty { return nil }
            let finalScore = ComputeScore.compute(
                matches: scoreInputs,
                ignoreFieldNorm: options.ignoreFieldNorm
            )
            return InternalResult(
                item: docs[docIndex],
                refIndex: docIndex,
                finalScore: finalScore,
                matches: matches
            )
        }

        /// Compare `options.keys` to the supplied index's stored keys for
        /// `(count, id, src, weight)` parity. Mismatch throws so a user
        /// can't silently feed the wrong index into a searcher whose options
        /// describe a different schema. See plan's Reviewer Question 1.
        private static func validateSuppliedIndex(
            _ index: FuseIndex<Element>,
            against optionsKeys: [FuseKey<Element>]
        ) throws {
            let parsed = index.keyStore.keys
            if parsed.count != optionsKeys.count {
                throw FuseError.parsedIndexKeyMismatch(
                    .countMismatch(parsed: parsed.count, options: optionsKeys.count)
                )
            }
            for (slot, (p, o)) in zip(parsed, optionsKeys).enumerated() {
                let pid = KeyStore<Element>.keyId(for: p.source)
                let oid = KeyStore<Element>.keyId(for: o.source)
                if pid != oid {
                    throw FuseError.parsedIndexKeyMismatch(
                        .idMismatch(slot: slot, parsed: pid, options: oid)
                    )
                }
                if p.source != o.source {
                    throw FuseError.parsedIndexKeyMismatch(
                        .sourceShapeMismatch(slot: slot, parsed: p.source, options: o.source)
                    )
                }
                if abs(p.weight - o.weight) > 1e-12 {
                    throw FuseError.parsedIndexKeyMismatch(
                        .weightMismatch(slot: slot, parsed: p.weight, options: o.weight)
                    )
                }
            }
        }
    }
}

/// Internal pre-format result: the unsorted, unformatted matches collected
/// for one document. Translates to a `FuseResult` at the end of `search`.
private struct InternalResult<Element> {
    let item: Element
    let refIndex: Int
    let finalScore: Double
    let matches: [InternalMatch]

    func sortItem() -> FuseSortItem<Element> {
        let sortMatches = matches.map { m in
            FuseSortMatch(
                key: m.key,
                value: m.value,
                score: m.score,
                indices: m.indices
            )
        }
        return FuseSortItem(
            item: item,
            refIndex: refIndex,
            score: finalScore,
            matches: sortMatches
        )
    }
}

/// Internal per-match record. `key` is nil for string-list matches; `refIndex`
/// is nil for non-array entries.
private struct InternalMatch {
    let score: Double
    let value: String
    let indices: [FuseRange]?
    let key: KeySource?
    let refIndex: Int?
    let norm: Double
    let weight: Double
}
