import Foundation

extension DXF {
    /// One row of the `LAYER` table.
    public struct Layer: Equatable, Sendable {
        public var name: String
        /// AutoCAD Color Index (group 62, sign removed).
        public var color: Int
        /// The layer is switched off (a negative colour in the file).
        public var isOff: Bool
        /// The layer is frozen (flag bit 1).
        public var isFrozen: Bool
        /// The layer is locked (flag bit 4).
        public var isLocked: Bool
        /// The name of the layer's line type (group 6).
        public var lineType: String

        /// Whether entities on the layer are drawn: neither off nor frozen.
        public var isVisible: Bool { !isOff && !isFrozen }

        public init(
            name: String, color: Int = 7, isOff: Bool = false, isFrozen: Bool = false,
            isLocked: Bool = false, lineType: String = "Continuous"
        ) {
            self.name = name
            self.color = color
            self.isOff = isOff
            self.isFrozen = isFrozen
            self.isLocked = isLocked
            self.lineType = lineType
        }
    }

    /// One row of the `LTYPE` table.
    public struct LineType: Equatable, Sendable {
        public var name: String
        public var description: String
        /// The dash pattern (group 49): positive is a dash, negative a gap, zero a dot.
        public var pattern: [Double]
        /// Total pattern length (group 40).
        public var patternLength: Double

        /// Whether the line is solid: no dash pattern.
        public var isContinuous: Bool { pattern.isEmpty }

        public init(
            name: String, description: String = "", pattern: [Double] = [],
            patternLength: Double = 0
        ) {
            self.name = name
            self.description = description
            self.pattern = pattern
            self.patternLength = patternLength
        }
    }
}

extension DXF.Drawing {
    /// The layer named `name`, compared case-insensitively.
    public func layer(named name: String) -> DXF.Layer? {
        layers[name] ?? layers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    /// The layer of the entity at `index` of ``entities``.
    public func layer(at index: Int) -> DXF.Layer? {
        guard entities.indices.contains(index) else { return nil }
        return layer(named: entities[index].layer)
    }

    /// The name of the line type of the entity at `index`: the one it names, or its layer's when
    /// it says by-layer, or `Continuous` when neither is known.
    ///
    /// An unexpanded `BYBLOCK` is returned as written.
    public func lineTypeName(at index: Int) -> String {
        let raw = entityLineTypes.indices.contains(index) ? entityLineTypes[index] : nil
        if let raw, raw.uppercased() != "BYLAYER" { return raw }
        return layer(at: index)?.lineType ?? "Continuous"
    }

    /// The line type of the entity at `index`, or `nil` when the table does not define it.
    public func lineType(at index: Int) -> DXF.LineType? {
        let name = lineTypeName(at: index)
        return lineTypeTable[name]
            ?? lineTypeTable.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    /// The index in ``entities`` of the entity with this handle (any case), or `nil`.
    public func index(ofHandle handle: String) -> Int? {
        let wanted = handle.uppercased()
        return identities.firstIndex { $0.handle == wanted && $0.via.isEmpty }
    }
}
