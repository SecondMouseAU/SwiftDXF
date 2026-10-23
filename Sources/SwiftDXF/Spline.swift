import Foundation

extension DXF {
    /// A `SPLINE` entity: the raw NURBS data as stored in the file, plus flattening helpers.
    ///
    /// Groups: degree 71, flags 70, control points 10/20/30, knots 40, weights 41, fit points
    /// 11/21/31. Malformed data never traps; see ``flattened(tolerance:)`` for the fallbacks.
    public struct Spline: Equatable, Sendable {
        /// Polynomial degree (group 71).
        public var degree: Int
        /// Raw spline flags (group 70).
        public var flags: Int
        public var controlPoints: [Point]
        public var knots: [Double]
        /// Control point weights (group 41).
        ///
        /// Empty for a non-rational spline.
        public var weights: [Double]
        public var fitPoints: [Point]
        public var layer: String
        public var color: Int

        public init(
            degree: Int, flags: Int = 0, controlPoints: [Point] = [], knots: [Double] = [],
            weights: [Double] = [], fitPoints: [Point] = [], layer: String = "0", color: Int = 256
        ) {
            self.degree = degree
            self.flags = flags
            self.controlPoints = controlPoints
            self.knots = knots
            self.weights = weights
            self.fitPoints = fitPoints
            self.layer = layer
            self.color = color
        }

        /// Flag bit 1: the spline is closed.
        public var isClosed: Bool { flags & 1 != 0 }
        /// Flag bit 2: the spline is periodic.
        public var isPeriodic: Bool { flags & 2 != 0 }
        /// Flag bit 4: the spline is rational.
        public var isRational: Bool { flags & 4 != 0 }
        /// Flag bit 8: the spline is planar.
        public var isPlanar: Bool { flags & 8 != 0 }

        /// The usable curve definition, after repairing what can be repaired. `nil` when there
        /// are fewer than two control points.
        struct Curve {
            var degree: Int
            var knots: [Double]
            var points: [Point]
            var weights: [Double]
            var domain: ClosedRange<Double>
        }

        /// The repaired curve definition.
        ///
        /// Degree is clamped to `1...(n - 1)`. A knot vector that does not have `n + degree + 1`
        /// non-decreasing finite values with a non-empty domain is replaced by a clamped uniform
        /// one. Weights that are not one positive finite value per control point are ignored.
        func curve() -> Curve? {
            let n = controlPoints.count
            guard n >= 2 else { return nil }
            let p = min(max(degree, 1), n - 1)
            var u = knots
            let valid =
                u.count == n + p + 1 && u.allSatisfy(\.isFinite)
                && zip(u, u.dropFirst()).allSatisfy { $0 <= $1 } && u[p] < u[n]
            if !valid {
                u = (0...(n + p)).map { Double(min(max($0 - p, 0), n - p)) }
            }
            let w =
                weights.count == n && weights.allSatisfy { $0.isFinite && $0 > 0 }
                ? weights : [Double](repeating: 1, count: n)
            return Curve(
                degree: p, knots: u, points: controlPoints, weights: w, domain: u[p]...u[n])
        }

        /// The parameter range over which ``point(at:)`` is defined, or `nil` when the control
        /// data cannot define a curve.
        public var parameterDomain: ClosedRange<Double>? { curve()?.domain }

        /// The point on the NURBS curve at parameter `t` (clamped into ``parameterDomain``).
        public func point(at t: Double) -> Point? {
            curve().map { $0.point(at: t) }
        }

        /// Flattens the spline to a polyline whose deviation from the curve is at most
        /// `tolerance` (drawing units), endpoints included.
        ///
        /// - Control points present: the rational B-spline is evaluated exactly, clamped or
        ///   periodic knots alike. A closed spline whose last point differs from its first gets
        ///   the first point appended.
        /// - No control points: a uniform Catmull-Rom curve through the fit points is used. This
        ///   approximates the curve, it does not reproduce a file's tangent data.
        /// - Fewer than two usable points: the points available are returned unchanged.
        public func flattened(tolerance: Double) -> [Point] {
            let tol = tolerance.isFinite && tolerance > 0 ? tolerance : 1e-6
            var out: [Point]
            if controlPoints.isEmpty {
                out = Self.catmullRom(fitPoints, closed: isClosed, tolerance: tol)
            } else if let c = curve() {
                out = c.flatten(tolerance: tol)
            } else {
                out = controlPoints
            }
            if isClosed, out.count > 2, let f = out.first, let l = out.last,
                Self.distance(f, l) > 1e-9
            {
                out.append(f)
            }
            return out
        }

        /// The flattened spline as a ``DXF/Entity/polyline(vertices:closed:layer:color:)``.
        public func asPolyline(tolerance: Double) -> Entity {
            .polyline(
                vertices: flattened(tolerance: tolerance).map { PolyVertex($0) },
                closed: false, layer: layer, color: color)
        }

        // MARK: fit-point fallback

        private static func catmullRom(_ pts: [Point], closed: Bool, tolerance: Double) -> [Point] {
            guard pts.count >= 3 else { return pts }
            var p = pts
            if closed, let f = p.first, let l = p.last, distance(f, l) < 1e-12 { p.removeLast() }
            let n = p.count
            let segs = closed ? n : n - 1
            func at(_ i: Int) -> Point {
                closed ? p[((i % n) + n) % n] : p[min(max(i, 0), n - 1)]
            }
            var out = [p[0]]
            for i in 0..<segs {
                let p0 = at(i - 1)
                let p1 = at(i)
                let p2 = at(i + 1)
                let p3 = at(i + 2)
                let b1 = p1 + (p2 - p0) * (1.0 / 6)
                let b2 = p2 - (p3 - p1) * (1.0 / 6)
                var seg: [Point] = [p1]
                subdivide(
                    0, 1, p1, p2, tolerance, 0,
                    { t in
                        let s = 1 - t
                        return p1 * (s * s * s) + b1 * (3 * s * s * t) + b2 * (3 * s * t * t)
                            + p2 * (t * t * t)
                    }, &seg)
                out.append(contentsOf: seg.dropFirst())
            }
            return out
        }

        // MARK: shared adaptive subdivision

        /// Appends points after `pa` up to and including `pb`.
        ///
        /// The 1/4, 1/2, 3/4 samples are
        /// tested against the chord; a span is split until all are within tolerance.
        static func subdivide(
            _ ta: Double, _ tb: Double, _ pa: Point, _ pb: Point, _ tol: Double, _ depth: Int,
            _ eval: (Double) -> Point, _ out: inout [Point]
        ) {
            if depth < 12 {
                let dev =
                    [0.25, 0.5, 0.75].map {
                        segmentDistance(eval(ta + $0 * (tb - ta)), pa, pb)
                    }.max() ?? 0
                if dev > tol * 0.9 || depth < 1 {
                    let tm = 0.5 * (ta + tb)
                    let pm = eval(tm)
                    subdivide(ta, tm, pa, pm, tol, depth + 1, eval, &out)
                    subdivide(tm, tb, pm, pb, tol, depth + 1, eval, &out)
                    return
                }
            }
            out.append(pb)
        }

        static func distance(_ a: Point, _ b: Point) -> Double {
            let d = a - b
            return (d.x * d.x + d.y * d.y + d.z * d.z).squareRoot()
        }

        static func segmentDistance(_ p: Point, _ a: Point, _ b: Point) -> Double {
            let ab = b - a
            let ap = p - a
            let len2 = ab.x * ab.x + ab.y * ab.y + ab.z * ab.z
            let t = len2 > 0 ? min(max((ap.x * ab.x + ap.y * ab.y + ap.z * ab.z) / len2, 0), 1) : 0
            return distance(p, a + ab * t)
        }
    }
}

extension DXF.Spline.Curve {
    /// Index `i` with `u[i] <= t < u[i + 1]`, restricted to the non-degenerate spans.
    private func span(_ t: Double) -> Int {
        let n = points.count
        if t >= knots[n] { return n - 1 }
        var lo = degree
        var hi = n
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if t < knots[mid] { hi = mid } else { lo = mid }
        }
        return lo
    }

    func point(at tIn: Double) -> DXF.Point {
        let t = tIn.isNaN ? domain.lowerBound : min(max(tIn, domain.lowerBound), domain.upperBound)
        let i = span(t)
        let p = degree
        // Cox-de Boor basis functions N[0...p] for the span.
        var basis = [Double](repeating: 0, count: p + 1)
        var left = basis
        var right = basis
        basis[0] = 1
        if p > 0 {
            for j in 1...p {
                left[j] = t - knots[i + 1 - j]
                right[j] = knots[i + j] - t
                var saved = 0.0
                for r in 0..<j {
                    let d = right[r + 1] + left[j - r]
                    let temp = d == 0 ? 0 : basis[r] / d
                    basis[r] = saved + right[r + 1] * temp
                    saved = left[j - r] * temp
                }
                basis[j] = saved
            }
        }
        var x = 0.0
        var y = 0.0
        var z = 0.0
        var w = 0.0
        for k in 0...p {
            let idx = i - p + k
            let b = basis[k] * weights[idx]
            x += b * points[idx].x
            y += b * points[idx].y
            z += b * points[idx].z
            w += b
        }
        return w > 0 ? DXF.Point(x / w, y / w, z / w) : points[i]
    }

    func flatten(tolerance: Double) -> [DXF.Point] {
        var distinct: [Double] = []
        for k in knots where k >= domain.lowerBound && k <= domain.upperBound {
            if distinct.last.map({ k > $0 }) ?? true { distinct.append(k) }
        }
        var out = [point(at: domain.lowerBound)]
        for (a, b) in zip(distinct, distinct.dropFirst()) {
            DXF.Spline.subdivide(
                a, b, out[out.count - 1], point(at: b), tolerance, 0, { point(at: $0) }, &out)
        }
        return out
    }
}

extension DXF.Point {
    static func + (a: Self, b: Self) -> Self { Self(a.x + b.x, a.y + b.y, a.z + b.z) }
    static func - (a: Self, b: Self) -> Self { Self(a.x - b.x, a.y - b.y, a.z - b.z) }
    static func * (a: Self, s: Double) -> Self { Self(a.x * s, a.y * s, a.z * s) }
}
