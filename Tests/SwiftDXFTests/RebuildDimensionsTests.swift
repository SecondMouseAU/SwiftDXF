import Foundation
import Testing

@testable import SwiftDXF

/// Dimensions rebuilt from loose pieces: value texts, dimension lines, extension lines and marks.
@Suite("Rebuilding dimensions")
struct RebuildDimensionsTests {
    typealias Record = DXFBuilder.Record

    // MARK: building the pieces

    static func text(
        _ string: String, _ x: Double, _ y: Double, rotation: Double = 0, layer: String = "0"
    ) -> Record {
        [
            (0, "TEXT"), (8, layer), (10, "\(x)"), (20, "\(y)"), (30, "0"), (40, "2.5"),
            (1, string), (50, "\(rotation)"),
        ]
    }

    static func line(
        _ a: (Double, Double), _ b: (Double, Double), layer: String = "0"
    ) -> Record {
        DXFBuilder.line(a, b, layer: layer)
    }

    static func point(_ x: Double, _ y: Double, layer: String = "0") -> Record {
        [(0, "POINT"), (8, layer), (10, "\(x)"), (20, "\(y)"), (30, "0")]
    }

    /// How the ends of a dimension line are marked.
    enum Ends {
        case extensionLines
        case points
        case arrowheads
        case dots
    }

    /// A chain of horizontal dimensions along `y`, one per length (in drawn units), each with its
    /// value text, which states the length times `scale`.
    static func chain(
        scale: Double, lengths: [Double], from x0: Double = 0, y: Double = -10,
        layer: String = "0", ends: Ends = .extensionLines, decimals: Int = 0, comma: Bool = false
    ) -> [Record] {
        var xs = [x0]
        for length in lengths { xs.append(xs.last! + length) }
        var records: [Record] = [line((xs.first!, y), (xs.last!, y), layer: layer)]
        for x in xs {
            switch ends {
            case .extensionLines: records.append(line((x, y + 10), (x, y - 2), layer: layer))
            case .points: records.append(point(x, y, layer: layer))
            case .dots:
                records.append(
                    DXFBuilder.circle((x, y), 0.2, layer: layer))
            case .arrowheads:
                let inward = x == xs.last! ? -1.0 : 1.0
                records.append(
                    [
                        (0, "LWPOLYLINE"), (8, layer), (90, "3"), (70, "1"),
                        (10, "\(x)"), (20, "\(y)"),
                        (10, "\(x + inward * 2.5)"), (20, "\(y + 0.4)"),
                        (10, "\(x + inward * 2.5)"), (20, "\(y - 0.4)"),
                    ])
            }
        }
        for (i, length) in lengths.enumerated() {
            var string = String(format: "%.\(decimals)f", length * scale)
            if comma {
                if decimals > 0 {
                    string = string.replacingOccurrences(of: ".", with: ",")
                } else if string.count > 3 {
                    string.insert(",", at: string.index(string.endIndex, offsetBy: -3))
                }
            }
            let width = Double(string.count) * 1.5
            records.append(text(string, xs[i] + length / 2 - width / 2, y + 0.5, layer: layer))
        }
        return records
    }

    static func drawing(_ records: [Record], options: DXF.ReadOptions = .init()) throws
        -> DXF.Drawing
    {
        var builder = DXFBuilder()
        builder.entities = records
        return try DXF.read(text: builder.text(), options: options)
    }

    static func rebuild(
        _ records: [Record], _ options: DXF.DimensionRebuild.Options = .init()
    ) throws -> (DXF.Drawing, DXF.DimensionRebuild) {
        let dwg = try drawing(records)
        return (dwg, dwg.rebuildingDimensions(options))
    }

    // MARK: a chain, however its ends are marked

    @Test(
        "a chain of linear dimensions is rebuilt, and its scale inferred",
        arguments: [Ends.extensionLines, .points, .arrowheads, .dots])
    func chainOfLinearDimensions(ends: Ends) throws {
        let (dwg, result) = try Self.rebuild(
            Self.chain(scale: 50, lengths: [20, 30, 15], ends: ends))
        #expect(result.dimensions.count == 3)
        #expect(result.warnings.isEmpty)
        #expect(
            result.scales == [
                .init(group: "0", scale: 50, supporting: 3, contradicting: 0)
            ])
        let strings = result.dimensions.map(\.textOverride)
        #expect(strings == ["1000", "1500", "750"])
        for (dimension, length) in zip(result.dimensions, [20.0, 30, 15]) {
            #expect(dimension.kind == .linear && dimension.rotation == 0)
            #expect(abs((dimension.measurement ?? 0) - length) < 1e-9)
            #expect(abs((dwg.displayedMeasurement(of: dimension) ?? 0) - length * 50) < 1e-6)
            #expect(abs((dimension.computedMeasurement ?? 0) - length) < 1e-9)
            #expect(dimension.rebuilt?.scale == 50)
        }
    }

    @Test("a dimension names the pieces it was built from, the text first")
    func pieces() throws {
        let records = Self.chain(scale: 50, lengths: [20, 30])
        let (dwg, result) = try Self.rebuild(records)
        let first = try #require(result.dimensions.first?.rebuilt)
        // The chain's records are the dimension line, three extension lines, then two texts.
        let textIndex = 4
        #expect(first.pieces.first == dwg.identity(ofEntityAt: textIndex))
        let locators = first.pieces.map(\.locator)
        #expect(locators.contains("ENTITIES:0"), "the dimension line")
        #expect(locators.contains("ENTITIES:1") && locators.contains("ENTITIES:2"))
        #expect(!locators.contains("ENTITIES:3"), "the extension line of the other end")
    }

    @Test("a vertical dimension has a vertical text and a rotation of 90")
    func vertical() throws {
        let (_, result) = try Self.rebuild([
            Self.line((0, 0), (0, 20)), Self.line((0, 20), (0, 50)),
            Self.line((-2, 0), (8, 0)), Self.line((-2, 20), (8, 20)), Self.line((-2, 50), (8, 50)),
            Self.text("1000", 1.0, 7.0, rotation: 90), Self.text("1500", 1.0, 31.0, rotation: 90),
        ])
        #expect(result.dimensions.count == 2)
        #expect(result.dimensions.allSatisfy { $0.kind == .linear && $0.rotation == 90 })
        let measured = result.dimensions.compactMap(\.computedMeasurement)
        #expect(measured.count == 2 && abs(measured[0] - 20) < 1e-9 && abs(measured[1] - 30) < 1e-9)
    }

    @Test("a dimension along a slanted line is aligned")
    func aligned() throws {
        let angle = 30.0 * .pi / 180
        let (c, s) = (cos(angle), sin(angle))
        func at(_ t: Double, _ offset: Double) -> (Double, Double) {
            (t * c - offset * s, t * s + offset * c)
        }
        var records: [Record] = [Self.line(at(0, 10), at(50, 10))]
        for t in [0.0, 20, 50] { records.append(Self.line(at(t, 12), at(t, -2))) }
        for (from, to, string) in [(0.0, 20.0, "1000"), (20, 50, "1500")] {
            let center = at((from + to) / 2 - 3, 10.5)
            records.append(Self.text(string, center.0, center.1, rotation: 30))
        }
        let (_, result) = try Self.rebuild(records)
        #expect(result.dimensions.count == 2)
        #expect(result.dimensions.allSatisfy { $0.kind == .aligned && $0.rotation == nil })
        let measured = result.dimensions.compactMap(\.computedMeasurement)
        #expect(measured.count == 2 && abs(measured[0] - 20) < 1e-6 && abs(measured[1] - 30) < 1e-6)
    }

    // MARK: values

    @Test("a comma is a decimal mark or a thousands separator, whichever the geometry bears out")
    func commas() throws {
        let decimal = try Self.rebuild(
            Self.chain(scale: 1, lengths: [2.5, 3.5, 6.5], decimals: 1, comma: true))
        #expect(decimal.1.dimensions.map(\.textOverride) == ["2,5", "3,5", "6,5"])
        #expect(decimal.1.scales.first?.scale == 1)
        let thousands = try Self.rebuild(
            Self.chain(scale: 80, lengths: [22.8625, 24.7625, 27.625], comma: true))
        #expect(thousands.1.dimensions.map(\.textOverride) == ["1,829", "1,981", "2,210"])
        #expect(thousands.1.scales.first?.scale == 80)
    }

    @Test("what a text states: symbols, commas, tolerances and the texts that are not rebuilt")
    func values() {
        typealias Value = DXF.DimensionRebuild.Value
        func read(_ s: String) -> Value? { Value.read(s) }
        #expect(read("12.5")?.readings == [.init(value: 12.5, decimals: 1)])
        #expect(
            read("1,829")?.readings == [
                .init(value: 1.829, decimals: 3), .init(value: 1829, decimals: 0),
            ])
        #expect(read("0,011")?.readings == [.init(value: 0.011, decimals: 3)])
        #expect(read("1,5")?.readings == [.init(value: 1.5, decimals: 1)])
        #expect(read("1,234.5")?.readings == [.init(value: 1234.5, decimals: 1)])
        #expect(read("1,234,567")?.readings == [.init(value: 1_234_567, decimals: 0)])
        #expect(read("\u{FF15}\u{FF10}\u{FF10}")?.readings == [.init(value: 500, decimals: 0)])
        #expect(read("\u{2300}26")?.symbol == .diameter && read("R7.5")?.symbol == .radius)
        #expect(read("R 7.5")?.symbol == .radius && read("26 mm")?.unsupported == nil)
        #expect(read("45\u{B0}")?.unsupported == .angular)
        #expect(read("2x45")?.unsupported == .severalNumbers)
        #expect(read("5m")?.unsupported == .unit && read("3\"")?.unsupported == .unit)
        #expect(read("Radius") == nil && read("L=100") == nil && read("") == nil)
        let stacked = DXF.TextContent(#"36{\H2.4;\S+0,011^ -0,005;}"#, syntax: .mtext)
        #expect(Value.read(stacked)?.readings == [.init(value: 36, decimals: 0)])
    }

    @Test("values a text assembler ran together are separate values")
    func runTogether() throws {
        let records =
            Self.chain(scale: 80, lengths: [30, 25], from: 20, y: 40)
            + [
                Self.line((0, 0), (0, 10)), Self.line((2.5, 0), (2.5, 10)),
                Self.line((10.4, 0), (10.4, 10)), Self.line((0, 3), (10.4, 3)),
                Self.text("200 632", -1, 3.5),
            ]
        let (_, result) = try Self.rebuild(records)
        #expect(result.dimensions.map(\.textOverride).suffix(2) == ["200", "632"])
        #expect(result.warnings.isEmpty)
    }

    // MARK: scales

    @Test("each layer group has its own scale, and groups that differ are reported, not averaged")
    func disagreeingGroups() throws {
        let (_, result) = try Self.rebuild(
            Self.chain(scale: 50, lengths: [20, 30], layer: "1-0")
                + Self.chain(scale: 100, lengths: [20, 30], y: 100, layer: "2-0"))
        #expect(result.dimensions.count == 4)
        #expect(result.scales.map(\.group) == ["1", "2"])
        #expect(result.scales.map(\.scale) == [50, 100])
        #expect(result.dimensions.map { $0.rebuilt?.scale } == [50, 50, 100, 100])
        #expect(result.warnings == [.scalesDisagree(result.scales)])
    }

    @Test("layers of one Jw_cad layer group share a scale, and groups that agree are not warned of")
    func agreeingGroups() throws {
        let (_, result) = try Self.rebuild(
            Self.chain(scale: 80, lengths: [20], layer: "0-E")
                + Self.chain(scale: 80, lengths: [30], y: 100, layer: "0-F")
                + Self.chain(scale: 80, lengths: [10, 25], y: 200, layer: "3-0"))
        #expect(result.scales.map(\.group) == ["0", "3"])
        #expect(result.scales.map(\.scale) == [80, 80])
        #expect(result.warnings.isEmpty)
        #expect(result.dimensions.count == 4)
    }

    @Test("a value that no geometry explains is a warning, and does not spoil the scale")
    func unexplainedValue() throws {
        var records = Self.chain(scale: 50, lengths: [20, 30, 15])
        records.append(Self.text("777", 5, -9.5))
        let (dwg, result) = try Self.rebuild(records)
        #expect(result.dimensions.count == 3)
        #expect(result.scales == [.init(group: "0", scale: 50, supporting: 3, contradicting: 1)])
        let identity = dwg.identity(ofEntityAt: records.count - 1)
        #expect(
            result.warnings == [
                .valueNotExplained(text: "777", identity: identity, reason: .noMatch)
            ])
    }

    @Test("one value cannot give a scale, unless the scale is stated")
    func oneValue() throws {
        let records = Self.chain(scale: 50, lengths: [20])
        let (dwg, result) = try Self.rebuild(records)
        #expect(result.dimensions.isEmpty && result.scales.isEmpty)
        #expect(
            result.warnings == [
                .valueNotExplained(
                    text: "1000", identity: dwg.identity(ofEntityAt: records.count - 1),
                    reason: .noScale)
            ])
        let stated = dwg.rebuildingDimensions(.init(scale: 50))
        #expect(stated.dimensions.count == 1 && stated.warnings.isEmpty)
        #expect(stated.scales == [.init(group: "0", scale: 50, supporting: 1, contradicting: 0)])
        // A stated scale the geometry does not bear out explains nothing.
        let wrong = dwg.rebuildingDimensions(.init(scale: 60))
        #expect(wrong.dimensions.isEmpty)
    }

    @Test("values that do not agree on any scale are not given one")
    func noConsistentScale() throws {
        var records = Self.chain(scale: 50, lengths: [20, 30, 15])
        // Change the values so no one scale explains them.
        records = records.map { record in
            guard record[0].1 == "TEXT" else { return record }
            var out = record
            let changed = ["1000": "913", "1500": "1777", "750": "421"]
            out[6].1 = changed[out[6].1] ?? out[6].1
            return out
        }
        let (_, result) = try Self.rebuild(records)
        #expect(result.dimensions.isEmpty)
    }

    @Test("a scale that is not round is reported as found, and a round one as round")
    func roundness() throws {
        let odd = try Self.rebuild(Self.chain(scale: 79.5, lengths: [20, 30, 15, 40])).1
        #expect(odd.dimensions.count == 4)
        let found = try #require(odd.scales.first?.scale)
        #expect(abs(found - 79.5) < 0.3 && found != 80, "reported \(found)")
        let small = try Self.rebuild(Self.chain(scale: 3.5, lengths: [20, 30, 15, 40])).1
        #expect(small.dimensions.count == 4 && abs((small.scales.first?.scale ?? 0) - 3.5) < 0.05)
        let enlarged = try Self.rebuild(Self.chain(scale: 0.5, lengths: [20, 30, 15, 40])).1
        #expect(enlarged.scales.first?.scale == 0.5 && enlarged.dimensions.count == 4)
    }

    @Test("equal values each take their own span")
    func equalValues() throws {
        let (_, result) = try Self.rebuild(Self.chain(scale: 50, lengths: [20, 30, 20, 10]))
        #expect(result.dimensions.map(\.textOverride) == ["1000", "1500", "1000", "500"])
        let spans = result.dimensions.map { $0.defPoint2?.x ?? .nan }
        #expect(spans == [0, 20, 50, 70])
    }

    @Test("a text nearer another span than its own takes the next span, as each is used once")
    func spanUsedOnce() throws {
        var records = Self.chain(scale: 50, lengths: [2, 2, 30, 20])
        // The second narrow dimension's text stands closer to the first span than to its own.
        let second = records.count - 3
        records[second] = Self.text("100", -0.45, -9.5)
        let (_, result) = try Self.rebuild(records)
        #expect(result.dimensions.map(\.textOverride) == ["100", "100", "1500", "1000"])
        #expect(result.dimensions.map { $0.defPoint2?.x ?? .nan } == [0, 2, 4, 34])
    }

    @Test("an extension line beyond the dimension line, or a gap that is not the text's, is no end")
    func strayPieces() throws {
        var records = Self.chain(scale: 50, lengths: [20, 30])
        // A line that meets the dimension line's axis beyond its end is not an end.
        records.append(Self.line((60, 0), (60, -20)))
        let (_, beyond) = try Self.rebuild(records)
        #expect(beyond.dimensions.count == 2 && beyond.warnings.isEmpty)
        // A dimension line with a hole where no text is does not span it.
        var holed: [Record] = []
        for x in [0.0, 20, 50] { holed.append(Self.line((x, 0), (x, -12))) }
        holed.append(Self.line((0, -10), (9, -10)))
        holed.append(Self.line((12, -10), (20, -10)))
        holed.append(Self.line((20, -10), (50, -10)))
        holed.append(Self.text("1000", 7.5, -10.5))
        holed.append(Self.text("1500", 32.0, -10.5))
        // The 3 units missing between 9 and 12 are under the text's place, so it is still found;
        // move the text away and the gap is no longer its own.
        let kept = try Self.rebuild(holed).1
        #expect(kept.dimensions.count == 2)
        holed[holed.count - 2] = Self.text("1000", 14.0, -10.5)
        let broken = try Self.rebuild(holed, .init(scale: 50)).1
        #expect(broken.dimensions.map(\.textOverride) == ["1500"])
    }

    @Test("only a piece that meets the dimension line, on it, is an end")
    func endsMustMeetTheLine() throws {
        var records = Self.chain(scale: 50, lengths: [20, 30, 15])
        // An extension line that meets the line's axis beyond its end, and a mark off the line:
        // texts that would be explained by them are not.
        records.append(Self.line((75, 0), (75, -20)))
        records.append(Self.point(10, 5))
        records.append(Self.text("500", 68, -10.5))
        records.append(Self.text("500", 3, -10.5))
        let (_, result) = try Self.rebuild(records)
        #expect(result.dimensions.map(\.textOverride) == ["1000", "1500", "750"])
        #expect(result.warnings.count == 2)
    }

    @Test("a join between two pieces of the dimension line is not an end")
    func joinIsNoEnd() throws {
        var records = Self.chain(scale: 50, lengths: [20, 30], from: 100)
        // Extension lines at 0 and 50 only, the dimension line in two pieces joined at 25.
        records.append(Self.line((0, 0), (0, -12)))
        records.append(Self.line((50, 0), (50, -12)))
        records.append(Self.line((0, -10), (25, -10)))
        records.append(Self.line((25, -10), (50, -10)))
        records.append(Self.text("2500", 22.0, -10.5))
        records.append(Self.text("1250", 4.0, -10.5))
        let (_, result) = try Self.rebuild(records)
        #expect(result.dimensions.map(\.textOverride).contains("2500"))
        #expect(!result.dimensions.map(\.textOverride).contains("1250"))
    }

    @Test("a text far along the line is not the value of a span of it")
    func farAlongTheLine() throws {
        var records = Self.chain(scale: 50, lengths: [20])
        records[records.count - 1] = Self.text("1000", 150, -10.5)
        let (_, result) = try Self.rebuild(records, .init(scale: 50))
        #expect(result.dimensions.isEmpty)
    }

    @Test("values that disagree with the scale outnumber the ones that agree: no scale")
    func majority() throws {
        var records = Self.chain(scale: 50, lengths: [20, 30, 15])
        for (x, value) in [(2.0, "913"), (12.0, "123"), (22.0, "617"), (32.0, "333")] {
            records.append(Self.text(value, x, -9.5))
        }
        let (_, result) = try Self.rebuild(records)
        #expect(result.dimensions.isEmpty && result.scales.isEmpty)
    }

    @Test("a line that ends on a circle but does not pass through its centre is no radius")
    func chordIsNoRadius() throws {
        let records: [Record] = [
            Self.circle(0, 0, 10), Self.line((9.539392, 3), (20, 3)), Self.text("R20", 14, 3.5),
        ]
        let (_, result) = try Self.rebuild(records, .init(scale: 2))
        #expect(result.dimensions.isEmpty)
    }

    @Test("a numbered sequence beside lines is not a scale")
    func sequence() throws {
        // Ten equal spans numbered 1 to 10 fit the scale 1/45, which no drawing is at.
        var records: [Record] = [Self.line((0, 0), (450, 0))]
        for k in 0...10 { records.append(Self.line((Double(k) * 45, 5), (Double(k) * 45, -2))) }
        for k in 1...10 { records.append(Self.text("\(k)", Double(k) * 45 - 25, 0.5)) }
        let (_, result) = try Self.rebuild(records)
        #expect(result.dimensions.isEmpty)
    }

    // MARK: diameters and radii

    static func circle(_ x: Double, _ y: Double, _ radius: Double) -> Record {
        DXFBuilder.circle((x, y), radius)
    }

    @Test(
        "a diameter is a line across a circle, a radius a line from its centre, whatever the text")
    func diametersAndRadii() throws {
        let records: [Record] = [
            // Diameters, with the symbol and without it.
            Self.circle(0, 0, 10), Self.line((-10, 0), (10, 0)), Self.text("\u{2300}40", -3, 1),
            Self.circle(40, 0, 5), Self.line((35, 0), (45, 0)), Self.text("20", 37, 1),
            // Radii, from the centre to the arc, with the symbol and without it.
            Self.circle(0, 40, 10), Self.line((0, 40), (10, 40)), Self.text("R20", 3, 41),
            Self.circle(40, 40, 5), Self.line((40, 40), (45, 40)), Self.text("10", 42, 41),
        ]
        let (dwg, result) = try Self.rebuild(records)
        #expect(result.warnings.isEmpty)
        #expect(result.dimensions.map(\.kind) == [.diameter, .diameter, .radius, .radius])
        #expect(result.dimensions.map(\.textOverride) == ["\u{2300}40", "20", "R20", "10"])
        #expect(result.scales == [.init(group: "0", scale: 2, supporting: 4, contradicting: 0)])
        #expect(result.dimensions.compactMap(\.measurement) == [20, 10, 10, 5])
        for dimension in result.dimensions {
            #expect(
                abs((dimension.computedMeasurement ?? 0) - (dimension.measurement ?? -1)) < 1e-9)
        }
        let radius = result.dimensions[2]
        #expect(radius.defPoint == DXF.Point(0, 40) && radius.defPoint4 == DXF.Point(10, 40))
        let shown = result.dimensions.compactMap { dwg.displayedMeasurement(of: $0) }
        #expect(shown == [40, 20, 20, 10])
    }

    @Test("an arc is dimensioned by a line from its centre to a point on it")
    func arcRadius() throws {
        let arc: Record = [
            (0, "ARC"), (8, "0"), (10, "0"), (20, "0"), (30, "0"), (40, "10"), (50, "0"),
            (51, "90"),
        ]
        let (_, result) = try Self.rebuild(
            [
                arc, Self.line((0, 0), (10, 0)), Self.text("R20", 4, 0.5),
                Self.circle(40, 0, 5), Self.line((40, 0), (45, 0)), Self.text("R10", 42, 0.5),
            ])
        #expect(result.dimensions.map(\.kind) == [.radius, .radius])
        // A line to a point the arc does not reach is no radius of it. The scale is stated, as a
        // single value cannot give one.
        let off: Record = [
            (0, "ARC"), (8, "0"), (10, "0"), (20, "0"), (30, "0"), (40, "10"), (50, "180"),
            (51, "270"),
        ]
        let none = try Self.rebuild(
            [
                off, Self.line((0, 0), (10, 0)), Self.text("R20", 4, 0.5),
                Self.circle(40, 0, 5), Self.line((40, 0), (45, 0)), Self.text("R10", 42, 0.5),
            ], .init(scale: 2))
        #expect(none.1.dimensions.map(\.textOverride) == ["R10"])
    }

    @Test("an arc of 360 degrees is a whole circle")
    func fullArc() throws {
        let full: Record = [
            (0, "ARC"), (8, "0"), (10, "0"), (20, "0"), (30, "0"), (40, "10"), (50, "0"),
            (51, "360"),
        ]
        let (_, result) = try Self.rebuild([
            full, Self.line((-10, 0), (10, 0)), Self.text("40", -3, 1),
            Self.circle(40, 0, 5), Self.line((35, 0), (45, 0)), Self.text("20", 37, 1),
        ])
        #expect(result.dimensions.map(\.kind) == [.diameter, .diameter])
    }

    @Test("a symbol the geometry does not bear out is reported, and the geometry decides")
    func symbolDisagrees() throws {
        let records: [Record] = [
            Self.circle(0, 0, 10), Self.line((-10, 0), (10, 0)), Self.text("R40", -3, 1),
            Self.circle(40, 0, 5), Self.line((35, 0), (45, 0)), Self.text("\u{2300}20", 37, 1),
        ]
        let (dwg, result) = try Self.rebuild(records)
        #expect(result.dimensions.map(\.kind) == [.diameter, .diameter])
        #expect(
            result.warnings == [
                .symbolDisagrees(
                    text: "R40", identity: dwg.identity(ofEntityAt: 2), geometry: .diameter)
            ])
    }

    // MARK: what is read, and where the pieces are

    @Test("a drawing with real dimensions and no loose pieces gains nothing and warns of nothing")
    func realDimensionsOnly() throws {
        let url = try #require(
            Bundle.module.url(
                forResource: "dimensions", withExtension: "dxf", subdirectory: "Fixtures"))
        let dwg = try DXF.read(contentsOf: url)
        #expect(dwg.counts.dimension > 0)
        let result = dwg.rebuildingDimensions()
        #expect(result.dimensions.isEmpty && result.warnings.isEmpty && result.scales.isEmpty)
        for case .dimension(let dimension) in dwg.entities { #expect(dimension.rebuilt == nil) }
    }

    @Test("the same text stored twice is one value, and both are in the pieces")
    func duplicateText() throws {
        var records = Self.chain(scale: 50, lengths: [20, 30])
        records.append(records[records.count - 2])
        let (dwg, result) = try Self.rebuild(records)
        #expect(result.dimensions.count == 2 && result.warnings.isEmpty)
        let pieces = result.dimensions[0].rebuilt?.pieces ?? []
        #expect(pieces.contains(dwg.identity(ofEntityAt: 4)))
        #expect(pieces.contains(dwg.identity(ofEntityAt: records.count - 1)))
    }

    @Test("pieces on other layers are left alone unless any layer is allowed")
    func layers() throws {
        var records = Self.chain(scale: 50, lengths: [20, 30])
        records = records.map { record in
            guard record[0].1 == "LINE" else { return record }
            return record.map { $0.0 == 8 ? (8, "GEOMETRY") : $0 }
        }
        let (_, same) = try Self.rebuild(records)
        #expect(same.dimensions.isEmpty)
        let (_, any) = try Self.rebuild(records, .init(pieceLayers: .any))
        #expect(any.dimensions.count == 2)
    }

    @Test("a text far from a line is not its value")
    func farText() throws {
        var records = Self.chain(scale: 50, lengths: [20, 30])
        records = records.map { record in
            guard record[0].1 == "TEXT" else { return record }
            return record.map { $0.0 == 20 ? (20, "30") : $0 }
        }
        let (_, result) = try Self.rebuild(records)
        #expect(result.dimensions.isEmpty)
    }

    @Test("a dimension line broken around its text is still one dimension")
    func brokenLine() throws {
        var records: [Record] = []
        for x in [0.0, 20, 50] { records.append(Self.line((x, 0), (x, -12))) }
        // Each dimension line has a gap of 6 for its text.
        records.append(Self.line((0, -10), (7, -10)))
        records.append(Self.line((13, -10), (20, -10)))
        records.append(Self.line((20, -10), (32, -10)))
        records.append(Self.line((38, -10), (50, -10)))
        records.append(Self.text("1000", 7.0, -10.5))
        records.append(Self.text("1500", 32.0, -10.5))
        let (_, result) = try Self.rebuild(records)
        #expect(result.dimensions.count == 2)
        #expect(result.warnings.isEmpty)
    }

    @Test("texts that cannot be rebuilt are listed with the reason")
    func unsupported() throws {
        var records = Self.chain(scale: 50, lengths: [20, 30, 15])
        records.append(Self.text("45\u{B0}", 5, -9.5))
        records.append(Self.text("2x45", 20, -9.5))
        records.append(Self.text("5m", 30, -9.5))
        let (_, result) = try Self.rebuild(records)
        #expect(result.dimensions.count == 3)
        let reasons = result.warnings.compactMap { warning -> DXF.DimensionRebuild.Reason? in
            guard case .valueNotExplained(_, _, let reason) = warning else { return nil }
            return reason
        }
        #expect(reasons == [.angular, .severalNumbers, .unit])
    }

    // MARK: the result

    @Test("the rebuilt dimensions can be added to the drawing, and the rest is kept")
    func applied() throws {
        let records = Self.chain(scale: 50, lengths: [20, 30])
        let (dwg, result) = try Self.rebuild(records)
        let out = result.applied(to: dwg)
        #expect(out.entities.count == dwg.entities.count + 2)
        #expect(out.counts.dimension == dwg.counts.dimension + 2)
        #expect(out.identities.count == out.entities.count)
        #expect(out.identity(ofEntityAt: dwg.entities.count).locator == "REBUILT:0")
        #expect(out.identity(ofEntityAt: 0) == dwg.identity(ofEntityAt: 0))
        #expect(out.textContents.count == out.entities.count)
        #expect(out.textContent(ofEntityAt: records.count - 1)?.raw == "1500")
        guard case .dimension(let added) = out.entities[dwg.entities.count] else {
            Issue.record("not a dimension")
            return
        }
        #expect(added.rebuilt != nil && added.textOverride == "1000")
    }

    // MARK: input that is not what it should be

    @Test("pieces of one line that tilt either way by a hair are still one dimension line")
    func tiltedPieces() throws {
        for tilt in [1e-9, -1e-9, 1e-12, -1e-12] {
            var records: [Record] = []
            for x in [0.0, 20, 50, 65] { records.append(Self.line((x, 0), (x, -12))) }
            records.append(Self.line((0, -10), (20, -10)))
            records.append(Self.line((20, -10), (50, -10 - tilt * 30)))
            records.append(Self.line((50, -10), (65, -10 + tilt * 15)))
            for (x, string) in [(7.0, "1000"), (32.0, "1500"), (55.0, "750")] {
                records.append(Self.text(string, x, -10.5))
            }
            let (_, result) = try Self.rebuild(records)
            #expect(result.dimensions.count == 3, "tilt \(tilt)")
        }
    }

    @Test("a tolerance or scale that is not a positive number is none, not a crash")
    func invalidOptions() throws {
        let records = Self.chain(scale: 50, lengths: [20, 30, 15])
        for tolerance in [0.0, -1, .nan, .infinity, -.infinity] {
            let (_, result) = try Self.rebuild(records, .init(tolerance: tolerance))
            #expect(result.dimensions.count == 3, "tolerance \(tolerance)")
        }
        for scale in [0.0, -5, .nan, .infinity] {
            let (_, result) = try Self.rebuild(records, .init(scale: scale))
            #expect(result.dimensions.count == 3 && result.scales.first?.scale == 50)
        }
    }

    @Test("pieces at absurd coordinates, and very long lines, do not stop the rest")
    func absurdPieces() throws {
        var records = Self.chain(scale: 50, lengths: [20, 30, 15])
        // Beyond what is read, and within it but vast: none may crash the rebuild or slow it.
        records.append(Self.line((0, 0), (1e30, 1e30)))
        records.append(Self.line((-1e300, 5), (1e300, 5)))
        records.append(Self.point(1e30, -1e30))
        records.append(Self.circle(1e30, 0, 1e30))
        records.append(Self.text("500", 1e30, 0))
        records.append(Self.line((-1e12, -1e12), (1e12, 1e12)))
        records.append(Self.line((-1e11, 5), (1e11, 5)))
        records.append(Self.line((0, 0), (1e5, 1e5)))
        records.append(Self.point(1e11, -1e11))
        records.append(Self.circle(0, 0, 1e11))
        records.append(Self.text("500", 5, 5))
        // A text 4e9 times as tall as the others puts every window across a vast number of cells.
        records.append([
            (0, "TEXT"), (8, "0"), (10, "0"), (20, "0"), (30, "0"), (40, "1e10"), (1, "100"),
        ])
        let start = Date()
        let (_, result) = try Self.rebuild(records)
        let found = Set(result.dimensions.compactMap(\.textOverride))
        #expect(found.isSuperset(of: ["1000", "1500", "750"]))
        #expect(Date().timeIntervalSince(start) < 20)
    }

    @Test("hundreds of values on one layer are rebuilt in reasonable time")
    func manyValues() throws {
        let start = Date()
        let (_, result) = try Self.rebuild(
            Self.chain(scale: 50, lengths: [Double](repeating: 10, count: 300)))
        #expect(result.dimensions.count == 300)
        #expect(Date().timeIntervalSince(start) < 30)
    }

    @Test("a value written in an MTEXT is read as one in a TEXT")
    func mtextValue() throws {
        let records = Self.chain(scale: 50, lengths: [20, 30, 15]).map { record -> Record in
            guard record[0].1 == "TEXT" else { return record }
            // An MTEXT is anchored at its top left, so the point is the TEXT's plus its height.
            let x = record.first { $0.0 == 10 }!.1
            let y = Double(record.first { $0.0 == 20 }!.1)! + 2.5
            let layer = record.first { $0.0 == 8 }!.1
            let string = record.first { $0.0 == 1 }!.1
            return [
                (0, "MTEXT"), (8, layer), (10, x), (20, "\(y)"), (30, "0"), (40, "2.5"),
                (1, string),
            ]
        }
        let (_, result) = try Self.rebuild(records)
        #expect(result.dimensions.map(\.textOverride) == ["1000", "1500", "750"])
    }

    @Test("Jw_cad writes the angle of a vertical text as 5156.62, and the dimension is still found")
    func jwcadRotation() throws {
        var records = Self.chain(scale: 80, lengths: [20, 30], layer: "14")
        records += [
            Self.line((0, 100), (0, 120), layer: "14"), Self.line((0, 120), (0, 150), layer: "14"),
            Self.line((-2, 100), (8, 100), layer: "14"),
            Self.line((-2, 120), (8, 120), layer: "14"),
            Self.line((-2, 150), (8, 150), layer: "14"),
            Self.point(0, 100, layer: "14"), Self.point(0, 120, layer: "14"),
            Self.point(0, 150, layer: "14"),
            Self.text("1600", 1.0, 107.0, rotation: 5156.6203, layer: "14"),
            Self.text("2400", 1.0, 131.0, rotation: 5156.6203, layer: "14"),
        ]
        let (_, result) = try Self.rebuild(records)
        #expect(result.dimensions.count == 4 && result.warnings.isEmpty)
        #expect(result.scales == [.init(group: "14", scale: 80, supporting: 4, contradicting: 0)])
        let vertical = result.dimensions.filter { $0.rotation == 90 }
        #expect(vertical.map(\.textOverride) == ["1600", "2400"])
    }

    @Test("European grouping is read, and a number that cannot be is listed")
    func europeanNumbers() throws {
        typealias Value = DXF.DimensionRebuild.Value
        #expect(Value.read("1.234,5")?.readings == [.init(value: 1234.5, decimals: 1)])
        #expect(Value.read("12.345,67")?.readings == [.init(value: 12345.67, decimals: 2)])
        #expect(Value.read("1.234.567")?.readings == [.init(value: 1_234_567, decimals: 0)])
        #expect(
            Value.read("1.234")?.readings == [
                .init(value: 1.234, decimals: 3), .init(value: 1234, decimals: 0),
            ])
        #expect(Value.read("0.125")?.readings == [.init(value: 0.125, decimals: 3)])
        #expect(Value.read("1.2.3")?.unsupported == .unreadable)
        #expect(Value.read("1,23,456")?.unsupported == .unreadable)
        // A value must be ten units of its last place to be evidence for a scale.
        #expect(Value.read("9")?.readings.first?.isSubstantial == false)
        #expect(Value.read("10")?.readings.first?.isSubstantial == true)
        #expect(Value.read("0.9")?.readings.first?.isSubstantial == false)
        #expect(Value.read("1.0")?.readings.first?.isSubstantial == true)
        #expect(Value.read("2.5")?.readings.first?.isSubstantial == true)
        var records = Self.chain(scale: 50, lengths: [20, 30, 15])
        records.append(Self.text("1.2.3", 5, -9.5))
        let (_, result) = try Self.rebuild(records)
        let reasons = result.warnings.compactMap { warning -> DXF.DimensionRebuild.Reason? in
            guard case .valueNotExplained(_, _, let reason) = warning else { return nil }
            return reason
        }
        #expect(reasons == [.unreadable])
    }

    // MARK: the real drawings

    /// Drawings that have real dimensions gain none: set `DXF_REBUILD_CORPUS` to a folder of DXFs.
    @Test(
        "no dimension is rebuilt from a drawing that has real ones",
        .enabled(if: ProcessInfo.processInfo.environment["DXF_REBUILD_CORPUS"] != nil))
    func realDimensionsGainNone() throws {
        let folder = try #require(ProcessInfo.processInfo.environment["DXF_REBUILD_CORPUS"])
        let files = FileManager.default.enumerator(atPath: folder)?.compactMap { $0 as? String }
            .filter { $0.lowercased().hasSuffix(".dxf") }
        var checked = 0
        for file in files ?? [] {
            let url = URL(fileURLWithPath: folder).appendingPathComponent(file)
            guard let dwg = try? DXF.read(contentsOf: url), dwg.counts.dimension > 0 else {
                continue
            }
            checked += 1
            #expect(dwg.rebuildingDimensions().dimensions.isEmpty, "\(file)")
        }
        #expect(checked > 0, "no drawing with dimensions in \(folder)")
    }

    /// The 2120 acceptance: set `DXF_REBUILD_FILE` to a Jw_cad export or the drawing of a PDF.
    @Test(
        "the 2120 gives 29 dimensions at 1:80",
        .enabled(if: ProcessInfo.processInfo.environment["DXF_REBUILD_FILE"] != nil))
    func realDrawing() throws {
        let path = try #require(ProcessInfo.processInfo.environment["DXF_REBUILD_FILE"])
        let dwg = try DXF.read(contentsOf: URL(fileURLWithPath: path))
        let result = dwg.rebuildingDimensions()
        #expect(result.dimensions.count == 29)
        #expect(result.scales.map(\.scale) == [80])
        #expect(result.scales.first?.supporting == 29)
        #expect(result.warnings.isEmpty)
    }
}
