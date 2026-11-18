import Foundation

extension DXF {
    /// Decodes the inline codes of `TEXT`, `MTEXT` and dimension text into tokens.
    ///
    /// The one scanner behind ``TextContent`` and ``DimensionText``.
    enum TextCodes {
        enum Token: Equatable {
            /// Decoded characters.
            case text(String)
            /// A code that is not understood, kept as written so that no character is lost.
            case code(String)
            case lineBreak
            case stack(StackedText)
        }

        static func tokens(_ raw: String, syntax: TextContent.Syntax) -> [Token] {
            var scanner = Scanner(Array(raw.unicodeScalars), mtext: syntax == .mtext)
            return scanner.run()
        }

        /// Appends a stack as it reads, `upper/lower`, after a space unless `text` is empty or
        /// already ends in one.
        static func append(_ stack: StackedText, to text: inout String) {
            if let last = text.last, !last.isWhitespace { text += " " }
            text += stack.plain
        }

        /// What one special-character code decodes to.
        private enum Piece {
            case text(String)
            case code(String)
            case lineBreak
            case nothing
        }

        /// MTEXT codes that take arguments up to a `;`: alignment, colour, font, height, oblique
        /// angle, tracking, width and paragraph properties.
        private static let withArguments: Set<Unicode.Scalar> = [
            "A", "C", "c", "F", "f", "H", "Q", "T", "W", "p",
        ]

        /// MTEXT codes that switch underline, overline and strike-through on or off.
        private static let toggles: Set<Unicode.Scalar> = ["L", "l", "O", "o", "K", "k"]

        private struct Scanner {
            let s: [Unicode.Scalar]
            let mtext: Bool
            var i = 0
            var tokens: [Token] = []
            var buffer = String.UnicodeScalarView()

            init(_ s: [Unicode.Scalar], mtext: Bool) {
                self.s = s
                self.mtext = mtext
            }

            func at(_ k: Int) -> Unicode.Scalar? { k < s.count ? s[k] : nil }

            func string(_ range: Range<Int>) -> String {
                String(String.UnicodeScalarView(s[range]))
            }

            mutating func emit(_ token: Token) {
                if !buffer.isEmpty { tokens.append(.text(String(buffer))) }
                buffer = .init()
                tokens.append(token)
            }

            mutating func run() -> [Token] {
                while i < s.count {
                    if let (piece, length) = special(at: i) {
                        switch piece {
                        case .text(let text): buffer.append(contentsOf: text.unicodeScalars)
                        case .code(let code): emit(.code(code))
                        case .lineBreak: emit(.lineBreak)
                        case .nothing: break
                        }
                        i += length
                    } else if mtext, s[i] == "{" || s[i] == "}" {
                        i += 1
                    } else if mtext, s[i] == "\\" {
                        formatting()
                    } else {
                        buffer.append(s[i])
                        i += 1
                    }
                }
                if !buffer.isEmpty { tokens.append(.text(String(buffer))) }
                return tokens
            }

            /// The special character that starts at `k`, and how many scalars it takes, or `nil`
            /// when none starts there: `%%c`, `%%d`, `%%p`, `%%%`, `%%nnn`, the underline and
            /// overline toggles `%%u`, `%%o` and `%%k`, `\U+XXXX`, `\M+nXXXX` (kept as written), and
            /// the control characters `^ ` (a caret), `^I` (a tab) and `^J` (a line break).
            func special(at k: Int) -> (Piece, Int)? {
                switch s[k] {
                case "%":
                    guard at(k + 1) == "%", let code = at(k + 2) else { return nil }
                    switch code {
                    case "c", "C": return (.text("\u{2300}"), 3)
                    case "d", "D": return (.text("\u{00B0}"), 3)
                    case "p", "P": return (.text("\u{00B1}"), 3)
                    case "%": return (.text("%"), 3)
                    case "u", "U", "o", "O", "k", "K": return (.nothing, 3)
                    default: return characterNumber(at: k)
                    }
                case "^":
                    switch at(k + 1) {
                    case " ": return (.text("^"), 2)
                    case "I": return (.text("\t"), 2)
                    case "J": return (.lineBreak, 2)
                    default: return nil
                    }
                case "\\":
                    guard at(k + 2) == "+" else { return nil }
                    if at(k + 1) == "M", k + 8 <= s.count,
                        string((k + 3)..<(k + 8)).allSatisfy(\.isHexDigit)
                    {
                        // `\M+nXXXX`, a character of a multibyte code page: kept as written.
                        return (.code(string(k..<(k + 8))), 8)
                    }
                    guard at(k + 1) == "U", k + 7 <= s.count else { return nil }
                    let hex = string((k + 3)..<(k + 7))
                    guard hex.allSatisfy(\.isHexDigit), let value = UInt32(hex, radix: 16) else {
                        return nil
                    }
                    guard let scalar = Unicode.Scalar(value) else {
                        return (.code(string(k..<(k + 7))), 7)
                    }
                    return (.text(String(scalar)), 7)
                default:
                    return nil
                }
            }

            /// `%%nnn`: the character with the number of up to three digits, when it is one that
            /// can be shown; any other number is kept as written.
            func characterNumber(at k: Int) -> (Piece, Int)? {
                var end = k + 2
                while end < k + 5, let digit = at(end), ("0"..."9").contains(digit) { end += 1 }
                guard end > k + 2 else { return nil }
                guard let value = UInt32(string((k + 2)..<end)), let scalar = Unicode.Scalar(value),
                    ![.control, .unassigned].contains(scalar.properties.generalCategory)
                else { return (.code(string(k..<end)), end - k) }
                return (.text(String(scalar)), end - k)
            }

            /// An MTEXT backslash code at `i`.
            mutating func formatting() {
                guard let code = at(i + 1) else {
                    buffer.append("\\")
                    i += 1
                    return
                }
                switch code {
                case "P", "N", "X":
                    // A paragraph, a column, or the break between text above and below a
                    // dimension line.
                    emit(.lineBreak)
                    i += 2
                case "~":
                    buffer.append("\u{00A0}")
                    i += 2
                case "\\", "{", "}":
                    buffer.append(code)
                    i += 2
                case "S":
                    stack()
                default:
                    if TextCodes.toggles.contains(code) {
                        i += 2
                    } else if TextCodes.withArguments.contains(code) {
                        // Its arguments run to the `;`, or to the end when it has none.
                        var end = i + 2
                        while end < s.count, s[end] != ";" { end += 1 }
                        i = min(end + 1, s.count)
                    } else {
                        emit(.code(string(i..<(i + 2))))
                        i += 2
                    }
                }
            }

            /// A `\S` stack at `i`, up to its `;` or the end of the text.
            ///
            /// The first `^`, `/` or `#` divides the parts; a `^` may be written `^ `, with the
            /// space of the DXF caret notation. A backslash makes the next character part of the
            /// text, so `\/` and `\;` do not divide or end the stack. Without a divider nothing is
            /// stacked and the text is read as it is.
            mutating func stack() {
                var parts = [String.UnicodeScalarView(), String.UnicodeScalarView()]
                var divider: Unicode.Scalar?
                var k = i + 2
                func add(_ text: String) {
                    parts[divider == nil ? 0 : 1].append(contentsOf: text.unicodeScalars)
                }
                while k < s.count {
                    let c = s[k]
                    if c == ";" {
                        k += 1
                        break
                    }
                    if divider == nil, c == "^" || c == "/" || c == "#" {
                        divider = c
                        k += (c == "^" && at(k + 1) == " ") ? 2 : 1
                    } else if let (piece, length) = special(at: k) {
                        switch piece {
                        case .text(let text), .code(let text): add(text)
                        case .lineBreak: add("\n")
                        case .nothing: break
                        }
                        k += length
                    } else if c == "\\", let next = at(k + 1) {
                        add(String(next))
                        k += 2
                    } else {
                        add(String(c))
                        k += 1
                    }
                }
                i = k
                let upper = String(parts[0])
                let lower = String(parts[1])
                switch divider {
                case "^": emit(.stack(StackedText(upper: upper, lower: lower, kind: .tolerance)))
                case "/": emit(.stack(StackedText(upper: upper, lower: lower, kind: .fraction)))
                case "#":
                    emit(.stack(StackedText(upper: upper, lower: lower, kind: .diagonalFraction)))
                default: buffer.append(contentsOf: upper.unicodeScalars)
                }
            }
        }
    }
}
