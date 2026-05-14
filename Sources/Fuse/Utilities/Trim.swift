import Foundation

/// Runtime helpers carved out of `../fuse-js/src/helpers/typeGuards.ts`.
///
/// `isBlank` uses the **ECMAScript** WhiteSpace + LineTerminator code-point
/// set, NOT Foundation's `.whitespaces` / `.whitespacesAndNewlines`. The two
/// overlap heavily but disagree on a handful of scalars (e.g. U+FEFF is in
/// ECMA-trim but not Foundation `.whitespacesAndNewlines`), and the upstream
/// `String.prototype.trim()` semantics are load-bearing for index-shape
/// parity on Unicode-whitespace inputs.
///
/// `toString` ports `baseToString` including the `-0` preservation path at
/// `../fuse-js/src/helpers/typeGuards.ts:9-23`. Naive `"\(value)"` interpolation
/// does not produce JS-equivalent output (it formats `1.0` as `"1.0"` and
/// `-0.0` as `"-0.0"`) and is **not** used.
enum Trim {
    static func isBlank(_ value: String) -> Bool {
        for scalar in value.unicodeScalars {
            if !isEcmaWhitespaceOrLineTerminator(scalar.value) {
                return false
            }
        }
        return true
    }

    static func toString(_ value: String) -> String { value }

    static func toString(_ value: Bool) -> String { value ? "true" : "false" }

    static func toString(_ value: Int) -> String { String(value) }

    static func toString(_ value: Double) -> String {
        if value.isNaN { return "NaN" }
        if value == .infinity { return "Infinity" }
        if value == -.infinity { return "-Infinity" }
        if value == 0 {
            return value.sign == .minus ? "-0" : "0"
        }
        let s = String(value)
        // Swift formats integral doubles as "N.0"; JS prints "N". Strip the
        // trailing ".0" so output matches `value + ''` in JS.
        if s.hasSuffix(".0") {
            return String(s.dropLast(2))
        }
        return s
    }

    private static func isEcmaWhitespaceOrLineTerminator(_ v: UInt32) -> Bool {
        switch v {
        case 0x0009, // TAB
             0x000A, // LF
             0x000B, // VT
             0x000C, // FF
             0x000D, // CR
             0x0020, // SPACE
             0x00A0, // NBSP
             0x1680, // OGHAM
             0x2028, // LS
             0x2029, // PS
             0x202F, // NNBSP
             0x205F, // MMSP
             0x3000, // IDEOGRAPHIC SPACE
             0xFEFF: // ZWNBSP / BOM
            return true
        case 0x2000...0x200A: // EN QUAD..HAIR SPACE
            return true
        default:
            return false
        }
    }
}
