import Foundation
import Testing

@testable import SwiftDXF

/// Shared helpers for the contour suites.
enum ContourSupport {
    static func fixture(_ name: String) throws -> DXF.Drawing {
        let url = try #require(
            Bundle.module.url(
                forResource: name, withExtension: "dxf", subdirectory: "Fixtures/Contours"))
        return try DXF.read(contentsOf: url)
    }

    static func line(
        _ ax: Double, _ ay: Double, _ bx: Double, _ by: Double, layer: String = "0"
    ) -> DXF.Entity {
        .line(a: .init(ax, ay), b: .init(bx, by), layer: layer, color: 256)
    }

    static func circle(
        _ x: Double, _ y: Double, _ r: Double, layer: String = "0"
    ) -> DXF.Entity {
        .circle(center: .init(x, y), radius: r, layer: layer, color: 256)
    }

    static func arc(
        _ x: Double, _ y: Double, _ r: Double, _ s: Double, _ e: Double, layer: String = "0"
    ) -> DXF.Entity {
        .arc(center: .init(x, y), radius: r, startDeg: s, endDeg: e, layer: layer, color: 256)
    }

    static func polygon(
        _ pts: [(Double, Double)], bulges: [Double] = [], layer: String = "0"
    ) -> DXF.Entity {
        let verts = pts.enumerated().map {
            DXF.PolyVertex(
                .init($1.0, $1.1), bulge: $0 < bulges.count ? bulges[$0] : 0)
        }
        return .polyline(vertices: verts, closed: true, layer: layer, color: 256)
    }

    /// Four lines around the box.
    static func box(
        _ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, layer: String = "0"
    ) -> [DXF.Entity] {
        [
            line(x0, y0, x1, y0, layer: layer), line(x1, y0, x1, y1, layer: layer),
            line(x1, y1, x0, y1, layer: layer), line(x0, y1, x0, y0, layer: layer),
        ]
    }

    static func drawing(_ entities: [DXF.Entity], insUnits: Int? = 4) -> DXF.Drawing {
        DXF.Drawing(entities: entities, insUnits: insUnits)
    }

    /// Largest distance from points sampled along `segments` to the polyline `curve`.
    static func deviation(
        of segments: [DXF.Contour.Segment], from curve: [DXF.Point2], samples: Int = 40
    ) -> Double {
        var worst = 0.0
        for s in segments {
            for k in 0...samples {
                let p = s.point(at: Double(k) / Double(samples))
                var best = Double.infinity
                for i in 0..<(curve.count - 1) {
                    let seg = DXF.Contour.Segment(start: curve[i], end: curve[i + 1])
                    best = min(best, ContourNesting.distance(p, seg))
                }
                worst = max(worst, best)
            }
        }
        return worst
    }

    /// Largest distance from the dense `curve` points to the nearest of `segments`.
    static func deviation(of curve: [DXF.Point2], from segments: [DXF.Contour.Segment]) -> Double {
        var worst = 0.0
        for p in curve {
            let best = segments.map { ContourNesting.distance(p, $0) }.min() ?? .infinity
            worst = max(worst, best)
        }
        return worst
    }

    /// Splitmix64, so shuffles are the same on every run.
    struct Generator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }
}

func near(_ a: Double, _ b: Double, _ tol: Double = 1e-9) -> Bool { abs(a - b) <= tol }
