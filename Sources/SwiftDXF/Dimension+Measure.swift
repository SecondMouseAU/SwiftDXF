import Foundation

extension DXF.Dimension {
    /// The text split into its parts: placeholder, typed numbers, unit, qualifiers, words.
    public var text: DXF.DimensionText { DXF.DimensionText(textOverride) }

    /// The measurement derived from the definition points, in drawing units, or `nil` when the
    /// type is not computed here or a point is missing.
    ///
    /// - `.linear`: the distance between the extension-line origins projected onto the
    ///   measurement direction, which is ``rotation`` degrees from the x axis (0 when absent).
    /// - `.aligned`: the distance between the extension-line origins.
    /// - `.radius`, `.diameter`: the distance between the two ends, the radius or the diameter.
    ///
    /// Angular and ordinate dimensions return `nil`. Lengths are measured in the drawing plane.
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
            guard let end = defPoint4 else { return nil }
            return hypot(end.x - defPoint.x, end.y - defPoint.y)
        case .angular, .angular3Point, .ordinate, .unknown:
            return nil
        }
    }

    /// The stored measurement when the file has one, else ``computedMeasurement``.
    public var measuredValue: Double? { measurement ?? computedMeasurement }

    /// The unit vector a linear dimension measures along, or `nil` for other types.
    public var measurementDirection: DXF.Point2? {
        switch kind {
        case .linear:
            let (c, s) = ArcPieces.cosSin(degrees: rotation ?? 0)
            return DXF.Point2(c, s)
        case .aligned:
            guard let a = defPoint2, let b = defPoint3 else { return nil }
            let length = hypot(b.x - a.x, b.y - a.y)
            return length > 0 ? DXF.Point2((b.x - a.x) / length, (b.y - a.y) / length) : nil
        default:
            return nil
        }
    }
}

extension DXF.Drawing {
    /// The style a dimension is stated in: its `DIMSTYLE` entry with its own overrides on top.
    ///
    /// A dimension naming no known style gets an empty style carrying only its overrides.
    public func style(of dimension: DXF.Dimension) -> DXF.DimensionStyle {
        let base =
            dimension.styleName.flatMap { dimensionStyles[$0] }
            ?? DXF.DimensionStyle(name: dimension.styleName ?? "")
        return base.applying(dimension.styleOverrides)
    }
}
