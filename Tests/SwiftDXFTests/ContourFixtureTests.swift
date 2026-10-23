import Foundation
import Testing

@testable import SwiftDXF

/// Contour extraction on DXF files written by ezdxf (`tools/contour_fixtures.py`).
///
/// Expected areas and bounds are analytic, stated in the generator next to each case.
@Suite("Contours from ezdxf files")
struct ContourFixtureTests {
    typealias S = ContourSupport

    @Test("a square of four lines is one CCW loop of area 100 with exact bounds")
    func square() throws {
        let r = try S.fixture("square").contours()
        #expect(r.warnings.isEmpty)
        #expect(r.openChains.isEmpty)
        let shape = try #require(r.shapes.first)
        #expect(r.shapes.count == 1)
        #expect(shape.holes.isEmpty)
        #expect(shape.outer.isCounterClockwise)
        #expect(shape.outer.segments.count == 4)
        #expect(shape.area == 100)
        #expect(shape.bounds == DXF.Box2(min: .init(0, 0), max: .init(10, 10)))
        for (a, b) in zip(shape.outer.segments, shape.outer.segments.dropFirst()) {
            #expect(a.end == b.start)
        }
        #expect(shape.outer.segments.last?.end == shape.outer.segments.first?.start)
    }

    @Test("a rounded rectangle from LWPOLYLINE bulges keeps exact arcs")
    func roundedRectangle() throws {
        let shape = try #require(try S.fixture("rounded_rect").contours().shapes.first)
        let arcs = shape.outer.segments.filter { $0.isArc }
        #expect(shape.outer.segments.count == 8)
        #expect(arcs.count == 4)
        for a in arcs {
            #expect(near(a.bulge, tan(Double.pi / 8)))
            #expect(near(a.radius ?? 0, 5))
        }
        #expect(near(shape.area, 800 - (4 - Double.pi) * 25))
        let b = shape.bounds
        #expect(near(b.min.x, 0) && near(b.min.y, 0) && near(b.max.x, 40) && near(b.max.y, 20))
    }

    @Test("a plate with three round holes")
    func plateWithHoles() throws {
        let r = try S.fixture("plate_holes").contours()
        let shape = try #require(r.shapes.first)
        #expect(r.shapes.count == 1)
        #expect(shape.holes.count == 3)
        #expect(shape.outer.isCounterClockwise)
        #expect(shape.holes.allSatisfy { !$0.isCounterClockwise })
        #expect(shape.holes.allSatisfy { $0.segments.count == 2 })
        #expect(near(shape.area, 6000 - 75 * Double.pi))
        #expect(near(r.area, shape.area))
        let centres = shape.holes.compactMap { $0.segments.first?.center?.x }.sorted()
        #expect(zip(centres, [20.0, 50, 80]).allSatisfy { near($0, $1) })
    }

    @Test("a hole inside an island inside a hole nests as two shapes")
    func nestedIslands() throws {
        let r = try S.fixture("nested").contours()
        #expect(r.shapes.count == 2)
        #expect(near(r.shapes[0].area, 3600))
        #expect(near(r.shapes[1].area, 2000))
        #expect(r.shapes.allSatisfy { $0.holes.count == 1 })
        #expect(r.shapes[1].bounds == DXF.Box2(min: .init(20, 20), max: .init(80, 80)))
        #expect(near(r.area, 5600))
    }

    @Test("arcs and lines given out of order and reversed chain into one slot")
    func slotChainedOutOfOrder() throws {
        let r = try S.fixture("slot_shuffled").contours()
        let shape = try #require(r.shapes.first)
        #expect(r.shapes.count == 1)
        #expect(shape.outer.segments.count == 4)
        #expect(near(shape.area, 100 * Double.pi + 400))
        let b = shape.bounds
        #expect(near(b.min.x, -10) && near(b.min.y, -10) && near(b.max.x, 30) && near(b.max.y, 10))
        #expect(shape.outer.isCounterClockwise)
    }

    @Test("a gap inside the join tolerance closes; a wider one stays open and is reported")
    func gaps() throws {
        let within = try S.fixture("gap_within").contours()
        #expect(within.shapes.count == 1)
        #expect(within.openChains.isEmpty)
        #expect(abs(within.area - 100) < 0.1)

        let beyond = try S.fixture("gap_beyond").contours()
        #expect(beyond.shapes.isEmpty)
        let chain = try #require(beyond.openChains.first)
        #expect(beyond.openChains.count == 1)
        #expect(chain.segments.count == 4)
        #expect(
            beyond.warnings.contains {
                if case .openChains(1, _) = $0 { return true } else { return false }
            })

        var wide = DXF.Contour.Options()
        wide.joinTolerance = 1
        let joined = try S.fixture("gap_beyond").contours(wide)
        #expect(joined.shapes.count == 1)
        #expect(joined.openChains.isEmpty)
    }

    @Test("duplicated entities collapse; the circle is a hole of the square")
    func duplicates() throws {
        let r = try S.fixture("duplicates").contours()
        let shape = try #require(r.shapes.first)
        #expect(r.shapes.count == 1)
        #expect(shape.holes.count == 1)
        #expect(shape.outer.segments.count == 4)
        #expect(near(shape.area, 100 - 9 * Double.pi))
        #expect(r.warnings.contains(.degenerateGeometry(count: 6)))
    }

    @Test("an ellipse is fitted within the tolerance and the deviation is reported")
    func ellipse() throws {
        for tolerance in [0.01, 0.001] {
            var o = DXF.Contour.Options()
            o.fitTolerance = tolerance
            let r = try S.fixture("ellipse").contours(o)
            let shape = try #require(r.shapes.first)
            #expect(r.shapes.count == 1)
            #expect(r.maxFitDeviation <= tolerance)
            #expect(
                r.warnings.contains { if case .fittedCurves(1, _) = $0 { true } else { false } })

            let t = Double.pi / 6
            let exact = (0...4000).map { k -> DXF.Point2 in
                let u = 2 * Double.pi * Double(k) / 4000
                let x = 30 * cos(u)
                let y = 15 * sin(u)
                return .init(100 + x * cos(t) - y * sin(t), 50 + x * sin(t) + y * cos(t))
            }
            let toCurve = S.deviation(of: shape.outer.segments, from: exact)
            let toLoop = S.deviation(of: exact, from: shape.outer.segments)
            let measured = max(toCurve, toLoop)
            #expect(measured <= r.maxFitDeviation)
            #expect(measured <= tolerance)
            #expect(abs(shape.area - 450 * Double.pi) < tolerance * shape.outer.length)
            if tolerance == 0.01 {
                print(
                    "ellipse: tol \(tolerance) measured \(measured) reported \(r.maxFitDeviation) segments \(shape.outer.segments.count)"
                )
            }
        }
    }

    @Test("an ellipse with ratio 1 is two exact arcs, not a fit")
    func roundEllipse() throws {
        let r = try S.fixture("ellipse_round").contours()
        let shape = try #require(r.shapes.first)
        #expect(shape.outer.segments.count == 2)
        #expect(near(shape.area, 144 * Double.pi))
        #expect(r.maxFitDeviation == 0)
        #expect(r.warnings.isEmpty)
    }

    @Test("a spline closed by a line is fitted within the tolerance")
    func spline() throws {
        let dwg = try S.fixture("spline")
        let r = dwg.contours()
        let shape = try #require(r.shapes.first)
        #expect(r.shapes.count == 1)
        #expect(r.maxFitDeviation <= 0.01)
        let splines = dwg.entities.compactMap { e -> DXF.Spline? in
            if case .spline(let sp) = e { return sp } else { return nil }
        }
        let sp = try #require(splines.first)
        let domain = try #require(sp.parameterDomain)
        let exact = (0...4000).compactMap { k -> DXF.Point2? in
            sp.point(
                at: domain.lowerBound + (domain.upperBound - domain.lowerBound) * Double(k) / 4000
            )
            .map { .init($0.x, $0.y) }
        }
        let curveSegments = shape.outer.segments.filter { $0.start.y > 0.5 || $0.end.y > 0.5 }
        let measured = max(
            S.deviation(of: curveSegments, from: exact),
            S.deviation(of: exact, from: shape.outer.segments))
        #expect(measured <= r.maxFitDeviation)
        #expect(measured <= 0.01)
        print(
            "spline: measured \(measured) reported \(r.maxFitDeviation) segments \(shape.outer.segments.count)"
        )
    }

    @Test("units: inches convert to millimetres, overrides win, unitless files warn")
    func units() throws {
        let inch = try S.fixture("inch").contours()
        #expect(inch.unit == .inch)
        #expect(inch.unitScale == 25.4)
        #expect(near(inch.area, 50.8 * 50.8))
        #expect(near(inch.bounds?.max.x ?? 0, 50.8))
        #expect(inch.warnings.isEmpty)

        let forced = try S.fixture("inch").contours(.init(units: .millimetre))
        #expect(near(forced.area, 4))

        let unitless = try S.fixture("unitless").contours()
        #expect(unitless.warnings == [.unitlessAssumed(.millimetre)])
        #expect(near(unitless.area, 100))
        let assumed = try S.fixture("unitless").contours(.init(unitlessFallback: .inch))
        #expect(near(assumed.area, 100 * 25.4 * 25.4))
        #expect(assumed.warnings == [.unitlessAssumed(.inch)])
    }

    @Test("layer filters, case-insensitive, and what each filter reports")
    func layers() throws {
        let dwg = try S.fixture("layers")
        let all = dwg.contours()
        #expect(all.shapes.count == 2)
        #expect(all.warnings.contains(.ignoredText(count: 1)))
        #expect(all.warnings.contains(.blockReferencesNotExpanded(count: 1)))
        #expect(all.warnings.contains(.skippedEntities(type: "HATCH", count: 1)))

        let cut = dwg.contours(.init(layers: ["cut"]))
        #expect(cut.shapes.count == 1)
        #expect(near(cut.area, 100))
        #expect(cut.shapes.first?.outer.layers == ["CUT"])
        #expect(cut.warnings == [.skippedEntities(type: "HATCH", count: 1)])

        let guides = dwg.contours(.init(layers: ["GUIDES"]))
        #expect(guides.shapes.count == 1)
        #expect(near(guides.area, 16 * Double.pi))
        #expect(guides.warnings == [.blockReferencesNotExpanded(count: 1)])

        let without = dwg.contours(.init(excludedLayers: ["GUIDES", "NOTES"]))
        #expect(without.shapes.count == 1)
        #expect(without.warnings == [.skippedEntities(type: "HATCH", count: 1)])
    }
}
