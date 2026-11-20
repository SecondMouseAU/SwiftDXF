import Foundation
import Testing

@testable import SwiftDXF

/// The header variables of a drawing: the five it names for #31 (`$MEASUREMENT`, `$DIMSTYLE`,
/// `$DIMSCALE`, `$LUNITS`, `$LUPREC`), the ones it always named, and the general dictionary.
///
/// Reference values come from `ezdxf` (`tools/header_fixtures.py` for the two fixtures,
/// `tools/oracle.py --header` for real drawings).
@Suite("Header variables")
struct HeaderVariablesTests {

    typealias Variable = (name: String, values: [(Int, String)])

    /// The `HEADER` section of `variables`, each a `9` and its name and then its group-coded values.
    static func header(_ variables: [Variable]) -> String {
        var lines = ["0", "SECTION", "2", "HEADER"]
        for variable in variables {
            lines += ["9", variable.name]
            for (code, value) in variable.values { lines += [String(code), value] }
        }
        return (lines + ["0", "ENDSEC"]).joined(separator: "\n")
    }

    /// A drawing with `variables` in its header and no entities.
    static func text(_ variables: [Variable], after: [String] = []) -> String {
        RawDXF.file([header(variables), RawDXF.section("ENTITIES", [])] + after)
    }

    static func read(_ variables: [Variable]) throws -> DXF.Drawing {
        try DXF.read(text: text(variables))
    }

    static func fixture(_ name: String) throws -> DXF.Drawing {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "dxf", subdirectory: "Fixtures"))
        return try DXF.read(contentsOf: url)
    }

    /// The five variables with a value each.
    static let five: [Variable] = [
        ("$MEASUREMENT", [(70, "1")]), ("$DIMSTYLE", [(2, "ISO-25")]),
        ("$DIMSCALE", [(40, "2.5")]), ("$LUNITS", [(70, "2")]), ("$LUPREC", [(70, "4")]),
    ]

    // MARK: the five variables

    @Test("a drawing with every variable reads each, as ezdxf does")
    func imperialFixture() throws {
        let dwg = try Self.fixture("header_imperial")
        #expect(dwg.version == "AC1032")
        #expect(dwg.measurement == 0)
        #expect(dwg.insUnits == 1)
        #expect(dwg.currentDimensionStyleName == "ARCH-48")
        #expect(dwg.dimensionScale == 48)
        #expect(dwg.linearUnitFormat == 4)
        #expect(dwg.linearUnitPrecision == 3)
        #expect(dwg.dimensionDefaults.unitSuffix == "<> in")
        #expect(dwg.currentDimensionStyle?.name == "ARCH-48")
    }

    @Test("a drawing saved as R12 has no $MEASUREMENT and no $INSUNITS")
    func r12Fixture() throws {
        let dwg = try Self.fixture("header_r12")
        #expect(dwg.version == "AC1009")
        #expect(dwg.measurement == nil && dwg.insUnits == nil)
        #expect(dwg.headerVariables["$MEASUREMENT"] == nil)
        #expect(dwg.headerVariables["$INSUNITS"] == nil)
        // R12 does have the other four.
        #expect(dwg.currentDimensionStyleName == "ISO-25")
        #expect(dwg.dimensionScale == 1)
        #expect(dwg.linearUnitFormat == 2 && dwg.linearUnitPrecision == 4)
    }

    @Test("a drawing with a custom current style names it, and its record is found")
    func styleFixture() throws {
        let dwg = try Self.fixture("dimensions")
        #expect(dwg.currentDimensionStyleName == "EZDXF")
        #expect(dwg.currentDimensionStyle?.name == "EZDXF")
        #expect(dwg.measurement == 1 && dwg.insUnits == 6)
        #expect(dwg.dimensionScale == 1 && dwg.linearUnitFormat == 2)
        #expect(dwg.linearUnitPrecision == 4)
    }

    @Test("each variable reads from a header that has it")
    func reads() throws {
        let dwg = try Self.read(Self.five)
        #expect(dwg.measurement == 1)
        #expect(dwg.currentDimensionStyleName == "ISO-25")
        #expect(dwg.dimensionScale == 2.5)
        #expect(dwg.linearUnitFormat == 2)
        #expect(dwg.linearUnitPrecision == 4)
    }

    @Test("$MEASUREMENT reads 0 for imperial and 1 for metric")
    func measurementValues() throws {
        for value in [0, 1] {
            let dwg = try Self.read([("$MEASUREMENT", [(70, "\(value)")])])
            #expect(dwg.measurement == value)
        }
    }

    static let readers: [(String, (DXF.Drawing) -> Bool)] = [
        ("$MEASUREMENT", { $0.measurement != nil }),
        ("$DIMSTYLE", { $0.currentDimensionStyleName != nil }),
        ("$DIMSCALE", { $0.dimensionScale != nil }),
        ("$LUNITS", { $0.linearUnitFormat != nil }),
        ("$LUPREC", { $0.linearUnitPrecision != nil }),
    ]

    @Test("each variable is nil when the header lacks it, and only that one", arguments: readers)
    func absent(_ entry: (String, (DXF.Drawing) -> Bool)) throws {
        let dwg = try Self.read(Self.five.filter { $0.name != entry.0 })
        #expect(!entry.1(dwg), "\(entry.0) is absent")
        for other in Self.readers where other.0 != entry.0 {
            #expect(other.1(dwg), "\(other.0) is still read")
        }
        #expect(dwg.headerVariables[entry.0] == nil)
    }

    @Test("a header with only $ACADVER, or none, has nothing else")
    func nothing() throws {
        let r14 = try Self.read([("$ACADVER", [(1, "AC1014")])])
        #expect(r14.version == "AC1014")
        #expect(r14.insUnits == nil && r14.extMin == nil && r14.extMax == nil)
        #expect(r14.measurement == nil && r14.currentDimensionStyleName == nil)
        #expect(r14.dimensionScale == nil && r14.linearUnitFormat == nil)
        #expect(r14.linearUnitPrecision == nil && r14.currentDimensionStyle == nil)
        #expect(r14.dimensionDefaults == .init())
        #expect(Set(r14.headerVariables.keys) == ["$ACADVER"])

        let none = try DXF.read(text: RawDXF.entities([]))
        #expect(none.version == "" && none.headerVariables.isEmpty)
        #expect(none.measurement == nil && none.currentDimensionStyleName == nil)
    }

    @Test("a value that is not the variable's type, or has another group code, is nil")
    func untyped() throws {
        let dwg = try Self.read([
            ("$MEASUREMENT", [(1, "1")]), ("$LUNITS", [(70, "2.0")]), ("$LUPREC", [(70, "four")]),
            ("$DIMSCALE", [(40, "1,5")]), ("$DIMSTYLE", [(70, "3")]),
        ])
        #expect(dwg.measurement == nil && dwg.linearUnitFormat == nil)
        #expect(dwg.linearUnitPrecision == nil && dwg.dimensionScale == nil)
        #expect(dwg.currentDimensionStyleName == nil)
        // The file's text is still there for a caller that reads it differently.
        #expect(dwg.headerVariables["$LUPREC"]?.value(70)?.text == "four")
        #expect(dwg.headerVariables["$MEASUREMENT"]?.values == [.init(code: 1, text: "1")])
    }

    @Test("an empty or blank $DIMSTYLE names no style, and a padded one is trimmed")
    func styleName() throws {
        #expect(try Self.read([("$DIMSTYLE", [(2, "")])]).currentDimensionStyleName == nil)
        #expect(try Self.read([("$DIMSTYLE", [(2, "  ")])]).currentDimensionStyleName == nil)
        let padded = try Self.read([("$DIMSTYLE", [(2, "  Standard ")])])
        #expect(padded.currentDimensionStyleName == "Standard")
        #expect(padded.headerVariables["$DIMSTYLE"]?.value(2)?.text == "  Standard ")
    }

    @Test("the current style is found in the table whatever the case")
    func styleRecord() throws {
        let tables = RawDXF.section(
            "TABLES",
            [
                RawDXF.table(
                    "DIMSTYLE",
                    [
                        RawDXF.record("DIMSTYLE", (2, "Standard"), (271, "3")),
                        RawDXF.record("DIMSTYLE", (2, "Other")),
                    ])
            ])
        func drawing(style: String?) throws -> DXF.Drawing {
            let vars: [Variable] = style.map { [("$DIMSTYLE", [(2, $0)])] } ?? []
            return try DXF.read(
                text: RawDXF.file([
                    Self.header(vars), tables, RawDXF.section("ENTITIES", []),
                ]))
        }
        #expect(try drawing(style: "STANDARD").currentDimensionStyle?.variables.decimalPlaces == 3)
        #expect(try drawing(style: "Other").currentDimensionStyle?.name == "Other")
        #expect(try drawing(style: "Missing").currentDimensionStyle == nil)
        #expect(try drawing(style: nil).currentDimensionStyle == nil)
    }

    // MARK: the dictionary

    @Test("every variable is kept with its values, in file order, typed by group code")
    func dictionary() throws {
        let dwg = try Self.read([
            ("$ACADVER", [(1, "AC1015")]), ("$MEASUREMENT", [(70, "1")]),
            ("$EXTMIN", [(10, "-5.5"), (20, "-7"), (30, "0.0")]),
            ("$LIMMIN", [(10, "0.0"), (20, "1.5")]),
            ("$SOMEFUTUREVAR", [(1, "text"), (40, "2.5"), (70, "3")]),
            ("$HANDSEED", [(5, "2A")]),
        ])
        let vars = dwg.headerVariables
        #expect(
            Set(vars.keys)
                == [
                    "$ACADVER", "$MEASUREMENT", "$EXTMIN", "$LIMMIN", "$SOMEFUTUREVAR", "$HANDSEED",
                ])
        #expect(vars["$MEASUREMENT"]?.values == [.init(code: 70, text: "1")])
        #expect(vars["$MEASUREMENT"]?.value(70)?.integer == 1)
        #expect(vars["$MEASUREMENT"]?.value(70)?.real == 1)
        #expect(vars["$EXTMIN"]?.values.map(\.code) == [10, 20, 30])
        #expect(vars["$EXTMIN"]?.point == DXF.Point(-5.5, -7, 0))
        #expect(vars["$LIMMIN"]?.point == DXF.Point(0, 1.5, 0))
        #expect(vars["$MEASUREMENT"]?.point == nil)

        // A variable this package does not name is still read, every group of it.
        let future = try #require(vars["$SOMEFUTUREVAR"])
        #expect(future.values.map(\.code) == [1, 40, 70])
        #expect(future.value(1)?.text == "text" && future.value(1)?.integer == nil)
        #expect(future.value(40)?.real == 2.5 && future.value(70)?.integer == 3)
        #expect(future.value(99) == nil)
        #expect(vars["$HANDSEED"]?.value(5)?.text == "2A")
    }

    @Test("the named properties that were always read are read from the same variables")
    func existingProperties() throws {
        let dwg = try Self.read([
            ("$ACADVER", [(1, " AC1015 ")]), ("$DWGCODEPAGE", [(3, "ANSI_1252")]),
            ("$INSUNITS", [(70, "4")]), ("$EXTMIN", [(10, "-5"), (20, "-7"), (30, "1")]),
            ("$EXTMAX", [(10, "100"), (20, "50")]), ("$DIMDEC", [(70, "3")]),
            ("$DIMZIN", [(70, "8")]), ("$DIMLFAC", [(40, "25.4")]), ("$DIMPOST", [(1, "<> mm")]),
        ])
        #expect(dwg.version == "AC1015")
        #expect(dwg.codePage?.number == 1252)
        #expect(dwg.insUnits == 4)
        #expect(dwg.extMin == DXF.Point(-5, -7, 1) && dwg.extMax == DXF.Point(100, 50, 0))
        #expect(
            dwg.dimensionDefaults
                == .init(
                    decimalPlaces: 3, zeroSuppression: 8, linearScale: 25.4, unitSuffix: "<> mm"))
    }

    @Test("a variable written twice keeps its first value")
    func duplicate() throws {
        let dwg = try Self.read([
            ("$MEASUREMENT", [(70, "1")]), ("$MEASUREMENT", [(70, "0")]),
            ("$LUPREC", [(70, "3")]), ("$LUPREC", [(70, "6")]),
        ])
        #expect(dwg.measurement == 1 && dwg.linearUnitPrecision == 3)
        #expect(dwg.headerVariables["$MEASUREMENT"]?.values.count == 1)
    }

    @Test("a variable with no values is present and empty, and one with no name is not read")
    func emptyVariables() throws {
        let dwg = try Self.read([("$NOVALUE", []), ("", [(70, "1")]), ("$LUPREC", [(70, "2")])])
        #expect(dwg.headerVariables["$NOVALUE"]?.values == [])
        #expect(dwg.headerVariables[""] == nil)
        #expect(dwg.linearUnitPrecision == 2)
    }

    @Test("only the HEADER section is read, to its end or to the next section")
    func section() throws {
        // A group 9 outside the header is not a header variable.
        let entities = RawDXF.section(
            "ENTITIES", ["9\n$MEASUREMENT\n70\n1", RawDXF.record("POINT", (8, "0"))])
        let outside = try DXF.read(
            text: RawDXF.file([Self.header([("$LUPREC", [(70, "2")])]), entities]))
        #expect(outside.measurement == nil && outside.headerVariables["$MEASUREMENT"] == nil)
        #expect(outside.linearUnitPrecision == 2)

        // No ENDSEC: the next section ends the header.
        let open =
            "0\nSECTION\n2\nHEADER\n9\n$LUPREC\n70\n5\n0\nSECTION\n2\nENTITIES\n9\n$LUNITS\n70\n1"
        let unclosed = try DXF.read(text: RawDXF.file([open, "0\nENDSEC"]))
        #expect(unclosed.linearUnitPrecision == 5)
        #expect(unclosed.linearUnitFormat == nil)

        // A header that is not the first section is still found.
        let late = try DXF.read(
            text: RawDXF.file([
                RawDXF.section("TABLES", []), Self.header([("$MEASUREMENT", [(70, "1")])]),
            ]))
        #expect(late.measurement == 1)
    }

    @Test("R12-style padded group codes and CRLF line endings are read")
    func padding() throws {
        let text =
            "  0\r\nSECTION\r\n  2\r\nHEADER\r\n  9\r\n$MEASUREMENT\r\n 70\r\n     1\r\n"
            + "  9\r\n$DIMSTYLE\r\n  2\r\nSTANDARD\r\n  0\r\nENDSEC\r\n  0\r\nEOF\r\n"
        let dwg = try DXF.read(text: text)
        #expect(dwg.measurement == 1)
        #expect(dwg.currentDimensionStyleName == "STANDARD")
        #expect(dwg.headerVariables["$MEASUREMENT"]?.values == [.init(code: 70, text: "     1")])
    }

    // MARK: text, through the code page

    /// A file whose header holds `$DIMSTYLE` and `$DIMPOST` as the given bytes, under `page`.
    static func file(
        page: String?, version: String = "AC1015", style: [UInt8], suffix: [UInt8]
    ) -> Data {
        var variables: [Variable] = [("$ACADVER", [(1, version)])]
        if let page { variables.append(("$DWGCODEPAGE", [(3, page)])) }
        variables += [("$DIMSTYLE", [(2, "@@")]), ("$DIMPOST", [(1, "##")])]
        var data = Data(Self.text(variables).utf8)
        data.replaceSubrange(data.range(of: Data("@@".utf8))!, with: style)
        data.replaceSubrange(data.range(of: Data("##".utf8))!, with: suffix)
        return data
    }

    @Test("$DIMSTYLE and $DIMPOST are read through the code page the header names")
    func codePage() throws {
        // Windows-1252: e acute, and the degree sign and euro sign.
        let latin = try DXF.read(
            data: Self.file(
                page: "ANSI_1252", style: [0x43, 0x61, 0x66, 0xE9], suffix: [0xB0, 0x80]))
        #expect(latin.currentDimensionStyleName == "Caf\u{E9}")
        #expect(latin.dimensionDefaults.unitSuffix == "\u{B0}\u{20AC}")
        #expect(latin.headerVariables["$DIMSTYLE"]?.value(2)?.text == "Caf\u{E9}")
        #expect(latin.headerVariables["$DIMPOST"]?.value(1)?.text == "\u{B0}\u{20AC}")

        // Windows-1251: a Cyrillic style name.
        let cyrillic = try DXF.read(
            data: Self.file(page: "ANSI_1251", style: [0xDF], suffix: [0x6D, 0x6D]))
        #expect(cyrillic.currentDimensionStyleName == "\u{42F}")

        // Shift-JIS, named and when the header names none.
        let japanese: [UInt8] = [0x93, 0xFA, 0x96, 0x7B]
        for page in ["ANSI_932", nil] {
            let dwg = try DXF.read(data: Self.file(page: page, style: japanese, suffix: japanese))
            #expect(dwg.currentDimensionStyleName == "\u{65E5}\u{672C}", "\(page ?? "no page")")
            #expect(dwg.dimensionDefaults.unitSuffix == "\u{65E5}\u{672C}")
        }
    }

    @Test("a header of R2007 or later is UTF-8 whatever its code page")
    func utf8() throws {
        let style = Array("Gr\u{F6}\u{DF}e".utf8)
        let dwg = try DXF.read(
            data: Self.file(page: "ANSI_1252", version: "AC1032", style: style, suffix: [0x6D]))
        #expect(dwg.currentDimensionStyleName == "Gr\u{F6}\u{DF}e")
        let text = try DXF.read(
            text: String(
                decoding: Self.file(
                    page: nil, version: "AC1032", style: style, suffix: [0x6D]), as: UTF8.self))
        #expect(text.currentDimensionStyleName == "Gr\u{F6}\u{DF}e")
    }

    @Test("a string keeps its % codes, which are for the text of the drawing")
    func percentCodes() throws {
        let dwg = try Self.read([("$DIMPOST", [(1, "<>%%d")]), ("$DIMSTYLE", [(2, "A%%c")])])
        #expect(dwg.headerVariables["$DIMPOST"]?.value(1)?.text == "<>%%d")
        #expect(dwg.currentDimensionStyleName == "A%%c")
    }

    // MARK: the drawing

    @Test("the memberwise init still takes what it did, and the new properties default to none")
    func memberwiseInit() {
        // The call OCCTSwiftPDF makes.
        let pdf = DXF.Drawing(
            version: "PDF", entities: [], counts: .init(), insUnits: 4, skipped: [:],
            skippedByLayer: [:], layers: [])
        #expect(pdf.version == "PDF" && pdf.insUnits == 4)
        #expect(pdf.measurement == nil && pdf.currentDimensionStyleName == nil)
        #expect(pdf.dimensionScale == nil && pdf.linearUnitFormat == nil)
        #expect(pdf.linearUnitPrecision == nil && pdf.headerVariables.isEmpty)
        #expect(pdf.currentDimensionStyle == nil)

        let built = DXF.Drawing(
            codePage: DXF.CodePage(name: "ANSI_1252"), measurement: 1,
            currentDimensionStyleName: "Standard", dimensionScale: 2, linearUnitFormat: 2,
            linearUnitPrecision: 3,
            headerVariables: ["$MEASUREMENT": .init(values: [.init(code: 70, text: "1")])])
        #expect(built.measurement == 1 && built.currentDimensionStyleName == "Standard")
        #expect(built.dimensionScale == 2 && built.linearUnitFormat == 2)
        #expect(built.linearUnitPrecision == 3 && built.codePage?.number == 1252)
        #expect(built.headerVariables["$MEASUREMENT"]?.value(70)?.integer == 1)
    }
}
