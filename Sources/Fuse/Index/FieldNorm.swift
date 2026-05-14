import Foundation

/// Field-length norm: the shorter the field, the higher the weight.
///
/// Mirrors `../fuse-js/src/tools/fieldNorm.ts` exactly. Counts only ASCII
/// space (U+0020), not tabs / newlines / general Unicode whitespace — upstream
/// uses `charCodeAt(i) === 32` in a per-character scan that increments the
/// count on each transition into a space run, so consecutive spaces count as
/// a single token boundary.
final class FieldNorm {
    let weight: Double
    private let mantissa: Int
    private let m: Double
    private var cache: [Int: Double] = [:]

    init(weight: Double = 1.0, mantissa: Int = 3) {
        self.weight = weight
        self.mantissa = mantissa
        self.m = pow(10.0, Double(mantissa))
    }

    func get(_ value: String) -> Double {
        var numTokens = 1
        var inSpace = false
        for codeUnit in value.utf16 {
            if codeUnit == 0x20 {
                if !inSpace {
                    numTokens += 1
                    inSpace = true
                }
            } else {
                inSpace = false
            }
        }
        if let cached = cache[numTokens] { return cached }
        let n = (m / pow(Double(numTokens), 0.5 * weight)).rounded() / m
        cache[numTokens] = n
        return n
    }

    func clear() {
        cache.removeAll(keepingCapacity: true)
    }
}
