extension DXF.Contour {
    /// Length units a drawing can be authored in, with the `$INSUNITS` code of each.
    public enum LengthUnit: Int, Sendable, CaseIterable {
        case inch = 1
        case foot = 2
        case mile = 3
        case millimetre = 4
        case centimetre = 5
        case metre = 6
        case kilometre = 7
        case microinch = 8
        case mil = 9
        case yard = 10
        case micron = 13
        case decimetre = 14

        /// Millimetres in one of this unit.
        public var millimetres: Double {
            switch self {
            case .inch: return 25.4
            case .foot: return 304.8
            case .mile: return 1_609_344
            case .millimetre: return 1
            case .centimetre: return 10
            case .metre: return 1000
            case .kilometre: return 1_000_000
            case .microinch: return 0.0000254
            case .mil: return 0.0254
            case .yard: return 914.4
            case .micron: return 0.001
            case .decimetre: return 100
            }
        }

        /// The unit for an `$INSUNITS` code, or `nil` for `0` (unitless) and unmodelled codes.
        public init?(insUnits code: Int) {
            self.init(rawValue: code)
        }
    }

    /// How loops nest into shapes.
    public enum NestingRule: Sendable {
        /// A loop inside one loop is a hole, inside two is an island, and so on (the usual CAD
        /// reading, and the default).
        case evenOdd
        /// Only loops not inside any other become shapes, with no holes. Nested loops are dropped.
        case outermostOnly
    }

    /// Settings for ``DXF/Drawing/contours(_:)``.
    ///
    /// Tolerances are in millimetres.
    public struct Options: Equatable, Sendable {
        /// Layers to read (compared case-insensitively). `nil` reads every layer.
        public var layers: Set<String>?
        /// Layers to skip, applied after ``layers``.
        public var excludedLayers: Set<String> = []
        /// Endpoints closer than this are joined.
        ///
        /// Default `0.01`.
        public var joinTolerance: Double = 0.01
        /// Maximum distance from a fitted line or arc to the curve it replaces.
        ///
        /// Default `0.01`.
        public var fitTolerance: Double = 0.01
        /// Forces the drawing's units, ignoring `$INSUNITS`.
        ///
        /// Use for files that declare the wrong unit.
        public var units: LengthUnit?
        /// Units assumed when the file declares none.
        ///
        /// Applies to code `0`, a missing code, or an unmodelled one, and a warning is reported.
        /// Default millimetres.
        public var unitlessFallback: LengthUnit = .millimetre
        public var nesting: NestingRule = .evenOdd

        public init(
            layers: Set<String>? = nil, excludedLayers: Set<String> = [],
            joinTolerance: Double = 0.01, fitTolerance: Double = 0.01,
            units: LengthUnit? = nil, unitlessFallback: LengthUnit = .millimetre,
            nesting: NestingRule = .evenOdd
        ) {
            self.layers = layers
            self.excludedLayers = excludedLayers
            self.joinTolerance = joinTolerance
            self.fitTolerance = fitTolerance
            self.units = units
            self.unitlessFallback = unitlessFallback
            self.nesting = nesting
        }
    }
}
