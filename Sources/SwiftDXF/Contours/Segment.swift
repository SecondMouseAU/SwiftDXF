import Foundation

extension DXF.Contour {
    /// One piece of a contour: a straight line, or a circular arc written as a chord plus a bulge.
    ///
    /// `bulge` is `tan(sweep / 4)`: `0` for a line, positive for a counter-clockwise arc from
    /// `start` to `end`, negative for a clockwise one. This is the DXF polyline convention, so the
    /// arc is defined exactly by its two endpoints and survives endpoint snapping. Arcs never sweep
    /// more than a half turn (`abs(bulge) <= 1`): longer arcs are split, which keeps the centre
    /// and radius well conditioned. A full circle is therefore two segments.
    public struct Segment: Equatable, Sendable {
        public var start: DXF.Point2
        public var end: DXF.Point2
        public var bulge: Double

        public init(start: DXF.Point2, end: DXF.Point2, bulge: Double = 0) {
            self.start = start
            self.end = end
            self.bulge = bulge
        }

        /// `true` when the segment is a circular arc rather than a line.
        public var isArc: Bool { abs(bulge) > 1e-12 }

        /// Signed sweep in radians: positive counter-clockwise, `0` for a line.
        public var sweep: Double { 4 * atan(bulge) }

        /// Distance between the endpoints.
        public var chord: Double { start.distance(to: end) }

        /// Arc radius, or `nil` for a line.
        public var radius: Double? {
            guard isArc, chord > 0 else { return nil }
            return abs(chord / (2 * sin(sweep / 2)))
        }

        /// Arc centre, or `nil` for a line.
        public var center: DXF.Point2? {
            guard isArc, chord > 0 else { return nil }
            let half = sweep / 2
            let offset = (chord / 2) * cos(half) / sin(half)
            let nx = -(end.y - start.y) / chord
            let ny = (end.x - start.x) / chord
            return DXF.Point2(
                (start.x + end.x) / 2 + nx * offset, (start.y + end.y) / 2 + ny * offset)
        }

        /// Angle of the start point about the centre, in radians (`nil` for a line).
        public var startAngle: Double? {
            guard let c = center else { return nil }
            return atan2(start.y - c.y, start.x - c.x)
        }

        /// Start angle plus the signed sweep (not normalised; `nil` for a line).
        public var endAngle: Double? { startAngle.map { $0 + sweep } }

        /// Arc length, or the chord for a line.
        public var length: Double {
            guard let r = radius else { return chord }
            return r * abs(sweep)
        }

        /// The same geometry traversed the other way.
        public func reversed() -> Segment {
            Segment(start: end, end: start, bulge: -bulge)
        }

        /// The point a fraction `t` (0 to 1) of the way along the segment by angle or length.
        public func point(at t: Double) -> DXF.Point2 {
            if t <= 0 { return start }
            if t >= 1 { return end }
            guard let c = center, let r = radius, let a0 = startAngle else {
                return DXF.Point2(start.x + (end.x - start.x) * t, start.y + (end.y - start.y) * t)
            }
            let a = a0 + sweep * t
            return DXF.Point2(c.x + r * cos(a), c.y + r * sin(a))
        }

        /// Exact axis-aligned bounds, including the arc's extreme points.
        public var bounds: DXF.Box2 {
            var lo = DXF.Point2(min(start.x, end.x), min(start.y, end.y))
            var hi = DXF.Point2(max(start.x, end.x), max(start.y, end.y))
            if let c = center, let r = radius, let a0 = startAngle {
                let span = abs(sweep)
                let ccw = sweep > 0
                let quarter = Double.pi / 2
                for k in 0..<4 {
                    let axis = Double(k) * quarter
                    let delta = ccw ? Self.wrap(axis - a0) : Self.wrap(a0 - axis)
                    guard delta <= span else { continue }
                    switch k {
                    case 0: hi.x = max(hi.x, c.x + r)
                    case 1: hi.y = max(hi.y, c.y + r)
                    case 2: lo.x = min(lo.x, c.x - r)
                    default: lo.y = min(lo.y, c.y - r)
                    }
                }
            }
            return DXF.Box2(min: lo, max: hi)
        }

        /// This segment's contribution to a loop's signed area (shoelace term plus arc cap).
        var areaTerm: Double {
            var term = (start.x * end.y - end.x * start.y) / 2
            if let r = radius {
                let s = sweep
                term += r * r / 2 * (s - sin(s))
            }
            return term
        }

        /// Direction of travel at the start, in radians.
        var startDirection: Double {
            atan2(end.y - start.y, end.x - start.x) - sweep / 2
        }

        /// Direction of travel at the end, in radians.
        var endDirection: Double {
            atan2(end.y - start.y, end.x - start.x) + sweep / 2
        }

        /// Wraps an angle into `[0, 2 pi)`.
        static func wrap(_ angle: Double) -> Double {
            let full = 2 * Double.pi
            var a = angle.truncatingRemainder(dividingBy: full)
            if a < 0 { a += full }
            return a
        }
    }
}
