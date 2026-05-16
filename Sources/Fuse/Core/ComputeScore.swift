import Foundation

/// Computes the overall result score from per-match `(score, norm, weight)`
/// tuples. Mirrors `../fuse-js/src/core/computeScore.ts` exactly.
///
/// Formula per match: `base ^ exponent` where
///   - `base = score`, except when `score == 0 && weight != 0`, in which case
///     `base = Double.ulpOfOne` (mirrors JS `Number.EPSILON` — Edge Cases item 8).
///   - `exponent = weight * (ignoreFieldNorm ? 1 : norm)`
/// Per-match contributions are multiplied together; for a single-match string
/// search the totalScore is one base-exponent contribution.
///
/// Norm is in the **exponent**, not a multiplier. A long field has a small
/// norm; a small exponent on `base < 1` pulls the contribution toward 1
/// (worse), which is why short fields rank higher when field-norm is enabled.
enum ComputeScore {
    struct MatchInput {
        let score: Double
        let norm: Double
        let weight: Double  // 1.0 for non-keyed string-list search
    }

    static func compute(
        matches: [MatchInput],
        ignoreFieldNorm: Bool
    ) -> Double {
        var totalScore: Double = 1
        for match in matches {
            let normTerm = ignoreFieldNorm ? 1.0 : match.norm
            let exponent = match.weight * normTerm
            let base: Double = (match.score == 0 && match.weight != 0)
                ? .ulpOfOne
                : match.score
            totalScore *= pow(base, exponent)
        }
        return totalScore
    }
}
