extension DXF.Drawing {
    /// The style variables in force for `dimension`: its own overrides, then the `DIMSTYLE` record
    /// it names (`Standard` when it names none).
    ///
    /// A variable neither states is `nil`. ``dimensionDefaults`` holds the header's values.
    public func styleVariables(of dimension: DXF.Dimension) -> DXF.DimensionStyle.Variables {
        let record = dimensionStyles.first(named: dimension.styleName ?? "Standard")
        return dimension.styleOverrides.filling(from: record?.variables ?? .init())
    }

    /// The text of `dimension` split into what it shows, with an angle read in the unit of its
    /// style (``DXF/DimensionStyle/Variables/angleUnit``).
    ///
    /// For a dimension whose style states no unit, this is ``DXF/Dimension/text(numbers:angleUnit:)``
    /// with none, which reads `45°` and nothing else as an angle. A typed angle in
    /// ``DXF/DimensionText/typedAngles`` is in degrees, as ``DXF/Dimension/computedMeasurement``
    /// is of an angular dimension, so they compare directly; the places the text is rounded to
    /// are ``DXF/DimensionStyle/Variables/effectiveAngleDecimalPlaces``.
    public func text(
        of dimension: DXF.Dimension, numbers: DXF.DimensionText.NumberConvention = .plain
    ) -> DXF.DimensionText {
        dimension.text(numbers: numbers, angleUnit: styleVariables(of: dimension).angleUnit)
    }

    /// The computed measurement times the style's linear scale, before rounding.
    ///
    /// An angle is not scaled, and stays in degrees whatever unit and decimal places its style
    /// shows it in (``DXF/DimensionStyle/Variables/angleUnit``). `nil` where
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
