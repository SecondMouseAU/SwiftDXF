import Foundation

extension DXF {
    /// The text of a dimension, split into what it shows.
    ///
    /// `<>` stands for the measured value. Real overrides seen on drawings: `<> mm` (the value with
    /// a unit), `<>\PBore Size` (a label under it), `67 mm\P(max)` (a typed limit), `40 - 60 mm`
    /// (a range) and `Length is representative` (a note).
    public struct DimensionText: Equatable, Sendable {
        public enum Part: Equatable, Sendable {
            /// `<>`: the measured value.
            case measurement
            /// A number typed into the text, with the characters it was written with.
            ///
            /// A number typed as an angle is an ``angle(_:text:)``, not a number: `45°` is not a
            /// length of 45.
            case number(Double, text: String)
            /// An angle typed into the text, in degrees, with the characters it was written with,
            /// the degree sign included: `45°`, however the sign is written (`°`, `%%d` or
            /// `\U+00B0`).
            case angle(Double, text: String)
            /// Other text, decoded as ``TextContent`` decodes `MTEXT`: `%%c` is `⌀`, and the
            /// formatting codes are removed. A code that is not understood is kept as written, and
            /// its digits are not read as typed numbers.
            case words(String)
            /// A line break: `\P` (a paragraph), `\N` (a column), `^J`, or `\X` (the break between
            /// the text above and below the dimension line).
            case lineBreak
            /// A `\S` stack, such as the tolerance `\S+0.1^ -0.2;`. Its numbers are not typed
            /// numbers.
            case stack(StackedText)
        }

        /// The override as stored (group 1), or `nil` when the dimension has none.
        public var raw: String?
        public var parts: [Part]

        /// Splits `raw`, the text override of a dimension (`nil` or empty when there is none),
        /// reading numbers as `numbers` says the drawing writes them and `%%nnn` through
        /// `codePage` (as a Unicode code point when it is `nil`).
        ///
        /// With the default, ``NumberConvention/plain``, `10,439` is the numbers 10 and 439.
        public init(
            _ raw: String?, numbers: NumberConvention = .plain, codePage: CodePage? = nil
        ) {
            self.raw = raw
            self.parts = Self.split(raw ?? "", numbers: numbers, codePage: codePage)
        }

        /// `true` when the dimension shows its measured value: no override, or one containing `<>`.
        public var showsMeasurement: Bool {
            guard let raw, !raw.isEmpty else { return true }
            return parts.contains(.measurement)
        }

        /// `true` for the single space AutoCAD uses to hide the dimension text.
        public var isSuppressed: Bool { raw == " " }

        /// The numbers typed into the text, in order, other than angles.
        ///
        /// A range such as `40 - 60` gives two. Which marks are part of a number is up to the
        /// ``NumberConvention`` the text was split with. The `45` of `45°` is not one: see
        /// ``typedAngles``.
        public var typedNumbers: [Double] {
            parts.compactMap {
                if case .number(let value, _) = $0 { return value } else { return nil }
            }
        }

        /// The angles typed into the text, in degrees, in order: a number with a degree sign right
        /// after it, such as `45°` or `45%%d`.
        public var typedAngles: [Double] {
            parts.compactMap {
                if case .angle(let value, _) = $0 { return value } else { return nil }
            }
        }

        /// The text segments that are not numbers or `<>`, trimmed, in order.
        public var words: [String] {
            parts.compactMap {
                guard case .words(let text) = $0 else { return nil }
                let trimmed = text.trimmingCharacters(in: .whitespaces)
                return trimmed.isEmpty ? nil : trimmed
            }
        }

        /// The stacks, in order.
        public var stacks: [StackedText] {
            parts.compactMap {
                guard case .stack(let stack) = $0 else { return nil }
                return stack
            }
        }

        /// The text as it reads, with `<>` where the measured value goes and each stack as
        /// `upper/lower` after a space, as in ``TextContent/plain``.
        public var plain: String {
            var out = ""
            for part in parts {
                switch part {
                case .measurement: out += "<>"
                case .number(_, let text), .angle(_, let text), .words(let text): out += text
                case .lineBreak: out += "\n"
                case .stack(let stack): TextCodes.append(stack, to: &out)
                }
            }
            return out
        }

        private static func split(
            _ raw: String, numbers: NumberConvention, codePage: CodePage?
        ) -> [Part] {
            var parts: [Part] = []
            var buffer = ""
            // The character before the current text, for the sign rule of `number`.
            var previous: Character?
            func flush() {
                if !buffer.isEmpty { parts.append(.words(buffer)) }
                buffer = ""
            }
            for token in TextCodes.tokens(raw, syntax: .mtext, codePage: codePage) {
                switch token {
                case .text(let text):
                    let chars = Array(text)
                    var i = 0
                    while i < chars.count {
                        if chars[i] == "<", i + 1 < chars.count, chars[i + 1] == ">" {
                            flush()
                            parts.append(.measurement)
                            i += 2
                        } else if let found = number(
                            chars, from: i, after: previous, numbers: numbers)
                        {
                            flush()
                            // A degree sign right after the number makes it an angle.
                            if found.end < chars.count, chars[found.end] == "\u{00B0}" {
                                let text = String(chars[i...found.end])
                                parts.append(.angle(found.value, text: text))
                                i = found.end + 1
                            } else {
                                parts.append(
                                    .number(found.value, text: String(chars[i..<found.end])))
                                i = found.end
                            }
                        } else {
                            buffer.append(chars[i])
                            i += 1
                        }
                    }
                    previous = chars.last
                case .code(let code):
                    // Kept as written; its digits are not typed numbers.
                    buffer += code
                    previous = code.last
                case .lineBreak:
                    flush()
                    parts.append(.lineBreak)
                    previous = "\n"
                case .stack(let stack):
                    flush()
                    parts.append(.stack(stack))
                    previous = "/"
                }
            }
            flush()
            return parts
        }

        /// The number starting at `start`, with its sign, and the index just past it; `nil` when
        /// none starts there.
        ///
        /// A sign counts only at the start of the text, after a space or after a line break, so
        /// `40 - 60` and `40-60` are two numbers. `previous` is the character before `chars`.
        private static func number(
            _ chars: [Character], from start: Int, after previous: Character?,
            numbers: NumberConvention
        ) -> (value: Double, end: Int)? {
            var i = start
            var sign = 1.0
            if chars[i] == "-" || chars[i] == "+" {
                let before = start == 0 ? previous : chars[start - 1]
                guard before == nil || before == " " || before == "\n" else { return nil }
                if chars[i] == "-" { sign = -1 }
                i += 1
            }
            guard let found = numbers.scan(chars, from: i) else { return nil }
            return (sign * found.value, found.end)
        }
    }
}
