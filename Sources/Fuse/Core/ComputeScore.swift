import Foundation

/// Computes the overall result score from per-match `(score, norm, weight)`
/// tuples. Mirrors `../fuse-js/src/core/computeScore.ts` exactly.
///
/// Formula per match: `base ^ exponent` where
///   - `base = score`, except when `score == 0 && weight != nil`, in which
///     case `base = Double.ulpOfOne` (the Swift equivalent of JS
///     `Number.EPSILON`).
///   - `exponent = (weight ?? 1) * (ignoreFieldNorm ? 1 : norm)`
///
/// `weight == nil` encodes upstream's `key ? key.weight : null` shape for
/// non-keyed (string-list) matches. Upstream gates the EPSILON swap on
/// `score === 0 && weight` — `null` is falsy in JS, so an exact string-list
/// match keeps base = 0, exponent = norm, and the contribution is
/// `pow(0, norm) === 0`. A keyed match with the default weight 1 hits the
/// swap and gets `pow(EPSILON, weight * norm)` instead, which propagates
/// the field-norm penalty even for an exact hit.
///
/// Per-match contributions are multiplied together; for a single-match
/// string search the totalScore is one base-exponent contribution.
///
/// Norm is in the **exponent**, not a multiplier. A long field has a small
/// norm; a small exponent on `base < 1` pulls the contribution toward 1
/// (worse), which is why short fields rank higher when field-norm is enabled.
enum ComputeScore {
    struct MatchInput {
        let score: Double
        let norm: Double
        let weight: Double?  // nil for non-keyed (string-list) matches
    }

    static func compute(
        matches: [MatchInput],
        ignoreFieldNorm: Bool
    ) -> Double {
        var totalScore: Double = 1
        for match in matches {
            let normTerm = ignoreFieldNorm ? 1.0 : match.norm
            let exponent = (match.weight ?? 1.0) * normTerm
            let base: Double = (match.score == 0 && match.weight != nil)
                ? .ulpOfOne
                : match.score
            totalScore *= pow(base, exponent)
        }
        return totalScore
    }
}
