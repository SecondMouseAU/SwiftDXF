import Foundation
import Testing

@testable import SwiftDXF

/// The drawing's code page: how a file's bytes, `%%nnn` and `\M+nXXXX` are read, and the join of
/// a surrogate pair written as two `\U+` escapes.
///
/// Expected values come from Python's codecs and from `ezdxf` (`tools/text_oracle.py`), apart from
/// `%%nnn`, which `ezdxf` does not decode.
@Suite("Code pages")
struct CodePageTests {

    /// A file with one `TEXT` whose string is `bytes` as they are, under the `$DWGCODEPAGE` `page`.
    static func file(page: String?, bytes: [UInt8]) -> Data {
        var builder = DXFBuilder()
        builder.codePage = page
        builder.entities = [DXFBuilder.text("@@")]
        var data = Data(builder.text().utf8)
        data.replaceSubrange(data.range(of: Data("@@".utf8))!, with: bytes)
        return data
    }

    static func strings(_ dwg: DXF.Drawing) -> [String] { TextContentTests.strings(dwg) }

    static func page(_ name: String) -> DXF.CodePage? { DXF.CodePage(name: name) }

    static func text(
        _ raw: String, _ syntax: DXF.TextContent.Syntax = .text, page: String? = nil
    ) -> DXF.TextContent {
        .init(raw, syntax: syntax, codePage: page.flatMap { Self.page($0) })
    }

    // MARK: the name

    @Test("$DWGCODEPAGE names a page as ANSI_ and its number")
    func names() throws {
        let sjis = try #require(Self.page("ANSI_932"))
        #expect(sjis.number == 932 && sjis.name == "ANSI_932")
        #expect(Self.page(" ansi_1252 ")?.number == 1252)
        for name in ["ANSI_874", "ANSI_936", "ANSI_949", "ANSI_950", "ANSI_1250", "ANSI_1258"] {
            #expect(Self.page(name)?.name == name)
        }
        // Johab (1361) is not decoded by the platform, so it is not a page this reads.
        for name in [
            "ANSI_1361", "DOS437", "ISO8859-1", "MACINTOSH", "ANSI_1200", "ANSI_", "932", "",
        ] {
            #expect(Self.page(name) == nil, "\(name) is not read")
        }
    }

    // MARK: the bytes of the file

    /// The pages every platform decodes, and, with CoreFoundation, the rest.
    static let pageCases: [(String, [UInt8], String)] = {
        var cases: [(String, [UInt8], String)] = [
            ("ANSI_932", [0x93, 0xFA, 0x96, 0x7B], "\u{65E5}\u{672C}"),
            ("ANSI_1252", [0x63, 0x61, 0x66, 0xE9, 0x20, 0x80], "caf\u{E9} \u{20AC}"),
            ("ANSI_1250", [0xB3], "\u{142}"),
            ("ANSI_1251", [0xDF], "\u{42F}"),
            ("ANSI_1253", [0xD9], "\u{3A9}"),
            ("ANSI_1254", [0xFE], "\u{15F}"),
        ]
        #if canImport(CoreFoundation)
            cases += [
                ("ANSI_936", [0xD6, 0xD0], "\u{4E2D}"),
                ("ANSI_949", [0xC7, 0xD1], "\u{D55C}"),
                ("ANSI_950", [0xA4, 0xA4], "\u{4E2D}"),
                ("ANSI_1255", [0xE0], "\u{5D0}"),
                ("ANSI_1256", [0xC7], "\u{627}"),
                ("ANSI_1257", [0xE2], "\u{101}"),
                ("ANSI_1258", [0xE3], "\u{103}"),
                ("ANSI_874", [0xA1], "\u{E01}"),
            ]
        #endif
        return cases
    }()

    @Test(
        "the bytes of a file are read in the page its header names",
        arguments: CodePageTests.pageCases)
    func fileBytes(page: String, bytes: [UInt8], expected: String) throws {
        let dwg = try DXF.read(data: Self.file(page: page, bytes: bytes))
        #expect(Self.strings(dwg) == [expected])
        #expect(dwg.codePage?.name == page)
    }

    @Test("a file that names no page, or one that is not read, is Shift-JIS, as before")
    func shiftJISDefault() throws {
        let bytes: [UInt8] = [0x93, 0xFA, 0x96, 0x7B]
        let none = try DXF.read(data: Self.file(page: nil, bytes: bytes))
        #expect(Self.strings(none) == ["\u{65E5}\u{672C}"] && none.codePage == nil)
        let dos = try DXF.read(data: Self.file(page: "DOS437", bytes: bytes))
        #expect(Self.strings(dos) == ["\u{65E5}\u{672C}"] && dos.codePage == nil)
    }

    @Test("a byte the page cannot decode is one character lost, not the file")
    func strayByte() throws {
        var builder = DXFBuilder()
        builder.codePage = "ANSI_1252"
        builder.entities = [
            DXFBuilder.text("##"), DXFBuilder.text("caf@@"), DXFBuilder.text("@@@@"),
        ]
        var data = Data(builder.text().utf8)
        data.replaceSubrange(data.range(of: Data("##".utf8))!, with: [0x81])
        data.replaceSubrange(data.range(of: Data("@@@@".utf8))!, with: [0xE9, 0x80])
        data.replaceSubrange(data.range(of: Data("@@".utf8))!, with: [0xE9])
        let strings = Self.strings(try DXF.read(data: data))
        #expect(strings.count == 3)
        #expect(strings[1] == "caf\u{E9}" && strings[2] == "\u{E9}\u{20AC}")
        // The same for a multibyte page: a lone lead byte is one character lost.
        var japanese = DXFBuilder()
        japanese.codePage = "ANSI_932"
        japanese.entities = [DXFBuilder.text("##"), DXFBuilder.text("@@")]
        var sjis = Data(japanese.text().utf8)
        sjis.replaceSubrange(sjis.range(of: Data("##".utf8))!, with: [0x81])
        sjis.replaceSubrange(sjis.range(of: Data("@@".utf8))!, with: [0x93, 0xFA])
        let lines = Self.strings(try DXF.read(data: sjis))
        #expect(lines.count == 2 && lines[1] == "\u{65E5}")
    }

    @Test("valid UTF-8 is UTF-8 whatever the header names, and the page is still read")
    func utf8() throws {
        let bytes = Array("caf\u{E9} \u{65E5}".utf8)
        let dwg = try DXF.read(data: Self.file(page: "ANSI_1252", bytes: bytes))
        #expect(Self.strings(dwg) == ["caf\u{E9} \u{65E5}"])
        #expect(dwg.codePage?.number == 1252)
    }

    @Test("the page is read from a string too, and the header of a hand-built drawing has none")
    func pageOfText() throws {
        var builder = DXFBuilder()
        builder.codePage = "ANSI_932"
        #expect(try DXF.read(text: builder.text()).codePage?.number == 932)
        #expect(try DXF.read(text: DXFBuilder().text()).codePage == nil)
        #expect(DXF.Drawing().codePage == nil)
    }

    // MARK: \M+nXXXX

    /// `\M+nXXXX` cases: Shift-JIS everywhere, and with CoreFoundation the other pages.
    static let multibyteCases: [(String, String)] = {
        var cases: [(String, String)] = [
            ("\\M+193FA\\M+1967B", "\u{65E5}\u{672C}"),
            ("\\M+193fa", "\u{65E5}"),
            ("a\\M+193FAb", "a\u{65E5}b"),
        ]
        #if canImport(CoreFoundation)
            cases += [
                ("\\M+2A4A4", "\u{4E2D}"),
                ("\\M+3C7D1", "\u{D55C}"),
                ("\\M+5D6D0", "\u{4E2D}"),
            ]
        #endif
        return cases
    }()

    @Test(
        "\\M+nXXXX is a character of the multibyte page n names",
        arguments: CodePageTests.multibyteCases)
    func multibyte(raw: String, expected: String) {
        for syntax in [DXF.TextContent.Syntax.text, .mtext] {
            #expect(Self.text(raw, syntax).plain == expected)
            // The drawing's own page does not change which page n names.
            #expect(Self.text(raw, syntax, page: "ANSI_1252").plain == expected)
        }
    }

    @Test("a \\M+nXXXX that cannot be read is kept as written")
    func multibyteKept() {
        for raw in [
            "\\M+6A4A4",  // n is 1 to 5
            "\\M+4B0A1",  // Korean Johab, which the platform does not decode
            "\\M+1ZZZZ",  // not hex digits
            "\\M+181FF",  // 0x81FF is not a Shift-JIS character
            "\\M+10041",  // 0x0041 holds a control character
            "\\M+193F",  // too short
        ] {
            for syntax in [DXF.TextContent.Syntax.text, .mtext] {
                #expect(Self.text(raw, syntax).plain == raw, "\(raw)")
            }
        }
    }

    @Test("\\M+nXXXX in a stack and in the text of a dimension")
    func multibyteInStacksAndDimensions() {
        let stacked = Self.text("\\S\\M+193FA^ \\M+1967B;", .mtext)
        #expect(stacked.stacks == [.init(upper: "\u{65E5}", lower: "\u{672C}", kind: .tolerance)])
        #expect(
            DXF.DimensionText("\\M+193FA<>").parts == [.words("\u{65E5}"), .measurement])
        // The digits of a character that was read are not a typed number.
        #expect(DXF.DimensionText("\\M+18342 5").typedNumbers == [5])
        // The digits of a code kept as written (Johab is not decoded) are not typed numbers either.
        #expect(DXF.DimensionText("\\M+48342 5").typedNumbers == [5])
    }

    // MARK: %%nnn

    @Test("%%nnn is a byte of the drawing's page")
    func characterNumbers() {
        #expect(Self.text("%%128", page: "ANSI_1252").plain == "\u{20AC}")
        #expect(Self.text("%%233%%176%%065", page: "ANSI_1252").plain == "\u{E9}\u{B0}A")
        #expect(Self.text("%%223", page: "ANSI_1251").plain == "\u{42F}")
        #expect(Self.text("%%177", page: "ANSI_932").plain == "\u{FF71}")
        #expect(Self.text("%%176", page: "ANSI_932").plain == "\u{FF70}")
        // Below 128 a byte is ASCII in every page, whether or not the platform decodes the page.
        for page in ["ANSI_874", "ANSI_936", "ANSI_949", "ANSI_950", "ANSI_1255", "ANSI_1258"] {
            #expect(Self.text("%%065%%048", page: page).plain == "A0", "\(page)")
        }
        // The first byte of a double-byte character is not a character of its own.
        #expect(Self.text("%%129", page: "ANSI_932").plain == "%%129")
        // A byte the page leaves unassigned, a control character, and a number above 255.
        #expect(Self.text("%%129", page: "ANSI_1252").plain == "%%129")
        #expect(Self.text("%%031", page: "ANSI_1252").plain == "%%031")
        #expect(Self.text("%%256", page: "ANSI_1252").plain == "%%256")
        // Without a page the number is a Unicode code point, as before.
        #expect(Self.text("%%233").plain == "\u{E9}")
        #expect(Self.text("%%128").plain == "%%128")
    }

    @Test("a drawing reads %%nnn through its page, in text, blocks and dimensions")
    func drawingReadsThroughItsPage() throws {
        var builder = DXFBuilder()
        builder.codePage = "ANSI_1252"
        builder.entities = [
            DXFBuilder.text("%%128 %%c"), DXFBuilder.mtext("{\\H2;%%233}"),
            [
                (0, "DIMENSION"), (8, "0"), (1, "%%128<>"), (70, "0"), (10, "0"), (20, "5"),
                (30, "0"), (11, "5"), (21, "5"), (31, "0"), (13, "0"), (23, "0"), (33, "0"),
                (14, "10"), (24, "0"), (34, "0"),
            ],
        ]
        builder.blocks = [(name: "B", base: (0, 0), body: [DXFBuilder.text("%%128")])]
        let dwg = try DXF.read(text: builder.text())
        #expect(Self.strings(dwg) == ["\u{20AC} \u{2300}", "\u{E9}"])
        #expect(dwg.blocks[0].textContents.first??.plain == "\u{20AC}")
        guard case .dimension(let dimension) = dwg.entities[2] else {
            Issue.record("not a dimension")
            return
        }
        #expect(dimension.codePage?.number == 1252)
        #expect(dimension.text.parts == [.words("\u{20AC}"), .measurement])
        // The raw override is untouched.
        #expect(dimension.textOverride == "%%128<>")
    }

    // MARK: surrogate pairs

    @Test(
        "two \\U+ escapes that make a surrogate pair are one character",
        arguments: [
            ("a\\U+D83D\\U+DE00b", "a\u{1F600}b"),
            ("\\U+d83d\\U+de00", "\u{1F600}"),
            ("\\U+D83D\\U+DE00\\U+D83D\\U+DE01", "\u{1F600}\u{1F601}"),
            ("\\U+D800\\U+DC00", "\u{10000}"),
            ("\\U+DBFF\\U+DFFF", "\u{10FFFF}"),
        ] as [(String, String)])
    func surrogatePairs(raw: String, expected: String) {
        for syntax in [DXF.TextContent.Syntax.text, .mtext] {
            #expect(Self.text(raw, syntax).plain == expected)
        }
    }

    @Test("half a surrogate pair is kept as written")
    func lonelySurrogates() {
        for raw in [
            "\\U+D83D",  // a high half alone
            "\\U+DE00",  // a low half alone
            "\\U+DE00\\U+D83D",  // the halves the wrong way round
            "\\U+D83Dx\\U+DE00",  // apart
            "\\U+D83D\\U+D83D",  // two high halves
        ] {
            #expect(Self.text(raw).plain == raw, "\(raw)")
        }
        // A high half before an ordinary escape leaves the escape alone.
        #expect(Self.text("\\U+D83D\\U+0041").plain == "\\U+D83DA")
        // A high half before a pair keeps its own and joins the pair.
        #expect(Self.text("\\U+D83D\\U+D83D\\U+DE00").plain == "\\U+D83D\u{1F600}")
    }

    @Test("a surrogate pair in a stack and in the text of a dimension")
    func surrogatePairsInStacksAndDimensions() {
        let stacked = Self.text("\\S\\U+D83D\\U+DE00/x;", .mtext)
        #expect(stacked.stacks == [.init(upper: "\u{1F600}", lower: "x", kind: .fraction)])
        #expect(
            DXF.DimensionText("\\U+D83D\\U+DE00<>").parts == [.words("\u{1F600}"), .measurement])
    }
}
