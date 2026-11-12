extension DXF {
    /// Base `DIMENSION` type, decoded from group 70's low 4 bits (`raw & 15`).
    ///
    /// Uses the same masking `ezdxf`'s `Dimension.dimtype` applies to strip the independent flag
    /// bits (32/64/128).
    public enum DimensionType: Sendable, Equatable {
        /// Group 70 value `0`: a rotated, horizontal, or vertical linear dimension.
        case linear
        case aligned
        case angular
        case diameter
        case radius
        case angular3Point
        case ordinate
        /// An unrecognised base type (values `7…15`; the DXF spec defines none).
        case unknown(Int)

        init(group70 raw: Int) {
            switch raw & 15 {
            case 0: self = .linear
            case 1: self = .aligned
            case 2: self = .angular
            case 3: self = .diameter
            case 4: self = .radius
            case 5: self = .angular3Point
            case 6: self = .ordinate
            default: self = .unknown(raw & 15)
            }
        }
    }

    /// A `DIMENSION` entity. Which definition points are populated depends on ``DimensionType``:
    /// - `.linear` / `.aligned`: `defPoint` is the dimension line location; `defPoint2`/`defPoint3`
    ///   are the two extension-line origins (the witness points, groups 13/14).
    /// - `.radius` / `.diameter`: `defPoint` and `defPoint4` are the two ends of the measured
    ///   radius/diameter (group 10 and 15); `defPoint2`/`defPoint3` are unused.
    /// - `.angular` / `.angular3Point`: `defPoint`…`defPoint4` bound the two measured lines/rays,
    ///   and `defPoint5` (group 16) is the dimension arc's location.
    public struct Dimension: Sendable {
        public var kind: DimensionType
        /// The measurement stored in the file (group 42), in drawing units.
        ///
        /// `nil` when the group is absent, zero or negative. Some writers store `-1` to mean
        /// "none"; use ``computedMeasurement`` for the value the geometry gives.
        public var measurement: Double?
        /// User-entered text override (group 1).
        ///
        /// `nil` when the field is absent or empty (the DXF convention for "use the default
        /// formatted measurement"). A literal single space is the convention for "suppress the
        /// dimension text" and is passed through as `" "` verbatim.
        public var textOverride: String?
        /// Midpoint of the dimension text (group 11/21/31).
        public var textPosition: Point
        /// Group 10/20/30, always present; meaning depends on ``kind`` (see above).
        public var defPoint: Point
        /// Group 13/23/33. `nil` when absent (e.g. radius/diameter dimensions).
        public var defPoint2: Point?
        /// Group 14/24/34. `nil` when absent (e.g. radius/diameter dimensions).
        public var defPoint3: Point?
        /// Group 15/25/35. `nil` when absent (e.g. plain linear/aligned dimensions).
        public var defPoint4: Point?
        /// Group 16/26/36, dimension-arc location (angular dimensions only).
        public var defPoint5: Point?
        /// Rotation of a linear dimension's measuring direction, in degrees (group 50).
        ///
        /// `nil` when absent, which means horizontal. For a linear dimension this is what says
        /// whether it measures horizontally, vertically or at another angle.
        public var rotation: Double?
        /// Oblique angle of the extension lines, in degrees (group 52), or `nil` when absent.
        public var obliqueAngle: Double?
        /// The name of the dimension style (group 3), or `nil` when absent.
        public var styleName: String?
        /// The style variables this dimension overrides in its own extended data.
        public var styleOverrides: DimensionStyle.Variables
        public var layer: String
        public var color: Int

        public init(
            kind: DimensionType, measurement: Double?, textOverride: String?,
            textPosition: Point, defPoint: Point, defPoint2: Point? = nil,
            defPoint3: Point? = nil, defPoint4: Point? = nil, defPoint5: Point? = nil,
            layer: String, color: Int, rotation: Double? = nil, obliqueAngle: Double? = nil,
            styleName: String? = nil, styleOverrides: DimensionStyle.Variables = .init()
        ) {
            self.kind = kind
            self.measurement = measurement
            self.textOverride = textOverride
            self.textPosition = textPosition
            self.defPoint = defPoint
            self.defPoint2 = defPoint2
            self.defPoint3 = defPoint3
            self.defPoint4 = defPoint4
            self.defPoint5 = defPoint5
            self.layer = layer
            self.color = color
            self.rotation = rotation
            self.obliqueAngle = obliqueAngle
            self.styleName = styleName
            self.styleOverrides = styleOverrides
        }
    }
}
