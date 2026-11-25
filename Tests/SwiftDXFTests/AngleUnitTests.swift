import Foundation
import Testing

@testable import SwiftDXF

/// The unit and decimal places an angular dimension is shown in (`DIMAUNIT`, `DIMADEC`,
/// SwiftDXF#46), and reading a typed angle in that unit.
///
/// `Fixtures/angle_units.dxf` is written by `tools/angle_unit_fixtures.py`, which prints what
/// `ezdxf` reads from it and the text its own renderer wrote for each dimension (`rendered`,
/// below). Every dimension is 45 degrees 30 minutes 15 seconds.
@Suite("Angle unit and decimal places")
struct AngleUnitTests {
    typealias Unit = DXF.DimensionStyle.AngleUnit

    static func fixture() throws -> DXF.Drawing {
        let url = try #require(
            Bundle.module.url(
                forResource: "angle_units", withExtension: "dxf", subdirectory: "Fixtures"))
        return try DXF.read(contentsOf: url)
    }

    /// 45 degrees 30 minutes 15 seconds.
    static let sweep = 45.0 + 30.0 / 60 + 15.0 / 3600

    /// What the script prints for each dimension of the fixture, in file order.
    ///
    /// Each is its style, the text ezdxf rendered, the angle in degrees that text states, and how
    /// far that can be from the angle: half a unit of its last place, or a whole one for degrees,
    /// minutes and seconds, which ezdxf truncates. The tests read the text from the dimension's own block as well, so a
    /// regenerated fixture that differs fails them.
    static let rendered: [(style: String, text: String, degrees: Double, tolerance: Double)] = [
        ("DEG1", "45.5\u{00B0}", 45.5, 0.05),
        ("DMS0", "45\u{00B0}", 45, 1),
        ("DMS2", "45\u{00B0}30'", 45.5, 1.0 / 60),
        ("DMS4", "45\u{00B0}30'15\"", sweep, 1.0 / 3600),
        ("DMS6", "45\u{00B0}30'15\"", sweep, 1.0 / 3600),
        // 50.56 gradians, and 0.7942 radians.
        ("GRAD2", "50.56g", 50.56 * 0.9, 0.005 * 0.9),
        ("RAD4", "0.7942r", 0.7942 * 180 / .pi, 0.00005 * 180 / .pi),
        ("DEG1", "45\u{00B0}30'15\"", sweep, 1.0 / 3600),
    ]

    /// The text in the anonymous block `*D<n>` that ezdxf made for the `n`th dimension.
    static func blockText(_ dwg: DXF.Drawing, dimension index: Int) throws -> String {
        let block = try #require(dwg.blocks.first { $0.name == "*D\(index + 1)" })
        for case .text(_, _, _, let string, _, _) in block.entities { return string }
        throw TextNotFound()
    }

    struct TextNotFound: Error {}

    // MARK: against ezdxf

    @Test("DIMSTYLE records carry the unit and the places, as ezdxf reads them")
    func styleRecords() throws {
        let dwg = try Self.fixture()
        // ezdxf: dimaunit / dimadec of each record.
        let expected: [(String, Int, Int, Unit)] = [
            ("DEG1", 0, 1, .decimalDegrees), ("DMS0", 1, 0, .degreesMinutesSeconds),
            ("DMS2", 1, 2, .degreesMinutesSeconds), ("DMS4", 1, 4, .degreesMinutesSeconds),
            ("DMS6", 1, 6, .degreesMinutesSeconds), ("GRAD2", 2, 2, .gradians),
            ("RAD4", 3, 4, .radians), ("USEDEC", 0, -1, .decimalDegrees),
        ]
        for (name, code, places, unit) in expected {
            let record = try #require(dwg.dimensionStyles.first { $0.name == name }, "\(name)")
            #expect(record.variables.angleUnitCode == code, "\(name)")
            #expect(record.variables.angleDecimalPlaces == places, "\(name)")
            #expect(record.variables.angleUnit == unit, "\(name)")
        }
    }

    @Test("a DIMADEC of -1 uses the places of DIMDEC")
    func placesFollowDimdec() throws {
        let dwg = try Self.fixture()
        let usesDimdec = try #require(dwg.dimensionStyles.first { $0.name == "USEDEC" }).variables
        let dimdec = try #require(usesDimdec.decimalPlaces)
        #expect(usesDimdec.angleDecimalPlaces == -1)
        #expect(usesDimdec.effectiveAngleDecimalPlaces == dimdec)
        // DMS6 states 6 places of its own, and its DIMDEC is not 6, so DIMADEC is not DIMDEC.
        let own = try #require(dwg.dimensionStyles.first { $0.name == "DMS6" }).variables
        #expect(own.decimalPlaces != 6 && own.effectiveAngleDecimalPlaces == 6)
    }

    @Test("the header's $DIMAUNIT and $DIMADEC are in the defaults, apart from any style")
    func headerVariables() throws {
        let dwg = try Self.fixture()
        // ezdxf: header $DIMAUNIT 2, $DIMADEC 3.
        #expect(dwg.dimensionDefaults.angleUnitCode == 2)
        #expect(dwg.dimensionDefaults.angleUnit == .gradians)
        #expect(dwg.dimensionDefaults.angleDecimalPlaces == 3)
        // They are not a style: a dimension in DEG1 is in decimal degrees.
        let first = try #require(DimensionTests.dimensions(dwg).first)
        #expect(dwg.styleVariables(of: first).angleUnit == .decimalDegrees)
    }

    @Test(
        "an override in the extended data wins over the style, and a dimension without one does not"
    )
    func overrides() throws {
        let dwg = try Self.fixture()
        let dims = DimensionTests.dimensions(dwg)
        #expect(dims.count == Self.rendered.count + 1)
        // ezdxf: dimaunit 1 and dimadec 4 on the eighth, whose style DEG1 has 0 and 1.
        let overridden = dims[7]
        #expect(overridden.styleName == "DEG1")
        #expect(overridden.styleOverrides.angleUnitCode == 1)
        #expect(overridden.styleOverrides.angleDecimalPlaces == 4)
        let resolved = dwg.styleVariables(of: overridden)
        #expect(resolved.angleUnit == .degreesMinutesSeconds)
        #expect(resolved.angleDecimalPlaces == 4)
        for index in [0, 1, 5, 6, 8] {
            #expect(dims[index].styleOverrides == .init(), "\(index)")
        }
        #expect(dwg.styleVariables(of: dims[6]).angleUnit == .radians)
    }

    @Test("the text ezdxf rendered reads back as the computed angle, in each unit")
    func renderedTextReadsBack() throws {
        let dwg = try Self.fixture()
        let dims = DimensionTests.dimensions(dwg)
        for (index, want) in Self.rendered.enumerated() {
            let dim = dims[index]
            let computed = try #require(dim.computedMeasurement)
            #expect(abs(computed - Self.sweep) < 1e-9, "\(index): \(computed)")
            #expect(dim.styleName == want.style, "\(index)")
            // The text in the file's own block is the one the table holds.
            #expect(try Self.blockText(dwg, dimension: index) == want.text, "\(index)")
            let unit = dwg.styleVariables(of: dim).angleUnit
            let text = DXF.DimensionText(want.text, angleUnit: unit)
            #expect(text.parts.count == 1, "\(index): \(text.parts)")
            let read = try #require(text.typedAngles.first, "\(index): \(want.text)")
            #expect(text.typedNumbers.isEmpty && text.words.isEmpty, "\(index)")
            // It reads as the angle it states, and that is near the computed one.
            #expect(abs(read - want.degrees) < 1e-9, "\(index): \(read) vs \(want.degrees)")
            #expect(
                abs(read - computed) <= want.tolerance + 1e-9, "\(index): \(read) vs \(computed)")
        }
    }

    @Test("a typed angle in a text override is read in the unit of the dimension's style")
    func typedAngleInOverride() throws {
        let dwg = try Self.fixture()
        let dim = DimensionTests.dimensions(dwg)[8]
        #expect(dim.textOverride == "<> typed 45\u{00B0}30'15\"")
        let text = dwg.text(of: dim)
        #expect(text.showsMeasurement && text.words == ["typed"])
        #expect(text.typedNumbers.isEmpty)
        let angle = try #require(text.typedAngles.first)
        #expect(text.typedAngles.count == 1 && abs(angle - Self.sweep) < 1e-12)
        let computed = try #require(dim.computedMeasurement)
        #expect(abs(angle - computed) < 1e-9)
        // Without the unit the same text is read as it always was.
        let plain = dim.text
        #expect(plain.typedAngles == [45] && plain.typedNumbers == [30, 15])
    }

    // MARK: reading an angle in a unit

    @Test("degrees, minutes and seconds are one angle, in degrees")
    func degreesMinutesSeconds() {
        func angles(_ raw: String, _ unit: Unit? = .degreesMinutesSeconds) -> [Double] {
            DXF.DimensionText(raw, angleUnit: unit).typedAngles
        }
        func same(_ a: [Double], _ b: [Double]) -> Bool {
            a.count == b.count && zip(a, b).allSatisfy { abs($0 - $1) < 1e-12 }
        }
        #expect(same(angles("45\u{00B0}30'15\""), [Self.sweep]))
        #expect(same(angles("45\u{00B0}30'"), [45.5]))
        #expect(same(angles("45\u{00B0}"), [45]))
        #expect(same(angles("0\u{00B0}0'30\""), [30.0 / 3600]))
        #expect(same(angles("45\u{00B0}30'15.5\""), [45 + 30.0 / 60 + 15.5 / 3600]))
        // The degree sign however it is written.
        #expect(same(angles("45%%d30'15\""), [Self.sweep]))
        #expect(same(angles("45\\U+00B030'15\""), [Self.sweep]))
        // The sign belongs to the whole angle, even where the degrees are zero.
        #expect(same(angles("-45\u{00B0}30'15\""), [-Self.sweep]))
        #expect(same(angles("-0\u{00B0}30'"), [-0.5]))
        #expect(same(angles("<> 10\u{00B0}30' to 20\u{00B0}15'"), [10.5, 20.25]))
        // Minutes and seconds written with a decimal point that adds nothing.
        #expect(same(angles("45\u{00B0}30.0'15\""), [Self.sweep]))
        #expect(same(angles("45\u{00B0}30.0'"), [45.5]))
        #expect(same(angles("45.0\u{00B0}30'15.0\""), [Self.sweep]))
        // The text is kept as written, and so is what follows.
        let text = DXF.DimensionText("<> 45\u{00B0}30'15\" max", angleUnit: .degreesMinutesSeconds)
        #expect(text.parts.contains(.angle(Self.sweep, text: "45\u{00B0}30'15\"")))
        #expect(text.plain == "<> 45\u{00B0}30'15\" max" && text.words == ["max"])
    }

    @Test("minutes and seconds that are not minutes and seconds are not read as them")
    func notMinutesAndSeconds() {
        let unit = Unit.degreesMinutesSeconds
        // 60 minutes, a fractional minute, and no minutes mark: the degrees stand alone.
        let sixty = DXF.DimensionText("45\u{00B0}60'", angleUnit: unit)
        #expect(sixty.typedAngles == [45] && sixty.typedNumbers == [60])
        let fraction = DXF.DimensionText("45\u{00B0}30.5'", angleUnit: unit)
        #expect(fraction.typedAngles == [45] && fraction.typedNumbers == [30.5])
        let unmarked = DXF.DimensionText("45\u{00B0}30", angleUnit: unit)
        #expect(unmarked.typedAngles == [45] && unmarked.typedNumbers == [30])
        // Seconds after minutes that are 60, or with no mark, are left out.
        let seconds = DXF.DimensionText("45\u{00B0}30'60\"", angleUnit: unit)
        #expect(seconds.typedAngles == [45.5] && seconds.typedNumbers == [60])
        let unmarkedSeconds = DXF.DimensionText("45\u{00B0}30'15", angleUnit: unit)
        #expect(unmarkedSeconds.typedAngles == [45.5] && unmarkedSeconds.typedNumbers == [15])
        // Minutes follow whole degrees.
        let fractionalDegrees = DXF.DimensionText("45.5\u{00B0}30'", angleUnit: unit)
        #expect(fractionalDegrees.typedAngles == [45.5] && fractionalDegrees.typedNumbers == [30])
        // Seconds with no minutes are not read.
        let bare = DXF.DimensionText("45\u{00B0}15\"", angleUnit: unit)
        #expect(bare.typedAngles == [45] && bare.typedNumbers == [15])
    }

    @Test("gradians end in g and radians in r, where the style says so")
    func gradiansAndRadians() throws {
        func angle(_ raw: String, _ unit: Unit?) -> Double? {
            DXF.DimensionText(raw, angleUnit: unit).typedAngles.first
        }
        // 50 gradians is 45 degrees, 100 a right angle.
        #expect(abs(try #require(angle("50g", .gradians)) - 45) < 1e-12)
        #expect(abs(try #require(angle("50.56g", .gradians)) - 45.504) < 1e-12)
        #expect(abs(try #require(angle("-100g", .gradians)) + 90) < 1e-12)
        #expect(abs(try #require(angle("0.7854r", .radians)) - 45.0000) < 1e-3)
        #expect(abs(try #require(angle("3.141592653589793r", .radians)) - 180) < 1e-12)
        #expect(abs(try #require(angle("<> (max 1r)", .radians)) - 180 / .pi) < 1e-12)
        // The degree sign is an angle in any unit.
        #expect(angle("45\u{00B0}", .gradians) == 45 && angle("45\u{00B0}", .radians) == 45)
        // Where the style says another unit, or none, the letter is a word: 50 g is a mass.
        for unit: Unit? in [nil, .decimalDegrees, .degreesMinutesSeconds, .radians] {
            let text = DXF.DimensionText("50g", angleUnit: unit)
            #expect(text.typedAngles.isEmpty && text.typedNumbers == [50] && text.words == ["g"])
        }
        for unit: Unit? in [nil, .decimalDegrees, .degreesMinutesSeconds, .gradians] {
            #expect(angle("2r", unit) == nil, "\(String(describing: unit))")
        }
        // A letter after it makes it a word.
        for (raw, unit) in [("50gal", Unit.gradians), ("5rpm", .radians), ("2rad", .radians)] {
            let text = DXF.DimensionText(raw, angleUnit: unit)
            #expect(text.typedAngles.isEmpty && text.typedNumbers.count == 1, "\(raw)")
        }
    }

    @Test("a text read with no unit is the text read before the unit was modelled")
    func noUnitNoChange() {
        let raw = "45\u{00B0}30'15\" 50g 2r"
        let before = DXF.DimensionText(raw).parts
        #expect(DXF.DimensionText(raw, angleUnit: nil).parts == before)
        #expect(DXF.DimensionText(raw, angleUnit: .decimalDegrees).parts == before)
        // As it was: the degrees are an angle and the rest are numbers and words.
        #expect(before.first == .angle(45, text: "45\u{00B0}"))
        #expect(DXF.DimensionText(raw).typedNumbers == [30, 15, 50, 2])
    }

    @Test("a dimension reads its text in a unit, with or without a number convention")
    func dimensionAPI() {
        let dim = DXF.Dimension(
            kind: .angular, measurement: nil, textOverride: "1,5 30\u{00B0}15'",
            textPosition: .init(0, 0), defPoint: .init(0, 0), layer: "0", color: 7)
        let unit = Unit.degreesMinutesSeconds
        #expect(dim.text(angleUnit: unit).typedAngles == [30.25])
        #expect(dim.text(numbers: .commaIsDecimalMark, angleUnit: unit).typedNumbers == [1.5])
        #expect(dim.text(numbers: .commaIsDecimalMark).typedAngles == [30])
        #expect(dim.text.typedAngles == [30])
    }

    // MARK: Variables

    @Test("the unit is named for the four codes and nothing else")
    func unitCodes() {
        let all: [(Int, Unit)] = [
            (0, .decimalDegrees), (1, .degreesMinutesSeconds), (2, .gradians), (3, .radians),
        ]
        for (code, unit) in all {
            #expect(Unit(code: code) == unit && unit.code == code)
            #expect(DXF.DimensionStyle.Variables(angleUnitCode: code).angleUnit == unit)
        }
        for code in [-1, 4, 7, 275] {
            #expect(Unit(code: code) == nil)
            let variables = DXF.DimensionStyle.Variables(angleUnitCode: code)
            #expect(variables.angleUnitCode == code && variables.angleUnit == nil)
        }
        #expect(DXF.DimensionStyle.Variables().angleUnit == nil)
    }

    @Test("the places of an angle are DIMADEC, or DIMDEC where DIMADEC is -1")
    func effectivePlaces() {
        typealias Variables = DXF.DimensionStyle.Variables
        #expect(Variables().effectiveAngleDecimalPlaces == nil)
        #expect(Variables(decimalPlaces: 3).effectiveAngleDecimalPlaces == nil)
        #expect(Variables(angleDecimalPlaces: 2).effectiveAngleDecimalPlaces == 2)
        #expect(Variables(decimalPlaces: 3, angleDecimalPlaces: 2).effectiveAngleDecimalPlaces == 2)
        #expect(
            Variables(decimalPlaces: 3, angleDecimalPlaces: -1).effectiveAngleDecimalPlaces == 3)
        #expect(Variables(angleDecimalPlaces: -1).effectiveAngleDecimalPlaces == nil)
        #expect(Variables(decimalPlaces: 3, angleDecimalPlaces: 0).effectiveAngleDecimalPlaces == 0)
    }

    @Test("each variable is filled from the base only where it is not stated")
    func filling() {
        typealias Variables = DXF.DimensionStyle.Variables
        let own = Variables(angleUnitCode: 3)
        let base = Variables(angleUnitCode: 1, angleDecimalPlaces: 4)
        let filled = own.filling(from: base)
        #expect(filled.angleUnitCode == 3 && filled.angleDecimalPlaces == 4)
        #expect(Variables().filling(from: base) == base)
        #expect(base.filling(from: Variables()) == base)
    }

    // MARK: reading them from a file

    /// A linear dimension of 8 units with `extra` extended data and the given tables and header.
    static func inline(
        extra: [(Int, String)] = [], tables: [String] = [], header: [String] = [],
        style: String = "STD"
    ) throws -> DXF.Drawing {
        let tags: [(Int, String)] =
            [
                (8, "0"), (3, style), (70, "0"), (10, "8"), (20, "0"), (11, "0"), (21, "0"),
                (13, "0"), (23, "0"), (14, "8"), (24, "0"),
            ] + extra
        var sections: [String] = []
        if !header.isEmpty { sections.append(RawDXF.section("HEADER", header)) }
        if !tables.isEmpty { sections.append(RawDXF.section("TABLES", tables)) }
        sections.append(RawDXF.section("ENTITIES", [RawDXF.record("DIMENSION", tags)]))
        return try DXF.read(text: RawDXF.file(sections))
    }

    @Test("the groups 275 and 179 of a record, an override and the header are the unit and places")
    func readFromTags() throws {
        let tables = [
            RawDXF.table(
                "DIMSTYLE",
                [
                    RawDXF.record("DIMSTYLE", (2, "STD"), (275, "2"), (179, "-1"), (271, "3")),
                    RawDXF.record("DIMSTYLE", (2, "BLANK"), (78, "8")),
                ])
        ]
        let header = [
            "9\n$DIMAUNIT\n70\n3", "9\n$DIMADEC\n70\n5", "9\n$DIMDEC\n70\n1",
        ]
        // The override states the unit and says nothing of the places.
        let xdata: [(Int, String)] = [
            (1001, "ACAD"), (1000, "DSTYLE"), (1002, "{"), (1070, "275"), (1070, "1"),
            (1002, "}"),
        ]
        let dwg = try Self.inline(extra: xdata, tables: tables, header: header)
        let dim = DimensionTests.dimensions(dwg)[0]
        #expect(dim.styleOverrides == .init(angleUnitCode: 1))
        let resolved = dwg.styleVariables(of: dim)
        #expect(resolved.angleUnit == .degreesMinutesSeconds)
        // The places come from the record: -1, so those of DIMDEC.
        #expect(resolved.angleDecimalPlaces == -1 && resolved.effectiveAngleDecimalPlaces == 3)
        #expect(dwg.dimensionDefaults.angleUnit == .radians)
        #expect(dwg.dimensionDefaults.angleDecimalPlaces == 5)
        #expect(dwg.dimensionDefaults.effectiveAngleDecimalPlaces == 5)
        // The record's own text, read in the resolved unit.
        let withoutOverride = try Self.inline(tables: tables, header: header)
        let plain = DimensionTests.dimensions(withoutOverride)[0]
        #expect(withoutOverride.styleVariables(of: plain).angleUnit == .gradians)
    }

    @Test("a record that states neither leaves them nil, and the header's are not applied")
    func unstated() throws {
        let tables = [
            RawDXF.table("DIMSTYLE", [RawDXF.record("DIMSTYLE", (2, "STD"), (271, "3"))])
        ]
        let header = ["9\n$DIMAUNIT\n70\n3", "9\n$DIMADEC\n70\n6"]
        let dwg = try Self.inline(tables: tables, header: header)
        let dim = DimensionTests.dimensions(dwg)[0]
        let resolved = dwg.styleVariables(of: dim)
        #expect(resolved.angleUnitCode == nil && resolved.angleUnit == nil)
        #expect(resolved.angleDecimalPlaces == nil && resolved.effectiveAngleDecimalPlaces == nil)
        #expect(dwg.dimensionDefaults.angleUnitCode == 3)
        // So a typed angle is read as it is with no unit.
        let angular = DXF.Dimension(
            kind: .angular, measurement: nil, textOverride: "45\u{00B0}30'",
            textPosition: .init(0, 0), defPoint: .init(0, 0), layer: "0", color: 7)
        #expect(dwg.text(of: angular).typedAngles == [45])
        // And a file with no header or table states none.
        let bare = try Self.inline()
        #expect(bare.dimensionDefaults == .init())
        #expect(
            bare.styleVariables(of: DimensionTests.dimensions(bare)[0]).angleUnitCode == nil)
    }

    @Test("an integer override written as a real is read where it is whole")
    func realValuedOverrides() throws {
        func overrides(_ pairs: [(Int, String)]) throws -> DXF.DimensionStyle.Variables {
            var xdata: [(Int, String)] = [(1001, "ACAD"), (1000, "DSTYLE"), (1002, "{")]
            for (variable, value) in pairs {
                xdata += [(1070, "\(variable)"), (1040, value)]
            }
            xdata.append((1002, "}"))
            let dwg = try Self.inline(extra: xdata)
            return DimensionTests.dimensions(dwg)[0].styleOverrides
        }
        // Every integer variable, as a real that is whole.
        let whole = try overrides([(271, "3.0"), (78, "8.0"), (275, "2.0"), (179, "-1.0")])
        #expect(whole.decimalPlaces == 3 && whole.zeroSuppression == 8)
        #expect(whole.angleUnitCode == 2 && whole.angleDecimalPlaces == -1)
        // The same, as the integers a 1070 writes, and with spaces round the number.
        let integers = try overrides([(271, "3"), (78, " 8 "), (275, "2"), (179, "-1")])
        #expect(integers == whole)
        #expect(try overrides([(275, "1e0")]).angleUnitCode == 1)
        // A real that is not whole, or not a number, is not an integer.
        let fractional = try overrides([(271, "2.5"), (78, "8.5"), (275, "1.5"), (179, "0.1")])
        #expect(fractional == .init())
        let junk = try overrides([(271, "x"), (275, "nan"), (179, "1e300"), (78, "inf")])
        #expect(junk == .init())
        // Whatever an Int holds exactly is read, and nothing it does not.
        #expect(try overrides([(179, "1e16")]).angleDecimalPlaces == 10_000_000_000_000_000)
        #expect(try overrides([(179, "9.3e18")]).angleDecimalPlaces == nil)
        #expect(try overrides([(179, "-0.0")]).angleDecimalPlaces == 0)
        // A real variable is still a real.
        #expect(try overrides([(144, "25.4")]).linearScale == 25.4)
    }

    @Test("a unit that is stated but not known is told from one that is not stated")
    func unrecognisedUnit() {
        typealias Variables = DXF.DimensionStyle.Variables
        #expect(!Variables().hasUnrecognisedAngleUnit)
        for code in 0...3 { #expect(!Variables(angleUnitCode: code).hasUnrecognisedAngleUnit) }
        for code in [-1, 4, 7] {
            let variables = Variables(angleUnitCode: code)
            #expect(variables.hasUnrecognisedAngleUnit && variables.angleUnit == nil, "\(code)")
        }
    }

    @Test("a code that is not a unit is kept as written and names none")
    func unknownCode() throws {
        let tables = [
            RawDXF.table("DIMSTYLE", [RawDXF.record("DIMSTYLE", (2, "STD"), (275, "7"))])
        ]
        let dwg = try Self.inline(tables: tables)
        let resolved = dwg.styleVariables(of: DimensionTests.dimensions(dwg)[0])
        #expect(resolved.angleUnitCode == 7 && resolved.angleUnit == nil)
        #expect(resolved.hasUnrecognisedAngleUnit)
    }
}
