public enum FuseError: Error {
    case invalidKeyWeight(name: String, weight: Double)
    case invalidDocIndex(idx: Int)
    case pathRequiresEncodableOrGetFn(keyName: String)
    case pathEncodingFailed(keyName: String, underlyingError: any Error)
    case parsedIndexKeyMismatch(ParsedIndexKeyMismatch)
    case invalidIndexRecord(InvalidIndexRecord)

    public enum ParsedIndexKeyMismatch: Sendable, Equatable {
        case countMismatch(parsed: Int, options: Int)
        case idMismatch(slot: Int, parsed: String, options: String)
        case sourceShapeMismatch(slot: Int, parsed: KeySource, options: KeySource)
        case weightMismatch(slot: Int, parsed: Double, options: Double)
    }

    public enum InvalidIndexRecord: Sendable, Equatable {
        case docIndexOutOfRange(slot: Int, i: Int)
        case docIndexNegative(slot: Int, i: Int)
        case duplicateDocIndex(i: Int)
    }
}
