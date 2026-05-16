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

    /// One-shot pattern-vs-text fuzzy match. Mirrors `Fuse.match` at
    /// `../fuse-js/src/entry.ts:15-26`. Skips the full Search / FuseIndex
    /// pipeline; suitable for ad-hoc string comparisons where there is no
    /// document corpus to index.
    ///
    /// On no match, returns `FuseMatchOutcome(isMatch: false, score: 1)`.
    /// On exact match, score is `0`. `indices` is non-nil only when
    /// `options.includeMatches` is true, matching upstream's optional-field
    /// emission contract.
    public static func match(
        _ pattern: String,
        in text: String,
        options: FuseMatchOptions = FuseMatchOptions()
    ) -> FuseMatchOutcome {
        let bitap = BitapSearch(
            pattern: pattern,
            options: BitapSearchOptions(
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
        )
        let r = bitap.searchIn(text: text)
        return FuseMatchOutcome(
            isMatch: r.isMatch,
            score: r.score,
            indices: options.includeMatches ? (r.indices ?? []) : nil
        )
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
    /// search and `Fuse.Search<Element>` for keyed object search. The class
    /// is intentionally non-`Sendable`; it owns mutable index / cache state
    /// and uses synchronous methods. See plan section "Sendable scope".
    public final class Search<Element> {
        private var docs: [Element]
        private let options: FuseOptions<Element>
        private var myIndex: FuseIndex<Element>

        // Searcher cache. Per upstream `_lastQuery` / `_lastSearcher`:
        // identical-pattern re-queries reuse the BitapSearch instance, and
        // mutations (setCollection / add / removeAt / remove with matches)
        // invalidate. Internal so cache-invalidation tests can observe
        // identity (===) without exposing the cache on the public surface.
        var cachedQuery: String?
        var cachedSearcher: BitapSearch?

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

        // ── public read surface ───────────────────────────────────────────

        /// Returns the live `FuseIndex` backing this searcher. Mirrors
        /// upstream `getIndex()` at `../fuse-js/src/core/index.ts:207-209`.
        /// Mutators on the returned index would desynchronize from `docs`;
        /// callers wanting persistence should use `index.toJSON()`.
        public func getIndex() -> FuseIndex<Element> {
            myIndex
        }

        /// Search for `pattern` across the collection.
        ///
        /// Per the plan's empty-query contract: blank / whitespace queries
        /// return one `FuseResult` per doc in `refIndex` order with
        /// `score = nil` and `matches = nil` (regardless of `includeScore` /
        /// `includeMatches`). `limit > 0` slices the result.
        ///
        /// When `limit > 0` and the query is non-blank, the heap-based
        /// top-K path runs **regardless of `shouldSort: false`** (parity
        /// with `../fuse-js/src/core/index.ts:236-263`). The heap selects
        /// the top-N candidates by score only; a custom `sortFn` only
        /// orders the extracted N, never affects which N are admitted.
        public func search(_ pattern: String, limit: Int? = nil) -> [FuseResult<Element>] {
            if Trim.isBlank(pattern) {
                var results = docs.enumerated().map { idx, item in
                    FuseResult<Element>(item: item, refIndex: idx, score: nil, matches: nil)
                }
                if let lim = limit, lim >= 0 {
                    results = Array(results.prefix(lim))
                }
                return results
            }

            let searcher = getSearcher(pattern: pattern)
            let useHeap = (limit ?? -1) > 0
            let collected: [InternalResult<Element>]

            if useHeap {
                collected = heapSearch(searcher: searcher, limit: limit!)
            } else {
                collected = linearSearch(searcher: searcher, limit: limit)
            }
            return formatResults(collected)
        }

        // ── mutators (synchronized docs / index / cache) ──────────────────

        /// Append `doc` to the collection. Atomic per Edge Cases #1:
        /// `myIndex.add` runs first; `docs` and the cache are only updated
        /// after the index succeeds. On `pathEncodingFailed`, every
        /// observable property is identical to its pre-call state.
        ///
        /// Cache always invalidates on success (parity with upstream
        /// `../fuse-js/src/core/index.ts:130-156`).
        public func add(_ doc: Element) throws {
            _ = try myIndex.add(doc, docIndex: docs.count)
            docs.append(doc)
            invalidateSearcherCache()
        }

        /// Remove docs matching `predicate`. Returns the removed docs in
        /// source order. Mirrors `../fuse-js/src/core/index.ts:158-183`.
        ///
        /// **No-op invariant**: when the predicate matches zero docs, the
        /// searcher cache is NOT invalidated (upstream gates invalidation
        /// inside `if (indicesToRemove.length)`). Tests at upstream
        /// `cache-invalidation.test.js:50` exercise this; the plan calls
        /// it out explicitly as a load-bearing invariant.
        @discardableResult
        public func remove(_ predicate: (Element, Int) -> Bool = { _, _ in false }) -> [Element] {
            var removed: [Element] = []
            var indicesToRemove: [Int] = []
            for (i, doc) in docs.enumerated() where predicate(doc, i) {
                removed.append(doc)
                indicesToRemove.append(i)
            }
            if indicesToRemove.isEmpty {
                return removed
            }
            let toRemove = Set(indicesToRemove)
            docs = docs.enumerated().compactMap { toRemove.contains($0.offset) ? nil : $0.element }
            myIndex.removeAll(indicesToRemove)
            invalidateSearcherCache()
            return removed
        }

        /// Remove the doc at `idx`. Throws `FuseError.invalidDocIndex` for
        /// out-of-range / negative input **before** any mutation, mirroring
        /// the post-fix upstream contract at `../fuse-js/src/core/index.ts:185-199`.
        /// Cache invalidates only after a successful removal.
        @discardableResult
        public func removeAt(_ idx: Int) throws -> Element {
            guard idx >= 0, idx < docs.count else {
                throw FuseError.invalidDocIndex(idx: idx)
            }
            let doc = docs.remove(at: idx)
            try myIndex.removeAt(idx)
            invalidateSearcherCache()
            return doc
        }

        /// Replace the entire collection. Atomic per Edge Cases #1: the
        /// replacement index is built / validated in a local first; the
        /// instance's docs / index / cache are only swapped after the new
        /// index is fully constructed.
        public func setCollection(_ docs: [Element], index: FuseIndex<Element>? = nil) throws {
            let newIndex: FuseIndex<Element>
            if let provided = index {
                try Search.validateSuppliedIndex(provided, against: options.keys)
                newIndex = provided.copy()
            } else {
                let built = FuseIndex<Element>(
                    keys: options.keys,
                    getFn: options.getFn,
                    fieldNormWeight: options.fieldNormWeight
                )
                built.setSources(docs)
                try built.create()
                newIndex = built
            }
            self.docs = docs
            self.myIndex = newIndex
            invalidateSearcherCache()
        }

        // ── private: search execution paths ───────────────────────────────

        private func linearSearch(
            searcher: BitapSearch,
            limit: Int?
        ) -> [InternalResult<Element>] {
            var results: [InternalResult<Element>] = []
            for record in myIndex.records {
                if let r = scoreRecord(record, searcher: searcher) {
                    results.append(r)
                }
            }
            if options.shouldSort {
                sortInternalResults(&results)
            }
            if let lim = limit, lim >= 0, results.count > lim {
                results = Array(results.prefix(lim))
            }
            return results
        }

        private func heapSearch(
            searcher: BitapSearch,
            limit: Int
        ) -> [InternalResult<Element>] {
            var heap = MaxHeap<InternalResult<Element>>(limit: limit) { $0.finalScore }
            for record in myIndex.records {
                guard let r = scoreRecord(record, searcher: searcher) else { continue }
                if heap.shouldInsert(score: r.finalScore) {
                    heap.insert(r)
                }
            }
            // The heap picks the top-N strictly by score; a custom `sortFn`
            // only re-orders the extracted N (parity with upstream
            // `extractSorted(sortFn)` at MaxHeap.ts:46-52 + index.ts:247).
            if let sortFn = options.sortFn {
                return heap.extractSorted { a, b in
                    sortFn(a.sortItem(), b.sortItem()) == .orderedAscending
                }
            }
            return heap.extractSorted { a, b in
                if a.finalScore != b.finalScore { return a.finalScore < b.finalScore }
                return a.refIndex < b.refIndex
            }
        }

        private func sortInternalResults(_ results: inout [InternalResult<Element>]) {
            if let sortFn = options.sortFn {
                results.sort { sortFn($0.sortItem(), $1.sortItem()) == .orderedAscending }
            } else {
                results.sort { a, b in
                    if a.finalScore != b.finalScore { return a.finalScore < b.finalScore }
                    return a.refIndex < b.refIndex
                }
            }
        }

        private func scoreRecord(
            _ record: IndexRecord,
            searcher: BitapSearch
        ) -> InternalResult<Element>? {
            switch record.kind {
            case .stringRecord(let value, let norm):
                return scoreStringRecord(
                    value: value, norm: norm, docIndex: record.i, searcher: searcher
                )
            case .objectRecord(let entries):
                return scoreObjectRecord(
                    entries: entries, docIndex: record.i, searcher: searcher
                )
            }
        }

        private func formatResults(
            _ internalResults: [InternalResult<Element>]
        ) -> [FuseResult<Element>] {
            internalResults.map { r in
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

        // ── searcher cache ────────────────────────────────────────────────

        private func getSearcher(pattern: String) -> BitapSearch {
            if cachedQuery == pattern, let s = cachedSearcher {
                return s
            }
            let s = BitapSearch(pattern: pattern, options: bitapOptions())
            cachedQuery = pattern
            cachedSearcher = s
            return s
        }

        private func invalidateSearcherCache() {
            cachedQuery = nil
            cachedSearcher = nil
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

        private func scoreStringRecord(
            value: String,
            norm: Double,
            docIndex: Int,
            searcher: BitapSearch
        ) -> InternalResult<Element>? {
            let r = searcher.searchIn(text: value)
            if !r.isMatch { return nil }
            // String-list path is keyless; passing `weight: nil` mirrors
            // upstream's `key ? key.weight : null` shape so the EPSILON
            // swap in ComputeScore stays off and an exact match scores 0.
            let scoreInput = ComputeScore.MatchInput(score: r.score, norm: norm, weight: nil)
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
                weight: nil
            )
            return InternalResult(
                item: docs[docIndex],
                refIndex: docIndex,
                finalScore: finalScore,
                matches: [match]
            )
        }

        private func scoreObjectRecord(
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
struct InternalResult<Element> {
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
/// is nil for non-array entries. `weight` is nil for keyless (string-list)
/// matches — same encoding as upstream's `key ? key.weight : null`.
struct InternalMatch {
    let score: Double
    let value: String
    let indices: [FuseRange]?
    let key: KeySource?
    let refIndex: Int?
    let norm: Double
    let weight: Double?
}
