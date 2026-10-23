import Foundation

/// Replaces a sampled curve by lines and circular arcs.
///
/// Greedy: from each start point it takes the longest run of samples that one line, or one circle
/// through the run's first, middle and last samples, reproduces within the tolerance.
enum CurveFitter {
    struct Result {
        var pieces: [(a: DXF.Point2, b: DXF.Point2, bulge: Double)] = []
        /// Largest distance from a sample to the piece that replaces it.
        var deviation = 0.0
    }

    static func fit(_ points: [DXF.Point2], tolerance: Double) -> Result {
        var result = Result()
        let n = points.count
        guard n >= 2 else { return result }
        var i = 0
        while i < n - 1 {
            let lineEnd = reach(from: i, last: n - 1) { lineDeviation(points, i, $0) <= tolerance }
            let arcEnd = reach(from: i, last: n - 1) {
                $0 >= i + 2 && arc(points, i, $0, tolerance: tolerance) != nil
            }
            if arcEnd > lineEnd, arcEnd >= i + 2,
                let fit = arc(points, i, arcEnd, tolerance: tolerance)
            {
                result.deviation = max(result.deviation, fit.deviation)
                for piece in fit.pieces { result.pieces.append(piece) }
                i = arcEnd
            } else {
                result.deviation = max(result.deviation, lineDeviation(points, i, lineEnd))
                result.pieces.append((points[i], points[lineEnd], 0))
                i = lineEnd
            }
        }
        return result
    }

    /// Largest index `j` in `i + 1 ... last` for which `fits(j)` holds.
    ///
    /// Assumes `fits` holds at `i + 1`. Gallops outward then bisects, so a long run costs a
    /// logarithmic number of checks.
    private static func reach(from i: Int, last: Int, _ fits: (Int) -> Bool) -> Int {
        var good = i + 1
        var bad = last + 1
        var step = 2
        while good < last {
            let candidate = min(last, i + step)
            if candidate <= good { break }
            if fits(candidate) {
                good = candidate
                step *= 2
            } else {
                bad = candidate
                break
            }
        }
        while bad - good > 1 {
            let mid = (good + bad) / 2
            if fits(mid) { good = mid } else { bad = mid }
        }
        return good
    }

    private static func lineDeviation(_ p: [DXF.Point2], _ i: Int, _ j: Int) -> Double {
        var worst = 0.0
        let a = p[i]
        let b = p[j]
        let dx = b.x - a.x
        let dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        for k in (i + 1)..<max(j, i + 1) {
            var t = len2 > 0 ? ((p[k].x - a.x) * dx + (p[k].y - a.y) * dy) / len2 : 0
            t = min(1, max(0, t))
            let d = p[k].distance(to: DXF.Point2(a.x + dx * t, a.y + dy * t))
            worst = max(worst, d)
        }
        return worst
    }

    private static func arc(_ p: [DXF.Point2], _ i: Int, _ j: Int, tolerance: Double) -> (
        pieces: [(a: DXF.Point2, b: DXF.Point2, bulge: Double)], deviation: Double
    )? {
        let m = (i + j) / 2
        let bx = p[m].x - p[i].x
        let by = p[m].y - p[i].y
        let cx = p[j].x - p[i].x
        let cy = p[j].y - p[i].y
        let d = 2 * (bx * cy - by * cx)
        let b2 = bx * bx + by * by
        let c2 = cx * cx + cy * cy
        guard abs(d) > 1e-9 * (b2 + c2), b2 > 0, c2 > 0 else { return nil }
        let centre = DXF.Point2(
            p[i].x + (cy * b2 - by * c2) / d, p[i].y + (bx * c2 - cx * b2) / d)
        let radius = centre.distance(to: p[i])
        guard radius.isFinite, radius < 1e6 else { return nil }
        let counterClockwise = d > 0
        let a0 = atan2(p[i].y - centre.y, p[i].x - centre.x)
        func progress(_ q: DXF.Point2) -> Double {
            let a = atan2(q.y - centre.y, q.x - centre.x)
            return DXF.Contour.Segment.wrap(counterClockwise ? a - a0 : a0 - a)
        }
        var worst = 0.0
        var last = 0.0
        for k in i...j {
            let dev = abs(p[k].distance(to: centre) - radius)
            if dev > tolerance { return nil }
            worst = max(worst, dev)
            if k > i {
                let along = progress(p[k])
                if along < last - 1e-9 && k != j { return nil }
                last = max(last, along)
            }
        }
        let total = progress(p[j])
        guard total > progress(p[m]), total > 0 else { return nil }
        let sweep = counterClockwise ? total : -total
        let pieces = ArcPieces.split(sweep: sweep, layer: 0) { k, n in
            if k == 0 { return p[i] }
            if k == n { return p[j] }
            let a = a0 + sweep * Double(k) / Double(n)
            return DXF.Point2(centre.x + radius * cos(a), centre.y + radius * sin(a))
        }
        return (pieces.map { ($0.a, $0.b, $0.bulge) }, worst)
    }
}
