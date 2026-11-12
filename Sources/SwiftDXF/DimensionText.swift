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
            /// Other text, as written. Formatting codes other than `\P` are left in.
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
                } else if c == "\\", i + 1 < chars.count, chars[i + 1] == "P" || chars[i + 1] == "p"
                {
                    flush()
                    parts.append(.lineBreak)
                    i += 2
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
