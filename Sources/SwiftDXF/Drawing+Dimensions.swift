extension DXF.Drawing {
    /// The style variables in force for `dimension`.
    ///
    /// The dimension's own overrides win, then the `DIMSTYLE` record it names (`Standard` when it
    /// names none). A variable that neither states is `nil`: the file leaves it unset, and a
    /// guess would be the reader's, not the file's. ``dimensionDefaults`` holds the header's
    /// current values, for a caller that wants them as a fallback.
    public func styleVariables(of dimension: DXF.Dimension) -> DXF.DimensionStyle.Variables {
        let name = (dimension.styleName ?? "Standard").lowercased()
        let record = dimensionStyles.first { $0.name.lowercased() == name }
        return dimension.styleOverrides.filling(from: record?.variables ?? .init())
    }

    /// The value a dimension's text shows before rounding: its computed measurement times the style's
    /// linear scale.
    ///
    /// `nil` where ``DXF/Dimension/computedMeasurement`` is. Rounding to
    /// ``DXF/DimensionStyle/Variables/decimalPlaces`` and the unit suffix are left to the caller.
    public func displayedMeasurement(of dimension: DXF.Dimension) -> Double? {
        dimension.computedMeasurement.map { $0 * styleVariables(of: dimension).effectiveScale }
    }
}
