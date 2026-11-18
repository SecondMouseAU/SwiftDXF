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
            case number(Double, text: String)
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

        /// Splits `raw`, the text override of a dimension (`nil` or empty when there is none).
        public init(_ raw: String?) {
            self.raw = raw
            self.parts = Self.split(raw ?? "")
        }

        /// `true` when the dimension shows its measured value: no override, or one containing `<>`.
        public var showsMeasurement: Bool {
            guard let raw, !raw.isEmpty else { return true }
            return parts.contains(.measurement)
        }

        /// `true` for the single space AutoCAD uses to hide the dimension text.
        public var isSuppressed: Bool { raw == " " }

        /// The numbers typed into the text, in order.
        ///
        /// A range such as `40 - 60` gives two.
        public var typedNumbers: [Double] {
            parts.compactMap {
                if case .number(let value, _) = $0 { return value } else { return nil }
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
                case .number(_, let text), .words(let text): out += text
                case .lineBreak: out += "\n"
                case .stack(let stack): TextCodes.append(stack, to: &out)
                }
            }
            return out
        }

        private static func split(_ raw: String) -> [Part] {
            var parts: [Part] = []
            var buffer = ""
            // The character before the current text, for the sign rule of `numberEnd`.
            var previous: Character?
            func flush() {
                if !buffer.isEmpty { parts.append(.words(buffer)) }
                buffer = ""
            }
            for token in TextCodes.tokens(raw, syntax: .mtext) {
                switch token {
                case .text(let text):
                    let chars = Array(text)
                    var i = 0
                    while i < chars.count {
                        if chars[i] == "<", i + 1 < chars.count, chars[i + 1] == ">" {
                            flush()
                            parts.append(.measurement)
                            i += 2
                        } else if let end = numberEnd(chars, from: i, after: previous) {
                            flush()
                            let number = String(chars[i..<end])
                            if let value = Double(number) {
                                parts.append(.number(value, text: number))
                            }
                            i = end
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

        /// The index just past a number starting at `start`, or `nil` when none starts there.
        ///
        /// A sign counts only at the start of the text, after a space or after a line break, so
        /// `40 - 60` and `40-60` are two numbers. `previous` is the character before `chars`.
        private static func numberEnd(
            _ chars: [Character], from start: Int, after previous: Character?
        ) -> Int? {
            var i = start
            if chars[i] == "-" || chars[i] == "+" {
                let before = start == 0 ? previous : chars[start - 1]
                guard before == nil || before == " " || before == "\n" else { return nil }
                i += 1
            }
            let digitsStart = i
            while i < chars.count, chars[i].isASCII, chars[i].isNumber { i += 1 }
            if i < chars.count, chars[i] == ".", i + 1 < chars.count, chars[i + 1].isASCII,
                chars[i + 1].isNumber
            {
                i += 1
                while i < chars.count, chars[i].isASCII, chars[i].isNumber { i += 1 }
            }
            return i > digitsStart ? i : nil
        }
    }
}
