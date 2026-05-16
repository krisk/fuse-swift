import Foundation

/// In-memory index of a document collection. Mirrors
/// `../fuse-js/src/tools/FuseIndex.ts`.
///
/// Public surface is intentionally narrow: `size()`,
/// `getEntry(at:keyId:)`, and `toJSON()`. Mutators (`add`, `removeAt`,
/// `removeAll`) are `internal` — the only correct path for mutation is
/// through `Fuse.Search<Element>`, which keeps `docs` / `records` /
/// the searcher cache in sync and validates keys-shape parity when a
/// prebuilt index is adopted via `init(_:options:index:)`.
///
/// **Not `Sendable`.** Mutable class state. Cross-isolation transfer
/// happens via `toJSON()` + `Fuse.parseIndex(_:)`.
public final class FuseIndex<Element> {
    let getFn: (@Sendable (Element, [String]) -> AccessorResult)?
    let fieldNormWeight: Double
    let norm: FieldNorm

    private(set) var docs: [Element]
    var records: [IndexRecord]
    let keyStore: KeyStore<Element>

    init(
        keys: [FuseKey<Element>] = [],
        getFn: (@Sendable (Element, [String]) -> AccessorResult)? = nil,
        fieldNormWeight: Double = 1.0
    ) {
        self.getFn = getFn
        self.fieldNormWeight = fieldNormWeight
        self.norm = FieldNorm(weight: fieldNormWeight)
        self.docs = []
        self.records = []
        self.keyStore = KeyStore(keys)
    }

    // ── public read surface ───────────────────────────────────────────

    public func size() -> Int {
        records.count
    }

    // ── internal building / mutation ──────────────────────────────────

    func setSources(_ docs: [Element]) {
        self.docs = docs
    }

    func setRecords(_ records: [IndexRecord]) {
        self.records = records
    }

    /// Build records from `docs`. Mirrors `FuseIndex.create()` at
    /// `../fuse-js/src/tools/FuseIndex.ts:51-79`. Pre-flights `.path` keys
    /// for `Element: Encodable` when no top-level `getFn` is supplied.
    func create() throws {
        guard !docs.isEmpty else { return }
        try preflightAccessors()

        var built: [IndexRecord] = []
        built.reserveCapacity(docs.count)

        if Element.self == String.self {
            for (i, doc) in docs.enumerated() {
                if let record = makeStringRecord(doc as! String, docIndex: i) {
                    built.append(record)
                }
            }
        } else {
            for (i, doc) in docs.enumerated() {
                built.append(try makeObjectRecord(doc, docIndex: i))
            }
        }

        self.records = built
        self.norm.clear()
    }

    /// Appends a record for `doc` at `docIndex`. Returns the appended
    /// record, or `nil` when `doc` is a blank string. Mirrors
    /// `FuseIndex.add` at `../fuse-js/src/tools/FuseIndex.ts:85-101`.
    @discardableResult
    func add(_ doc: Element, docIndex: Int) throws -> IndexRecord? {
        guard docIndex >= 0 else {
            throw FuseError.invalidDocIndex(idx: docIndex)
        }
        if Element.self == String.self {
            if let record = makeStringRecord(doc as! String, docIndex: docIndex) {
                records.append(record)
                return record
            }
            return nil
        }
        let record = try makeObjectRecord(doc, docIndex: docIndex)
        records.append(record)
        return record
    }

    /// Doc-index-canonical removal. Removes the record matching `idx` (if
    /// any — blank-string indices have no record) and decrements every
    /// surviving record's `i` that was strictly greater than `idx`.
    /// Mirrors `FuseIndex.removeAt` at upstream lines 106-127, post the
    /// `0b8e3ca2` fix that made `idx` a doc-index (rather than a
    /// records-array slot) so it composes correctly with `add` /
    /// `removeAll` when blank-string docs are present.
    func removeAt(_ idx: Int) throws {
        guard idx >= 0 else {
            throw FuseError.invalidDocIndex(idx: idx)
        }
        if let position = records.firstIndex(where: { $0.i == idx }) {
            records.remove(at: position)
        }
        for record in records where record.i > idx {
            record.i -= 1
        }
    }

    /// Removes records for every doc-index in `indices`, then shifts each
    /// surviving record's `i` down by the count of removed indices strictly
    /// less than it. Drops invalid entries (negative `i`) from the removal
    /// set silently. Mirrors upstream lines 135-161.
    func removeAll(_ indices: [Int]) {
        var toRemove: Set<Int> = []
        for v in indices where v >= 0 {
            toRemove.insert(v)
        }
        if toRemove.isEmpty { return }

        records.removeAll { toRemove.contains($0.i) }

        let sorted = toRemove.sorted()
        for record in records {
            // shift = count of removed indices strictly less than record.i
            var lo = 0
            var hi = sorted.count
            while lo < hi {
                let mid = (lo + hi) >> 1
                if sorted[mid] < record.i {
                    lo = mid + 1
                } else {
                    hi = mid
                }
            }
            record.i -= lo
        }
    }

    /// Returns the entry at `keyId` for the `slot`-th record, or `nil`
    /// if the key is absent on that record. Mirrors upstream
    /// `getValueForItemAtKeyId` semantics in spirit (slot rather than
    /// item-pointer; the keyed-search caller in `Fuse.Search` has the
    /// slot index already from its iteration). Returns `nil` for string
    /// records.
    func entry(atRecordSlot slot: Int, keyId: String) -> IndexEntry? {
        guard slot >= 0, slot < records.count else { return nil }
        guard case .objectRecord(let entries) = records[slot].kind else { return nil }
        guard let keySlot = keyStore.slot(forId: keyId) else { return nil }
        return entries[keySlot]
    }

    /// Deep copy for the copy-on-adopt path used by
    /// `Fuse.Search<Element>.init(_:options:index:)`. When a user supplies
    /// a prebuilt index to a new searcher, the copy ensures the user's
    /// original `FuseIndex` instance is never mutated by the new
    /// searcher's lifecycle (add / removeAt / removeAll / setCollection).
    func copy() -> FuseIndex<Element> {
        let dup = FuseIndex<Element>(
            keys: keyStore.keys,
            getFn: getFn,
            fieldNormWeight: fieldNormWeight
        )
        dup.docs = docs
        dup.records = records.map { $0.copy() }
        return dup
    }

    // ── JSON serialization ────────────────────────────────────────────

    /// Emit the index as JSON `Data` with shape parity with fuse-js
    /// (`{keys, records}` at the top level; per-record shape mirrors
    /// `../fuse-js/src/types.ts:80-114`). The cross-runtime parity
    /// harness at `scripts/parity-check.sh` exercises round-tripping.
    public func toJSON() throws -> Data {
        let payload = SerializedIndex(
            keys: keyStore.serialized(),
            records: records.map { $0.serialized() }
        )
        return try JSONEncoder().encode(payload)
    }

    // ── private helpers ───────────────────────────────────────────────

    private func makeStringRecord(_ doc: String, docIndex: Int) -> IndexRecord? {
        if Trim.isBlank(doc) { return nil }
        return IndexRecord(
            i: docIndex,
            kind: .stringRecord(value: doc, norm: norm.get(doc))
        )
    }

    private func makeObjectRecord(_ doc: Element, docIndex: Int) throws -> IndexRecord {
        var entries: [Int: IndexEntry] = [:]
        for (slot, key) in keyStore.keys.enumerated() {
            let value = try resolveAccessor(key, for: doc, slot: slot)
            switch value {
            case .none:
                continue
            case .single(let s):
                if Trim.isBlank(s) { continue }
                entries[slot] = .single(IndexSubRecord(
                    value: s,
                    norm: norm.get(s),
                    arrayIndex: nil
                ))
            case .multiple(let arr):
                var subs: [IndexSubRecord] = []
                subs.reserveCapacity(arr.count)
                for item in arr {
                    if Trim.isBlank(item.value) { continue }
                    subs.append(IndexSubRecord(
                        value: item.value,
                        norm: norm.get(item.value),
                        arrayIndex: item.index
                    ))
                }
                entries[slot] = .multiple(subs)
            }
        }
        return IndexRecord(i: docIndex, kind: .objectRecord(entries: entries))
    }

    private func resolveAccessor(
        _ key: FuseKey<Element>,
        for doc: Element,
        slot: Int
    ) throws -> AccessorResult {
        switch key.accessor {
        case .eager(let closure):
            return closure(doc)
        case .path(let path):
            if let topGetFn = getFn {
                return topGetFn(doc, path)
            }
            return try ValueAccessor.defaultGet(doc, path: path)
        }
    }

    /// Pre-flight check before walking docs: if any key is `.path`, no
    /// top-level `getFn` is supplied, and `Element` is not `Encodable`,
    /// throw a clean error at index-build time rather than per-doc.
    private func preflightAccessors() throws {
        if getFn != nil { return }
        if ValueAccessor.isEncodable(Element.self) { return }
        for key in keyStore.keys {
            if case .path = key.accessor {
                throw FuseError.pathRequiresEncodableOrGetFn(keyName: key.name)
            }
        }
    }
}
