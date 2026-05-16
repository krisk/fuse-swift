/// Converts a per-code-unit match mask into a list of [start, end] ranges.
/// Mirrors `../fuse-js/src/search/bitap/convertMaskToIndices.ts`.
///
/// Each contiguous run of nonzero entries becomes one range. Runs shorter than
/// `minMatchCharLength` are dropped. The trailing-run cleanup at the end of
/// the loop mirrors upstream's `matchmask[i - 1]` check at line 27.
func convertMaskToIndices(
    matchMask: [Int],
    minMatchCharLength: Int = 1
) -> [FuseRange] {
    var indices: [FuseRange] = []
    var start = -1
    var i = 0
    let len = matchMask.count
    while i < len {
        let match = matchMask[i]
        if match != 0 && start == -1 {
            start = i
        } else if match == 0 && start != -1 {
            let end = i - 1
            if end - start + 1 >= minMatchCharLength {
                indices.append(FuseRange(start: start, end: end))
            }
            start = -1
        }
        i += 1
    }

    // Trailing run that didn't close before the loop exit.
    if len > 0
        && matchMask[i - 1] != 0
        && start != -1
        && i - start >= minMatchCharLength {
        indices.append(FuseRange(start: start, end: i - 1))
    }

    return indices
}
