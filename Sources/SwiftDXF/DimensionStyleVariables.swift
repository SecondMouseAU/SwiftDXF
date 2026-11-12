extension DXF.DimensionStyle {
    /// The dimension style variables that decide how a measured value is stated.
    ///
    /// A `nil` variable is one the record does not state. A `DIMSTYLE` record and a dimension's
    /// own overrides both use this type; ``DXF/Drawing/styleVariables(of:)`` combines them.
    public struct Variables: Equatable, Sendable {
        /// `DIMDEC` (group 271): decimal places of the value.
        public var decimalPlaces: Int?
        /// `DIMZIN` (group 78): which zeros are suppressed, as a bit set.
        public var zeroSuppression: Int?
        /// `DIMLFAC` (group 144): the factor the measured value is multiplied by.
        ///
        /// A negative value applies to paper-space dimensions only.
        public var linearScale: Double?
        /// `DIMPOST` (group 3): text around the value, with `<>` standing for the value.
        public var unitSuffix: String?

        public init(
            decimalPlaces: Int? = nil, zeroSuppression: Int? = nil, linearScale: Double? = nil,
            unitSuffix: String? = nil
        ) {
            self.decimalPlaces = decimalPlaces
            self.zeroSuppression = zeroSuppression
            self.linearScale = linearScale
            self.unitSuffix = unitSuffix
        }

        /// `DIMZIN` bit 4: leading zeros are suppressed, so `0.5` shows as `.5`.
        public var suppressesLeadingZeros: Bool { (zeroSuppression ?? 0) & 4 != 0 }

        /// `DIMZIN` bit 8: trailing zeros are suppressed, so `8.100` shows as `8.1`.
        public var suppressesTrailingZeros: Bool { (zeroSuppression ?? 0) & 8 != 0 }

        /// The scale applied to a model-space value: ``linearScale`` when positive, otherwise `1`.
        public var effectiveScale: Double {
            if let scale = linearScale, scale > 0 { return scale }
            return 1
        }

        /// These variables, with every one that is not stated taken from `base`.
        public func filling(from base: Variables) -> Variables {
            Variables(
                decimalPlaces: decimalPlaces ?? base.decimalPlaces,
                zeroSuppression: zeroSuppression ?? base.zeroSuppression,
                linearScale: linearScale ?? base.linearScale,
                unitSuffix: unitSuffix ?? base.unitSuffix)
        }
    }
}
