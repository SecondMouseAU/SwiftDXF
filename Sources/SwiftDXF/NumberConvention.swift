extension DXF.DimensionText {
    /// How a drawing writes numbers, which its text cannot say by itself.
    ///
    /// Japanese drawings write ten thousand four hundred and thirty-nine as `10,439`, as Jw_cad
    /// does. A drawing from a country that writes decimals with a comma means `0,125` as one eighth.
    /// Under either setting a point is a decimal mark. Full-width digits, point and comma
    /// (`１０，４３９`) read as their ordinary forms.
    public enum NumberConvention: Equatable, Sendable {
        /// A comma is not part of a number: `10,439` is the two numbers 10 and 439.
        case plain
        /// A comma separates thousands, but only between groups of three digits: `1,930`,
        /// `12,345,678` and `5,186.6` are one number, and `40,60`, `1,2345` and `0,125` are not.
        case commaSeparatesThousands
        /// A comma between digits is the decimal mark: `0,125` is 0.125 and `10,439` is 10.439.
        case commaIsDecimalMark
    }
}

extension DXF.DimensionText.NumberConvention {
    /// A number found in text.
    struct Scanned: Equatable {
        /// The index just past the number.
        var end: Int
        /// Its value, without any sign.
        var value: Double
        /// The digits it states after the decimal mark.
        var decimals: Int
    }

    /// The number that starts at `start`, or `nil` when a digit does not.
    ///
    /// Reads digits, the marks this convention gives a meaning, and nothing else: a sign is for the
    /// caller.
    func scan(_ chars: [Character], from start: Int) -> Scanned? {
        var i = start
        var integer = ""
        while i < chars.count, let digit = Self.digit(chars[i]) {
            integer.append(digit)
            i += 1
        }
        guard !integer.isEmpty else { return nil }
        if self == .commaSeparatesThousands, Self.canStartGroups(integer) {
            while let group = Self.group(chars, at: i) {
                integer += group
                i += 4
            }
        }
        var fraction = ""
        if i + 1 < chars.count, isDecimalMark(chars[i]), Self.digit(chars[i + 1]) != nil {
            i += 1
            while i < chars.count, let digit = Self.digit(chars[i]) {
                fraction.append(digit)
                i += 1
            }
        }
        guard let value = Double(fraction.isEmpty ? integer : integer + "." + fraction) else {
            return nil
        }
        return Scanned(end: i, value: value, decimals: fraction.count)
    }

    /// Whether `digits` can be the first group of a number with thousands groups.
    ///
    /// They are one to three digits with no leading zero, and every group after them has three.
    static func canStartGroups<S: StringProtocol>(_ digits: S) -> Bool {
        (1...3).contains(digits.count) && digits.first != "0"
    }

    private func isDecimalMark(_ c: Character) -> Bool {
        switch Self.halfWidth(c) {
        case ".": return true
        case ",": return self == .commaIsDecimalMark
        default: return false
        }
    }

    /// The three digits of a thousands group at `i` (a comma and three digits, and no fourth), or
    /// `nil`.
    private static func group(_ chars: [Character], at i: Int) -> String? {
        guard i + 3 < chars.count, halfWidth(chars[i]) == "," else { return nil }
        let digits = (i + 1...i + 3).compactMap { digit(chars[$0]) }
        guard digits.count == 3, i + 4 >= chars.count || digit(chars[i + 4]) == nil else {
            return nil
        }
        return String(digits)
    }

    /// The ASCII digit that `c` is, or `nil`; a full-width digit is read as its ordinary form.
    private static func digit(_ c: Character) -> Character? {
        let folded = halfWidth(c)
        return folded.isASCII && folded.isNumber ? folded : nil
    }

    /// `c` with a full-width digit, point or comma as its ASCII form, as Japanese drawings write
    /// them, and any other character as it is.
    private static func halfWidth(_ c: Character) -> Character {
        guard c.unicodeScalars.count == 1, let scalar = c.unicodeScalars.first else { return c }
        return Character(halfWidth(scalar))
    }

    /// `scalar` with a full-width digit, point or comma as its ASCII form.
    static func halfWidth(_ scalar: Unicode.Scalar) -> Unicode.Scalar {
        switch scalar.value {
        case 0xFF10...0xFF19: return Unicode.Scalar(scalar.value - 0xFF10 + 0x30) ?? scalar
        case 0xFF0E: return "."
        case 0xFF0C: return ","
        default: return scalar
        }
    }
}
