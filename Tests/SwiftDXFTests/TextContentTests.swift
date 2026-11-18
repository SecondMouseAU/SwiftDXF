import Foundation
import Testing

@testable import SwiftDXF

/// TEXT and MTEXT strings: the special characters, the MTEXT formatting codes and the stacks.
///
/// The expected values agree with ezdxf (`tools/text_oracle.py`) apart from the differences the
/// README lists.
@Suite("Text codes")
struct TextContentTests {

    /// A drawing whose entities are `records`.
    static func read(
        _ records: [DXFBuilder.Record], options: DXF.ReadOptions = .init()
    ) throws -> DXF.Drawing {
        var b = DXFBuilder()
        b.entities = records
        return try DXF.read(text: b.text(), options: options)
    }

    /// The `string` of each text entity, in order.
    static func strings(_ dwg: DXF.Drawing) -> [String] {
        dwg.entities.compactMap {
            guard case .text(_, _, _, let string, _, _) = $0 else { return nil }
            return string
        }
    }

    static func text(_ raw: String) -> DXF.TextContent { .init(raw, syntax: .text) }
    static func mtext(_ raw: String) -> DXF.TextContent { .init(raw, syntax: .mtext) }

    @Test("TEXT reads the diameter, degree and plus-minus signs")
    func specialCharacters() throws {
        let dwg = try Self.read([
            DXFBuilder.text("Fresa %%c 26"), DXFBuilder.text("1x45%%d"),
            DXFBuilder.text("%%p0,02"), DXFBuilder.text("%%C42"),
        ])
        #expect(Self.strings(dwg) == ["Fresa ⌀ 26", "1x45°", "±0,02", "⌀42"])
        let content = try #require(dwg.textContent(ofEntityAt: 0))
        #expect(content.raw == "Fresa %%c 26" && content.syntax == .text)
        #expect(content.parts == [.text("Fresa ⌀ 26")] && content.stacks.isEmpty)
    }

    @Test("%%nnn is the character with that number; %%u, %%o and %%k are dropped")
    func characterNumbers() {
        #expect(Self.text("45%%176").plain == "45°")
        #expect(Self.text("%%065%%066").plain == "AB")
        #expect(Self.text("100%%%").plain == "100%")
        #expect(Self.text("%%uunder%%u, %%oover%%o, %%kstruck%%k").plain == "under, over, struck")
        #expect(Self.mtext("%%d%%P%%U").plain == "°±")
        // Not a code, or the number of a control character or of none up to 255: kept as written.
        #expect(Self.text("10% of %%x").plain == "10% of %%x")
        #expect(Self.text("a%%").plain == "a%%")
        #expect(Self.text("%%010 %%128 %%256").plain == "%%010 %%128 %%256")
        // The number has three digits.
        #expect(Self.text("%%65").plain == "%%65")
    }

    @Test("MTEXT: a fit tolerance is a stack, and the plain text reads the value and tolerance")
    func stackedTolerance() throws {
        let raw = #"36{\H2.4;\S+0,011^ -0,005;}"#
        let dwg = try Self.read([DXFBuilder.mtext(raw)])
        #expect(Self.strings(dwg) == ["36 +0,011/-0,005"])
        let content = try #require(dwg.textContent(ofEntityAt: 0))
        #expect(content.raw == raw && content.syntax == .mtext)
        let tolerance = DXF.StackedText(upper: "+0,011", lower: "-0,005", kind: .tolerance)
        #expect(content.parts == [.text("36"), .stack(tolerance)])
        #expect(content.stacks == [tolerance])
        #expect(tolerance.upperValue == 0.011 && tolerance.lowerValue == -0.005)
    }

    @Test("MTEXT formatting codes are removed with their arguments, and the groups with them")
    func formattingCodes() {
        #expect(Self.mtext(#"{\fArial|b1|i0|c0|p34;www.example.com}"#).plain == "www.example.com")
        #expect(Self.mtext(#"\A1;0,8{\H1.5;%%p0,02}"#).plain == "0,8±0,02")
        #expect(Self.mtext(#"{\H2x;\lA}"#).plain == "A")
        let codes = #"\A1;\C1;\c16711680;\FRomans|c0;\H2.5x;\Q15;\T1.2;\W0.8;\pxqc;x"#
        #expect(Self.mtext(codes).plain == "x")
        #expect(Self.mtext(#"\Lunder\l \Oover\o \Kstruck\k"#).plain == "under over struck")
        #expect(Self.mtext(#"a\~b \\ \{c\}"#).plain == "a\u{00A0}b \\ {c}")
        #expect(Self.mtext("{{a}b}c}").plain == "abc")
        #expect(Self.mtext(#"one\Ptwo\Nthree\Xfour"#).plain == "one\ntwo\nthree\nfour")
        // Without its `;`, a code with one value ends with the value, and a font or paragraph code
        // takes the rest of the text, as ezdxf reads them.
        #expect(
            Self.mtext(#"\H2xBig \T1.1abc \A1x \Q-15.5y \C1z \c255w"#).plain == "Big abc x y z w")
        #expect(
            Self.mtext(#"\H2.5x\S1/2;"#).stacks == [.init(upper: "1", lower: "2", kind: .fraction)])
        #expect(Self.mtext(#"\H.5;a\H5.;b\H1e1xc"#).plain == "abc")
        // An oblique angle takes no `x` factor.
        #expect(Self.mtext(#"\Q15xA"#).plain == "xA")
        #expect(Self.mtext(#"a\H2.5"#).plain == "a")
        #expect(Self.mtext(#"a\fArial|b1 rest"#).plain == "a")
    }

    @Test("stacks: fractions, a diagonal fraction, escapes, and a stack with no divider")
    func stacks() {
        let mixed = Self.mtext(#"1\S1/2;""#)
        #expect(mixed.plain == #"1 1/2""#)
        #expect(mixed.stacks == [.init(upper: "1", lower: "2", kind: .fraction)])
        let diagonal = DXF.StackedText(upper: "3", lower: "4", kind: .diagonalFraction)
        #expect(Self.mtext(#"\S3#4;"#).stacks == [diagonal])
        // A backslash makes the next character text, so `\/` does not divide the parts.
        #expect(
            Self.mtext(#"\S1\/2/3;"#).stacks == [.init(upper: "1/2", lower: "3", kind: .fraction)])
        // Only the first divider divides.
        #expect(
            Self.mtext(#"\S1/2/3;"#).stacks == [.init(upper: "1", lower: "2/3", kind: .fraction)])
        // A `^` written without the space of the caret notation divides too.
        #expect(
            Self.mtext(#"\S+0.1^-0.2;"#).stacks == [
                .init(upper: "+0.1", lower: "-0.2", kind: .tolerance)
            ])
        // The special characters inside a stack are read.
        #expect(
            Self.mtext(#"\S%%p0,1^ 0;"#).stacks == [
                .init(upper: "±0,1", lower: "0", kind: .tolerance)
            ])
        // Without a `;` the stack runs to the end; without a divider nothing is stacked, and `^J`
        // is a line break, not a divider.
        #expect(Self.mtext(#"\S1/2"#).stacks == [.init(upper: "1", lower: "2", kind: .fraction)])
        #expect(Self.mtext(#"\S1^J2;"#).stacks.isEmpty)
        #expect(Self.mtext(#"\S1^I2;"#).plain == "1\t2")
        let flat = Self.mtext(#"a\Sbc;d"#)
        #expect(flat.stacks.isEmpty && flat.plain == "abcd")
        #expect(Self.mtext(#"\S1^ 2;\S3^ 4;"#).plain == "1/2 3/4")
        // A space already there is not doubled.
        #expect(Self.mtext(#"36 \S+0,011^ -0,005;"#).plain == "36 +0,011/-0,005")
        // A stack whose `;` is missing ends with its group.
        let grouped = Self.mtext(#"{\S1/2}mm"#)
        #expect(grouped.stacks == [.init(upper: "1", lower: "2", kind: .fraction)])
        #expect(grouped.plain == "1/2mm")
    }

    @Test("in TEXT a backslash is a character, so a file path stays whole")
    func textBackslash() throws {
        let path = #"C:\DOCUMENTS\BACKUP\SANITARY\PLANTA.DWG"#
        let dwg = try Self.read([DXFBuilder.text(path), DXFBuilder.text(#"{\H2;x}"#)])
        #expect(Self.strings(dwg) == [path, #"{\H2;x}"#])
        #expect(Self.text(#"x\U+00B1y"#).plain == "x±y")
    }

    @Test("caret notation: a caret, a tab and a line break; other carets are text")
    func carets() {
        #expect(Self.mtext("For M4^JScrew Size").plain == "For M4\nScrew Size")
        #expect(Self.text("x^ 2^Iy").plain == "x^2\ty")
        // Jw_cad writes `^u` before a superscript, which is not caret notation.
        #expect(Self.text("ｍ^u3").plain == "ｍ^u3")
    }

    @Test("a code that is not understood is kept as written")
    func unknownCodes() {
        #expect(Self.mtext(#"a\zb"#).plain == #"a\zb"#)
        #expect(Self.mtext(#"\M+18342"#).plain == #"\M+18342"#)
        #expect(Self.text(#"\U+D800 \U+000A"#).plain == #"\U+D800 \U+000A"#)
        #expect(Self.mtext(#"end\"#).plain == #"end\"#)
    }

    @Test("an MTEXT string continued in group 3 is joined before it is decoded")
    func continuation() throws {
        let dwg = try Self.read([
            DXFBuilder.mtext(#"11^ -0,005;}"#, continued: [#"36{\H2.4;\S+0,0"#])
        ])
        #expect(Self.strings(dwg) == ["36 +0,011/-0,005"])
        #expect(dwg.textContent(ofEntityAt: 0)?.raw == #"36{\H2.4;\S+0,011^ -0,005;}"#)
    }

    @Test("the decoded strings line up with the entities, also through a block")
    func alignment() throws {
        var b = DXFBuilder()
        b.blocks = [(name: "TAG", base: (0, 0), body: [DXFBuilder.text("%%c8")])]
        b.entities = [
            DXFBuilder.line((0, 0), (1, 0)), DXFBuilder.insert("TAG", at: (5, 5)),
            DXFBuilder.mtext(#"\S1/2;"#),
        ]
        let dwg = try DXF.read(text: b.text())
        #expect(dwg.textContent(ofEntityAt: 0) == nil)
        #expect(dwg.textContent(ofEntityAt: 1)?.stacks.count == 1)
        #expect(dwg.textContent(ofEntityAt: 2) == nil)
        let block = try #require(dwg.blocks.first { $0.name == "TAG" })
        #expect(block.textContents == [Self.text("%%c8")])

        var expanded = try DXF.read(text: b.text(), options: .init(expandBlocks: true))
        #expect(Self.strings(expanded) == ["1/2", "⌀8"])
        #expect(expanded.textContent(ofEntityAt: 2)?.raw == "%%c8")
        expanded.entities.removeFirst()
        #expect(expanded.textContents.isEmpty && expanded.textContent(ofEntityAt: 1) == nil)
    }

    @Test("a stacked part reads as a number with a point or a comma as the decimal mark")
    func stackNumbers() {
        #expect(DXF.StackedText.number("+0,011") == 0.011)
        #expect(DXF.StackedText.number(" -0.005 ") == -0.005)
        #expect(DXF.StackedText.number("0") == 0)
        #expect(DXF.StackedText.number("\u{2212}0,2") == -0.2)
        for text in ["", "+", "1,2,3", "H7", "5-", "1.5mm", "1e3", "inf"] {
            #expect(DXF.StackedText.number(text) == nil, "\(text)")
        }
    }
}
