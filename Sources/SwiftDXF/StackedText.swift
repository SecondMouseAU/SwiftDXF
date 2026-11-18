import Foundation

extension DXF {
    /// Stacked text: two parts written one above the other, from an MTEXT `\S` code.
    ///
    /// On a drawing this is a tolerance (`\S+0,011^ -0,005;`, the upper and lower deviation) or a
    /// fraction (`\S1/2;`). The parts are kept as written, so a comma stays a comma.
    public struct StackedText: Equatable, Sendable {
        /// How the two parts are drawn, from the character that divides them.
        public enum Kind: Equatable, Sendable {
            /// `^`: one part over the other with no line, as a tolerance is written.
            case tolerance
            /// `/`: a fraction with a horizontal line.
            case fraction
            /// `#`: a fraction with a diagonal line.
            case diagonalFraction
        }

        /// The upper part, such as `+0,011`.
        public var upper: String
        /// The lower part, such as `-0,005`.
        public var lower: String
        public var kind: Kind

        public init(upper: String, lower: String, kind: Kind) {
            self.upper = upper
            self.lower = lower
            self.kind = kind
        }

        /// The upper part as a number, or `nil` when it is not one; see ``number(_:)``.
        public var upperValue: Double? { Self.number(upper) }

        /// The lower part as a number, or `nil` when it is not one; see ``number(_:)``.
        public var lowerValue: Double? { Self.number(lower) }

        /// The two parts on one line, `upper/lower`, whatever the kind.
        public var plain: String { upper + "/" + lower }

        /// A part read as a number: an optional sign, digits, and a point or a comma as the
        /// decimal mark, with the spaces around it ignored.
        ///
        /// `+0,011` is 0.011, `-0.005` and `−0.005` (with the minus sign U+2212) are -0.005, and
        /// `0` is 0; empty text or anything else is `nil`.
        public static func number(_ part: String) -> Double? {
            let text = part.trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "\u{2212}", with: "-")
            // `Double` also reads `1e3`, `inf` and `0x10`, which are not deviations.
            guard text.allSatisfy({ $0.isASCII && ($0.isNumber || "+-.,".contains($0)) }) else {
                return nil
            }
            return Double(text.replacingOccurrences(of: ",", with: "."))
        }
    }
}
