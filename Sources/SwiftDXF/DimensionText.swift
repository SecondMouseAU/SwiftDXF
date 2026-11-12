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
            /// Other text, as written. Formatting codes other than `\P` are left in, and the
            /// numbers inside them are not read as typed numbers.
            case words(String)
            /// `\P`: a paragraph break.
            case lineBreak
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

        /// MTEXT codes written `\X...;`: alignment, colour, font, height, oblique, stack,
        /// tracking, width and paragraph properties.
        private static let takesArguments: Set<Character> = [
            "A", "C", "c", "F", "f", "H", "Q", "S", "T", "W", "p",
        ]

        private static func split(_ raw: String) -> [Part] {
            let chars = Array(raw)
            var parts: [Part] = []
            var buffer = ""
            func flush() {
                if !buffer.isEmpty { parts.append(.words(buffer)) }
                buffer = ""
            }
            var i = 0
            while i < chars.count {
                let c = chars[i]
                if c == "<", i + 1 < chars.count, chars[i + 1] == ">" {
                    flush()
                    parts.append(.measurement)
                    i += 2
                } else if c == "%", i + 2 < chars.count, chars[i + 1] == "%" {
                    // `%%d`, `%%c`, `%%p` and `%%176`: AutoCAD symbols, not numbers.
                    var end = i + 3
                    if chars[i + 2].isASCII, chars[i + 2].isNumber {
                        while end < i + 5, end < chars.count, chars[end].isASCII,
                            chars[end].isNumber
                        {
                            end += 1
                        }
                    }
                    buffer.append(contentsOf: chars[i..<end])
                    i = end
                } else if c == "\\", i + 1 < chars.count {
                    let code = chars[i + 1]
                    if code == "P" {
                        flush()
                        parts.append(.lineBreak)
                        i += 2
                    } else if code == "U", i + 2 < chars.count, chars[i + 2] == "+" {
                        // `\U+00B0`: a unicode escape, whose hex digits are not typed numbers.
                        var end = i + 3
                        while end < i + 7, end < chars.count, chars[end].isHexDigit { end += 1 }
                        buffer.append(contentsOf: chars[i..<end])
                        i = end
                    } else if Self.takesArguments.contains(code),
                        let end = chars[(i + 2)...].firstIndex(of: ";")
                    {
                        // Colour, font, height, stack and the like: its digits are not typed.
                        buffer.append(contentsOf: chars[i...end])
                        i = end + 1
                    } else if code == "\\" || code == "{" || code == "}" || code.isLetter {
                        buffer.append(c)
                        buffer.append(code)
                        i += 2
                    } else {
                        buffer.append(c)
                        i += 1
                    }
                } else if let end = numberEnd(chars, from: i) {
                    flush()
                    let text = String(chars[i..<end])
                    if let value = Double(text) { parts.append(.number(value, text: text)) }
                    i = end
                } else {
                    buffer.append(c)
                    i += 1
                }
            }
            flush()
            return parts
        }

        /// The index just past a number starting at `start`, or `nil` when none starts there.
        ///
        /// A sign counts only at the start of the text or after a space, so `40 - 60` and `40-60`
        /// are two numbers.
        private static func numberEnd(_ chars: [Character], from start: Int) -> Int? {
            var i = start
            if chars[i] == "-" || chars[i] == "+" {
                guard start == 0 || chars[start - 1] == " " else { return nil }
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
