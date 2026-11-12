import Foundation

extension DXF.Dimension {
    /// The measurement the geometry gives, in drawing units, with no style scale applied.
    ///
    /// Linear: the distance between the extension-line origins along ``rotation`` (horizontal when
    /// absent). Aligned: the distance between them. Radius and diameter: the distance between the
    /// two definition points. `nil` for angular and ordinate dimensions, an unrecognised type, or
    /// when a definition point is missing. Only `x` and `y` are used.
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
        case .angular, .angular3Point, .ordinate, .unknown:
            return nil
        }
    }

    /// The text override split into what it shows; see ``DXF/DimensionText``.
    public var text: DXF.DimensionText { DXF.DimensionText(textOverride) }
}
