import Foundation

public enum KeySource: Sendable, Equatable {
    case string(String)
    case array([String])
}

extension KeySource: Codable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let a = try? c.decode([String].self) {
            self = .array(a)
        } else {
            throw DecodingError.dataCorruptedError(
                in: c,
                debugDescription: "KeySource expects String or [String]"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        }
    }
}

public struct SubRecordValue: Sendable, Equatable {
    public let value: String
    public let index: Int
    public init(value: String, index: Int) {
        self.value = value
        self.index = index
    }
}

public enum AccessorResult: Sendable, Equatable {
    case none
    case single(String)
    case multiple([SubRecordValue])
}

public struct FuseKey<Element>: Sendable {
    public let name: String
    public let weight: Double
    public let source: KeySource
    let accessor: Accessor

    enum Accessor: Sendable {
        case eager(@Sendable (Element) -> AccessorResult)
        case path([String])
    }

    public init(
        _ name: String,
        keyPath: KeyPath<Element, String> & Sendable,
        weight: Double = 1.0
    ) throws {
        guard weight > 0 else {
            throw FuseError.invalidKeyWeight(name: name, weight: weight)
        }
        self.name = name
        self.weight = weight
        self.source = .string(name)
        self.accessor = .eager { value in .single(value[keyPath: keyPath]) }
    }

    public init(
        _ name: String,
        keyPath: KeyPath<Element, String?> & Sendable,
        weight: Double = 1.0
    ) throws {
        guard weight > 0 else {
            throw FuseError.invalidKeyWeight(name: name, weight: weight)
        }
        self.name = name
        self.weight = weight
        self.source = .string(name)
        self.accessor = .eager { value in
            if let s = value[keyPath: keyPath] { return .single(s) }
            return .none
        }
    }

    public init(
        _ name: String,
        get: @escaping @Sendable (Element) -> String?,
        weight: Double = 1.0
    ) throws {
        guard weight > 0 else {
            throw FuseError.invalidKeyWeight(name: name, weight: weight)
        }
        self.name = name
        self.weight = weight
        self.source = .string(name)
        self.accessor = .eager { value in
            if let s = get(value) { return .single(s) }
            return .none
        }
    }

    public init(
        _ name: String,
        get: @escaping @Sendable (Element) -> [String],
        weight: Double = 1.0
    ) throws {
        guard weight > 0 else {
            throw FuseError.invalidKeyWeight(name: name, weight: weight)
        }
        self.name = name
        self.weight = weight
        self.source = .string(name)
        self.accessor = .eager { value in
            let arr = get(value)
            return .multiple(arr.enumerated().map { SubRecordValue(value: $1, index: $0) })
        }
    }

    public init(
        path: String,
        weight: Double = 1.0
    ) throws {
        guard weight > 0 else {
            throw FuseError.invalidKeyWeight(name: path, weight: weight)
        }
        self.name = path
        self.weight = weight
        self.source = .string(path)
        self.accessor = .path(
            path.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        )
    }

    public init(
        path: [String],
        weight: Double = 1.0
    ) throws {
        let name = path.joined(separator: ".")
        guard weight > 0 else {
            throw FuseError.invalidKeyWeight(name: name, weight: weight)
        }
        self.name = name
        self.weight = weight
        self.source = .array(path)
        self.accessor = .path(path)
    }

    /// Rehydration init for `Fuse.parseIndex`: reconstructs a `FuseKey`
    /// from the serialized JSON shape. The accessor is set to `.path` —
    /// no live binding is created here. Phase 8's `Fuse.Search` init then
    /// matches these slots against user-supplied `options.keys` by
    /// `(id, src, weight)` to bind live accessors (Reviewer Question 1).
    init(rehydratedFrom serialized: SerializedKey) throws {
        guard serialized.weight > 0 else {
            throw FuseError.invalidKeyWeight(
                name: serialized.id,
                weight: serialized.weight
            )
        }
        self.name = serialized.id
        self.weight = serialized.weight
        self.source = serialized.src
        self.accessor = .path(serialized.path)
    }
}

public struct FuseOptions<Element> {
    public var isCaseSensitive: Bool
    public var ignoreDiacritics: Bool
    public var includeMatches: Bool
    public var includeScore: Bool
    public var keys: [FuseKey<Element>]
    public var shouldSort: Bool
    public var sortFn: FuseSortFunction<Element>?
    public var location: Int
    public var threshold: Double
    public var distance: Int
    public var findAllMatches: Bool
    public var minMatchCharLength: Int
    public var ignoreLocation: Bool
    public var ignoreFieldNorm: Bool
    public var fieldNormWeight: Double
    public var getFn: (@Sendable (Element, [String]) -> AccessorResult)?

    public init(
        isCaseSensitive: Bool = false,
        ignoreDiacritics: Bool = false,
        includeMatches: Bool = false,
        includeScore: Bool = false,
        keys: [FuseKey<Element>] = [],
        shouldSort: Bool = true,
        sortFn: FuseSortFunction<Element>? = nil,
        location: Int = 0,
        threshold: Double = 0.6,
        distance: Int = 100,
        findAllMatches: Bool = false,
        minMatchCharLength: Int = 1,
        ignoreLocation: Bool = false,
        ignoreFieldNorm: Bool = false,
        fieldNormWeight: Double = 1.0,
        getFn: (@Sendable (Element, [String]) -> AccessorResult)? = nil
    ) throws {
        // The `throws` annotation lifts the `try` to one keyword at the call
        // chain top so per-`FuseKey` validation propagates without each key
        // needing its own `try`. Per-key weight validation happens at FuseKey
        // construction; no additional throw conditions land at the FuseOptions
        // level until a future phase adds one.
        self.isCaseSensitive = isCaseSensitive
        self.ignoreDiacritics = ignoreDiacritics
        self.includeMatches = includeMatches
        self.includeScore = includeScore
        self.keys = keys
        self.shouldSort = shouldSort
        self.sortFn = sortFn
        self.location = location
        self.threshold = threshold
        self.distance = distance
        self.findAllMatches = findAllMatches
        self.minMatchCharLength = minMatchCharLength
        self.ignoreLocation = ignoreLocation
        self.ignoreFieldNorm = ignoreFieldNorm
        self.fieldNormWeight = fieldNormWeight
        self.getFn = getFn
    }
}

extension FuseOptions: Sendable where Element: Sendable {}

extension FuseOptions {
    public var indexOptions: FuseIndexOptions<Element> {
        FuseIndexOptions(getFn: getFn, fieldNormWeight: fieldNormWeight)
    }
}

public struct FuseIndexOptions<Element> {
    public var getFn: (@Sendable (Element, [String]) -> AccessorResult)?
    public var fieldNormWeight: Double

    public init(
        getFn: (@Sendable (Element, [String]) -> AccessorResult)? = nil,
        fieldNormWeight: Double = 1.0
    ) {
        self.getFn = getFn
        self.fieldNormWeight = fieldNormWeight
    }
}

extension FuseIndexOptions: Sendable where Element: Sendable {}

/// Options for the one-shot `Fuse.match(_:in:options:)` helper. Scoped to
/// the bitap-relevant subset of `FuseOptions`; keyed-search / sort /
/// accessor flags don't apply to a single string-vs-string comparison.
/// Mirrors the field set consulted by upstream's `Fuse.match` at
/// `../fuse-js/src/entry.ts:15-26` (which accepts a full `IFuseOptions`
/// but only reads the bitap subset).
public struct FuseMatchOptions: Sendable {
    public var location: Int
    public var distance: Int
    public var threshold: Double
    public var findAllMatches: Bool
    public var minMatchCharLength: Int
    public var includeMatches: Bool
    public var ignoreLocation: Bool
    public var isCaseSensitive: Bool
    public var ignoreDiacritics: Bool

    public init(
        location: Int = 0,
        distance: Int = 100,
        threshold: Double = 0.6,
        findAllMatches: Bool = false,
        minMatchCharLength: Int = 1,
        includeMatches: Bool = false,
        ignoreLocation: Bool = false,
        isCaseSensitive: Bool = false,
        ignoreDiacritics: Bool = false
    ) {
        self.location = location
        self.distance = distance
        self.threshold = threshold
        self.findAllMatches = findAllMatches
        self.minMatchCharLength = minMatchCharLength
        self.includeMatches = includeMatches
        self.ignoreLocation = ignoreLocation
        self.isCaseSensitive = isCaseSensitive
        self.ignoreDiacritics = ignoreDiacritics
    }
}
