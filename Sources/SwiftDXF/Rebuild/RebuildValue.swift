import Foundation

extension DXF.DimensionRebuild {
    /// The number a dimension value text states, in every way it can be read.
    struct Value: Equatable {
        /// One way to read the number: `1,829` is 1.829 with a comma as the decimal mark, and 1829
        /// with a comma as a thousands separator.
        struct Reading: Equatable {
            var value: Double
            var decimals: Int

            /// How far a measured value may differ from the stated one: one unit of the last place
            /// the text states, as the value may have been rounded either way.
            var tolerance: Double { pow(10, -Double(decimals)) + 1e-9 }

            /// Whether the value is at least ten units of its last place, so that it can be
            /// evidence for a scale: `5` is within a fifth of `4` and `6`, and a numbered sequence
            /// of such values fits some scale beside any lines.
            var isSubstantial: Bool { value * pow(10, Double(decimals)) >= 10 - 1e-9 }
        }

        /// What the text cannot be rebuilt as, so that it is listed rather than guessed at.
        enum Unsupported: Equatable {
            /// An angle (`45°`).
            case angular
            /// More than one number (`2x45`, `200 629`).
            case severalNumbers
            /// A unit other than millimetres (`5m`, `3"`).
            case unit
            /// Digits that are not a number written in a way that is read (`1.2.3`).
            case unreadable
        }

        enum Symbol: Equatable {
            case diameter
            case radius

            var text: String { self == .diameter ? "\u{2300}" : "R" }
        }

        var symbol: Symbol?
        var readings: [Reading]
        var unsupported: Unsupported?

        /// The number a text states, or `nil` for text that does not start with one, after an
        /// optional diameter or radius symbol.
        ///
        /// Only the text before the first stack is read: `36 +0,011/-0,005` states 36. `numbers`
        /// is as for ``read(_:numbers:)`` of a string.
        static func read(
            _ content: DXF.TextContent, numbers: DXF.DimensionText.NumberConvention? = nil
        ) -> Value? {
            var main = ""
            for part in content.parts {
                guard case .text(let text) = part else { break }
                main += text
            }
            return read(main, numbers: numbers)
        }

        /// The number a string states, as the drawing writes numbers, or `nil` for a string that
        /// does not start with one.
        ///
        /// With a `numbers` convention a mark is read as it says, and the number is the one the
        /// text states: `10,439` is 10439 where a comma separates thousands, and 10.439 where it
        /// is the decimal mark. With `nil` a mark is read every way it can be, `1,829` as 1.829
        /// and as 1829, for the geometry to choose between.
        static func read(
            _ string: String, numbers: DXF.DimensionText.NumberConvention? = nil
        ) -> Value? {
            let scalars = Array(halfWidth(string).unicodeScalars)
            var i = 0
            func skipSpaces() {
                while i < scalars.count, scalars[i].properties.isWhitespace { i += 1 }
            }
            skipSpaces()
            var symbol: Symbol?
            if i < scalars.count {
                switch scalars[i] {
                case "\u{2300}", "\u{00D8}", "\u{00F8}", "\u{2205}", "\u{03C6}", "\u{03A6}",
                    "\u{03D5}":
                    symbol = .diameter
                    i += 1
                case "R", "r":
                    if i + 1 < scalars.count,
                        scalars[i + 1].properties.isWhitespace || isDigit(scalars[i + 1])
                    {
                        symbol = .radius
                        i += 1
                    }
                default: break
                }
            }
            skipSpaces()
            let readings: [Reading]
            let rest: String
            if let numbers {
                let characters = Array(String(String.UnicodeScalarView(scalars[i...])))
                guard let found = numbers.scan(characters, from: 0) else { return nil }
                readings = [Reading(value: found.value, decimals: found.decimals)]
                rest = String(characters[found.end...])
            } else {
                var token = ""
                while i < scalars.count {
                    let c = scalars[i]
                    if isDigit(c) {
                        token.unicodeScalars.append(c)
                    } else if c == "." || c == ",", i + 1 < scalars.count,
                        isDigit(scalars[i + 1]), !token.isEmpty
                    {
                        token.unicodeScalars.append(c)
                    } else {
                        break
                    }
                    i += 1
                }
                guard !token.isEmpty else { return nil }
                readings = Self.readings(of: token)
                rest = String(String.UnicodeScalarView(scalars[i...]))
            }
            var value = Value(symbol: symbol, readings: readings, unsupported: nil)
            if value.readings.isEmpty {
                value.unsupported = .unreadable
            } else if rest.contains("\u{00B0}") {
                value.unsupported = .angular
            } else if rest.contains(where: \.isNumber) {
                value.unsupported = .severalNumbers
            } else if rest.contains("\"") || rest.contains("'") || hasUnit(rest) {
                value.unsupported = .unit
            }
            return value
        }

        /// The readings of a number token such as `1,829`, `12.5`, `1,234.5`, `1.234,5` or `0,011`.
        ///
        /// A single mark followed by three digits is a decimal mark or a thousands separator, and
        /// both are read. With two kinds of mark the last is the decimal mark.
        static func readings(of token: String) -> [Reading] {
            let parts = token.split(omittingEmptySubsequences: false) { $0 == "." || $0 == "," }
            let marks = token.filter { $0 == "." || $0 == "," }
            guard let last = marks.last else {
                return Double(token).map { [Reading(value: $0, decimals: 0)] } ?? []
            }
            let after = parts[parts.count - 1]
            if marks.count == 1 {
                var found: [Reading] = []
                if let value = Double(token.replacingOccurrences(of: ",", with: ".")) {
                    found.append(Reading(value: value, decimals: after.count))
                }
                if isGrouping(parts), let value = Double(parts.joined()) {
                    found.append(Reading(value: value, decimals: 0))
                }
                return found
            }
            if marks.allSatisfy({ $0 == last }) {
                // `1,234,567` or `1.234.567`: thousands groups only.
                guard isGrouping(parts), let value = Double(parts.joined()) else { return [] }
                return [Reading(value: value, decimals: 0)]
            }
            // `1,234.5` or `1.234,5`: the last mark is the decimal mark, the others group.
            let groups = Array(parts.dropLast())
            guard marks.dropLast().allSatisfy({ $0 != last }), isGrouping(groups),
                let value = Double(groups.joined() + "." + after)
            else { return [] }
            return [Reading(value: value, decimals: after.count)]
        }

        /// Whether `parts` are thousands groups: one to three digits, then groups of three, and no
        /// leading zero.
        private static func isGrouping<S: StringProtocol>(_ parts: [S]) -> Bool {
            guard let first = parts.first, (1...3).contains(first.count), first.first != "0"
            else { return false }
            return parts.dropFirst().allSatisfy { $0.count == 3 || $0.isEmpty }
        }

        private static func isDigit(_ c: Unicode.Scalar) -> Bool {
            c.value >= 0x30 && c.value <= 0x39
        }

        /// A trailing unit that is not millimetres: `m`, `cm`, `in`, `ft`.
        private static func hasUnit(_ rest: String) -> Bool {
            let word = rest.trimmingCharacters(in: .whitespaces).lowercased()
            return ["m", "cm", "in", "ft", "inch", "inches"].contains {
                word == $0 || word.hasPrefix($0 + " ") || word.hasPrefix($0 + ")")
            }
        }

        /// `s` with full-width digits, point and comma as their ASCII forms, as Japanese drawings
        /// write them, and the full-width `R` of a radius.
        private static func halfWidth(_ s: String) -> String {
            String(
                String.UnicodeScalarView(
                    s.unicodeScalars.map {
                        switch $0.value {
                        case 0xFF32: return "R"
                        case 0xFF52: return "r"
                        default: return DXF.DimensionText.NumberConvention.halfWidth($0)
                        }
                    }))
        }
    }
}
