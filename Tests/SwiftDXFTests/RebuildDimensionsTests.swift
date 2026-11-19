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

    @Test("a line that ends on a circle but does not pass through its centre is no radius")
    func chordIsNoRadius() throws {
        let records: [Record] = [
            Self.circle(0, 0, 10), Self.line((9.539392, 3), (20, 3)), Self.text("R20", 14, 3.5),
        ]
        let (_, result) = try Self.rebuild(records, .init(scale: 2))
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
        // The same with drawing around them: an outline, a note and a title, no dimension line.
        var builder = DXFBuilder()
        builder.entities = [
            [
                (0, "DIMENSION"), (8, "0"), (1, "<>"), (70, "0"), (10, "0"), (20, "5"), (30, "0"),
                (11, "5"), (21, "5"), (31, "0"), (13, "0"), (23, "0"), (33, "0"), (14, "10"),
                (24, "0"), (34, "0"),
            ],
            Self.line((0, 0), (10, 0)), Self.line((10, 0), (10, 8)), Self.line((10, 8), (0, 8)),
            Self.line((0, 8), (0, 0)), Self.text("12 OFF", 30, 4), Self.text("DRAWING 2120", 2, 20),
        ]
        let around = try DXF.read(text: builder.text()).rebuildingDimensions()
        #expect(around.dimensions.isEmpty && around.warnings.isEmpty)
    }

    @Test("rebuilding a drawing that already has the rebuilt dimensions adds none")
    func rebuildingTwice() throws {
        let (dwg, first) = try Self.rebuild(Self.chain(scale: 50, lengths: [20, 30, 15]))
        let applied = first.applied(to: dwg)
        let second = applied.rebuildingDimensions()
        #expect(first.dimensions.count == 3)
        #expect(second.dimensions.isEmpty && second.warnings.isEmpty)
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
