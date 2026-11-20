import Foundation
import Testing

@testable import SwiftDXF

/// The value of angular, three-point angular and ordinate dimensions (SwiftDXF#33).
///
/// `Fixtures/angular.dxf` is written by `tools/angular_fixtures.py`, which prints what `ezdxf`
/// reads from it: `Dimension.get_measurement()` is the angle counter-clockwise from the first line
/// to the second, whichever side the arc location is on, and AutoCAD displays the angle on the
/// arc's side. Where those differ the tests expect the arc's side, which is what AutoCAD's own
/// anonymous blocks show (`AutoCAD`, below).
@Suite("Angular and ordinate dimensions")
struct AngularDimensionTests {
    typealias Point = DXF.Point

    static func fixture() throws -> [DXF.Dimension] {
        let url = try #require(
            Bundle.module.url(
                forResource: "angular", withExtension: "dxf", subdirectory: "Fixtures"))
        return DimensionTests.dimensions(try DXF.read(contentsOf: url))
    }

    static func close(_ a: Double?, _ b: Double, tolerance: Double = 1e-9) -> Bool {
        guard let a else { return false }
        return abs(a - b) <= tolerance
    }

    /// A three-point angular dimension.
    static func threePoint(
        vertex: (Double, Double), _ a: (Double, Double), _ b: (Double, Double),
        arc: (Double, Double)
    ) -> DXF.Dimension {
        DXF.Dimension(
            kind: .angular3Point, measurement: nil, textOverride: nil, textPosition: Point(0, 0),
            defPoint: Point(arc.0, arc.1), defPoint2: Point(a.0, a.1), defPoint3: Point(b.0, b.1),
            defPoint4: Point(vertex.0, vertex.1), layer: "0", color: 7)
    }

    /// A two-line angular dimension: the first line `a` to `b`, the second `c` to `d`.
    static func twoLine(
        _ a: (Double, Double), _ b: (Double, Double), _ c: (Double, Double), _ d: (Double, Double),
        arc: (Double, Double)
    ) -> DXF.Dimension {
        DXF.Dimension(
            kind: .angular, measurement: nil, textOverride: nil, textPosition: Point(0, 0),
            defPoint: Point(d.0, d.1), defPoint2: Point(a.0, a.1), defPoint3: Point(b.0, b.1),
            defPoint4: Point(c.0, c.1), defPoint5: Point(arc.0, arc.1), layer: "0", color: 7)
    }

    // MARK: against ezdxf

    /// What `tools/angular_fixtures.py` prints: ezdxf's `get_measurement()`, and the angle on the
    /// side of the arc location.
    static let angles: [(name: String, ezdxf: Double, arcSide: Double)] = [
        ("3p ccw side", 90, 90),
        ("3p other side, over 180", 90, 270),
        ("3p rays swapped, arc between", 270, 90),
        ("3p rays swapped, arc outside", 270, 270),
        ("3p obtuse, vertex off the origin", 126.86989764584402, 126.86989764584402),
        ("3p obtuse, over 180", 126.86989764584402, 233.13010235415598),
        ("3p straight, arc above", 180, 180),
        ("2l first angle", 53.13010235415598, 53.13010235415598),
        ("2l second angle", 53.13010235415598, 126.86989764584402),
        ("2l third angle", 53.13010235415598, 53.13010235415598),
        ("2l fourth angle", 53.13010235415598, 126.86989764584402),
        ("2l lines reversed", 53.13010235415595, 53.13010235415598),
        ("2l crossing off the origin", 63.43494882292201, 63.43494882292201),
    ]

    @Test("an angular dimension is the angle on the side of its arc location, in degrees")
    func angularMatchesEzdxf() throws {
        let dims = try Self.fixture()
        #expect(dims.count == Self.angles.count + 6)
        for (dim, want) in zip(dims, Self.angles) {
            let got = try #require(dim.computedMeasurement, "\(want.name)")
            #expect(Self.close(got, want.arcSide), "\(want.name): \(got) != \(want.arcSide)")
        }
        // ezdxf agrees where the arc is on the side it measures, and not in these five, where the
        // arc is on the other side of the lines or rays: the angle there is what AutoCAD draws.
        let differing = zip(dims, Self.angles).filter {
            !Self.close($0.computedMeasurement, $1.ezdxf)
        }
        #expect(
            differing.map(\.1.name) == [
                "3p other side, over 180", "3p rays swapped, arc between", "3p obtuse, over 180",
                "2l second angle", "2l fourth angle",
            ])
        #expect(dims.prefix(7).allSatisfy { $0.kind == .angular3Point })
        #expect(dims[7..<13].allSatisfy { $0.kind == .angular })
    }

    @Test("an angular dimension is not scaled by the linear scale, which a length is")
    func angleIsNotScaled() throws {
        let dwg = try DXF.read(
            contentsOf: try #require(
                Bundle.module.url(
                    forResource: "angular", withExtension: "dxf", subdirectory: "Fixtures")))
        let dims = DimensionTests.dimensions(dwg)
        // ezdxf's default style has a linear scale of 100, and writes `90°` and `1050`.
        #expect(dwg.styleVariables(of: dims[0]).effectiveScale == 100)
        #expect(Self.close(dwg.displayedMeasurement(of: dims[0]), 90))
        #expect(Self.close(dwg.displayedMeasurement(of: dims[7]), 53.13010235415598))
        #expect(Self.close(dwg.displayedMeasurement(of: dims[13]), 1050))
    }

    @Test("an ordinate dimension is the distance along its axis from the origin to the feature")
    func ordinateMatchesEzdxf() throws {
        let dims = try Self.fixture().suffix(6)
        // What ezdxf draws (1050 and 400 under a scale of 100): |12.5 - 2| and |7 - 3|, then
        // |-4 - 2| and |-1 - 3|, then the same in a coordinate system turned 30 degrees, where
        // ezdxf puts the feature at 10.5 along its x axis and 4 along its y axis.
        let reference: [(isX: Bool, value: Double, rotation: Double)] = [
            (true, 10.5, 0), (false, 4, 0), (true, 6, 0), (false, 4, 0), (true, 10.5, 30),
            (false, 4, 30),
        ]
        #expect(dims.count == reference.count)
        for (dim, want) in zip(dims, reference) {
            #expect(dim.kind == .ordinate && dim.isXOrdinate == want.isX, "\(want)")
            #expect(Self.close(dim.rotation ?? 0, want.rotation), "\(want)")
            #expect(Self.close(dim.computedMeasurement, want.value, tolerance: 1e-6), "\(want)")
        }
    }

    // MARK: against AutoCAD

    /// A three-point angular dimension that AutoCAD wrote, and the angle it drew.
    struct Drawn {
        var vertex: (Double, Double)
        var first: (Double, Double)
        var second: (Double, Double)
        var arc: (Double, Double)
        var degrees: Double
    }

    /// Three-point angular dimensions from two DWG files that AutoCAD wrote (read through
    /// SwiftDWG), with the text of the anonymous block that AutoCAD drew for each.
    ///
    /// The two last have the arc on the side that is not counter-clockwise from the first ray to
    /// the second: that angle is 235 and 230, and AutoCAD drew 125 and 130.
    static let autocad: [Drawn] = [
        Drawn(
            vertex: (-49.5, -39.865), first: (-47.05, -37.415), second: (-50.0, -39.865),
            arc: (-52.6353, -32.2956), degrees: 135),
        Drawn(
            vertex: (-51.5, -45.715), first: (-55.9521, -45.715), second: (-51.0, -46.215),
            arc: (-53.7083, -51.0464), degrees: 135),
        Drawn(
            vertex: (124.5, 99.5), first: (125.0, 100.0), second: (120.0, 99.5),
            arc: (122.6847, 103.8826), degrees: 135),
        Drawn(
            vertex: (127.6645, 98.2), first: (126.25, 95.75), second: (130.0, 98.2),
            arc: (129.661, 94.742), degrees: 120),
        Drawn(
            vertex: (64.4041, -45.715), first: (60.0, -45.715), second: (65.0, -46.215),
            arc: (61.9677, -52.4091), degrees: 140),
        Drawn(
            vertex: (243.9655, 98.2), first: (246.0, 98.2), second: (242.25, 95.75),
            arc: (247.1713, 92.0418), degrees: 125),
        Drawn(
            vertex: (240.5805, 99.5), first: (236.0, 99.5), second: (241.0, 100.0),
            arc: (237.4272, 106.2621), degrees: 130),
    ]

    @Test("a three-point angular dimension is the angle AutoCAD drew")
    func matchesAutoCAD() {
        // The points have four decimals, so the angle is within a few thousandths of a degree.
        for drawn in Self.autocad {
            let dimension = Self.threePoint(
                vertex: drawn.vertex, drawn.first, drawn.second, arc: drawn.arc)
            #expect(
                Self.close(dimension.computedMeasurement, drawn.degrees, tolerance: 0.01),
                "\(String(describing: dimension.computedMeasurement)) != \(drawn.degrees)")
        }
    }

    @Test("a two-line angular dimension is the gap between the lines that holds the arc")
    func twoLineAutoCAD() {
        // AutoCAD's two-line dimension of two lines that cross at (249.25, 122), with the arc
        // location at (276.8533, 127.4573), drew an arc from 329.5 to 30.5 degrees inside the gap
        // from -38.66 to 38.66 degrees: its text was typed over as `60°`, and the gap is 77.32.
        let dimension = Self.twoLine(
            (255.5, 124), (258, 126), (255.5, 120), (258, 118), arc: (276.8533, 127.4573))
        #expect(Self.close(dimension.computedMeasurement, 77.3197, tolerance: 1e-3))
    }

    // MARK: the choice of side

    @Test("a three-point angle is the same from either side of the vertex, and over 180")
    func threePointOrientations() {
        func angle(_ a: (Double, Double), _ b: (Double, Double), _ arc: (Double, Double))
            -> Double?
        {
            Self.threePoint(vertex: (0, 0), a, b, arc: arc).computedMeasurement
        }
        // The rays at 0 and 90 degrees: the quarter turn, and the three quarters.
        #expect(Self.close(angle((5, 0), (0, 5), (3, 3)), 90))
        #expect(Self.close(angle((5, 0), (0, 5), (-3, -3)), 270))
        #expect(Self.close(angle((5, 0), (0, 5), (-3, 3)), 270))
        // Naming the rays the other way round changes nothing: the arc says which.
        #expect(Self.close(angle((0, 5), (5, 0), (3, 3)), 90))
        #expect(Self.close(angle((0, 5), (5, 0), (-3, -3)), 270))
        // A ray past the 180 turn: the rays at 0 and 200 degrees.
        let far = (5 * cos(200 * Double.pi / 180), 5 * sin(200 * Double.pi / 180))
        #expect(Self.close(angle((5, 0), far, (1, -3)), 160))
        #expect(Self.close(angle((5, 0), far, (1, 3)), 200))
        // How far the arc is from the vertex does not matter.
        #expect(Self.close(angle((5, 0), (0, 5), (0.001, 0.001)), 90))
        #expect(Self.close(angle((5, 0), (0, 5), (1e6, 1e6)), 90))
    }

    @Test("a three-point angle follows the vertex through any move, turn, mirror or scale")
    func threePointInvariance() {
        let base = Self.threePoint(vertex: (0, 0), (5, 0), (-2, 4), arc: (1, -4))
        let want = base.computedMeasurement ?? .nan
        #expect(Self.close(want, 360 - 116.56505117707799))
        let (c, s) = (cos(0.7), sin(0.7))
        let p = [(0.0, 0.0), (5, 0), (-2, 4), (1, -4)].map {
            (c * $0.0 - s * $0.1 + 30, s * $0.0 + c * $0.1 - 12)
        }
        #expect(
            Self.close(
                Self.threePoint(vertex: p[0], p[1], p[2], arc: p[3]).computedMeasurement, want))
        // A mirror turns the counter-clockwise order round, and the angle on the arc's side stays.
        let mirrored = [(0.0, 0.0), (-5, 0), (2, 4), (-1, -4)]
        #expect(
            Self.close(
                Self.threePoint(
                    vertex: mirrored[0], mirrored[1], mirrored[2], arc: mirrored[3]
                )
                .computedMeasurement, want))
        let scaled = [(0.0, 0.0), (50, 0), (-20, 40), (10, -40)]
        #expect(
            Self.close(
                Self.threePoint(vertex: scaled[0], scaled[1], scaled[2], arc: scaled[3])
                    .computedMeasurement, want))
    }

    @Test("two lines make four angles, and the arc location picks the one it is in")
    func twoLineSectors() {
        // A horizontal line, and one at 60 degrees, that cross at (1, 1) beyond both segments. Round
        // that point the four gaps between the rays, from 0 degrees, are 60, 120, 60 and 120.
        let root3 = 3.0.squareRoot()
        func angle(at degrees: Double) -> Double? {
            let r = degrees * Double.pi / 180
            return Self.twoLine(
                (5, 1), (9, 1), (3, 1 + 2 * root3), (4, 1 + 3 * root3),
                arc: (1 + 6 * cos(r), 1 + 6 * sin(r))
            ).computedMeasurement
        }
        for (degrees, want) in [
            (30.0, 60.0), (90, 120), (150, 120), (210, 60), (270, 120), (330, 120),
        ] {
            #expect(Self.close(angle(at: degrees), want), "\(degrees)")
        }
        // Never more than 180, and never nothing, wherever the arc is.
        for degrees in stride(from: 5.0, to: 360, by: 17) {
            #expect(angle(at: degrees).map { $0 > 0 && $0 < 180 } == true, "\(degrees)")
        }
    }

    @Test("a missing definition point, or none that gives an angle, is no value")
    func noValue() {
        var three = Self.threePoint(vertex: (0, 0), (5, 0), (0, 5), arc: (3, 3))
        #expect(Self.close(three.computedMeasurement, 90))
        for missing in 0..<3 {
            var broken = three
            switch missing {
            case 0: broken.defPoint2 = nil
            case 1: broken.defPoint3 = nil
            default: broken.defPoint4 = nil
            }
            #expect(broken.computedMeasurement == nil, "three-point without point \(missing)")
        }
        // A ray of no length, the two rays one, and the arc location on the vertex.
        three.defPoint2 = Point(0, 0)
        #expect(three.computedMeasurement == nil)
        #expect(
            Self.threePoint(vertex: (0, 0), (5, 0), (9, 0), arc: (3, 3)).computedMeasurement == nil)
        #expect(
            Self.threePoint(vertex: (0, 0), (5, 0), (0, 5), arc: (0, 0)).computedMeasurement == nil)
        #expect(
            Self.threePoint(vertex: (0, 0), (5, 0), (0, 5), arc: (.nan, 3)).computedMeasurement
                == nil)
        #expect(
            Self.threePoint(vertex: (0, 0), (.infinity, 0), (0, 5), arc: (3, 3))
                .computedMeasurement == nil)

        var two = Self.twoLine((5, 1), (9, 1), (3, 3), (4, 5), arc: (6, 3))
        #expect(two.computedMeasurement != nil)
        for missing in 0..<4 {
            var broken = two
            switch missing {
            case 0: broken.defPoint2 = nil
            case 1: broken.defPoint3 = nil
            case 2: broken.defPoint4 = nil
            default: broken.defPoint5 = nil
            }
            #expect(broken.computedMeasurement == nil, "two-line without point \(missing)")
        }
        // Parallel lines never meet, and a line of no length has no direction.
        two = Self.twoLine((0, 0), (5, 0), (0, 2), (5, 2), arc: (2, 1))
        #expect(two.computedMeasurement == nil)
        two = Self.twoLine((0, 0), (0, 0), (0, 2), (5, 2), arc: (2, 1))
        #expect(two.computedMeasurement == nil)
        // The arc location on the crossing has no side.
        two = Self.twoLine((5, 0), (9, 0), (0, 4), (0, 8), arc: (0, 0))
        #expect(two.computedMeasurement == nil)

        var ordinate = DXF.Dimension(
            kind: .ordinate, measurement: nil, textOverride: nil, textPosition: Point(0, 0),
            defPoint: Point(1, 2), defPoint2: Point(4, 8), layer: "0", color: 7)
        #expect(Self.close(ordinate.computedMeasurement, 6))
        ordinate.isXOrdinate = true
        #expect(Self.close(ordinate.computedMeasurement, 3))
        ordinate.defPoint2 = nil
        #expect(ordinate.computedMeasurement == nil)
    }

    // MARK: reading

    @Test("bit 64 of the type says an ordinate dimension is of the X type, and only then")
    func ordinateType() throws {
        func dimension(_ type: Int) throws -> DXF.Dimension {
            let tags: [(Int, String)] = [
                (70, "\(type)"), (10, "1"), (20, "2"), (30, "0"), (13, "4"), (23, "8"),
                (33, "0"),
            ]
            return DimensionTests.dimensions(try DimensionTests.inline(tags))[0]
        }
        let y = try dimension(6)
        #expect(y.kind == .ordinate && !y.isXOrdinate && Self.close(y.computedMeasurement, 6))
        let x = try dimension(6 + 64)
        #expect(x.kind == .ordinate && x.isXOrdinate && Self.close(x.computedMeasurement, 3))
        // The extra flags (32, a block of its own, and 128, the text moved) do not matter.
        #expect(try dimension(6 + 32 + 64 + 128).isXOrdinate)
        #expect(try !dimension(6 + 32 + 128).isXOrdinate)
        // The bit means nothing for the other kinds.
        #expect(try !dimension(0 + 64).isXOrdinate)
        #expect(try !dimension(5 + 64).isXOrdinate)
    }

    // MARK: the text

    @Test("a typed angle is not a length")
    func typedAngles() {
        let sign = "\u{00B0}"
        let angle = DXF.DimensionText("45\\U+00B0")
        #expect(angle.parts == [.angle(45, text: "45" + sign)])
        #expect(angle.typedAngles == [45] && angle.typedNumbers.isEmpty)
        #expect(angle.plain == "45" + sign && angle.words.isEmpty)
        for raw in ["45%%d", "45" + sign, "45\\U+00B0"] {
            let text = DXF.DimensionText(raw)
            #expect(text.typedAngles == [45] && text.typedNumbers.isEmpty, "\(raw)")
        }
        // A degree sign that does not follow a number is a word, and a number next to a word is
        // still a number.
        #expect(DXF.DimensionText(sign).words == [sign])
        #expect(DXF.DimensionText("45 " + sign).typedNumbers == [45])
        #expect(DXF.DimensionText("45 " + sign).typedAngles.isEmpty)
        #expect(DXF.DimensionText("5 mm").typedAngles.isEmpty)
        // Both can be in one text, and the measurement is still shown.
        let both = DXF.DimensionText("<> 12 mm 30\\U+00B0 -15%%d")
        #expect(both.showsMeasurement && both.typedNumbers == [12])
        #expect(both.typedAngles == [30, -15])
        #expect(both.plain == "<> 12 mm 30" + sign + " -15" + sign)
        let tolerance = DXF.DimensionText("<>\\U+00B1 0.5\\U+00B0")
        #expect(tolerance.typedAngles == [0.5] && tolerance.words == ["\u{00B1}"])
        // The numbers follow the convention, whichever way the sign is written.
        let thousands = DXF.DimensionText("1,234%%d", numbers: .commaSeparatesThousands)
        #expect(thousands.typedAngles == [1234])
    }

    // MARK: in a block

    /// An angular and a linear dimension, each with a stored value, in a block inserted with
    /// `scale`.
    static func inserted(scale: (Double, Double), rotation: Double = 0) throws
        -> (angular: DXF.Dimension, linear: DXF.Dimension)
    {
        let angular: DXFBuilder.Record = [
            (0, "DIMENSION"), (8, "0"), (70, "5"), (42, "1.5707963267948966"), (10, "7"),
            (20, "7"), (30, "0"), (11, "7"), (21, "7"), (31, "0"), (13, "10"), (23, "0"),
            (33, "0"), (14, "0"), (24, "10"), (34, "0"), (15, "0"), (25, "0"), (35, "0"),
        ]
        let linear: DXFBuilder.Record = [
            (0, "DIMENSION"), (8, "0"), (70, "0"), (42, "10"), (10, "5"), (20, "2"), (30, "0"),
            (11, "5"), (21, "2"), (31, "0"), (13, "0"), (23, "0"), (33, "0"), (14, "10"),
            (24, "0"), (34, "0"),
        ]
        var builder = DXFBuilder()
        builder.blocks = [("B", (0, 0), [angular, linear])]
        builder.entities = [DXFBuilder.insert("B", at: (3, 4), scale: scale, rotation: rotation)]
        let dwg = try DXF.read(text: builder.text(), options: .init(expandBlocks: true))
        let dims = DimensionTests.dimensions(dwg)
        return (try #require(dims.first), try #require(dims.last))
    }

    @Test("an ordinate dimension in a block measures along its own axes, whatever the insertion")
    func ordinateInABlock() throws {
        for type in [6 + 64, 6] {
            let ordinate: DXFBuilder.Record = [
                (0, "DIMENSION"), (8, "0"), (70, "\(type)"), (42, "10"), (10, "0"), (20, "0"),
                (30, "0"), (11, "5"), (21, "5"), (31, "0"), (13, "10"), (23, "3"), (33, "0"),
                (14, "10"), (24, "9"), (34, "0"),
            ]
            let insertions = [((1.0, 1.0), 0.0), ((1, 1), 30), ((1, 1), 90), ((-1, 1), 200)]
            for (scale, rotation) in insertions {
                var builder = DXFBuilder()
                builder.blocks = [("B", (0, 0), [ordinate])]
                builder.entities = [
                    DXFBuilder.insert("B", at: (3, 4), scale: scale, rotation: rotation)
                ]
                let dwg = try DXF.read(text: builder.text(), options: .init(expandBlocks: true))
                let dimension = try #require(DimensionTests.dimensions(dwg).first)
                // The feature is 10 along x and 3 along y from the origin, as it was drawn.
                let want = type == 6 + 64 ? 10.0 : 3.0
                #expect(
                    Self.close(dimension.computedMeasurement, want, tolerance: 1e-9),
                    "\(type) \(scale) \(rotation)")
            }
        }
    }

    @Test("an ordinate dimension on a -z plane turns its axes round with the plane")
    func ordinateOnADownPlane() throws {
        // The coordinate system is turned 20 degrees (group 51 is -20) in the plane's own system,
        // whose x axis is the world's -x: so in the world its x axis points at 160 degrees. The
        // feature is 10 along that axis and 3 along the one 90 degrees from it, and the definition
        // points are world coordinates.
        func world(_ degrees: Double, _ length: Double) -> (Double, Double) {
            (length * cos(degrees * .pi / 180), length * sin(degrees * .pi / 180))
        }
        let (along, across) = (world(160, 10), world(250, 3))
        let feature = (along.0 + across.0, along.1 + across.1)
        for (type, want) in [(6 + 64, 10.0), (6, 3.0)] {
            let tags: [(Int, String)] = [
                (70, "\(type)"), (51, "-20"), (10, "0"), (20, "0"), (30, "0"), (13, "\(feature.0)"),
                (23, "\(feature.1)"), (33, "0"), (210, "0"), (220, "0"), (230, "-1"),
            ]
            let dimension = DimensionTests.dimensions(try DimensionTests.inline(tags))[0]
            #expect(Self.close(dimension.rotation, 160, tolerance: 1e-9))
            #expect(Self.close(dimension.computedMeasurement, want, tolerance: 1e-9), "\(type)")
        }
    }

    @Test(
        "a block inserted with a uniform scale keeps the angle of a dimension and scales a length")
    func dimensionsInABlock() throws {
        for scale in [(2.0, 2.0), (-1, 1), (1, -1), (-3, -3)] {
            let (angular, linear) = try Self.inserted(scale: scale, rotation: 30)
            let factor = abs(scale.0)
            // The angle and the stored value that is one: neither is scaled.
            #expect(Self.close(angular.computedMeasurement, 90), "\(scale)")
            #expect(Self.close(angular.measurement, 1.5707963267948966), "\(scale)")
            #expect(Self.close(linear.measurement, 10 * factor), "\(scale)")
        }
        // A scale that is not uniform turns the angle, so what the file stored is out of date.
        let (angular, linear) = try Self.inserted(scale: (2, 1))
        #expect(angular.measurement == nil && linear.measurement == nil)
    }
}
