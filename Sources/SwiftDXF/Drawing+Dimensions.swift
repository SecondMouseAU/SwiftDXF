extension DXF.Drawing {
    /// The style variables in force for `dimension`: its own overrides, then the `DIMSTYLE` record
    /// it names (`Standard` when it names none).
    ///
    /// A variable neither states is `nil`. ``dimensionDefaults`` holds the header's values.
    public func styleVariables(of dimension: DXF.Dimension) -> DXF.DimensionStyle.Variables {
        let record = dimensionStyles.first(named: dimension.styleName ?? "Standard")
        return dimension.styleOverrides.filling(from: record?.variables ?? .init())
    }

    /// The computed measurement times the style's linear scale, before rounding.
    ///
    /// An angle is not scaled, and stays in degrees: the style states its decimal places and unit
    /// apart from a length's, and they are not modelled. `nil` where
    /// ``DXF/Dimension/computedMeasurement`` is.
    public func displayedMeasurement(of dimension: DXF.Dimension) -> Double? {
        switch dimension.kind {
        case .angular, .angular3Point: return dimension.computedMeasurement
        default:
            return dimension.computedMeasurement.map {
                $0 * styleVariables(of: dimension).effectiveScale
            }
        }
    }
}
