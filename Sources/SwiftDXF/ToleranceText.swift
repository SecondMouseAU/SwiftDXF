import Foundation

extension DXF.Tolerance {
    /// The frames of the string of a `TOLERANCE`.
    ///
    /// Rows are separated by `^J` and the boxes of a row by `%%v`. A symbol is a lowercase letter
    /// of the GDT font in a group, `{\Fgdt;j}`; every other piece of text is decoded as `MTEXT`
    /// is, through ``DXF/TextContent``.
    static func frames(in text: String, codePage: DXF.CodePage?) -> [Frame] {
        var frames: [Frame] = []
        for row in split(Array(text.unicodeScalars), at: isRowBreak) {
            let boxes = split(row, at: isBoxBreak).map { Box(pieces(of: $0), codePage) }
            guard boxes.contains(where: { !$0.isEmpty }) else { continue }
            frames.append(frame(raw: String(String.UnicodeScalarView(row)), boxes))
        }
        return frames
    }

    // MARK: Symbols

    /// The characteristic a letter of the GDT font stands for.
    ///
    /// From the table of `gdt.shx`, which `GDT_IV25` and `GDT_IV50` share, in Goodheart-Willcox,
    /// *AutoCAD and Its Applications*, "Drafting Symbols". The other letters of the font are
    /// material conditions and a diameter (`l`, `m`, `s`, `n`), a projected zone (`p`) and
    /// dimension symbols (`o`, `q`, `v`, `w`, `x`, `y`, `z`), which no frame starts with.
    static let characteristics: [Unicode.Scalar: Characteristic] = [
        "a": .angularity, "b": .perpendicularity, "c": .flatness, "d": .profileOfSurface,
        "e": .circularity, "f": .parallelism, "g": .cylindricity, "h": .circularRunout,
        "i": .symmetry, "j": .position, "k": .profileOfLine, "r": .concentricity,
        "t": .totalRunout, "u": .straightness,
    ]

    /// The fonts whose lowercase letters are these symbols.
    private static let symbolFonts: Set<String> = ["gdt", "gdt_iv25", "gdt_iv50"]

    // MARK: Splitting

    /// The length of the row separator `^J` (the line break of the DXF caret notation) at `i`.
    private static func isRowBreak(_ s: [Unicode.Scalar], _ i: Int) -> Int? {
        s[i] == "^" && i + 1 < s.count && s[i + 1] == "J" ? 2 : nil
    }

    /// The length of the box separator `%%v` at `i`.
    private static func isBoxBreak(_ s: [Unicode.Scalar], _ i: Int) -> Int? {
        s[i] == "%" && i + 2 < s.count && s[i + 1] == "%" && (s[i + 2] == "v" || s[i + 2] == "V")
            ? 3 : nil
    }

    /// `s` cut at every separator that `at` finds, given its length.
    ///
    /// A literal caret (`^ `) and a percent sign (`%%%`) are copied whole, so the `J` or `v` that
    /// follows them is not part of a separator.
    private static func split(
        _ s: [Unicode.Scalar], at separator: ([Unicode.Scalar], Int) -> Int?
    ) -> [[Unicode.Scalar]] {
        var parts: [[Unicode.Scalar]] = [[]]
        var i = 0
        while i < s.count {
            if let length = separator(s, i) {
                parts.append([])
                i += length
            } else if s[i] == "^", i + 1 < s.count, s[i + 1] == " " {
                parts[parts.count - 1] += s[i..<(i + 2)]
                i += 2
            } else if s[i] == "%", i + 2 < s.count, s[i + 1] == "%", s[i + 2] == "%" {
                parts[parts.count - 1] += s[i..<(i + 3)]
                i += 3
            } else {
                parts[parts.count - 1].append(s[i])
                i += 1
            }
        }
        return parts
    }

    // MARK: Pieces of a box

    /// A box is text, and symbols of the GDT font.
    private enum Piece {
        /// Text as written, still to be decoded.
        case text(String)
        /// A lowercase letter of the GDT font, with the group it was written in.
        case symbol(Unicode.Scalar, raw: String)
    }

    private static func pieces(of box: [Unicode.Scalar]) -> [Piece] {
        var out: [Piece] = []
        var buffer = String.UnicodeScalarView()
        func flush() {
            if !buffer.isEmpty { out.append(.text(String(buffer))) }
            buffer = .init()
        }
        var i = 0
        while i < box.count {
            if let group = symbolGroup(in: box, at: i) {
                flush()
                let written = String(String.UnicodeScalarView(box[i..<group.end]))
                for c in group.letters {
                    out.append(("a"..."z").contains(c) ? .symbol(c, raw: written) : .text("\(c)"))
                }
                i = group.end
            } else {
                buffer.append(box[i])
                i += 1
            }
        }
        flush()
        return out
    }

    /// A `{\Fgdt;…}` group that starts at `i`: the characters it holds and the index after it, or
    /// `nil` when there is no group in a font of symbols there.
    private static func symbolGroup(
        in s: [Unicode.Scalar], at i: Int
    ) -> (letters: [Unicode.Scalar], end: Int)? {
        // A font name and its properties are short, so the search for the `;` is too, however many
        // `{\F` a string repeats.
        let searchEnd = min(i + 3 + 64, s.count)
        guard s[i] == "{", i + 2 < s.count, s[i + 1] == "\\", s[i + 2] == "F" || s[i + 2] == "f",
            let semicolon = s[(i + 3)..<searchEnd].firstIndex(of: ";")
        else { return nil }
        // The font name ends at a `|`, which starts the font's properties (`\fgdt|b0|i0;`).
        let font = String(String.UnicodeScalarView(s[(i + 3)..<semicolon]))
        var name = (font.split(separator: "|", maxSplits: 1).first ?? "").lowercased()
        if name.hasSuffix(".shx") { name.removeLast(4) }
        guard symbolFonts.contains(name) else { return nil }
        let close = s[(semicolon + 1)...].firstIndex(of: "}") ?? s.count
        return (Array(s[(semicolon + 1)..<close]), min(close + 1, s.count))
    }

    // MARK: Boxes and frames

    /// A box read into the parts a tolerance or a datum is made of.
    private struct Box {
        /// The decoded text of the box, without the diameter and material condition read from it.
        var text = ""
        var isDiameter = false
        var materialCondition: MaterialCondition?
        /// The letters of the symbols of the box, in order.
        var letters: [Unicode.Scalar] = []
        /// Symbols that are neither a diameter nor a material condition, as written.
        var unread: [String] = []
        /// Whether the box has text besides its symbols.
        var hasText = false
        /// The box as written, trimmed.
        var written = ""

        init(_ pieces: [Piece], _ codePage: DXF.CodePage?) {
            for piece in pieces {
                switch piece {
                case .text(let raw):
                    written += raw
                    let decoded = DXF.TextContent(raw, syntax: .mtext, codePage: codePage).plain
                    if !decoded.allSatisfy(\.isWhitespace) { hasText = true }
                    text += decoded
                case .symbol(let letter, let raw):
                    written += raw
                    letters.append(letter)
                    read(letter, written: raw)
                }
            }
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            // `%%c` decodes to the diameter sign.
            if text.hasPrefix("\u{2300}") {
                isDiameter = true
                text.removeFirst()
                text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            written = written.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private mutating func read(_ letter: Unicode.Scalar, written raw: String) {
            switch (letter, materialCondition) {
            case ("n", _): isDiameter = true
            case ("m", nil): materialCondition = .maximum
            case ("l", nil): materialCondition = .least
            case ("s", nil): materialCondition = .regardlessOfFeatureSize
            default:
                // A symbol that is not read stays in the text, and is listed.
                text += raw
                unread.append(raw)
            }
        }

        /// Whether the box holds nothing: no symbol, and no text but spaces.
        var isEmpty: Bool { written.isEmpty }

        var zone: Zone {
            Zone(
                isDiameter: isDiameter, value: DXF.Tolerance.number(text), text: text,
                materialCondition: materialCondition)
        }

        /// The box as a datum; a diameter sign stays in its reference.
        var datum: Datum {
            Datum(
                reference: (isDiameter ? "\u{2300}" : "") + text,
                materialCondition: materialCondition)
        }

        /// The characteristic a first box states: one letter of the font and nothing else.
        var characteristic: Characteristic {
            if letters.count == 1, !hasText, let kind = DXF.Tolerance.characteristics[letters[0]] {
                return kind
            }
            return .unrecognised(written)
        }
    }

    /// The boxes of one row read into a frame: the symbol, two tolerances and three datums.
    private static func frame(raw: String, _ boxes: [Box]) -> Frame {
        func box(_ index: Int) -> Box? {
            index < boxes.count && !boxes[index].isEmpty ? boxes[index] : nil
        }
        var frame = Frame(raw: raw)
        frame.characteristic = box(0)?.characteristic
        frame.tolerance = box(1)?.zone
        frame.secondTolerance = box(2)?.zone
        for index in 3...5 {
            if let datum = box(index)?.datum { frame.datums.append(datum) }
        }
        for index in 1...5 {
            frame.unread += box(index)?.unread ?? []
        }
        // The boxes after the sixth have no place in the layout above.
        frame.unread += boxes.dropFirst(6).filter { !$0.isEmpty }.map(\.written)
        return frame
    }

    // MARK: Numbers

    /// The number a box states, or `nil` for anything else, not a guess.
    ///
    /// An optional sign, digits and at most one decimal mark, which is a point or, when there is no
    /// point, a comma.
    static func number(_ text: String) -> Double? {
        var scalars = Array(text.unicodeScalars)
        let negative = scalars.first == "-"
        if let sign = scalars.first, sign == "+" || sign == "-" { scalars.removeFirst() }
        let digits = scalars.filter { ("0"..."9").contains($0) }
        let marks = scalars.filter { $0 == "." || $0 == "," }
        guard !digits.isEmpty, digits.count + marks.count == scalars.count, marks.count <= 1
        else { return nil }
        let normalised = String(String.UnicodeScalarView(scalars)).replacingOccurrences(
            of: ",", with: ".")
        // A string of digits too long for a Double is not a number to report.
        return Double(normalised).flatMap { $0.isFinite ? (negative ? -$0 : $0) : nil }
    }
}
