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
            ///
            /// Given the angle unit of the style (see ``init(_:numbers:codePage:angleUnit:)``) it is
            /// also `45°30'15"`, `50g` or `0.7854r`; the value is in degrees whichever way it was
            /// written.
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
        ///
        /// `angleUnit` is the unit the dimension's style shows an angle in
        /// (``DXF/DimensionStyle/Variables/angleUnit``), which lets the text state an angle in it:
        ///
        /// - ``DXF/DimensionStyle/AngleUnit/degreesMinutesSeconds``: `45°30'15"`, `45°30'` and
        ///   `45°` are each one angle, `45.504166…` for the first. Degrees and minutes are whole,
        ///   and minutes and seconds are below 60.
        /// - ``DXF/DimensionStyle/AngleUnit/gradians``: `50g` is an angle of 45 degrees, where the
        ///   `g` is not followed by a letter, so `50gal` is not one.
        /// - ``DXF/DimensionStyle/AngleUnit/radians``: `0.7854r` is an angle of 45 degrees, with the
        ///   same rule for the `r`.
        ///
        /// A degree sign right after a number is an angle under every unit, and with no unit or
        /// ``DXF/DimensionStyle/AngleUnit/decimalDegrees`` nothing else is read as one: `50g` is a
        /// number and a word, as it would be a mass. Each ``Part/angle(_:text:)`` is in degrees
        /// whatever unit it was written in.
        public init(
            _ raw: String?, numbers: NumberConvention = .plain, codePage: CodePage? = nil,
            angleUnit: DimensionStyle.AngleUnit? = nil
        ) {
            self.raw = raw
            self.parts = Self.split(
                raw ?? "", numbers: numbers, codePage: codePage, angleUnit: angleUnit)
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
            _ raw: String, numbers: NumberConvention, codePage: CodePage?,
            angleUnit: DimensionStyle.AngleUnit?
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
                            // A degree sign right after the number makes it an angle, and the
                            // style's unit can make other endings one.
                            if let angle = Self.angle(
                                chars, after: found, numbers: numbers, unit: angleUnit)
                            {
                                parts.append(
                                    .angle(angle.degrees, text: String(chars[i..<angle.end])))
                                i = angle.end
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

        /// The angle the number `found` starts, in degrees, and the index just past it, or `nil`
        /// when the text after the number does not make it one.
        ///
        /// A degree sign does, in every unit. Where the unit is degrees, minutes and seconds the
        /// degrees may be followed by whole minutes and a `'`, and then by seconds and a `"`;
        /// gradians end in `g` and radians in `r`, each not followed by a letter.
        private static func angle(
            _ chars: [Character], after found: (value: Double, end: Int),
            numbers: NumberConvention, unit: DimensionStyle.AngleUnit?
        ) -> (degrees: Double, end: Int)? {
            let end = found.end
            guard end < chars.count else { return nil }
            func standsAlone(_ i: Int) -> Bool { i >= chars.count || !chars[i].isLetter }
            switch (chars[end], unit) {
            case ("\u{00B0}", .degreesMinutesSeconds?):
                // Minutes follow whole degrees: `45.5°30'` is not 45 degrees 30 minutes.
                guard found.value == found.value.rounded(),
                    let rest = minutesAndSeconds(chars, from: end + 1, numbers: numbers)
                else { return (found.value, end + 1) }
                let degrees = abs(found.value) + rest.minutes / 60 + rest.seconds / 3600
                return (found.value.sign == .minus ? -degrees : degrees, rest.end)
            case ("\u{00B0}", _):
                return (found.value, end + 1)
            case ("g", .gradians?) where standsAlone(end + 1):
                return (found.value * 0.9, end + 1)
            case ("r", .radians?) where standsAlone(end + 1):
                return (found.value * 180 / .pi, end + 1)
            default:
                return nil
            }
        }

        /// The whole minutes and `'` at `start`, then the seconds and `"` when they follow, or
        /// `nil` when there are no minutes or a part is 60 or more.
        private static func minutesAndSeconds(
            _ chars: [Character], from start: Int, numbers: NumberConvention
        ) -> (minutes: Double, seconds: Double, end: Int)? {
            guard let minutes = numbers.scan(chars, from: start), minutes.decimals == 0,
                minutes.end < chars.count, chars[minutes.end] == "'", minutes.value < 60
            else { return nil }
            var seconds = 0.0
            var end = minutes.end + 1
            if let found = numbers.scan(chars, from: end), found.end < chars.count,
                chars[found.end] == "\"", found.value < 60
            {
                seconds = found.value
                end = found.end + 1
            }
            return (minutes.value, seconds, end)
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
