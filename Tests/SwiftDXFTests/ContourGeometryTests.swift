import Foundation
import Testing

@testable import SwiftDXF

/// Segment geometry, chaining, nesting and degenerate input, on drawings built in code.
@Suite("Contour geometry")
struct ContourGeometryTests {
    typealias S = ContourSupport

    // MARK: Segment

    @Test("an arc segment recovers its centre, radius, angles, length and bounds")
    func segmentGeometry() throws {
        // Counter-clockwise quarter circle about (1, 2), radius 3, from angle 0 to 90 degrees.
        let q = DXF.Contour.Segment(
            start: .init(4, 2), end: .init(1, 5), bulge: tan(Double.pi / 8))
        let c = try #require(q.center)
        #expect(near(c.x, 1) && near(c.y, 2))
        #expect(near(q.radius ?? 0, 3))
        #expect(near(q.startAngle ?? 9, 0))
        #expect(near(q.endAngle ?? 9, Double.pi / 2))
        #expect(near(q.length, 3 * Double.pi / 2))
        #expect(q.bounds == DXF.Box2(min: .init(1, 2), max: .init(4, 5)))

        // The same arc running clockwise the other way round the circle is its reverse.
        let back = q.reversed()
        #expect(near(back.bulge, -q.bulge))
        #expect(near(back.center?.x ?? 9, 1) && near(back.center?.y ?? 9, 2))
        #expect(back.reversed() == q)

        // A semicircle over the top reaches y = r although neither endpoint does.
        let half = DXF.Contour.Segment(start: .init(5, 0), end: .init(-5, 0), bulge: 1)
        #expect(near(half.bounds.max.y, 5) && near(half.bounds.min.y, 0))
        #expect(near(half.bounds.max.x, 5) && near(half.bounds.min.x, -5))
        let under = DXF.Contour.Segment(start: .init(5, 0), end: .init(-5, 0), bulge: -1)
        #expect(near(under.bounds.min.y, -5) && near(under.bounds.max.y, 0))
    }

    @Test("arcs over a half turn are split so every bulge stays within one")
    func bigArcsSplit() throws {
        // 270 degrees from (10, 0) round the top to (0, -10), closed by the chord.
        let b = tan(3 * Double.pi / 8)
        let r = S.drawing([S.polygon([(10, 0), (0, -10)], bulges: [b])]).contours()
        let shape = try #require(r.shapes.first)
        #expect(shape.outer.segments.count == 3)
        #expect(shape.outer.segments.allSatisfy { abs($0.bulge) <= 1 })
        #expect(near(shape.area, 50 * (3 * Double.pi / 2 + 1)))
        let box = shape.bounds
        #expect(near(box.min.x, -10) && near(box.max.x, 10) && near(box.max.y, 10))

        let a = S.drawing([
            S.arc(0, 0, 10, 30, 350),
            S.line(
                10 * cos(-10 * .pi / 180), 10 * sin(-10 * .pi / 180), 10 * cos(30 * .pi / 180),
                10 * sin(30 * .pi / 180)),
        ])
        .contours()
        #expect(a.shapes.count == 1)
        #expect(a.shapes[0].outer.segments.filter { $0.isArc }.count == 2)
    }

    // MARK: Chaining

    @Test("a closed polyline, its reverse and loose lines all give the same loop")
    func orientationNormalised() throws {
        let cw = S.drawing([S.polygon([(0, 0), (0, 10), (10, 10), (10, 0)])]).contours()
        let ccw = S.drawing([S.polygon([(0, 0), (10, 0), (10, 10), (0, 10)])]).contours()
        for r in [cw, ccw] {
            let shape = try #require(r.shapes.first)
            #expect(shape.outer.isCounterClockwise)
            #expect(shape.area == 100)
        }
    }

    @Test("lines that stop at a T junction do not stop the loop closing")
    func spur() throws {
        let r = S.drawing(S.box(0, 0, 10, 10) + [S.line(10, 10, 20, 20), S.line(20, 20, 20, 30)])
            .contours()
        #expect(r.shapes.count == 1)
        #expect(r.shapes[0].area == 100)
        #expect(r.openChains.count == 1)
        #expect(r.openChains[0].segments.count == 2)
        #expect(r.openChains[0].length > 10)
    }

    @Test("two squares touching at one corner stay two shapes")
    func touchingCorners() {
        let r = S.drawing(S.box(0, 0, 10, 10) + S.box(10, 10, 20, 20)).contours()
        #expect(r.shapes.count == 2)
        #expect(r.shapes.allSatisfy { $0.area == 100 && $0.outer.segments.count == 4 })
        #expect(r.openChains.isEmpty)
    }

    @Test("a figure of eight drawn as one polyline splits at the pinch")
    func pinch() throws {
        let pts: [(Double, Double)] = [
            (0, 0), (10, 0), (10, 10), (20, 10), (20, 20), (10, 20), (10, 10), (0, 10),
        ]
        let r = S.drawing([S.polygon(pts)]).contours()
        #expect(r.shapes.count == 2)
        #expect(near(r.area, 200))
    }

    @Test("a loop of many tiny arcs through the join tolerance still chains")
    func tinySegments() throws {
        // A square whose sides are cut into 0.004 mm pieces: each is shorter than the tolerance
        // only in the sense that neighbours merge, but the loop must survive.
        var lines: [DXF.Entity] = []
        let n = 2500
        for k in 0..<n {
            let x0 = 10 * Double(k) / Double(n)
            let x1 = 10 * Double(k + 1) / Double(n)
            lines.append(S.line(x0, 0, x1, 0))
        }
        lines.append(S.line(10, 0, 10, 10))
        lines.append(S.line(10, 10, 0, 10))
        lines.append(S.line(0, 10, 0, 0))
        let r = S.drawing(lines).contours()
        #expect(r.shapes.count == 1)
        #expect(abs(r.area - 100) < 0.2)
    }

    // MARK: Nesting

    @Test("concentric circles alternate hole and island")
    func concentric() throws {
        let r = S.drawing([S.circle(0, 0, 10), S.circle(0, 0, 6), S.circle(0, 0, 3)]).contours()
        #expect(r.shapes.count == 2)
        #expect(near(r.shapes[0].area, Double.pi * (100 - 36)))
        #expect(r.shapes[0].holes.count == 1)
        #expect(near(r.shapes[1].area, 9 * Double.pi))
        #expect(r.shapes[1].holes.isEmpty)
    }

    @Test("a hole touching the outer boundary at a vertex is still a hole")
    func touchingHole() throws {
        let diamond = S.polygon([(10, 0), (15, 5), (10, 10), (5, 5)])
        let r = S.drawing(S.box(0, 0, 20, 20) + [diamond]).contours()
        let shape = try #require(r.shapes.first)
        #expect(r.shapes.count == 1)
        #expect(shape.holes.count == 1)
        #expect(near(shape.area, 400 - 50))
    }

    @Test("a circle tangent to the walls is a hole, not a duplicate")
    func tangentCircle() throws {
        let r = S.drawing(S.box(0, 0, 10, 10) + [S.circle(5, 5, 5)]).contours()
        let shape = try #require(r.shapes.first)
        #expect(shape.holes.count == 1)
        #expect(near(shape.area, 100 - 25 * Double.pi))
        #expect(!r.warnings.contains { if case .coincidentLoops = $0 { true } else { false } })
    }

    @Test("a loop drawn twice with different pieces is dropped once and reported")
    func coincident() throws {
        let r = S.drawing([S.circle(0, 0, 10), S.arc(0, 0, 10, 0, 90), S.arc(0, 0, 10, 90, 360)])
            .contours()
        #expect(r.shapes.count == 1)
        #expect(r.warnings.contains(.coincidentLoops(count: 1)))
    }

    @Test("loops that cross are reported and not nested")
    func crossing() {
        let r = S.drawing(S.box(0, 0, 10, 10) + S.box(5, 5, 15, 15)).contours()
        #expect(r.shapes.count == 2)
        #expect(r.shapes.allSatisfy { $0.holes.isEmpty })
        #expect(r.warnings.contains { if case .crossingLoops = $0 { true } else { false } })
    }

    @Test("the outermost-only rule drops nested loops and says so")
    func outermost() {
        var o = DXF.Contour.Options()
        o.nesting = .outermostOnly
        let r = S.drawing(S.box(0, 0, 10, 10) + S.box(2, 2, 4, 4)).contours(o)
        #expect(r.shapes.count == 1)
        #expect(r.shapes[0].holes.isEmpty)
        #expect(r.shapes[0].area == 100)
        #expect(r.warnings.contains(.nestedLoopsDropped(count: 1)))
    }

    @Test("the ray test counts arcs correctly through tangents and vertices")
    func rayCrossings() {
        let r = S.drawing([S.circle(0, 0, 5)]).contours()
        let segs = r.shapes[0].outer.segments
        func inside(_ x: Double, _ y: Double) -> Bool {
            segs.filter { ContourNesting.crosses(.init(x, y), $0) }.count % 2 == 1
        }
        #expect(inside(0, 0))
        #expect(inside(-4.9, 0))
        #expect(!inside(-10, 0))
        #expect(!inside(10, 0))
        #expect(!inside(-1, 5))
        #expect(!inside(-1, -5))
        #expect(inside(0, 4.999))
        #expect(!inside(0, 5.001))
    }

    // MARK: Degenerate input

    @Test("degenerate and non-finite geometry is dropped, counted, and never crashes")
    func degenerate() throws {
        let nan = Double.nan
        let junk: [DXF.Entity] = [
            S.line(1, 1, 1, 1), S.line(nan, 0, 1, 1), S.line(0, 0, .infinity, 1),
            S.circle(0, 0, 0), S.circle(0, 0, -3), S.circle(nan, 0, 1),
            S.arc(0, 0, 5, nan, 10), S.arc(0, 0, 5, 20, 20), S.arc(0, 0, 0, 0, 90),
            .polyline(vertices: [], closed: true, layer: "0", color: 256),
            .polyline(vertices: [.init(.init(1, 1))], closed: true, layer: "0", color: 256),
            S.polygon([(0, 0), (nan, 1), (2, 2)]),
            .polyline(
                vertices: [.init(.init(0, 0), bulge: nan), .init(.init(4, 0))], closed: false,
                layer: "0", color: 256),
            .ellipse(
                center: .init(0, 0), majorAxis: .init(0, 0), ratio: 0.5, startParam: 0,
                endParam: 6, layer: "0", color: 256),
            .ellipse(
                center: .init(0, 0), majorAxis: .init(5, 0), ratio: 0, startParam: 0,
                endParam: 6, layer: "0", color: 256),
            .spline(DXF.Spline(degree: 3, controlPoints: [], layer: "0")),
            .spline(
                DXF.Spline(degree: 3, controlPoints: [.init(nan, 0), .init(1, 1)], layer: "0")),
            S.line(0, 0, 1e308, 1e308), S.circle(0, 0, 1e308),
        ]
        let r = S.drawing(junk + S.box(0, 0, 10, 10)).contours()
        #expect(r.shapes.count == 1)
        #expect(r.shapes[0].area == 100)
        let dropped = r.warnings.compactMap { w -> Int? in
            if case .degenerateGeometry(let n) = w { n } else { nil }
        }
        #expect((dropped.first ?? 0) >= 12)

        let empty = S.drawing(junk).contours()
        #expect(empty.shapes.isEmpty)
        #expect(S.drawing([]).contours().shapes.isEmpty)
        #expect(S.drawing([]).contours().bounds == nil)
    }

    @Test("zero or negative tolerances and a huge tolerance do not trap")
    func extremeOptions() {
        let dwg = S.drawing(S.box(0, 0, 10, 10) + [S.circle(50, 50, 3)])
        for join in [0.0, -1, 1e-300, 1e9] {
            _ = dwg.contours(.init(joinTolerance: join, fitTolerance: join))
        }
        let exact = dwg.contours(.init(joinTolerance: 0))
        #expect(exact.shapes.count == 2)
    }

    // MARK: Scale

    @Test("tens of thousands of shuffled segments chain and nest in near-linear time")
    func large() throws {
        // A 30,000-sided polygon, shuffled with half its sides reversed, holding 2,500 squares.
        var rng = S.Generator(state: 42)
        let sides = 30_000
        let radius = 1000.0
        let ring = (0..<sides).map { k -> (Double, Double) in
            let t = 2 * Double.pi * Double(k) / Double(sides)
            return (radius * cos(t), radius * sin(t))
        }
        var entities: [DXF.Entity] = []
        for k in 0..<sides {
            let a = ring[k]
            let b = ring[(k + 1) % sides]
            entities.append(k % 2 == 0 ? S.line(a.0, a.1, b.0, b.1) : S.line(b.0, b.1, a.0, a.1))
        }
        for i in 0..<50 {
            for j in 0..<50 {
                let x = -600 + 25 * Double(i)
                let y = -600 + 25 * Double(j)
                entities.append(contentsOf: S.box(x, y, x + 10, y + 10))
            }
        }
        entities.shuffle(using: &rng)
        let dwg = S.drawing(entities)
        #expect(entities.count == 40_000)

        let start = Date()
        let r = dwg.contours()
        let elapsed = Date().timeIntervalSince(start)
        print("large: \(entities.count) segments chained and nested in \(elapsed) s")

        let shape = try #require(r.shapes.first)
        #expect(r.shapes.count == 1)
        #expect(shape.holes.count == 2500)
        #expect(r.openChains.isEmpty)
        let polygon = 0.5 * Double(sides) * radius * radius * sin(2 * Double.pi / Double(sides))
        #expect(abs(shape.area - (polygon - 2500 * 100)) < 1e-4)
        // Quadratic chaining of 40,000 segments takes minutes in a debug build.
        #expect(elapsed < 15)
    }
}
