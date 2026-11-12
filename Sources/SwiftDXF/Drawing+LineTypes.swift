extension DXF.Drawing {
    /// The layer record called `name`, compared case-insensitively.
    public func layer(named name: String) -> DXF.Layer? {
        let key = name.lowercased()
        return layers.first { $0.name.lowercased() == key }
    }

    /// The line type record called `name`, compared case-insensitively.
    public func lineType(named name: String) -> DXF.LineType? {
        let key = name.lowercased()
        return lineTypes.first { $0.name.lowercased() == key }
    }

    /// The line type name written on the entity at `index` (group 6), or `nil` when it has none.
    public func lineTypeName(ofEntityAt index: Int) -> String? {
        entityLineTypes.indices.contains(index) ? entityLineTypes[index] : nil
    }

    /// The name of the line type the entity at `index` is drawn with.
    ///
    /// An entity with no line type, or `BYLAYER`, takes its layer's. `BYBLOCK` is `Continuous` for
    /// model-space entities, which have no block to take it from. A named type is returned with
    /// the spelling of the `LTYPE` table when the table has it. Use ``lineType(named:)`` for the
    /// dash pattern.
    public func effectiveLineType(ofEntityAt index: Int) -> String {
        guard index >= 0, index < entities.count else { return Self.continuous }
        let written = lineTypeName(ofEntityAt: index)
        let name: String
        switch written?.uppercased() {
        case nil, "BYLAYER":
            name = layer(named: entities[index].layer)?.lineTypeName ?? Self.continuous
        case "BYBLOCK":
            name = Self.continuous
        default:
            name = written ?? Self.continuous
        }
        return lineType(named: name)?.name ?? name
    }

    /// Whether the entity at `index` is on a layer that is on and not frozen.
    ///
    /// An entity on a layer missing from the layer table counts as visible.
    public func isVisible(entityAt index: Int) -> Bool {
        guard index >= 0, index < entities.count else { return false }
        return layer(named: entities[index].layer)?.isVisible ?? true
    }

    private static let continuous = "Continuous"
}
