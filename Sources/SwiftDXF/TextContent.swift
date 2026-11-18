import Foundation

extension DXF {
    /// The string of a `TEXT` or `MTEXT` entity: as written, as it reads, and its stacked parts.
    ///
    /// `%%c`, `%%d` and `%%p` become `⌀`, `°` and `±`, `%%nnn` the Unicode character with that
    /// number up to 255, and `\U+XXXX` the Unicode character. In `MTEXT` the formatting codes
    /// (font, height, colour, alignment and the like) and the grouping braces are removed, `\P` is
    /// a line break, and a `\S` stack is kept as a ``StackedText``. A code that is not understood
    /// is kept as written.
    public struct TextContent: Equatable, Sendable {
        /// Which codes a string holds.
        public enum Syntax: Equatable, Sendable {
            /// `TEXT`: the `%%` special characters, `\U+XXXX` and `^` control characters only. A
            /// backslash is an ordinary character, as in a file path.
            case text
            /// `MTEXT`, and the text of a dimension: the codes of `TEXT`, plus the backslash
            /// formatting codes, `{` and `}` groups and `\S` stacks.
            case mtext
        }

        /// A piece of the decoded text.
        public enum Part: Equatable, Sendable {
            /// Text, with line breaks as `"\n"`.
            case text(String)
            /// Stacked text, such as a tolerance.
            case stack(StackedText)
        }

        /// The string as the file writes it: for `MTEXT`, its continuation groups (3) and then
        /// group 1, joined.
        public var raw: String
        public var syntax: Syntax
        /// The decoded text in order, with each stack as a part of its own.
        public var parts: [Part]

        /// Decodes `raw`, written with the codes of `syntax`.
        public init(_ raw: String, syntax: Syntax) {
            self.raw = raw
            self.syntax = syntax
            var parts: [Part] = []
            func add(_ text: String) {
                if case .text(let before) = parts.last {
                    parts[parts.count - 1] = .text(before + text)
                } else {
                    parts.append(.text(text))
                }
            }
            for token in TextCodes.tokens(raw, syntax: syntax) {
                switch token {
                case .text(let text), .code(let text): add(text)
                case .lineBreak: add("\n")
                case .stack(let stack): parts.append(.stack(stack))
                }
            }
            self.parts = parts
        }

        /// The text as it reads, with each stack as `upper/lower` after a space.
        ///
        /// `36{\H2.4;\S+0,011^ -0,005;}` reads `36 +0,011/-0,005`.
        public var plain: String {
            var out = ""
            for part in parts {
                switch part {
                case .text(let text): out += text
                case .stack(let stack): TextCodes.append(stack, to: &out)
                }
            }
            return out
        }

        /// The stacks, in order.
        public var stacks: [StackedText] {
            parts.compactMap {
                guard case .stack(let stack) = $0 else { return nil }
                return stack
            }
        }
    }
}
