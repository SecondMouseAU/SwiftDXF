import Foundation

/// A segment in flight: endpoints, bulge and the index of its source layer.
struct RawSegment {
    var a: DXF.Point2
    var b: DXF.Point2
    var bulge: Double
    var layer: Int
}

/// Builds arcs that respect the "at most a half turn" segment rule.
enum ArcPieces {
    /// Splits an arc sweeping `sweep` radians into equal pieces of at most a half turn.
    ///
    /// `pointAt(k)` returns the k-th of `n + 1` boundary points; the caller owns exactness of the
    /// first and last.
    static func split(
        sweep: Double, layer: Int, pointAt: (Int, Int) -> DXF.Point2
    ) -> [RawSegment] {
        let n = max(1, Int((abs(sweep) / Double.pi - 1e-9).rounded(.up)))
        let bulge = snapped(tan(sweep / Double(4 * n)))
        var out: [RawSegment] = []
        var prev = pointAt(0, n)
        for k in 1...n {
            let next = pointAt(k, n)
            out.append(RawSegment(a: prev, b: next, bulge: bulge, layer: layer))
            prev = next
        }
        return out
    }

    /// Cosine and sine of an angle in degrees, exact at multiples of 90.
    static func cosSin(degrees d: Double) -> (Double, Double) {
        var m = d.truncatingRemainder(dividingBy: 360)
        if m < 0 { m += 360 }
        switch m {
        case 0: return (1, 0)
        case 90: return (0, 1)
        case 180: return (-1, 0)
        case 270: return (0, -1)
        default: return (cos(m * Double.pi / 180), sin(m * Double.pi / 180))
        }
    }

    /// Cosine and sine of an angle in radians, with float dust at the axes cleaned to zero.
    static func cosSin(radians a: Double) -> (Double, Double) {
        let c = cos(a)
        let s = sin(a)
        return (abs(c) < 1e-15 ? 0 : c, abs(s) < 1e-15 ? 0 : s)
    }

    private static func snapped(_ bulge: Double) -> Double {
        if abs(abs(bulge) - 1) < 1e-14 { return bulge < 0 ? -1 : 1 }
        return bulge
    }
}
