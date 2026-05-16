/// Builds the Bitap pattern alphabet: for each code unit in the pattern, the
/// bit mask of positions where that code unit appears. Mirrors
/// `../fuse-js/src/search/bitap/createPatternAlphabet.ts`.
///
/// The pattern is indexed in UTF-16 code units — see `String.UTF16View` — so
/// the algorithm runs byte-equivalent to JS on supplementary scalars,
/// NFD-decomposed accents, and emoji.
func createPatternAlphabet(_ pattern: [UInt16]) -> [UInt16: UInt32] {
    var mask: [UInt16: UInt32] = [:]
    let len = pattern.count
    for i in 0..<len {
        let codeUnit = pattern[i]
        let bit: UInt32 = UInt32(1) << (len - i - 1)
        mask[codeUnit, default: 0] |= bit
    }
    return mask
}
