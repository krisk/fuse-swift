/// Bitap-internal score: maps an error count and a match position to a score
/// in [0, 1+]. Mirrors `../fuse-js/src/search/bitap/computeScore.ts`. Inlined
/// inside the bitap inner loop for performance; the standalone function exists
/// for testability and for the documented version of the formula.
///
/// `score = accuracy + proximity / distance`, where `accuracy = errors /
/// patternLen` and `proximity = abs(expectedLocation - currentLocation)`. If
/// `ignoreLocation` is true, only the accuracy term applies. If `distance` is
/// zero, the dodge-divide-by-zero branch from upstream caps to 1.0 for any
/// nonzero proximity.
func bitapComputeScore(
    patternLen: Int,
    errors: Int = 0,
    currentLocation: Int = 0,
    expectedLocation: Int = 0,
    distance: Int = 100,
    ignoreLocation: Bool = false
) -> Double {
    let accuracy = Double(errors) / Double(patternLen)
    if ignoreLocation { return accuracy }
    let proximity = abs(expectedLocation - currentLocation)
    if distance == 0 {
        return proximity != 0 ? 1.0 : accuracy
    }
    return accuracy + Double(proximity) / Double(distance)
}
