import Fuse
import Foundation

// fuse-swift side of the parity harness. Same input (queries.json +
// fixtures/), same output shape as oracle-js.mjs. Emits canonicalized
// JSON to stdout; the parity-check.sh wrapper diffs the two.

// MARK: - Schema for queries.json

struct QueryBattery: Decodable {
    let cases: [QueryCase]
}

struct QueryCase: Decodable {
    let name: String
    let fixture: String
    let options: ParityOptions
    let queries: [String]
}

/// Mirrors the upstream `IFuseOptions` subset relevant for fuse-swift v1.
/// Manual `init(from:)` because `keys` is heterogeneous (strings, arrays,
/// or `{name, weight}` objects) and `Codable`'s synthesized init can't
/// express that shape without a wrapper enum per field.
struct ParityOptions {
    var includeScore: Bool
    var includeMatches: Bool
    var findAllMatches: Bool
    var ignoreLocation: Bool
    var isCaseSensitive: Bool
    var ignoreDiacritics: Bool
    var ignoreFieldNorm: Bool
    var shouldSort: Bool
    var threshold: Double
    var location: Int
    var distance: Int
    var minMatchCharLength: Int
    var fieldNormWeight: Double
    var limit: Int?
    var keys: [KeyDecl]
}

extension ParityOptions: Decodable {
    enum CodingKeys: String, CodingKey {
        case includeScore, includeMatches, findAllMatches, ignoreLocation
        case isCaseSensitive, ignoreDiacritics, ignoreFieldNorm, shouldSort
        case threshold, location, distance, minMatchCharLength, fieldNormWeight
        case limit, keys
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.includeScore = try c.decodeIfPresent(Bool.self, forKey: .includeScore) ?? false
        self.includeMatches = try c.decodeIfPresent(Bool.self, forKey: .includeMatches) ?? false
        self.findAllMatches = try c.decodeIfPresent(Bool.self, forKey: .findAllMatches) ?? false
        self.ignoreLocation = try c.decodeIfPresent(Bool.self, forKey: .ignoreLocation) ?? false
        self.isCaseSensitive = try c.decodeIfPresent(Bool.self, forKey: .isCaseSensitive) ?? false
        self.ignoreDiacritics = try c.decodeIfPresent(Bool.self, forKey: .ignoreDiacritics) ?? false
        self.ignoreFieldNorm = try c.decodeIfPresent(Bool.self, forKey: .ignoreFieldNorm) ?? false
        self.shouldSort = try c.decodeIfPresent(Bool.self, forKey: .shouldSort) ?? true
        self.threshold = try c.decodeIfPresent(Double.self, forKey: .threshold) ?? 0.6
        self.location = try c.decodeIfPresent(Int.self, forKey: .location) ?? 0
        self.distance = try c.decodeIfPresent(Int.self, forKey: .distance) ?? 100
        self.minMatchCharLength = try c.decodeIfPresent(Int.self, forKey: .minMatchCharLength) ?? 1
        self.fieldNormWeight = try c.decodeIfPresent(Double.self, forKey: .fieldNormWeight) ?? 1.0
        self.limit = try c.decodeIfPresent(Int.self, forKey: .limit)
        self.keys = try c.decodeIfPresent([KeyDecl].self, forKey: .keys) ?? []
    }
}

/// One of: dotted-string `"title"`, segmented `["author", "firstName"]`,
/// or weighted `{"name": ..., "weight": N}` where `name` is itself
/// either a string or an array.
enum KeyDecl: Decodable {
    case path(String)
    case arrayPath([String])
    case weighted(name: NameForm, weight: Double)

    enum NameForm {
        case string(String), array([String])
    }

    private enum WeightedKeys: String, CodingKey { case name, weight }

    init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if let s = try? single.decode(String.self) {
            self = .path(s)
            return
        }
        if let a = try? single.decode([String].self) {
            self = .arrayPath(a)
            return
        }
        let keyed = try decoder.container(keyedBy: WeightedKeys.self)
        let weight = try keyed.decodeIfPresent(Double.self, forKey: .weight) ?? 1.0
        // Probe `name` as String first; fall back to array form.
        if let s = try? keyed.decode(String.self, forKey: .name) {
            self = .weighted(name: .string(s), weight: weight)
        } else {
            let a = try keyed.decode([String].self, forKey: .name)
            self = .weighted(name: .array(a), weight: weight)
        }
    }
}

// MARK: - Element wrapper for non-string fixtures

/// Transparent JSON wrapper. fuse-swift's default Codable walker
/// re-encodes the Element through JSONEncoder; `singleValueContainer`
/// makes the wrapper effectively invisible so path keys resolve against
/// the original JSON structure.
struct AnyDoc: Codable {
    let raw: JSON
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        self.raw = try c.decode(JSON.self)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(raw)
    }
}

enum JSON: Codable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([JSON])
    case object([String: JSON])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let i = try? c.decode(Int64.self) { self = .int(i); return }
        if let d = try? c.decode(Double.self) { self = .double(d); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([JSON].self) { self = .array(a); return }
        if let o = try? c.decode([String: JSON].self) { self = .object(o); return }
        throw DecodingError.dataCorruptedError(
            in: c, debugDescription: "unrecognized JSON shape"
        )
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .int(let i): try c.encode(i)
        case .double(let d): try c.encode(d)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}

// MARK: - Canonical output shape

/// Per-result row matching the JS oracle exactly. `score` / `matches` are
/// optional so they're omitted when the case doesn't request them.
struct CanonicalResult: Encodable {
    let refIndex: Int
    let score: Double?
    let matches: [CanonicalMatch]?

    enum CodingKeys: String, CodingKey { case refIndex, score, matches }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(refIndex, forKey: .refIndex)
        if let score = score { try c.encode(score, forKey: .score) }
        if let matches = matches { try c.encode(matches, forKey: .matches) }
    }
}

struct CanonicalMatch: Encodable {
    let key: KeySource?
    let value: String?
    let indices: [[Int]]
    let refIndex: Int?

    enum CodingKeys: String, CodingKey { case key, value, indices, refIndex }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        // null when nil so the shape matches the JS oracle exactly.
        if let key = key {
            try c.encode(key, forKey: .key)
        } else {
            try c.encodeNil(forKey: .key)
        }
        if let value = value {
            try c.encode(value, forKey: .value)
        } else {
            try c.encodeNil(forKey: .value)
        }
        try c.encode(indices, forKey: .indices)
        if let refIndex = refIndex {
            try c.encode(refIndex, forKey: .refIndex)
        } else {
            try c.encodeNil(forKey: .refIndex)
        }
    }
}

struct CanonicalRow: Encodable {
    let `case`: String
    let fixture: String
    let query: String
    let results: [CanonicalResult]
}

// MARK: - Conversions

func keyForOptions<Element>(_ k: KeyDecl) throws -> FuseKey<Element> {
    switch k {
    case .path(let s):
        return try FuseKey<Element>(path: s)
    case .arrayPath(let a):
        return try FuseKey<Element>(path: a)
    case .weighted(let name, let weight):
        switch name {
        case .string(let s): return try FuseKey<Element>(path: s, weight: weight)
        case .array(let a): return try FuseKey<Element>(path: a, weight: weight)
        }
    }
}

func buildOptions<Element>(_ p: ParityOptions) throws -> FuseOptions<Element> {
    let keys = try p.keys.map { try keyForOptions($0) as FuseKey<Element> }
    return try FuseOptions<Element>(
        isCaseSensitive: p.isCaseSensitive,
        ignoreDiacritics: p.ignoreDiacritics,
        includeMatches: p.includeMatches,
        includeScore: p.includeScore,
        keys: keys,
        shouldSort: p.shouldSort,
        location: p.location,
        threshold: p.threshold,
        distance: p.distance,
        findAllMatches: p.findAllMatches,
        minMatchCharLength: p.minMatchCharLength,
        ignoreLocation: p.ignoreLocation,
        ignoreFieldNorm: p.ignoreFieldNorm,
        fieldNormWeight: p.fieldNormWeight
    )
}

func canonicalizeResult<Element>(
    _ r: FuseResult<Element>,
    options: ParityOptions
) -> CanonicalResult {
    let matches: [CanonicalMatch]?
    if options.includeMatches, let raw = r.matches {
        matches = raw.map { m in
            let sorted = m.indices
                .map { [$0.start, $0.end] }
                .sorted { lhs, rhs in
                    if lhs[0] != rhs[0] { return lhs[0] < rhs[0] }
                    return lhs[1] < rhs[1]
                }
            return CanonicalMatch(
                key: m.key,
                value: m.value,
                indices: sorted,
                refIndex: m.refIndex
            )
        }
    } else {
        matches = nil
    }
    return CanonicalResult(
        refIndex: r.refIndex,
        score: options.includeScore ? r.score : nil,
        matches: matches
    )
}

// MARK: - Driver

let scriptDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()        // SwiftOracle/Sources/SwiftOracle
    .deletingLastPathComponent()        // SwiftOracle/Sources
    .deletingLastPathComponent()        // SwiftOracle
    .deletingLastPathComponent()        // parity/

let battery: QueryBattery = try {
    let url = scriptDir.appendingPathComponent("queries.json")
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(QueryBattery.self, from: data)
}()

func loadFixture(_ name: String) throws -> Data {
    let url = scriptDir
        .appendingPathComponent("fixtures")
        .appendingPathComponent("\(name).json")
    return try Data(contentsOf: url)
}

var output: [CanonicalRow] = []

for c in battery.cases {
    let fixtureData = try loadFixture(c.fixture)

    // Branch on top-level shape: array-of-strings → Fuse.Search<String>,
    // anything else → Fuse.Search<AnyDoc>. Matches the upstream behavior
    // where a string list and an object list take different internal paths.
    let asStrings = try? JSONDecoder().decode([String].self, from: fixtureData)
    if let docs = asStrings {
        let opts: FuseOptions<String> = try buildOptions(c.options)
        let fuse = try Fuse.Search<String>(docs, options: opts)
        for q in c.queries {
            let raw = fuse.search(q, limit: c.options.limit)
            output.append(CanonicalRow(
                case: c.name,
                fixture: c.fixture,
                query: q,
                results: raw.map { canonicalizeResult($0, options: c.options) }
            ))
        }
    } else {
        let docs = try JSONDecoder().decode([AnyDoc].self, from: fixtureData)
        let opts: FuseOptions<AnyDoc> = try buildOptions(c.options)
        let fuse = try Fuse.Search<AnyDoc>(docs, options: opts)
        for q in c.queries {
            let raw = fuse.search(q, limit: c.options.limit)
            output.append(CanonicalRow(
                case: c.name,
                fixture: c.fixture,
                query: q,
                results: raw.map { canonicalizeResult($0, options: c.options) }
            ))
        }
    }
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
let data = try encoder.encode(output)
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write(Data([0x0A]))  // trailing newline
