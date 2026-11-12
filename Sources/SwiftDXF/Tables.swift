extension DXF {
    /// A record of the `LAYER` table.
    public struct Layer: Equatable, Sendable {
        public var name: String
        public var identity: Identity
        /// The AutoCAD Color Index of the layer (group 62, without the sign).
        public var color: Int
        /// The layer's line type name (group 6).
        public var lineTypeName: String
        /// `true` when the layer is switched off (a negative colour in group 62).
        public var isOff: Bool
        /// Flag bit 1: the layer is frozen.
        public var isFrozen: Bool
        /// Flag bit 4: the layer is locked.
        public var isLocked: Bool

        public init(
            name: String, identity: Identity, color: Int = 7, lineTypeName: String = "Continuous",
            isOff: Bool = false, isFrozen: Bool = false, isLocked: Bool = false
        ) {
            self.name = name
            self.identity = identity
            self.color = color
            self.lineTypeName = lineTypeName
            self.isOff = isOff
            self.isFrozen = isFrozen
            self.isLocked = isLocked
        }

        /// The record's handle (group 5), or `nil` when the file has none.
        public var handle: String? { identity.handle }

        /// `false` for a layer that is off or frozen, whose entities the drawing does not show.
        public var isVisible: Bool { !isOff && !isFrozen }
    }

    /// A record of the `LTYPE` table.
    public struct LineType: Equatable, Sendable {
        public var name: String
        public var identity: Identity
        public var description: String
        /// The pattern elements (group 49), empty for a continuous line.
        ///
        /// A positive length is a dash, a negative one a gap and zero a dot.
        public var pattern: [Double]
        /// The total length of one pattern repeat (group 40).
        public var patternLength: Double

        public init(
            name: String, identity: Identity, description: String = "", pattern: [Double] = [],
            patternLength: Double = 0
        ) {
            self.name = name
            self.identity = identity
            self.description = description
            self.pattern = pattern
            self.patternLength = patternLength
        }

        /// The record's handle (group 5), or `nil` when the file has none.
        public var handle: String? { identity.handle }

        /// `true` when the pattern has no gaps, so the line is drawn solid.
        public var isContinuous: Bool { pattern.isEmpty }
    }

    /// A record of the `DIMSTYLE` table.
    public struct DimensionStyle: Equatable, Sendable {
        public var name: String
        public var identity: Identity
        /// The variables the record states: decimal places, zero suppression, scale and suffix.
        public var variables: Variables

        public init(name: String, identity: Identity, variables: Variables = .init()) {
            self.name = name
            self.identity = identity
            self.variables = variables
        }

        /// The record's handle (group 105), or `nil` when the file has none.
        public var handle: String? { identity.handle }
    }
}
