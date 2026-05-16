import Foundation

/// Bitap maximum pattern length per mask. JS uses 32-bit ints throughout the
/// bitap operations; longer patterns are split into 32-code-unit chunks above
/// this layer. `../fuse-js/src/search/bitap/constants.ts:2`.
let bitapMaxBits: Int = 32

struct BitapSearchOptions {
    var location: Int = 0
    var distance: Int = 100
    var threshold: Double = 0.6
    var findAllMatches: Bool = false
    var minMatchCharLength: Int = 1
    var includeMatches: Bool = false
    var ignoreLocation: Bool = false
    var isCaseSensitive: Bool = false
    var ignoreDiacritics: Bool = false
}

struct BitapSearchResult {
    var isMatch: Bool
    var score: Double
    var indices: [FuseRange]?
}

/// Low-level Bitap search over a single pattern chunk (length ≤ 32 UTF-16
/// code units). Literal port of `../fuse-js/src/search/bitap/search.ts`.
///
/// Operates in UTF-16 code-unit space (see Edge Cases item 5b in the plan).
/// Both `text` and `pattern` are pre-lowercased / pre-diacritic-stripped by
/// the caller (the `BitapSearch` class handles that pass).
func bitapSingleChunkSearch(
    text: [UInt16],
    pattern: [UInt16],
    patternAlphabet: [UInt16: UInt32],
    options: BitapSearchOptions = BitapSearchOptions()
) -> BitapSearchResult {
    let patternLen = pattern.count
    let textLen = text.count

    precondition(
        patternLen > 0 && patternLen <= bitapMaxBits,
        "bitap pattern chunk must be in 1...32 code units; chunking happens above this layer"
    )

    let expectedLocation = max(0, min(options.location, textLen))
    var currentThreshold = options.threshold
    var bestLocation = expectedLocation

    // Inlined score — kept aligned with `bitapComputeScore` above.
    let calcScore: (Int, Int) -> Double = { errors, currentLocation in
        let accuracy = Double(errors) / Double(patternLen)
        if options.ignoreLocation { return accuracy }
        let proximity = abs(expectedLocation - currentLocation)
        if options.distance == 0 {
            return proximity != 0 ? 1.0 : accuracy
        }
        return accuracy + Double(proximity) / Double(options.distance)
    }

    // Only compute matches when needed (used for filter-by-min-length OR for
    // include-matches output). Upstream comment at line 45.
    let computeMatches = options.minMatchCharLength > 1 || options.includeMatches
    var matchMask: [Int] = computeMatches ? Array(repeating: 0, count: textLen) : []

    // Find all exact matches first to seed bestLocation and lower the
    // threshold quickly. Upstream lines 53-67.
    var index = utf16IndexOf(text: text, pattern: pattern, from: bestLocation)
    while index > -1 {
        let score = calcScore(0, index)
        currentThreshold = min(score, currentThreshold)
        bestLocation = index + patternLen
        if computeMatches {
            for i in 0..<patternLen {
                matchMask[index + i] = 1
            }
        }
        index = utf16IndexOf(text: text, pattern: pattern, from: bestLocation)
    }

    bestLocation = -1

    var lastBitArr: [UInt32] = []
    var finalScore: Double = 1
    var bestErrors = 0
    var binMax = patternLen + textLen
    let mask: UInt32 = UInt32(1) << (patternLen - 1)

    for i in 0..<patternLen {
        // Binary search the maximum stride at this error level.
        var binMin = 0
        var binMid = binMax
        while binMin < binMid {
            let score = calcScore(i, expectedLocation + binMid)
            if score <= currentThreshold {
                binMin = binMid
            } else {
                binMax = binMid
            }
            binMid = (binMax - binMin) / 2 + binMin
        }
        binMax = binMid

        var start = max(1, expectedLocation - binMid + 1)
        let finish = options.findAllMatches
            ? textLen
            : min(expectedLocation + binMid, textLen) + patternLen

        var bitArr: [UInt32] = Array(repeating: 0, count: finish + 2)
        bitArr[finish + 1] = (UInt32(1) << i) - 1

        var j = finish
        while j >= start {
            let currentLocation = j - 1
            let charMatch: UInt32
            if currentLocation < textLen {
                charMatch = patternAlphabet[text[currentLocation]] ?? 0
            } else {
                charMatch = 0
            }

            // First pass: exact match.
            bitArr[j] = ((bitArr[j + 1] << 1) | 1) & charMatch

            // Subsequent passes: fuzzy match. Upstream reads `lastBitArr[j+1]`
            // and `lastBitArr[j]`; out-of-range reads return undefined which
            // JS coerces to 0 in bitops. Swift mirrors with bounds checks.
            if i > 0 {
                let lJp1: UInt32 = (j + 1) < lastBitArr.count ? lastBitArr[j + 1] : 0
                let lJ: UInt32 = j < lastBitArr.count ? lastBitArr[j] : 0
                bitArr[j] |= ((lJp1 | lJ) << 1) | 1 | lJp1
            }

            if (bitArr[j] & mask) != 0 {
                finalScore = calcScore(i, currentLocation)
                if finalScore <= currentThreshold {
                    currentThreshold = finalScore
                    bestLocation = currentLocation
                    bestErrors = i

                    // Already past expectedLocation, can't improve.
                    if bestLocation <= expectedLocation {
                        break
                    }
                    start = max(1, 2 * expectedLocation - bestLocation)
                }
            }

            j -= 1
        }

        // Bail if no hope at higher error levels.
        let score = calcScore(i + 1, expectedLocation)
        if score > currentThreshold {
            break
        }

        lastBitArr = bitArr
    }

    // Fill matchMask across the matched window only. Bitap anchors a match at
    // bestLocation (the start), spanning patternLen characters plus up to
    // bestErrors extra characters when errors are text-side insertions.
    // Upstream commit 622f105 (#792).
    if computeMatches && bestLocation >= 0 {
        let matchEnd = min(textLen - 1, bestLocation + patternLen - 1 + bestErrors)
        if matchEnd >= bestLocation {
            for k in bestLocation...matchEnd {
                if patternAlphabet[text[k]] != nil {
                    matchMask[k] = 1
                }
            }
        }
    }

    var result = BitapSearchResult(
        isMatch: bestLocation >= 0,
        score: max(0.001, finalScore),
        indices: nil
    )

    if computeMatches {
        let indices = convertMaskToIndices(
            matchMask: matchMask,
            minMatchCharLength: options.minMatchCharLength
        )
        if indices.isEmpty {
            result.isMatch = false
        } else if options.includeMatches {
            result.indices = indices
        }
    }

    return result
}

/// Pattern + alphabet + start-offset for one chunk of a long pattern.
struct BitapChunk {
    let pattern: [UInt16]
    let alphabet: [UInt16: UInt32]
    let startIndex: Int
}

/// Bitap searcher wrapping the low-level single-chunk function with chunking
/// for >32-code-unit patterns and the case-fold + diacritic-strip pre-pass.
/// Mirrors `../fuse-js/src/search/bitap/index.ts`.
final class BitapSearch {
    let options: BitapSearchOptions
    let processedPattern: [UInt16]
    let chunks: [BitapChunk]

    init(pattern: String, options: BitapSearchOptions = BitapSearchOptions()) {
        self.options = options

        var p = pattern
        if !options.isCaseSensitive { p = p.lowercased() }
        if options.ignoreDiacritics { p = Diacritics.strip(p) }
        let processed = Array(p.utf16)
        self.processedPattern = processed

        if processed.isEmpty {
            self.chunks = []
            return
        }

        var built: [BitapChunk] = []
        let len = processed.count
        if len > bitapMaxBits {
            var i = 0
            let remainder = len % bitapMaxBits
            let end = len - remainder
            while i < end {
                let slice = Array(processed[i..<(i + bitapMaxBits)])
                built.append(BitapChunk(
                    pattern: slice,
                    alphabet: createPatternAlphabet(slice),
                    startIndex: i
                ))
                i += bitapMaxBits
            }
            if remainder > 0 {
                let startIndex = len - bitapMaxBits
                let slice = Array(processed[startIndex..<len])
                built.append(BitapChunk(
                    pattern: slice,
                    alphabet: createPatternAlphabet(slice),
                    startIndex: startIndex
                ))
            }
        } else {
            built.append(BitapChunk(
                pattern: processed,
                alphabet: createPatternAlphabet(processed),
                startIndex: 0
            ))
        }
        self.chunks = built
    }

    /// Search a target text for the pattern. Mirrors `BitapSearch.searchIn`
    /// in `../fuse-js/src/search/bitap/index.ts:97`.
    func searchIn(text: String) -> BitapSearchResult {
        var t = text
        if !options.isCaseSensitive { t = t.lowercased() }
        if options.ignoreDiacritics { t = Diacritics.strip(t) }
        let textCU = Array(t.utf16)

        // Exact-match fast path.
        if processedPattern == textCU {
            var result = BitapSearchResult(isMatch: true, score: 0, indices: nil)
            if options.includeMatches {
                let endIdx = textCU.count - 1
                if endIdx >= 0 {
                    result.indices = [FuseRange(start: 0, end: endIdx)]
                } else {
                    result.indices = []
                }
            }
            return result
        }

        if chunks.isEmpty {
            return BitapSearchResult(isMatch: false, score: 1, indices: nil)
        }

        var allIndices: [FuseRange] = []
        var totalScore: Double = 0
        var hasMatches = false

        for chunk in chunks {
            var chunkOptions = options
            chunkOptions.location = options.location + chunk.startIndex

            let res = bitapSingleChunkSearch(
                text: textCU,
                pattern: chunk.pattern,
                patternAlphabet: chunk.alphabet,
                options: chunkOptions
            )

            if res.isMatch { hasMatches = true }
            totalScore += res.score
            if res.isMatch, let indices = res.indices {
                allIndices.append(contentsOf: indices)
            }
        }

        var result = BitapSearchResult(
            isMatch: hasMatches,
            score: hasMatches ? totalScore / Double(chunks.count) : 1,
            indices: nil
        )

        if hasMatches && options.includeMatches {
            result.indices = MergeIndices.merge(allIndices)
        }

        return result
    }
}

/// UTF-16-space `indexOf`. Direct port of `text.indexOf(pattern, from)` from
/// JS. Returns -1 when no match exists.
@inline(__always)
func utf16IndexOf(text: [UInt16], pattern: [UInt16], from: Int) -> Int {
    let textLen = text.count
    let patternLen = pattern.count
    if patternLen == 0 {
        return from >= 0 && from <= textLen ? from : -1
    }
    if from > textLen - patternLen {
        return -1
    }
    let startIdx = max(0, from)
    if startIdx > textLen - patternLen {
        return -1
    }
    var i = startIdx
    while i <= textLen - patternLen {
        var matched = true
        for j in 0..<patternLen {
            if text[i + j] != pattern[j] {
                matched = false
                break
            }
        }
        if matched { return i }
        i += 1
    }
    return -1
}
