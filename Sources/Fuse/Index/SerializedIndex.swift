import Foundation

/// JSON-shape parity types for `FuseIndex<Element>` serialization. Field
/// names mirror `../fuse-js/src/types.ts:80-114` and the runtime emission
/// at `../fuse-js/src/tools/FuseIndex.ts:168-238,239-247`.
///
/// `keys`: array of key descriptors (no `getFn`).
/// `records`: heterogeneous array — string records `{v, i, n}` from
/// `Fuse<String>`, object records `{i, $: {<keyIdx>: ...}}` from
/// `Fuse<Element>`. SubRecord entries are either a single `{v, n}` for
/// scalar values or `[{v, i, n}, ...]` for array-derived values; the
/// empty array `[]` is **not** equivalent to a missing key — it
/// represents "key resolved through an array traversal that yielded
/// zero elements" (key present, empty subrecord list).
///
/// These types are internal — users round-trip through `Data` via
/// `Fuse.parseIndex(_:)` / `FuseIndex.toJSON()`.

struct SerializedKey: Codable, Equatable {
    let path: [String]
    let id: String
    let weight: Double
    let src: KeySource
}

struct SerializedSubRecord: Codable, Equatable {
    let v: String
    let n: Double
    let i: Int?

    enum CodingKeys: String, CodingKey { case v, n, i }

    init(v: String, n: Double, i: Int? = nil) {
        self.v = v
        self.n = n
        self.i = i
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.v = try c.decode(String.self, forKey: .v)
        self.n = try c.decode(Double.self, forKey: .n)
        self.i = try c.decodeIfPresent(Int.self, forKey: .i)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(v, forKey: .v)
        try c.encodeIfPresent(i, forKey: .i)
        try c.encode(n, forKey: .n)
    }
}

/// Single sub-record (scalar value at key) or multiple (array-derived).
enum SerializedEntry: Codable, Equatable {
    case single(SerializedSubRecord)
    case multiple([SerializedSubRecord])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let arr = try? c.decode([SerializedSubRecord].self) {
            self = .multiple(arr)
        } else {
            self = .single(try c.decode(SerializedSubRecord.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .single(let s): try c.encode(s)
        case .multiple(let arr): try c.encode(arr)
        }
    }
}

/// `record.$` in JS — a map from numeric key index to entry. Emitted as
/// `{"0": ..., "1": ...}` in JSON to mirror upstream's object-with-numeric-
/// string-keys shape. Foundation's `JSONEncoder` cannot emit a Swift
/// `[Int: V]` as object-with-numeric-string-keys (it produces a flat array
/// of alternating key/value entries by default), so the dictionary is
/// wrapped with a custom Codable using a dynamic string-key container.
struct SerializedRecordEntries: Codable, Equatable {
    var entries: [Int: SerializedEntry]

    init(_ entries: [Int: SerializedEntry]) {
        self.entries = entries
    }

    struct DynamicKey: CodingKey {
        let stringValue: String
        let intValue: Int?
        init?(stringValue: String) {
            self.stringValue = stringValue
            self.intValue = Int(stringValue)
        }
        init?(intValue: Int) {
            self.intValue = intValue
            self.stringValue = String(intValue)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: DynamicKey.self)
        var result: [Int: SerializedEntry] = [:]
        for key in c.allKeys {
            guard let intKey = Int(key.stringValue) else {
                throw DecodingError.dataCorruptedError(
                    forKey: key,
                    in: c,
                    debugDescription: "record.$ key must be a numeric string"
                )
            }
            result[intKey] = try c.decode(SerializedEntry.self, forKey: key)
        }
        self.entries = result
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: DynamicKey.self)
        for k in entries.keys.sorted() {
            guard let key = DynamicKey(intValue: k) else { continue }
            try c.encode(entries[k]!, forKey: key)
        }
    }
}

/// Heterogeneous record shape: string-form (`{v, i, n}`) or object-form
/// (`{i, $: ...}`). The two shapes are disjoint at the field level; this
/// type uses optionals and a custom encoder to omit absent fields. Decoder
/// distinguishes by presence of `v` vs `$`.
struct SerializedRecord: Codable, Equatable {
    let i: Int
    let v: String?
    let n: Double?
    let dollar: SerializedRecordEntries?

    enum CodingKeys: String, CodingKey {
        case i, v, n, dollar = "$"
    }

    init(i: Int, v: String? = nil, n: Double? = nil, dollar: SerializedRecordEntries? = nil) {
        self.i = i
        self.v = v
        self.n = n
        self.dollar = dollar
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.i = try c.decode(Int.self, forKey: .i)
        self.v = try c.decodeIfPresent(String.self, forKey: .v)
        self.n = try c.decodeIfPresent(Double.self, forKey: .n)
        self.dollar = try c.decodeIfPresent(SerializedRecordEntries.self, forKey: .dollar)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        // Upstream's string record emits `{v, i, n}` in that source order;
        // object record emits `{i, $}`. Foundation's JSONEncoder does not
        // preserve declaration order, but byte-equivalent comparison against
        // the upstream golden uses field-order-canonicalized parsing — see
        // IndexingTests.swift.
        if let v = v {
            try c.encode(v, forKey: .v)
        }
        try c.encode(i, forKey: .i)
        if let n = n {
            try c.encode(n, forKey: .n)
        }
        if let dollar = dollar {
            try c.encode(dollar, forKey: .dollar)
        }
    }
}

/// Top-level shape emitted by `FuseIndex.toJSON()`.
struct SerializedIndex: Codable, Equatable {
    let keys: [SerializedKey]
    let records: [SerializedRecord]
}
