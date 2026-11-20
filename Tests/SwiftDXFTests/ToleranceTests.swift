import Foundation
import Testing

@testable import SwiftDXF

/// TOLERANCE, the geometric tolerance of GD&T, and its frame string.
///
/// The record of the first test is the one in issue 34, as AutoCAD's DXF export writes it. The
/// symbol letters are those of `gdt.shx` (Goodheart-Willcox, *AutoCAD and Its Applications*), and
/// the string of `autodeskExample` is the one in Autodesk's own example for the feature control
/// frame. No drawing on the machine holds a TOLERANCE, and `ezdxf` has no parser
/// for the string, so the frames are asserted here from the format; `Fixtures/solids.dxf`
/// (`tools/solid_fixtures.py`) checks the record around the string against `ezdxf`.
@Suite("TOLERANCE")
struct ToleranceTests {

    static func tolerances(_ dwg: DXF.Drawing) -> [DXF.Tolerance] {
        dwg.entities.compactMap {
            if case .tolerance(let t) = $0 { return t } else { return nil }
        }
    }

    /// The only TOLERANCE of a drawing whose entities are `records`.
    static func read(_ records: [String]) throws -> DXF.Tolerance {
        let dwg = try DXF.read(text: RawDXF.entities(records))
        return try #require(tolerances(dwg).first)
    }

    /// A TOLERANCE record with group 1 `text`.
    static func record(_ text: String) -> String {
        RawDXF.record("TOLERANCE", (8, "Quote"), (3, "ISO-25"), (10, "1"), (20, "2"), (1, text))
    }

    /// The frames of `text`, read through a TOLERANCE record.
    static func frames(_ text: String) throws -> [DXF.Tolerance.Frame] {
        try read([record(text)]).frames
    }

    // MARK: The acceptance record

    @Test(
        "the record of the issue reads as one frame: symmetry, 0.012, datum B, at (388.5, 557.92)")
    func acceptance() throws {
        // As in the issue: no group 30, and direction groups 11 and 21 only.
        let dwg = try DXF.read(
            text: RawDXF.entities([
                RawDXF.record(
                    "TOLERANCE", (8, "Quote"), (3, "ISO-25"), (10, "388.5"), (20, "557.92"),
                    (11, "1.0"), (21, "0.0"), (1, #"{\Fgdt;i}%%v0.012%%v%%vB%%v%%v"#))
            ]))
        #expect(dwg.skipped.isEmpty && dwg.counts.tolerance == 1 && dwg.counts.total == 1)
        let t = try #require(Self.tolerances(dwg).first)
        #expect(t.insertion == DXF.Point(388.5, 557.92, 0))
        #expect(t.direction == DXF.Point(1, 0, 0) && t.rotationDeg == 0)
        #expect(t.styleName == "ISO-25" && t.layer == "Quote" && t.color == 256)
        #expect(t.text == #"{\Fgdt;i}%%v0.012%%v%%vB%%v%%v"#)

        #expect(t.frames.count == 1)
        let frame = try #require(t.frames.first)
        #expect(frame.characteristic == .symmetry)
        #expect(frame.tolerance == .init(isDiameter: false, value: 0.012, text: "0.012"))
        #expect(frame.secondTolerance == nil)
        #expect(frame.datums == [.init(reference: "B")])
        #expect(frame.unread.isEmpty && frame.isFullyRead && t.isFullyRead)
        #expect(frame.raw == t.text)
    }

    @Test("a TOLERANCE with no direction, style or layer reads with the defaults")
    func defaults() throws {
        let t = try Self.read([RawDXF.record("TOLERANCE", (10, "5"), (20, "6"), (1, "x"))])
        #expect(t.direction == DXF.Point(1, 0, 0) && t.styleName == nil && t.layer == "0")
        #expect(t.insertion == DXF.Point(5, 6, 0))
        // A group 3 with nothing in it is no style.
        let blank = try Self.read([RawDXF.record("TOLERANCE", (3, "  "), (10, "5"), (20, "6"))])
        #expect(blank.styleName == nil)
        let none = try Self.read([RawDXF.record("TOLERANCE", (10, "5"), (20, "6"))])
        #expect(none.text == "" && none.frames.isEmpty && none.isFullyRead)
    }

    @Test("the direction gives the rotation of the frame")
    func rotation() throws {
        let t = try Self.read([
            RawDXF.record("TOLERANCE", (10, "0"), (20, "0"), (11, "0"), (21, "2"), (31, "0"))
        ])
        #expect(t.direction == DXF.Point(0, 2, 0) && abs(t.rotationDeg - 90) < 1e-12)
    }

    // MARK: Characteristics

    @Test("each letter of the GDT font that starts a frame is its characteristic")
    func characteristics() throws {
        let expected: [(Character, DXF.Tolerance.Characteristic)] = [
            ("a", .angularity), ("b", .perpendicularity), ("c", .flatness),
            ("d", .profileOfSurface), ("e", .circularity), ("f", .parallelism),
            ("g", .cylindricity), ("h", .circularRunout), ("i", .symmetry), ("j", .position),
            ("k", .profileOfLine), ("r", .concentricity), ("t", .totalRunout),
            ("u", .straightness),
        ]
        for (letter, characteristic) in expected {
            let frames = try Self.frames("{\\Fgdt;\(letter)}%%v0.1")
            #expect(frames.first?.characteristic == characteristic, "letter \(letter)")
        }
    }

    @Test("a letter that is not a characteristic is kept as written and flagged, not guessed")
    func unrecognisedSymbol() throws {
        // y is the conical taper of the font, and n a diameter: neither starts a frame.
        for letter in ["y", "n", "m", "z"] {
            let t = try Self.read([Self.record("{\\Fgdt;\(letter)}%%v0.1")])
            let frame = try #require(t.frames.first)
            #expect(frame.characteristic == .unrecognised("{\\Fgdt;\(letter)}"), "letter \(letter)")
            #expect(!frame.isFullyRead && !t.isFullyRead)
            // The rest of the frame is still read.
            #expect(frame.tolerance?.value == 0.1)
        }
        // Text, or a symbol and text, is no symbol either.
        #expect(try Self.frames("PLANE%%v0.1").first?.characteristic == .unrecognised("PLANE"))
        #expect(
            try Self.frames(#"{\Fgdt;j}x%%v0.1"#).first?.characteristic
                == .unrecognised(#"{\Fgdt;j}x"#))
    }

    @Test("the font of the symbol may be written as AutoCAD writes the other fonts")
    func fontSpellings() throws {
        for font in ["gdt", "GDT", "gdt.shx", "gdt|b0|i0|c0|p34", "GDT_IV25", "gdt_iv50"] {
            let frames = try Self.frames("{\\F\(font);j}%%v0.1")
            #expect(frames.first?.characteristic == .position, "font \(font)")
        }
        // The same letter in another font is only text.
        let other = try Self.frames("{\\Farial;j}%%v0.1")
        #expect(other.first?.characteristic == .unrecognised("{\\Farial;j}"))
    }

    // MARK: Tolerances

    @Test("a diameter written with the GDT font, as in Autodesk's example, is a diameter zone")
    func autodeskExample() throws {
        // AddTolerance in Autodesk's .NET guide: position, diameter 0.001, no datum.
        let frame = try #require(try Self.frames(#"{\Fgdt;j}%%v{\Fgdt;n}0.001%%v%%v%%v%%v"#).first)
        #expect(frame.characteristic == .position)
        #expect(frame.tolerance == .init(isDiameter: true, value: 0.001, text: "0.001"))
        #expect(frame.secondTolerance == nil && frame.datums.isEmpty && frame.isFullyRead)
    }

    @Test("%%c is a diameter, and a material condition follows its value or datum")
    func diameterAndMaterialCondition() throws {
        let frame = try #require(
            try Self.frames(#"{\Fgdt;j}%%v%%c0.1{\Fgdt;m}%%v%%vA%%vB{\Fgdt;m}%%vC"#).first)
        #expect(frame.characteristic == .position)
        #expect(
            frame.tolerance
                == .init(isDiameter: true, value: 0.1, text: "0.1", materialCondition: .maximum))
        #expect(
            frame.datums == [
                .init(reference: "A"), .init(reference: "B", materialCondition: .maximum),
                .init(reference: "C"),
            ])
        #expect(frame.isFullyRead)
        // `%%C` is the same code in capitals.
        let upper = try Self.frames(#"{\Fgdt;j}%%v%%C0.1"#).first
        #expect(upper?.tolerance?.isDiameter == true && upper?.tolerance?.value == 0.1)
    }

    @Test("the three material conditions are the letters m, l and s")
    func materialConditions() throws {
        let kinds: [(Character, DXF.Tolerance.MaterialCondition)] = [
            ("m", .maximum), ("l", .least), ("s", .regardlessOfFeatureSize),
        ]
        for (letter, kind) in kinds {
            let frame = try #require(
                try Self.frames("{\\Fgdt;j}%%v0.5{\\Fgdt;\(letter)}%%vA").first)
            #expect(frame.tolerance?.materialCondition == kind, "letter \(letter)")
            #expect(frame.tolerance?.value == 0.5 && frame.tolerance?.text == "0.5")
        }
    }

    @Test("a comma is the decimal mark with no point, and a value that is not a number is nil")
    func values() throws {
        #expect(try Self.frames(#"{\Fgdt;c}%%v0,05"#).first?.tolerance?.value == 0.05)
        #expect(try Self.frames(#"{\Fgdt;c}%%v.5"#).first?.tolerance?.value == 0.5)
        #expect(try Self.frames(#"{\Fgdt;c}%%v +0.02 "#).first?.tolerance?.value == 0.02)
        for text in ["0.05/25", "0.05.1", "1,000.5", "1e3", "inf", "abc", "-"] {
            let zone = try #require(try Self.frames("{\\Fgdt;c}%%v\(text)").first?.tolerance)
            #expect(zone.value == nil && zone.text == text, "text \(text)")
            // The frame says it has a box that is no number.
            #expect(try Self.frames("{\\Fgdt;c}%%v\(text)").first?.isFullyRead == false)
        }
    }

    @Test("text on both sides of a modifier is not run together into one number")
    func modifierBetweenText() throws {
        let value = try #require(try Self.frames(#"{\Fgdt;j}%%v5{\Fgdt;m}12%%v%%vA"#).first)
        #expect(value.tolerance?.text == "5 12" && value.tolerance?.value == nil)
        #expect(value.tolerance?.materialCondition == .maximum && !value.isFullyRead)
        let projected = try #require(try Self.frames(#"{\Fgdt;j}%%v0.05{\Fgdt;p}12"#).first)
        #expect(projected.tolerance?.value == nil && projected.tolerance?.isProjected == true)
        #expect(!projected.isFullyRead)
        let datum = try #require(try Self.frames(#"{\Fgdt;j}%%v0.1%%v%%vA{\Fgdt;m}B"#).first)
        #expect(datum.datums == [.init(reference: "A B", materialCondition: .maximum)])
        // A modifier at either end leaves the text as it was.
        let ends = try #require(try Self.frames(#"{\Fgdt;j}%%v{\Fgdt;n}0.5{\Fgdt;m}"#).first)
        #expect(ends.tolerance?.text == "0.5" && ends.tolerance?.value == 0.5)
    }

    @Test("a minus sign, written as U+2212, is read as a stack part is")
    func minusSign() throws {
        #expect(try Self.frames("{\\Fgdt;c}%%v\u{2212}0.5").first?.tolerance?.value == -0.5)
    }

    @Test("a tolerance box with only a modifier has no number, and the frame is not fully read")
    func zoneWithoutNumber() throws {
        let frame = try #require(try Self.frames(#"{\Fgdt;j}%%v{\Fgdt;n}%%v%%vA"#).first)
        #expect(frame.tolerance == .init(isDiameter: true, value: nil, text: ""))
        #expect(!frame.isFullyRead)
    }

    @Test("a second tolerance box is the second tolerance, apart from the first")
    func secondTolerance() throws {
        let frame = try #require(try Self.frames(#"{\Fgdt;j}%%v%%c0.5%%v0.2%%vA"#).first)
        #expect(frame.tolerance?.value == 0.5 && frame.tolerance?.isDiameter == true)
        #expect(frame.secondTolerance == .init(isDiameter: false, value: 0.2, text: "0.2"))
        #expect(frame.datums == [.init(reference: "A")])
    }

    @Test("a symbol the reader does not know in a box is kept in its text and listed")
    func unreadSymbolInBox() throws {
        // o is the square of the font: not a diameter or a material condition.
        let frame = try #require(try Self.frames(#"{\Fgdt;c}%%v{\Fgdt;o}0.5"#).first)
        #expect(frame.characteristic == .flatness)
        #expect(frame.tolerance?.text == #"{\Fgdt;o}0.5"# && frame.tolerance?.value == nil)
        #expect(frame.unread == [#"{\Fgdt;o}"#] && !frame.isFullyRead)
        // A second material condition is not read over the first.
        let twice = try #require(try Self.frames(#"{\Fgdt;c}%%v0.5{\Fgdt;m}{\Fgdt;l}"#).first)
        #expect(twice.tolerance?.materialCondition == .maximum)
        #expect(twice.unread == [#"{\Fgdt;l}"#])
    }

    @Test("a group of several letters is kept as one group per letter, not repeated")
    func groupOfSeveralLetters() throws {
        let first = try Self.frames(#"{\Fgdt;oq}%%v0.1"#).first
        #expect(first?.characteristic == .unrecognised(#"{\Fgdt;o}{\Fgdt;q}"#))
        let frame = try #require(try Self.frames(#"{\Fgdt;c}%%v{\Fgdt;oq}0.5"#).first)
        #expect(frame.tolerance?.text == #"{\Fgdt;o}{\Fgdt;q}0.5"#)
        #expect(frame.unread == [#"{\Fgdt;o}"#, #"{\Fgdt;q}"#])
        // The letters that are read are read from a group of several as from one of their own.
        let read = try #require(try Self.frames(#"{\Fgdt;j}%%v{\Fgdt;nm}0.5"#).first)
        #expect(
            read.tolerance
                == .init(
                    isDiameter: true, value: 0.5, text: "0.5", materialCondition: .maximum))
        #expect(read.isFullyRead)
    }

    @Test("a projected zone follows a tolerance, and is not a datum")
    func projectedZone() throws {
        let frame = try #require(
            try Self.frames(#"{\Fgdt;j}%%v%%c0.5{\Fgdt;m}{\Fgdt;p}%%v%%vA"#).first)
        #expect(
            frame.tolerance
                == .init(
                    isDiameter: true, value: 0.5, text: "0.5", materialCondition: .maximum,
                    isProjected: true))
        #expect(frame.isFullyRead)
        // In a datum box the symbol is not understood, so it is kept and listed.
        let datum = try #require(try Self.frames(#"{\Fgdt;j}%%v0.5%%v%%vA{\Fgdt;p}"#).first)
        #expect(datum.datums == [.init(reference: #"A{\Fgdt;p}"#)])
        #expect(datum.unread == [#"{\Fgdt;p}"#])
    }

    @Test("a box after the sixth has no place in the layout and is kept as written")
    func extraBoxes() throws {
        let frame = try #require(
            try Self.frames(#"{\Fgdt;j}%%v0.1%%v%%vA%%v%%v%%v12%%v%%vX"#).first)
        #expect(frame.datums == [.init(reference: "A")])
        #expect(frame.unread == ["12", "X"] && !frame.isFullyRead)
    }

    // MARK: Rows and boxes

    @Test("a second line, after ^J, is a second frame of a composite")
    func compositeFrame() throws {
        let frames = try Self.frames(#"{\Fgdt;j}%%v%%c0.5%%v%%vA%%vB%%v^J%%v%%c0.2%%v%%vA"#)
        #expect(frames.count == 2)
        #expect(frames[0].characteristic == .position && frames[0].tolerance?.value == 0.5)
        #expect(frames[0].datums == [.init(reference: "A"), .init(reference: "B")])
        // The second row has no symbol of its own.
        #expect(frames[1].characteristic == nil && frames[1].tolerance?.value == 0.2)
        #expect(frames[1].datums == [.init(reference: "A")])
        #expect(frames[1].raw == "%%v%%c0.2%%v%%vA")
    }

    @Test("a row with nothing in it is left out, and the empty string has no frames")
    func emptyRows() throws {
        #expect(try Self.frames("").isEmpty)
        #expect(try Self.frames("%%v%%v%%v").isEmpty)
        #expect(try Self.frames("   ").isEmpty)
        let frames = try Self.frames(#"^J{\Fgdt;c}%%v0.1^J^J%%v%%v"#)
        #expect(frames.count == 1 && frames[0].characteristic == .flatness)
    }

    @Test("a caret and a space is a caret, and %%% is a percent sign, not the start of a code")
    func literalCodes() throws {
        let caret = try #require(try Self.frames(#"{\Fgdt;c}%%v0.1^ J"#).first)
        #expect(caret.tolerance?.text == "0.1^J")
        let percent = try #require(try Self.frames(#"{\Fgdt;c}%%v50%%%v1"#).first)
        #expect(percent.tolerance?.text == "50%v1" && percent.datums.isEmpty)
    }

    @Test("a long string of font codes, boxes or rows is read, and never traps")
    func longStrings() throws {
        let codes = DXF.Tolerance(
            insertion: DXF.Point(0, 0), text: String(repeating: #"{\F"#, count: 100_000))
        #expect(codes.frames.count == 1)
        let boxes = DXF.Tolerance(
            insertion: DXF.Point(0, 0),
            text: #"{\Fgdt;j}"# + String(repeating: "%%vA", count: 100_000))
        #expect(boxes.frames.first?.datums.count == 3)
        let rows = DXF.Tolerance(
            insertion: DXF.Point(0, 0), text: String(repeating: #"{\Fgdt;c}%%v1^J"#, count: 50_000))
        #expect(rows.frames.count == 50_000)
        // A string of digits too long for a Double is not a value.
        let huge = try Self.frames("{\\Fgdt;c}%%v" + String(repeating: "9", count: 400))
        #expect(huge.first?.tolerance?.value == nil && huge.first?.tolerance?.text.count == 400)
        // An unterminated group, and a group with no letters, hold nothing.
        #expect(try Self.frames(#"{\Fgdt;"#).isEmpty)
        let empty = try Self.frames(#"{\Fgdt;}%%v1"#)
        #expect(empty.count == 1 && empty[0].characteristic == nil)
        #expect(empty[0].tolerance?.value == 1)
    }

    // MARK: Code pages

    @Test("%%nnn in a box is read through the code page of the drawing, as in other text")
    func codePage() throws {
        var b = DXFBuilder()
        b.codePage = "ANSI_1252"
        b.entities = [
            [
                (0, "TOLERANCE"), (8, "Quote"), (10, "1"), (20, "2"),
                (1, #"{\Fgdt;c}%%v0.05%%128"#),
            ]
        ]
        let dwg = try DXF.read(text: b.text())
        let t = try #require(Self.tolerances(dwg).first)
        #expect(t.codePage == DXF.CodePage(name: "ANSI_1252"))
        // %%128 is the euro sign in Windows-1252.
        #expect(t.frames.first?.tolerance?.text == "0.05\u{20AC}")
        // Without the page the number is a code point, a control character, kept as written.
        let bare = DXF.Tolerance(insertion: DXF.Point(0, 0), text: #"{\Fgdt;c}%%v0.05%%128"#)
        #expect(bare.frames.first?.tolerance?.text == "0.05%%128")
    }

    @Test("text is decoded as it is in MTEXT: a formatting group inside a box is dropped")
    func mtextDecoding() throws {
        let frame = try #require(try Self.frames(#"{\Fgdt;j}%%v{\H1.2;0.05}%%v%%vA"#).first)
        #expect(frame.tolerance?.text == "0.05" && frame.tolerance?.value == 0.05)
    }

    // MARK: Blocks, and the rest of the model

    @Test("a block expansion moves the insertion and turns the direction; the frames are unchanged")
    func expansion() throws {
        var b = DXFBuilder()
        b.blocks = [
            (
                "FCF", (0, 0),
                [
                    [
                        (0, "TOLERANCE"), (8, "0"), (3, "ISO-25"), (10, "1"), (20, "2"),
                        (30, "0"), (1, #"{\Fgdt;i}%%v0.012%%v%%vB%%v%%v"#), (11, "1"), (21, "0"),
                        (31, "0"),
                    ]
                ]
            )
        ]
        b.entities = [
            DXFBuilder.insert("FCF", at: (10, 20), scale: (2, 2), rotation: 90, layer: "SHEET")
        ]
        let dwg = try DXF.read(text: b.text(), options: .init(expandBlocks: true))
        #expect(dwg.skipped.isEmpty && dwg.counts.tolerance == 1)
        let t = try #require(Self.tolerances(dwg).first)
        // (1, 2) turned by 90 degrees and doubled about (10, 20) is (10 - 4, 20 + 2) = (6, 22).
        #expect(abs(t.insertion.x - 6) < 1e-9 && abs(t.insertion.y - 22) < 1e-9)
        #expect(abs(t.direction.x) < 1e-9 && abs(t.direction.y - 2) < 1e-9)
        #expect(abs(t.rotationDeg - 90) < 1e-9)
        #expect(t.layer == "SHEET" && t.frames.first?.characteristic == .symmetry)
        #expect(t.frames.first?.tolerance?.value == 0.012)
    }

    @Test("a TOLERANCE in a block that is not expanded is counted in the block, not skipped")
    func inBlock() throws {
        var b = DXFBuilder()
        b.blocks = [
            ("FCF", (0, 0), [[(0, "TOLERANCE"), (8, "0"), (10, "0"), (20, "0"), (1, "x")]])
        ]
        let dwg = try DXF.read(text: b.text())
        let block = try #require(dwg.blocks.first)
        #expect(block.entities.count == 1 && block.skippedByLayer.isEmpty)
    }

    @Test("a drawing assembled by hand can hold one, and a change of layer keeps the frames")
    func byHand() {
        var t = DXF.Tolerance(
            insertion: DXF.Point(1, 2), direction: DXF.Point(0, 1), styleName: "S",
            text: #"{\Fgdt;b}%%v0.1%%v%%vA"#, layer: "L", color: 3)
        #expect(t.frames.first?.characteristic == .perpendicularity)
        t.text = #"{\Fgdt;f}%%v0.2%%v%%vA"#
        #expect(t.frames.first?.characteristic == .parallelism)
        let entity = DXF.Entity.tolerance(t)
        #expect(entity.layer == "L" && entity.colorIndex == 3 && entity.typeName == "TOLERANCE")
        let moved = entity.replacing(layer: "M", color: 5)
        #expect(moved.layer == "M" && moved.colorIndex == 5)
    }

    @Test("every entity type of this kind can be given another layer and colour")
    func replacingLayerAndColour() {
        let entities: [DXF.Entity] = [
            .tolerance(DXF.Tolerance(insertion: DXF.Point(0, 0), text: "x", layer: "A", color: 1)),
            .solid(DXF.Solid(corners: [DXF.Point(0, 0)], layer: "A", color: 2)),
            .wipeout(DXF.Wipeout(boundary: [DXF.Point(0, 0)], layer: "A", color: 3)),
            .face3D(DXF.Face3D(corners: [DXF.Point(0, 0)], layer: "A", color: 4)),
        ]
        #expect(entities.map(\.layer) == ["A", "A", "A", "A"])
        #expect(entities.map(\.colorIndex) == [1, 2, 3, 4])
        #expect(entities.map(\.typeName) == ["TOLERANCE", "SOLID", "WIPEOUT", "3DFACE"])
        let moved = entities.map { $0.replacing(layer: "B", color: 7) }
        #expect(moved.map(\.layer) == ["B", "B", "B", "B"])
        #expect(moved.map(\.colorIndex) == [7, 7, 7, 7])
    }

    @Test("the fixture's records are read as ezdxf reads them")
    func fixtureRecords() throws {
        let dwg = try SolidTests.fixture()
        let tolerances = Self.tolerances(dwg)
        #expect(tolerances.count == 4)
        // ezdxf: insert, x_axis_vector, dimstyle and content of each.
        for t in tolerances {
            #expect(t.insertion == DXF.Point(388.5, 557.92, 0) && t.direction == DXF.Point(1, 0, 0))
            #expect(t.styleName == "ISO-25" && t.layer == "Quote")
        }
        #expect(
            tolerances.map(\.text) == [
                #"{\Fgdt;i}%%v0.012%%v%%vB%%v%%v"#,
                #"{\Fgdt;j}%%v{\Fgdt;n}0.001%%v%%v%%v%%v"#,
                #"{\Fgdt;j}%%v%%c0.1{\Fgdt;m}%%v%%vA%%vB{\Fgdt;m}%%vC"#,
                #"{\Fgdt;j}%%v%%c0.5%%v%%vA%%vB%%v^J%%v%%c0.2%%v%%vA"#,
            ])
        #expect(tolerances.map { $0.frames.count } == [1, 1, 1, 2])
        #expect(tolerances.allSatisfy { $0.isFullyRead })
    }
}
