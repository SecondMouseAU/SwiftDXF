import Foundation

/// Where an angle is wrapped into `0..<2 pi`.
private typealias Wrap = DXF.Contour.Segment

extension DXF.Dimension {
    /// The measurement the geometry gives, with no style scale applied: a length in drawing units,
    /// or an angle in **degrees** for an angular dimension, as ``rotation`` and the angles of an
    /// `ARC` are.
    ///
    /// Linear: the distance between the extension-line origins along ``rotation`` (horizontal when
    /// absent). Aligned: the distance between them. Radius and diameter: the distance between the
    /// two definition points. Ordinate: the distance from the origin (``defPoint``) to the feature
    /// location (``defPoint2``) along x when ``isXOrdinate`` and along y when not, where ``rotation``
    /// turns the axes (horizontal when absent), and always positive: which side of the origin the
    /// feature is on is not part of it.
    ///
    /// Angular: the angle between the first line, ``defPoint2`` to ``defPoint3``, and the second,
    /// ``defPoint4`` to ``defPoint``, where the two lines cross. Two crossing lines make four
    /// angles, two and their supplements; it is the one on the side of the arc location
    /// ``defPoint5``, so it is between 0 and 180, and `nil` for lines that are parallel or an arc
    /// location exactly on their crossing. Three-point angular: the angle at the vertex ``defPoint4``
    /// between the rays to ``defPoint2`` and ``defPoint3``, on the side of the arc location
    /// ``defPoint``, so it is between 0 and 360 and may be more than 180. `nil` for a ray of no
    /// length, two rays that are one, and an arc location exactly on the vertex.
    ///
    /// `nil` for an unrecognised type, or when a definition point is missing. Only `x` and `y` are
    /// used.
    ///
    /// Group 42 is often `-1` or missing, so this is the number every consumer can rely on; see
    /// ``measurement`` for what the file stored.
    public var computedMeasurement: Double? {
        switch kind {
        case .linear:
            guard let a = defPoint2, let b = defPoint3 else { return nil }
            let (c, s) = ArcPieces.cosSin(degrees: rotation ?? 0)
            return abs((b.x - a.x) * c + (b.y - a.y) * s)
        case .aligned:
            guard let a = defPoint2, let b = defPoint3 else { return nil }
            return hypot(b.x - a.x, b.y - a.y)
        case .radius, .diameter:
            guard let other = defPoint4 else { return nil }
            return hypot(other.x - defPoint.x, other.y - defPoint.y)
        case .angular:
            guard let a = defPoint2, let b = defPoint3, let c = defPoint4, let at = defPoint5
            else { return nil }
            return Self.angle(between: (a, b), and: (c, defPoint), arcAt: at)
        case .angular3Point:
            guard let a = defPoint2, let b = defPoint3, let vertex = defPoint4 else { return nil }
            return Self.angle(at: vertex, from: a, to: b, arcAt: defPoint)
        case .ordinate:
            guard let feature = defPoint2 else { return nil }
            // Along the x axis of the coordinate system the dimension was made in (``rotation``),
            // or across it.
            let (c, s) = ArcPieces.cosSin(degrees: rotation ?? 0)
            let (dx, dy) = (feature.x - defPoint.x, feature.y - defPoint.y)
            return abs(isXOrdinate ? dx * c + dy * s : dy * c - dx * s)
        case .unknown:
            return nil
        }
    }

    /// The text override split into what it shows; see ``DXF/DimensionText``.
    ///
    /// A comma is not part of a number; ``text(numbers:)`` says how the drawing writes them.
    public var text: DXF.DimensionText { DXF.DimensionText(textOverride, codePage: codePage) }

    /// The text override split into what it shows, with numbers read as the drawing writes them.
    ///
    /// For a Jw_cad drawing, `text(numbers: .commaSeparatesThousands).typedNumbers` of `10,439`
    /// is `[10439]`.
    public func text(numbers: DXF.DimensionText.NumberConvention) -> DXF.DimensionText {
        DXF.DimensionText(textOverride, numbers: numbers, codePage: codePage)
    }

    // MARK: angles

    /// The angle in degrees at `vertex` from the ray to `first` to the ray to `second`, on the side
    /// of `arc`: counter-clockwise from the first when the arc is in that wedge, else the rest of
    /// the turn.
    private static func angle(
        at vertex: DXF.Point, from first: DXF.Point, to second: DXF.Point, arcAt arc: DXF.Point
    ) -> Double? {
        guard let a = direction(from: vertex, to: first),
            let b = direction(from: vertex, to: second), let w = direction(from: vertex, to: arc)
        else { return nil }
        let turn = Wrap.wrap(b - a)
        // Rays that are one are an angle of 0 or 360, and the points do not say which.
        guard turn > 1e-12, turn < 2 * .pi - 1e-12 else { return nil }
        let angle = Wrap.wrap(w - a) <= turn ? turn : 2 * .pi - turn
        return angle * 180 / .pi
    }

    /// The angle in degrees between the lines `first` and `second` that is on the side of `arc`.
    private static func angle(
        between first: (DXF.Point, DXF.Point), and second: (DXF.Point, DXF.Point),
        arcAt arc: DXF.Point
    ) -> Double? {
        let (d1x, d1y) = (first.1.x - first.0.x, first.1.y - first.0.y)
        let (d2x, d2y) = (second.1.x - second.0.x, second.1.y - second.0.y)
        let cross = d1x * d2y - d1y * d2x
        let scale = hypot(d1x, d1y) * hypot(d2x, d2y)
        guard cross.isFinite, scale.isFinite, scale > 0, abs(cross) > 1e-12 * scale else {
            return nil
        }
        // Where the lines cross: `first.0` plus `t` along the first.
        let t = ((second.0.x - first.0.x) * d2y - (second.0.y - first.0.y) * d2x) / cross
        let vertex = DXF.Point(first.0.x + t * d1x, first.0.y + t * d1y)
        guard let w = direction(from: vertex, to: arc) else { return nil }
        // The four rays from the crossing, in turn: the angle is the gap that holds the arc.
        let a1 = atan2(d1y, d1x)
        let a2 = atan2(d2y, d2x)
        let rays = [a1, a2, a1 + .pi, a2 + .pi].map(Wrap.wrap).sorted()
        let at = Wrap.wrap(w)
        var (lower, upper) = (rays[3], rays[0] + 2 * .pi)
        for i in 0..<3 where rays[i] <= at && at < rays[i + 1] {
            (lower, upper) = (rays[i], rays[i + 1])
        }
        return (upper - lower) * 180 / .pi
    }

    /// The direction from `a` to `b` as an angle in radians, or `nil` when they are one point or a
    /// coordinate is not a finite number.
    private static func direction(from a: DXF.Point, to b: DXF.Point) -> Double? {
        let (dx, dy) = (b.x - a.x, b.y - a.y)
        guard dx.isFinite, dy.isFinite, dx != 0 || dy != 0 else { return nil }
        return atan2(dy, dx)
    }

}
