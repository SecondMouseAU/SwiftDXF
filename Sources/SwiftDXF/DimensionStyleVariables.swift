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
        /// `DIMAUNIT` (group 275): the unit an angle is shown in, as the file writes it: `0` decimal
        /// degrees, `1` degrees, minutes and seconds, `2` gradians, `3` radians.
        ///
        /// ``angleUnit`` names it. A record that does not state it shows angles in decimal degrees,
        /// which is the variable's default, but the reader does not fill that in.
        public var angleUnitCode: Int?
        /// `DIMADEC` (group 179): the decimal places of an angle, or `-1` for the places of
        /// ``decimalPlaces``.
        ///
        /// ``effectiveAngleDecimalPlaces`` resolves the `-1`. For degrees, minutes and seconds it
        /// decides how far the angle is written (degrees, then minutes, then seconds, then decimals
        /// of a second), and which values do that is up to the application that drew the text.
        public var angleDecimalPlaces: Int?

        public init(
            decimalPlaces: Int? = nil, zeroSuppression: Int? = nil, linearScale: Double? = nil,
            unitSuffix: String? = nil, angleUnitCode: Int? = nil, angleDecimalPlaces: Int? = nil
        ) {
            self.decimalPlaces = decimalPlaces
            self.zeroSuppression = zeroSuppression
            self.linearScale = linearScale
            self.unitSuffix = unitSuffix
            self.angleUnitCode = angleUnitCode
            self.angleDecimalPlaces = angleDecimalPlaces
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

        /// The unit ``angleUnitCode`` names, or `nil` when the record does not state one or the code
        /// is not one of the four.
        public var angleUnit: AngleUnit? { angleUnitCode.flatMap(AngleUnit.init(code:)) }

        /// `true` when the record states a ``angleUnitCode`` that is not one of the four, which
        /// is what tells it from one that states none: ``angleUnit`` is `nil` for both.
        public var hasUnrecognisedAngleUnit: Bool { angleUnitCode != nil && angleUnit == nil }

        /// The decimal places an angle is shown with: ``angleDecimalPlaces``, or ``decimalPlaces``
        /// where that is `-1` (`DIMADEC` then uses `DIMDEC`). `nil` when the one that applies is
        /// not stated: the places the application then uses are its own, which the reader does not
        /// know.
        public var effectiveAngleDecimalPlaces: Int? {
            angleDecimalPlaces == -1 ? decimalPlaces : angleDecimalPlaces
        }

        /// These variables, with every one that is not stated taken from `base`.
        public func filling(from base: Variables) -> Variables {
            Variables(
                decimalPlaces: decimalPlaces ?? base.decimalPlaces,
                zeroSuppression: zeroSuppression ?? base.zeroSuppression,
                linearScale: linearScale ?? base.linearScale,
                unitSuffix: unitSuffix ?? base.unitSuffix,
                angleUnitCode: angleUnitCode ?? base.angleUnitCode,
                angleDecimalPlaces: angleDecimalPlaces ?? base.angleDecimalPlaces)
        }
    }

    /// The unit an angular dimension shows its value in (`DIMAUNIT`).
    ///
    /// The text of each is what AutoCAD writes, and what `ezdxf` writes: `45.5°`, `45°30'15"`,
    /// `50.5g` and `0.7854r`.
    public enum AngleUnit: Int, Equatable, Sendable {
        /// `0`: decimal degrees, `45.5°`.
        case decimalDegrees = 0
        /// `1`: degrees, minutes and seconds, `45°30'15"`.
        case degreesMinutesSeconds = 1
        /// `2`: gradians, `50.5g`, a right angle being 100.
        case gradians = 2
        /// `3`: radians, `0.7854r`.
        case radians = 3

        /// The unit `DIMAUNIT` value `code` names, or `nil` for any other number.
        public init?(code: Int) { self.init(rawValue: code) }

        /// The `DIMAUNIT` value.
        public var code: Int { rawValue }
    }
}
