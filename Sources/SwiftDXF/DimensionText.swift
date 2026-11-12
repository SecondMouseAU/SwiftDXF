import Foundation

extension DXF {
    /// The text of a `DIMENSION` split into what it says.
    ///
    /// Real files carry a decorated default (`<> mm`), a label (`<>\PBore Size`), a limit
    /// (`67 mm\P(max)`), a range (`40 - 60 mm\P(Adjustable)`) or a note. This keeps the parts
    /// apart so no consumer has to parse the string again.
    public struct DimensionText: Equatable, Sendable {
        /// The override as stored (group 1), or `nil` when there is none.
        public var raw: String?
        /// Whether the measured value is shown: no override, or an override holding `<>`.
        public var showsMeasurement: Bool
        /// Whether the text is suppressed (a single space, the DXF convention).
        public var isSuppressed: Bool
        /// Text before the `<>` placeholder on its line.
        public var prefix: String
        /// Text after the `<>` placeholder, up to the end of its line, such as ` mm`.
        public var suffix: String
        /// The lines of the override, split at `\P` paragraph breaks.
        public var lines: [String]
        /// Numbers typed into the override, in order.
        ///
        /// Empty when ``showsMeasurement``.
        public var typedNumbers: [Double]
        /// The unit word typed with the number, lower case (`mm`, `in`), if any.
        public var unit: String?
        /// Qualifier words found: `max`, `min`, `adjustable`, `approx`, `ref`, `typ`, `nom`.
        public var qualifiers: [String]
        /// What is left of the text once the placeholder, numbers, units and qualifiers are
        /// removed, with lines joined by a space.
        public var words: String

        /// The one typed value, when the text states exactly one number and no qualifier.
        public var typedValue: Double? {
            typedNumbers.count == 1 && qualifiers.isEmpty ? typedNumbers[0] : nil
        }

        /// Whether the text states a range such as `40 - 60 mm`.
        public var isRange: Bool { typedNumbers.count >= 2 }

        /// Whether the text states a limit or reference value: one number with a qualifier.
        public var isLimit: Bool { typedNumbers.count == 1 && !qualifiers.isEmpty }

        /// Whether the text is words only, with no value in it and no placeholder.
        public var isNote: Bool {
            !showsMeasurement && !isSuppressed && typedNumbers.isEmpty && !words.isEmpty
        }

        static let qualifierWords = ["max", "min", "adjustable", "approx", "ref", "typ", "nom"]
        static let unitWords = ["mm", "cm", "m", "in", "inch", "ft"]

        public init(_ override: String?) {
            raw = override
            guard let override, !override.isEmpty else {
                showsMeasurement = true
                isSuppressed = false
                prefix = ""
                suffix = ""
                lines = []
                typedNumbers = []
                unit = nil
                qualifiers = []
                words = ""
                return
            }
            isSuppressed = override == " "
            let split = Self.lines(of: override)
            lines = split
            let placeholder = "<>"
            showsMeasurement = override.contains(placeholder)
            if let line = split.first(where: { $0.contains(placeholder) }),
                let range = line.range(of: placeholder)
            {
                prefix = String(line[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                suffix = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            } else {
                prefix = ""
                suffix = ""
            }

            var numbers: [Double] = []
            var unitFound: String?
            var found: [String] = []
            var left: [String] = []
            for line in split {
                let cleaned = line.replacingOccurrences(of: placeholder, with: " ")
                var lineWords: [String] = []
                for token in Self.tokens(of: cleaned) {
                    switch token {
                    case .number(let value):
                        if !showsMeasurement { numbers.append(value) }
                    case .word(let word):
                        let lowered = word.lowercased()
                        if Self.qualifierWords.contains(lowered) {
                            if !found.contains(lowered) { found.append(lowered) }
                        } else if Self.unitWords.contains(lowered) {
                            if unitFound == nil { unitFound = lowered }
                        } else {
                            lineWords.append(word)
                        }
                    case .separator:
                        break
                    }
                }
                if !lineWords.isEmpty { left.append(lineWords.joined(separator: " ")) }
            }
            typedNumbers = numbers
            unit = unitFound
            qualifiers = found
            words = isSuppressed ? "" : left.joined(separator: " ")
        }

        private enum Token {
            case number(Double)
            case word(String)
            case separator
        }

        /// Splits at the MTEXT paragraph break `\P` (either case) and at real newlines.
        private static func lines(of text: String) -> [String] {
            var out: [String] = []
            var current = ""
            var iterator = text.makeIterator()
            var pending: Character?
            while let c = pending ?? iterator.next() {
                pending = nil
                if c == "\\" {
                    guard let n = iterator.next() else {
                        current.append(c)
                        break
                    }
                    if n == "P" || n == "p" {
                        out.append(current)
                        current = ""
                    } else {
                        pending = n
                    }
                } else if c == "\n" {
                    out.append(current)
                    current = ""
                } else {
                    current.append(c)
                }
            }
            out.append(current)
            return out.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }

        /// Numbers, words and separators.
        ///
        /// A `-` is a sign only when a digit follows it directly and it opens the text or follows
        /// a space, so `40 - 60` is two numbers, not 40 and -60.
        private static func tokens(of text: String) -> [Token] {
            let chars = Array(text)
            var out: [Token] = []
            var i = 0
            while i < chars.count {
                let c = chars[i]
                let startsNumber =
                    c.isASCII && c.isNumber
                    || (c == "." && i + 1 < chars.count && chars[i + 1].isNumber)
                let signed =
                    c == "-" && i + 1 < chars.count && chars[i + 1].isASCII && chars[i + 1].isNumber
                    && (i == 0 || chars[i - 1] == " ")
                if startsNumber || signed {
                    var j = i + 1
                    var seenDot = c == "."
                    while j < chars.count,
                        chars[j].isASCII && chars[j].isNumber || (chars[j] == "." && !seenDot)
                    {
                        if chars[j] == "." { seenDot = true }
                        j += 1
                    }
                    if let value = Double(String(chars[i..<j])) { out.append(.number(value)) }
                    i = j
                } else if c.isLetter {
                    var j = i + 1
                    while j < chars.count, chars[j].isLetter || chars[j] == "'" { j += 1 }
                    out.append(.word(String(chars[i..<j])))
                    i = j
                } else {
                    out.append(.separator)
                    i += 1
                }
            }
            return out
        }
    }
}
