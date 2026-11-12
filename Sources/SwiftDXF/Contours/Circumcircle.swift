/// The circle through three points.
struct Circumcircle {
    var centre: DXF.Point2
    var radius: Double
    /// Whether `a`, `b`, `c` run counter-clockwise round the centre.
    var counterClockwise: Bool

    /// The circle through `a`, `b` and `c`, or `nil` when they are collinear or coincide.
    init?(_ a: DXF.Point2, _ b: DXF.Point2, _ c: DXF.Point2) {
        let bx = b.x - a.x
        let by = b.y - a.y
        let cx = c.x - a.x
        let cy = c.y - a.y
        let d = 2 * (bx * cy - by * cx)
        let b2 = bx * bx + by * by
        let c2 = cx * cx + cy * cy
        guard abs(d) > 1e-9 * (b2 + c2), b2 > 0, c2 > 0 else { return nil }
        centre = DXF.Point2(a.x + (cy * b2 - by * c2) / d, a.y + (bx * c2 - cx * b2) / d)
        radius = centre.distance(to: a)
        guard radius.isFinite else { return nil }
        counterClockwise = d > 0
    }
}
