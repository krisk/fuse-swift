import Foundation

/// In-memory index record. Mirrors the union type at
/// `../fuse-js/src/types.ts:103-114`: either string-form (`v, n, i`) for
/// `Fuse<String>`, or object-form (`i, $`) for `Fuse<Element>`.
///
/// Stored as a `final class` so mutators (`add`, `removeAt`, `removeAll`)
/// can update `i` in place; the records-array is the unit of identity that
/// `FuseIndex` mutates.
final class IndexRecord {
    enum Kind {
        case stringRecord(value: String, norm: Double)
        case objectRecord(entries: [Int: IndexEntry])
    }

    var i: Int
    var kind: Kind

    init(i: Int, kind: Kind) {
        self.i = i
        self.kind = kind
    }

    /// Deep copy for the copy-on-adopt path: when a `Fuse.Search` adopts
    /// a user-supplied prebuilt index, the records must not be aliased
    /// back into the user's `FuseIndex` instance.
    func copy() -> IndexRecord {
        switch kind {
        case .stringRecord:
            return IndexRecord(i: i, kind: kind)
        case .objectRecord(let entries):
            return IndexRecord(i: i, kind: .objectRecord(entries: entries))
        }
    }
}

/// Per-key entry inside an object record. Mirrors `RecordEntry` at
/// `../fuse-js/src/types.ts:80-82`. Single-value keys use `.single`;
/// array-derived keys use `.multiple` (including the empty-array case,
/// which is **not** equivalent to a missing key — an empty array still
/// produces an entry, matching upstream `_createObjectRecord` at
/// `../fuse-js/src/tools/FuseIndex.ts:226`).
enum IndexEntry {
    case single(IndexSubRecord)
    case multiple([IndexSubRecord])
}

struct IndexSubRecord {
    let value: String
    let norm: Double
    let arrayIndex: Int?
}

// ── Conversions to / from the serialized JSON-shape types. ──────────────

extension IndexSubRecord {
    init(_ s: SerializedSubRecord) {
        self.value = s.v
        self.norm = s.n
        self.arrayIndex = s.i
    }

    func serialized() -> SerializedSubRecord {
        SerializedSubRecord(v: value, n: norm, i: arrayIndex)
    }
}

extension IndexEntry {
    init(_ e: SerializedEntry) {
        switch e {
        case .single(let s): self = .single(IndexSubRecord(s))
        case .multiple(let arr): self = .multiple(arr.map(IndexSubRecord.init))
        }
    }

    func serialized() -> SerializedEntry {
        switch self {
        case .single(let s): return .single(s.serialized())
        case .multiple(let arr): return .multiple(arr.map { $0.serialized() })
        }
    }
}

extension IndexRecord {
    convenience init(_ s: SerializedRecord) {
        if let v = s.v, let n = s.n {
            self.init(i: s.i, kind: .stringRecord(value: v, norm: n))
        } else if let dollar = s.dollar {
            let entries = dollar.entries.mapValues(IndexEntry.init)
            self.init(i: s.i, kind: .objectRecord(entries: entries))
        } else {
            // Empty object record (no keys configured, or all keys absent).
            self.init(i: s.i, kind: .objectRecord(entries: [:]))
        }
    }

    func serialized() -> SerializedRecord {
        switch kind {
        case .stringRecord(let value, let norm):
            return SerializedRecord(i: i, v: value, n: norm)
        case .objectRecord(let entries):
            let mapped = entries.mapValues { $0.serialized() }
            return SerializedRecord(i: i, dollar: SerializedRecordEntries(mapped))
        }
    }
}
