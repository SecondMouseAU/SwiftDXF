extension DXF.Tolerance {
    /// One row of a feature control frame: a characteristic, its tolerance and its datums.
    ///
    /// The boxes of a row are, in order, the symbol, the first and second tolerance, and up to
    /// three datums, separated by `%%v` in the string.
    public struct Frame: Equatable, Sendable {
        /// The row as the string writes it.
        public var raw: String
        /// What the frame controls, from the symbol of its first box, or `nil` when that box is
        /// empty, as in the second row of a composite frame.
        public var characteristic: Characteristic?
        /// The first tolerance box, or `nil` when it is empty.
        public var tolerance: Zone?
        /// The second tolerance box, or `nil` when it is empty.
        public var secondTolerance: Zone?
        /// The datums the frame refers to, in order; an empty box is left out.
        public var datums: [Datum]
        /// What the reader kept as written because it did not understand it: a symbol in a
        /// tolerance or datum box that is not a diameter or a material condition, and the text of
        /// any box after the sixth.
        public var unread: [String]

        public init(
            raw: String, characteristic: Characteristic? = nil, tolerance: Zone? = nil,
            secondTolerance: Zone? = nil, datums: [Datum] = [], unread: [String] = []
        ) {
            self.raw = raw
            self.characteristic = characteristic
            self.tolerance = tolerance
            self.secondTolerance = secondTolerance
            self.datums = datums
            self.unread = unread
        }

        /// Whether the symbol was recognised and nothing was kept as written; see ``unread``.
        public var isFullyRead: Bool {
            if case .unrecognised? = characteristic { return false }
            return unread.isEmpty
        }
    }

    /// What a feature control frame controls, from the letter of a symbol in the GDT font.
    ///
    /// The letters are those of `gdt.shx`, the font AutoCAD writes a TOLERANCE in
    /// (`{\Fgdt;j}` is position).
    public enum Characteristic: Equatable, Sendable {
        case angularity
        case perpendicularity
        case flatness
        case profileOfSurface
        case circularity
        case parallelism
        case cylindricity
        case circularRunout
        case symmetry
        case position
        case profileOfLine
        case concentricity
        case totalRunout
        case straightness
        /// A first box that is not one of the symbols above, kept as written.
        case unrecognised(String)
    }

    /// A tolerance box: the size of the tolerance zone and how it is modified.
    public struct Zone: Equatable, Sendable {
        /// Whether the zone is a diameter (`%%c` or the GDT font's `n` before the value).
        public var isDiameter: Bool
        /// The tolerance as a number, or `nil` when the box does not hold one.
        ///
        /// A comma is read as the decimal mark when there is no point.
        public var value: Double?
        /// The text of the box without the diameter, material condition and projection read from it.
        public var text: String
        public var materialCondition: MaterialCondition?
        /// Whether the zone is projected (`{\Fgdt;p}` after the value).
        public var isProjected: Bool

        public init(
            isDiameter: Bool = false, value: Double? = nil, text: String = "",
            materialCondition: MaterialCondition? = nil, isProjected: Bool = false
        ) {
            self.isDiameter = isDiameter
            self.value = value
            self.text = text
            self.materialCondition = materialCondition
            self.isProjected = isProjected
        }
    }

    /// A datum box: the datum named, with its material condition.
    public struct Datum: Equatable, Sendable {
        /// The datum as written, such as `B`.
        public var reference: String
        public var materialCondition: MaterialCondition?

        public init(reference: String, materialCondition: MaterialCondition? = nil) {
            self.reference = reference
            self.materialCondition = materialCondition
        }
    }

    /// A material condition modifier, the circled letter after a value or a datum.
    public enum MaterialCondition: Equatable, Sendable {
        /// `{\Fgdt;m}`, M.
        case maximum
        /// `{\Fgdt;l}`, L.
        case least
        /// `{\Fgdt;s}`, S: regardless of feature size.
        case regardlessOfFeatureSize
    }
}
