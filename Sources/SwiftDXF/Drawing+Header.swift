extension DXF.Drawing {
    /// The record of ``dimensionStyles`` that ``currentDimensionStyleName`` names, ignoring case,
    /// or `nil` when the header names none or the table has no such record.
    public var currentDimensionStyle: DXF.DimensionStyle? {
        currentDimensionStyleName.flatMap { dimensionStyles.first(named: $0) }
    }
}
