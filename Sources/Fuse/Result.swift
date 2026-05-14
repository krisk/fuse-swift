import Foundation

public struct FuseRange: Sendable, Equatable, Codable {
    public let start: Int
    public let end: Int
    public init(start: Int, end: Int) {
        self.start = start
        self.end = end
    }
}

public struct FuseMatchOutcome: Sendable, Equatable, Codable {
    public let isMatch: Bool
    public let score: Double
    public let indices: [FuseRange]?
    public init(isMatch: Bool, score: Double, indices: [FuseRange]? = nil) {
        self.isMatch = isMatch
        self.score = score
        self.indices = indices
    }
}

public struct FuseMatch: Sendable, Equatable, Codable {
    public let indices: [FuseRange]
    public let key: KeySource?
    public let refIndex: Int?
    public let value: String?
    public init(
        indices: [FuseRange],
        key: KeySource? = nil,
        refIndex: Int? = nil,
        value: String? = nil
    ) {
        self.indices = indices
        self.key = key
        self.refIndex = refIndex
        self.value = value
    }
}

public struct FuseResult<Element> {
    public let item: Element
    public let refIndex: Int
    public let score: Double?
    public let matches: [FuseMatch]?
    public init(
        item: Element,
        refIndex: Int,
        score: Double? = nil,
        matches: [FuseMatch]? = nil
    ) {
        self.item = item
        self.refIndex = refIndex
        self.score = score
        self.matches = matches
    }
}

extension FuseResult: Sendable where Element: Sendable {}
extension FuseResult: Equatable where Element: Equatable {}
extension FuseResult: Codable where Element: Codable {}

public struct FuseSortMatch: Sendable, Equatable {
    public let key: KeySource?
    public let value: String
    public let score: Double
    public let indices: [FuseRange]?
    public init(
        key: KeySource?,
        value: String,
        score: Double,
        indices: [FuseRange]? = nil
    ) {
        self.key = key
        self.value = value
        self.score = score
        self.indices = indices
    }
}

public struct FuseSortItem<Element> {
    public let item: Element
    public let refIndex: Int
    public let score: Double
    public let matches: [FuseSortMatch]
    public init(
        item: Element,
        refIndex: Int,
        score: Double,
        matches: [FuseSortMatch]
    ) {
        self.item = item
        self.refIndex = refIndex
        self.score = score
        self.matches = matches
    }
}

extension FuseSortItem: Sendable where Element: Sendable {}

public typealias FuseSortFunction<Element> =
    @Sendable (FuseSortItem<Element>, FuseSortItem<Element>) -> ComparisonResult
