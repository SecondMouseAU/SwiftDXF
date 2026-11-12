import Foundation
import Testing

@testable import SwiftDXF

/// What a DIMENSION states: the stored measurement, rotation, the computed value, the style
/// variables and the text.
///
/// The reference values come from `ezdxf` reading `Fixtures/dimensions.dxf`
/// (`tools/dimension_fixtures.py`); its `Dimension.get_measurement()` is the geometric value.
@Suite("Dimension measurement, style and text")
struct DimensionTests {

    static func fixture() throws -> DXF.Drawing {
        let url = try #require(
            Bundle.module.url(
                forResource: "dimensions", withExtension: "dxf", subdirectory: "Fixtures"))
        return try DXF.read(contentsOf: url)
    }

    static func dimensions(_ dwg: DXF.Drawing) -> [DXF.Dimension] {
        dwg.entities.compactMap { if case .dimension(let d) = $0 { return d } else { return nil } }
    }

    /// A DIMENSION record, with a style table and header when given.
    static func inline(
        _ tags: [(Int, String)], tables: [String] = [], header: [String] = []
    ) throws -> DXF.Drawing {
        var sections: [String] = []
        if !header.isEmpty { sections.append(RawDXF.section("HEADER", header)) }
        if !tables.isEmpty { sections.append(RawDXF.section("TABLES", tables)) }
        sections.append(RawDXF.section("ENTITIES", [RawDXF.record("DIMENSION", tags)]))
        return try DXF.read(text: RawDXF.file(sections))
    }

    /// Linear dimension tags: extension origins `a` and `b`, group 10 on the dimension line.
    static func linear(
        a: (Double, Double), b: (Double, Double), rotation: Double? = nil,
        extra: [(Int, String)] = []
    ) -> [(Int, String)] {
        var tags: [(Int, String)] = [
            (8, "0"), (3, "STD"), (70, "0"), (10, "\(b.0)"), (20, "\(b.1)"),
            (11, "0"), (21, "0"), (13, "\(a.0)"), (23, "\(a.1)"), (14, "\(b.0)"), (24, "\(b.1)"),
        ]
        if let rotation { tags.append((50, "\(rotation)")) }
        return tags + extra
    }

    // MARK: Stored measurement and rotation

    @Test("the stored measurement is nil when absent, zero or negative")
    func storedMeasurement() throws {
        let dims = Self.dimensions(try Self.fixture())
        // ezdxf: group 42 is 12.5, 0.0 and -1.0 on the first three.
        #expect(dims[0].measurement == 12.5)
        #expect(dims[1].measurement == nil)
        #expect(dims[2].measurement == nil)
        #expect(dims[3].measurement == nil)
        let mcmaster = try Self.inline(Self.linear(a: (0, 0), b: (8, 0), extra: [(42, "-1.0")]))
        #expect(Self.dimensions(mcmaster)[0].measurement == nil)
    }

    @Test("rotation and oblique angle are read, and absent when the file omits them")
    func rotationAndOblique() throws {
        let dims = Self.dimensions(try Self.fixture())
        #expect(dims[0].rotation == 0 && dims[0].obliqueAngle == 20)
        #expect(dims[1].rotation == 90 && dims[1].obliqueAngle == nil)
        #expect(dims[2].rotation == 30)
        let none = try Self.inline(Self.linear(a: (0, 0), b: (8, 0)))
        #expect(Self.dimensions(none)[0].rotation == nil)
    }

    // MARK: Computed value

    @Test("the computed value equals ezdxf's measurement for every dimension type it computes")
    func computedMatchesEzdxf() throws {
        let dims = Self.dimensions(try Self.fixture())
        // ezdxf Dimension.get_measurement(): linear 40, 25, 27.320508; aligned 36.055513;
        // radius 7.5; diameter 12; angular has none; then 12.5, 8, 15, 67.
        let reference: [Double?] = [
            40, 25, 27.320508075688775, 36.05551275463989, 7.5, 12, nil, 12.5, 8, 15, 67,
        ]
        #expect(dims.count == reference.count)
        for (dim, want) in zip(dims, reference) {
            if let want {
                let got = try #require(dim.computedMeasurement)
                #expect(abs(got - want) < 1e-9, "\(dim.kind): \(got) != \(want)")
            } else {
                #expect(dim.computedMeasurement == nil)
            }
        }
    }

    @Test("the computed value ignores what is stored")
    func computedIgnoresStored() throws {
        let first = Self.dimensions(try Self.fixture())[0]
        #expect(first.measurement == 12.5)
        #expect(first.computedMeasurement == 40)
    }

    @Test("a linear dimension without a rotation measures horizontally")
    func linearWithoutRotation() throws {
        let dwg = try Self.inline(Self.linear(a: (0, 0), b: (8, 6)))
        #expect(Self.dimensions(dwg)[0].computedMeasurement == 8)
        let vertical = try Self.inline(Self.linear(a: (0, 0), b: (8, 6), rotation: 90))
        #expect(Self.dimensions(vertical)[0].computedMeasurement == 6)
    }

    @Test("a dimension missing its definition points has no computed value")
    func missingPoints() throws {
        let dwg = try Self.inline([(8, "0"), (70, "0"), (10, "0"), (20, "0")])
        #expect(Self.dimensions(dwg)[0].computedMeasurement == nil)
        let radius = try Self.inline([(70, "4"), (10, "0"), (20, "0")])
        #expect(Self.dimensions(radius)[0].computedMeasurement == nil)
    }

    // MARK: Style

    @Test("DIMSTYLE records carry decimal places, zero suppression and scale")
    func styleRecords() throws {
        let dwg = try Self.fixture()
        let plain = try #require(dwg.dimensionStyles.first { $0.name == "PLAIN" })
        #expect(plain.variables.decimalPlaces == 2 && plain.variables.zeroSuppression == 8)
        #expect(plain.variables.linearScale == 1)
        let scaled = try #require(dwg.dimensionStyles.first { $0.name == "SCALED" })
        #expect(scaled.variables.decimalPlaces == 3 && scaled.variables.linearScale == 2)
        #expect(plain.handle == "8A" && scaled.handle == "8B")
    }

    @Test("per-entity overrides in the extended data win over the style")
    func entityOverrides() throws {
        let dwg = try Self.fixture()
        let dims = Self.dimensions(dwg)
        // ezdxf: dimdec 1, dimzin 4, dimlfac 25.4, dimpost "<> in" on the eighth dimension.
        let overridden = dims[7]
        #expect(
            overridden.styleOverrides
                == .init(
                    decimalPlaces: 1, zeroSuppression: 4, linearScale: 25.4, unitSuffix: "<> in"))
        let resolved = dwg.styleVariables(of: overridden)
        #expect(resolved.decimalPlaces == 1 && resolved.zeroSuppression == 4)
        #expect(resolved.linearScale == 25.4 && resolved.unitSuffix == "<> in")
        #expect(resolved.suppressesLeadingZeros && !resolved.suppressesTrailingZeros)
        // A dimension with none takes its style.
        #expect(dims[1].styleOverrides == .init())
        #expect(dwg.styleVariables(of: dims[1]).decimalPlaces == 2)
        #expect(dwg.styleVariables(of: dims[1]).suppressesTrailingZeros)
    }

    @Test("the displayed value is the computed value times the style's linear scale")
    func displayedMeasurement() throws {
        let dwg = try Self.fixture()
        let dims = Self.dimensions(dwg)
        #expect(dwg.displayedMeasurement(of: dims[0]) == 40)
        // SCALED has dimlfac 2.
        #expect(abs(try #require(dwg.displayedMeasurement(of: dims[2])) - 54.64101615137755) < 1e-9)
        // dimlfac 25.4 from the override.
        #expect(abs(try #require(dwg.displayedMeasurement(of: dims[7])) - 12.5 * 25.4) < 1e-9)
        #expect(dwg.displayedMeasurement(of: dims[6]) == nil)
    }

    @Test("the header's current values are kept apart and never used as a style")
    func headerDefaultsAreNotAStyle() throws {
        let dwg = try Self.fixture()
        // The header holds the current style of the file: dimlfac 100 here.
        #expect(dwg.dimensionDefaults.linearScale == 100)
        #expect(dwg.dimensionDefaults.decimalPlaces == 2 && dwg.dimensionDefaults.unitSuffix == nil)
        let plain = Self.dimensions(dwg)[1]
        #expect(dwg.styleVariables(of: plain).linearScale == 1)
        #expect(dwg.displayedMeasurement(of: plain) == 25)
    }

    @Test("a style that states nothing leaves the variables nil, not guessed")
    func unstatedVariables() throws {
        let tables = [
            RawDXF.table(
                "DIMSTYLE",
                [
                    RawDXF.record("DIMSTYLE", (2, "STD"), (78, "12"), (3, "")),
                    RawDXF.record("DIMSTYLE", (2, "OTHER"), (271, "3"), (144, "0.5"), (3, "<> mm")),
                ])
        ]
        // Header variables as `9 / name`, then the value group; $DIMPOST is empty.
        let header = ["9\n$DIMDEC\n70\n4", "9\n$DIMPOST\n1\n"]
        let dwg = try Self.inline(
            Self.linear(a: (0, 0), b: (8.128, 0)), tables: tables, header: header)
        let dim = Self.dimensions(dwg)[0]
        let vars = dwg.styleVariables(of: dim)
        #expect(vars.decimalPlaces == nil && vars.linearScale == nil && vars.unitSuffix == nil)
        #expect(vars.zeroSuppression == 12 && vars.suppressesTrailingZeros)
        #expect(vars.effectiveScale == 1)
        #expect(dwg.dimensionDefaults.decimalPlaces == 4 && dwg.dimensionDefaults.unitSuffix == nil)
        #expect(dwg.displayedMeasurement(of: dim) == 8.128)
        // Another style on another dimension.
        let other = Self.linear(a: (0, 0), b: (8, 0)).map { $0.0 == 3 ? (3, "other") : $0 }
        let dwg2 = try Self.inline(other, tables: tables)
        let vars2 = dwg2.styleVariables(of: Self.dimensions(dwg2)[0])
        #expect(
            vars2
                == .init(
                    decimalPlaces: 3, zeroSuppression: nil, linearScale: 0.5,
                    unitSuffix: "<> mm"))
    }

    @Test("a negative linear scale applies to paper space only and is ignored")
    func negativeScale() {
        #expect(DXF.DimensionStyle.Variables(linearScale: -2).effectiveScale == 1)
        #expect(DXF.DimensionStyle.Variables(linearScale: 0).effectiveScale == 1)
        #expect(DXF.DimensionStyle.Variables(linearScale: 2).effectiveScale == 2)
        #expect(DXF.DimensionStyle.Variables().effectiveScale == 1)
    }

    @Test("zero suppression bits")
    func zeroSuppression() {
        func vars(_ z: Int?) -> DXF.DimensionStyle.Variables { .init(zeroSuppression: z) }
        #expect(!vars(nil).suppressesLeadingZeros && !vars(nil).suppressesTrailingZeros)
        #expect(vars(8).suppressesTrailingZeros && !vars(8).suppressesLeadingZeros)
        #expect(vars(4).suppressesLeadingZeros && !vars(4).suppressesTrailingZeros)
        #expect(vars(12).suppressesLeadingZeros && vars(12).suppressesTrailingZeros)
    }

    @Test("extended data in another order, with other applications, is read")
    func extendedDataVariants() throws {
        let xdata: [(Int, String)] = [
            (1001, "OTHERAPP"), (1000, "ignored"), (1070, "271"), (1070, "9"),
            (1001, "ACAD"), (1000, "DSTYLE"), (1002, "{"), (1070, "3"), (1000, "<> cm"),
            (1070, "144"), (1040, "0.1"), (1070, "78"), (1070, "8"), (1002, "}"),
            (1001, "LATER"), (1070, "271"), (1070, "7"),
        ]
        let dwg = try Self.inline(Self.linear(a: (0, 0), b: (8, 0), extra: xdata))
        let overrides = Self.dimensions(dwg)[0].styleOverrides
        #expect(
            overrides
                == .init(
                    decimalPlaces: nil, zeroSuppression: 8, linearScale: 0.1, unitSuffix: "<> cm"))
    }

    // MARK: Text

    @Test("the five override texts seen on McMaster drawings split into their parts")
    func textParts() {
        func text(_ s: String) -> DXF.DimensionText { .init(s) }

        let unit = text("<> mm")
        #expect(unit.parts == [.measurement, .words(" mm")])
        #expect(unit.showsMeasurement && unit.typedNumbers.isEmpty && unit.words == ["mm"])

        let label = text("<>\\PBore Size")
        #expect(label.parts == [.measurement, .lineBreak, .words("Bore Size")])
        #expect(label.showsMeasurement && label.words == ["Bore Size"])

        let limit = text("67 mm\\P(max)")
        #expect(
            limit.parts == [
                .number(67, text: "67"), .words(" mm"), .lineBreak, .words("(max)"),
            ])
        #expect(!limit.showsMeasurement && limit.typedNumbers == [67])
        #expect(limit.words == ["mm", "(max)"])

        let range = text("40 - 60 mm\\P(Adjustable)")
        #expect(range.typedNumbers == [40, 60] && !range.showsMeasurement)
        #expect(range.words == ["-", "mm", "(Adjustable)"])

        let note = text("Length is representative\\PProduct sold by Length")
        #expect(!note.showsMeasurement && note.typedNumbers.isEmpty)
        #expect(note.words == ["Length is representative", "Product sold by Length"])
    }

    @Test("no override shows the measurement; a single space hides the text")
    func textDefaults() {
        let none = DXF.DimensionText(nil)
        #expect(none.showsMeasurement && none.parts.isEmpty && none.raw == nil)
        #expect(DXF.DimensionText("").showsMeasurement)
        #expect(DXF.DimensionText("<>").parts == [.measurement])
        let hidden = DXF.DimensionText(" ")
        #expect(hidden.isSuppressed && !hidden.showsMeasurement)
    }

    @Test("numbers: decimals, signs, ranges without spaces, and prefixed values")
    func textNumbers() {
        #expect(DXF.DimensionText("R7.5").typedNumbers == [7.5])
        #expect(DXF.DimensionText("R7.5").words == ["R"])
        #expect(DXF.DimensionText("40-60").typedNumbers == [40, 60])
        #expect(DXF.DimensionText("-5 mm").typedNumbers == [-5])
        #expect(DXF.DimensionText("12.").typedNumbers == [12])
        #expect(DXF.DimensionText("0.25 TYP").parts.first == .number(0.25, text: "0.25"))
        #expect(DXF.DimensionText("a - b").typedNumbers.isEmpty)
    }

    @Test("numbers inside MTEXT formatting codes are not typed numbers")
    func formattingCodes() {
        #expect(DXF.DimensionText("\\C1;12.5").typedNumbers == [12.5])
        let font = DXF.DimensionText("{\\fArial|b0|i0|c0|p34;<> mm}")
        #expect(font.typedNumbers.isEmpty && font.parts.contains(.measurement))
        #expect(DXF.DimensionText("\\S1/2;").typedNumbers.isEmpty)
        #expect(DXF.DimensionText("\\H2.5;<>").typedNumbers.isEmpty)
        // Only `\P` breaks a line; `\p` carries paragraph properties.
        #expect(!DXF.DimensionText("\\pxqc;<>").parts.contains(.lineBreak))
        #expect(DXF.DimensionText("a\\Pb").parts == [.words("a"), .lineBreak, .words("b")])
        // An escaped backslash is text, so the number after it is typed.
        #expect(DXF.DimensionText("\\\\5").typedNumbers == [5])
    }

    @Test("unicode escapes and percent symbols are text, not typed numbers")
    func symbolEscapes() {
        #expect(DXF.DimensionText("45\\U+00B0").typedNumbers == [45])
        #expect(DXF.DimensionText("<>\\U+00B1 0.1").typedNumbers == [0.1])
        #expect(DXF.DimensionText("\\U+00D8<>").typedNumbers.isEmpty)
        #expect(DXF.DimensionText("\\U+00D8<>").parts.contains(.measurement))
        #expect(DXF.DimensionText("45%%d").typedNumbers == [45])
        #expect(DXF.DimensionText("%%c20").typedNumbers == [20])
        #expect(DXF.DimensionText("5%%176").typedNumbers == [5])
        #expect(DXF.DimensionText("%%p0.05").typedNumbers == [0.05])
        #expect(DXF.DimensionText("100%").typedNumbers == [100])
    }

    @Test("a dimension exposes its text parts")
    func dimensionText() throws {
        let dims = Self.dimensions(try Self.fixture())
        #expect(dims[0].text.showsMeasurement && dims[0].text.raw == "<>")
        #expect(dims[9].text.parts == [.measurement, .words(" mm")])
        #expect(dims[10].text.typedNumbers == [67])
    }
}
