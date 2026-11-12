import Foundation
import Testing

@testable import SwiftDXF

@Suite("DIMENSION measurement, rotation, style and text")
struct DimensionTests {

    /// A DXF document with a `DIMSTYLE` table and then the given entities, as group-code pairs.
    static func document(styles: [[(Int, String)]] = [], entities: [[(Int, String)]]) -> String {
        func lines(_ pairs: [(Int, String)]) -> String {
            pairs.map { "\($0.0)\n\($0.1)" }.joined(separator: "\n")
        }
        var out = "0\nSECTION\n2\nHEADER\n9\n$ACADVER\n1\nAC1032\n0\nENDSEC\n"
        out += "0\nSECTION\n2\nTABLES\n0\nTABLE\n2\nDIMSTYLE\n"
        for style in styles { out += "0\nDIMSTYLE\n" + lines(style) + "\n" }
        out += "0\nENDTAB\n0\nENDSEC\n0\nSECTION\n2\nENTITIES\n"
        for entity in entities { out += lines(entity) + "\n" }
        out += "0\nENDSEC\n0\nEOF\n"
        return out
    }

    /// The first McMaster record of 7021N13: a vertical rotated dimension with no stored value.
    static let mcmasterVertical: [(Int, String)] = [
        (0, "DIMENSION"), (5, "FD"), (8, "0"), (10, "396.1580270667"), (20, "219.0219670063"),
        (30, "0.0"), (11, "396.1580270667"), (21, "164.0319647"), (31, "0.0"), (70, "160"),
        (1, "<>"), (71, "2"), (42, "-1.0"), (3, "SLDDIMSTYLE0"), (13, "303.7339586256"),
        (23, "109.0219670063"), (33, "0.0"), (14, "303.7339586256"), (24, "219.0219670063"),
        (34, "0.0"), (50, "90.0"),
    ]

    /// The second record: horizontal, no group 50.
    static let mcmasterHorizontal: [(Int, String)] = [
        (0, "DIMENSION"), (5, "109"), (8, "0"), (10, "303.7339586256"), (20, "82.7941226"),
        (30, "0.0"), (11, "271.2296576667"), (21, "82.7941226"), (31, "0.0"), (70, "160"),
        (1, "<>"), (71, "2"), (42, "-1.0"), (3, "SLDDIMSTYLE0"), (13, "238.7339586256"),
        (23, "109.0219670063"), (33, "0.0"), (14, "303.7339586256"), (24, "109.0219670063"),
        (34, "0.0"),
    ]

    static func dimension(_ drawing: DXF.Drawing, _ index: Int = 0) -> DXF.Dimension? {
        guard case .dimension(let d) = drawing.entities[index] else { return nil }
        return d
    }

    @Test("a stored measurement of -1, 0 or nothing reads as not stored")
    func missingMeasurementIsNil() throws {
        let drawing = try DXF.read(
            text: Self.document(entities: [Self.mcmasterVertical, Self.mcmasterHorizontal]))
        for index in 0..<2 {
            if let d = Self.dimension(drawing, index) {
                #expect(d.measurement == nil)
                #expect(d.rawMeasurement == -1)
            } else {
                Issue.record("entity \(index) is not a dimension")
            }
        }
        var zero = Self.mcmasterHorizontal
        zero[zero.firstIndex { $0.0 == 42 }!] = (42, "0.0")
        var absent = Self.mcmasterHorizontal
        absent.removeAll { $0.0 == 42 }
        var stored = Self.mcmasterHorizontal
        stored[stored.firstIndex { $0.0 == 42 }!] = (42, "65.0")
        let more = try DXF.read(text: Self.document(entities: [zero, absent, stored]))
        #expect(Self.dimension(more, 0)?.measurement == nil)
        #expect(Self.dimension(more, 1)?.measurement == nil)
        #expect(Self.dimension(more, 1)?.rawMeasurement == nil)
        #expect(Self.dimension(more, 2)?.measurement == 65)
    }

    @Test("rotation selects the measurement direction and the value is computed from it")
    func rotationAndComputedValue() throws {
        let drawing = try DXF.read(
            text: Self.document(entities: [Self.mcmasterVertical, Self.mcmasterHorizontal]))
        if let vertical = Self.dimension(drawing, 0) {
            #expect(vertical.rotation == 90)
            #expect(vertical.measurementDirection == DXF.Point2(0, 1))
            if let value = vertical.computedMeasurement {
                #expect(abs(value - 109.9999999) < 1e-6)
            } else {
                Issue.record("no computed value")
            }
        }
        if let horizontal = Self.dimension(drawing, 1) {
            #expect(horizontal.rotation == nil)
            #expect(horizontal.measurementDirection == DXF.Point2(1, 0))
            if let value = horizontal.computedMeasurement {
                #expect(abs(value - 65) < 1e-9)
            } else {
                Issue.record("no computed value")
            }
            #expect(horizontal.measuredValue == horizontal.computedMeasurement)
        }
    }

    @Test("witness points that coincide still have a direction from the rotation")
    func coincidentWitnessPoints() {
        let d = DXF.Dimension(
            kind: .linear, measurement: nil, textOverride: nil, textPosition: DXF.Point(0, 0),
            defPoint: DXF.Point(5, 5), defPoint2: DXF.Point(0, 0), defPoint3: DXF.Point(30, 40),
            layer: "0", color: 7, rotation: 36.8698976458)
        // Direction (0.8, 0.6): 30 * 0.8 + 40 * 0.6 = 48.
        if let value = d.computedMeasurement { #expect(abs(value - 48) < 1e-6) }
        let aligned = DXF.Dimension(
            kind: .aligned, measurement: nil, textOverride: nil, textPosition: DXF.Point(0, 0),
            defPoint: DXF.Point(5, 5), defPoint2: DXF.Point(0, 0), defPoint3: DXF.Point(30, 40),
            layer: "0", color: 7)
        #expect(aligned.computedMeasurement == 50)
    }

    @Test("radius and diameter measure the distance between their two points")
    func radiusAndDiameter() {
        func make(_ kind: DXF.DimensionType) -> DXF.Dimension {
            DXF.Dimension(
                kind: kind, measurement: nil, textOverride: nil, textPosition: DXF.Point(0, 0),
                defPoint: DXF.Point(0, 0), defPoint4: DXF.Point(3, 4), layer: "0", color: 7)
        }
        #expect(make(.radius).computedMeasurement == 5)
        #expect(make(.diameter).computedMeasurement == 5)
        #expect(make(.angular).computedMeasurement == nil)
        #expect(make(.ordinate).computedMeasurement == nil)
    }

    @Test("the oblique angle is read from group 52")
    func obliqueAngle() throws {
        let record = Self.mcmasterHorizontal + [(52, "30.0")]
        let drawing = try DXF.read(text: Self.document(entities: [record]))
        #expect(Self.dimension(drawing)?.obliqueAngle == 30)
    }

    @Test("the style supplies precision and suffix, and the entity's overrides win")
    func styleAndOverrides() throws {
        let style: [(Int, String)] = [
            (2, "SLDDIMSTYLE0"), (70, "0"), (3, "<> mm"), (144, "1.0"), (271, "2"),
        ]
        let overridden =
            Self.mcmasterHorizontal + [
                (1001, "ACAD"), (1000, "DSTYLE"), (1002, "{"), (1070, "271"), (1070, "3"),
                (1070, "144"), (1040, "25.4"), (1002, "}"),
            ]
        let drawing = try DXF.read(
            text: Self.document(styles: [style], entities: [Self.mcmasterHorizontal, overridden]))
        #expect(drawing.dimensionStyles["SLDDIMSTYLE0"]?.decimals == 2)
        guard let plain = Self.dimension(drawing, 0), let over = Self.dimension(drawing, 1) else {
            Issue.record("missing dimensions")
            return
        }
        #expect(plain.styleName == "SLDDIMSTYLE0")
        #expect(plain.styleOverrides.isEmpty)
        let plainStyle = drawing.style(of: plain)
        #expect(plainStyle.decimals == 2 && plainStyle.suffix == "<> mm")
        #expect(plainStyle.format(65) == "65.00 mm")
        #expect(over.styleOverrides.decimals == 3)
        #expect(over.styleOverrides.linearScale == 25.4)
        #expect(drawing.style(of: over).decimals == 3)
        #expect(drawing.style(of: over).format(1) == "25.400 mm")
    }

    @Test("a style the file does not carry leaves precision unknown, not guessed")
    func unknownStyle() throws {
        let drawing = try DXF.read(text: Self.document(entities: [Self.mcmasterHorizontal]))
        if let d = Self.dimension(drawing) {
            let style = drawing.style(of: d)
            #expect(style.decimals == nil && style.suffix == nil && style.linearScale == nil)
        }
    }

    // MARK: text

    @Test("a decorated default keeps the placeholder and the words around it")
    func decoratedDefault() {
        let plain = DXF.DimensionText("<> mm")
        #expect(plain.showsMeasurement && plain.typedNumbers.isEmpty)
        #expect(plain.suffix == "mm" && plain.prefix == "")
        #expect(plain.unit == "mm" && plain.words == "")

        let labelled = DXF.DimensionText("<>\\PBore Size")
        #expect(labelled.showsMeasurement)
        #expect(labelled.words == "Bore Size")
        #expect(labelled.lines == ["<>", "Bore Size"])
        #expect(labelled.typedValue == nil && !labelled.isNote)
    }

    @Test("no override and a bare placeholder both show the measured value")
    func defaultText() {
        for override in [nil, "", "<>"] {
            let t = DXF.DimensionText(override)
            #expect(t.showsMeasurement && !t.isSuppressed && t.typedNumbers.isEmpty)
            #expect(t.words == "" && !t.isNote)
        }
    }

    @Test("a limit is one number with a qualifier")
    func limit() {
        let t = DXF.DimensionText("67 mm\\P(max)")
        #expect(!t.showsMeasurement)
        #expect(t.typedNumbers == [67] && t.unit == "mm")
        #expect(t.qualifiers == ["max"])
        #expect(t.isLimit && t.typedValue == nil && !t.isRange)
        #expect(t.words == "")
    }

    @Test("a range is two numbers, and a hyphen between them is not a sign")
    func range() {
        let t = DXF.DimensionText("40 - 60 mm\\P(Adjustable)")
        #expect(t.typedNumbers == [40, 60] && t.isRange)
        #expect(t.qualifiers == ["adjustable"] && t.unit == "mm")
        #expect(!t.isLimit && t.typedValue == nil)
    }

    @Test("a note is words with no value")
    func note() {
        let t = DXF.DimensionText("Length is representative\\PProduct sold by Length")
        #expect(t.isNote && t.typedNumbers.isEmpty && !t.showsMeasurement)
        #expect(t.words == "Length is representative Product sold by Length")
        #expect(t.lines.count == 2)
    }

    @Test("a typed number is a value, and a signed one keeps its sign")
    func typedValue() {
        #expect(DXF.DimensionText("12.5").typedValue == 12.5)
        #expect(DXF.DimensionText("-3 mm").typedValue == -3)
        #expect(DXF.DimensionText("R7.5").typedValue == 7.5)
        #expect(DXF.DimensionText("R7.5").words == "R")
    }

    @Test("a single space suppresses the text")
    func suppressed() {
        let t = DXF.DimensionText(" ")
        #expect(t.isSuppressed && !t.showsMeasurement && !t.isNote)
    }

    @Test("the entity exposes its text parts")
    func entityText() throws {
        var record = Self.mcmasterHorizontal
        record[record.firstIndex { $0.0 == 1 }!] = (1, "<> mm\\PBore Size")
        let drawing = try DXF.read(text: Self.document(entities: [record]))
        if let d = Self.dimension(drawing) {
            #expect(d.text.showsMeasurement && d.text.words == "Bore Size")
        }
    }
}
