import Foundation

extension DXF.Drawing {
    /// Flattens every top-level block reference into ``entities``.
    ///
    /// Nested references, scale, rotation, mirroring and the array form are carried through. An
    /// expanded entity on layer `0` takes the reference's layer, `BYBLOCK` colour and line type
    /// take the reference's, and the identity of each expanded entity lists the references it came
    /// through. The expanded `INSERT`s leave ``skipped``; what a block holds that has no entity
    /// form is added to it instead.
    ///
    /// With `attributes`, the visible attributes of each reference come through as `TEXT` too, and
    /// the constant ones of its block (see ``ReadOptions/expandAttributes``). The identity of such
    /// an entity names its reference in `via`, and an attribute is where the file drew it, in the
    /// space the reference is in, so only the transform of that space applies to it.
    ///
    /// A file can multiply entities without bound (an array of arrays, or a block that holds ten
    /// references to the next), so expansion stops after about `limit` entities and says so.
    mutating func expandBlockReferences(limit: Int = 2_000_000, attributes: Bool = false) {
        let blockByName = Dictionary(
            blocks.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        let layerTable = Dictionary(
            layers.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        var missing: [String: Int] = [:]
        var cycles: [String] = []
        var tooDeep: [String] = []
        var dropped: [String: Int] = [:]
        var tilted = 0
        var truncated = false
        var budget = limit
        let maxDepth = 32

        // Assigning `entities` clears the parallel arrays, so they are rebuilt aside and put back.
        var newEntities = entities
        var newIdentities = identities
        var newLineTypes = entityLineTypes
        var newTextContents = textContents
        var newCounts = counts
        var newSkipped = skipped
        var newSkippedByLayer = skippedByLayer

        /// What entities inside a reference inherit from it.
        struct Inherited {
            var layer: String
            var color: Int
            var lineType: String
        }

        func inherited(by ref: DXF.BlockReference, parent: Inherited?) -> Inherited {
            let layer = ref.layer == "0" ? (parent?.layer ?? ref.layer) : ref.layer
            let layerRow = layerTable[layer.lowercased()]
            let color: Int
            switch ref.color {
            case 0: color = parent?.color ?? 256
            case 256: color = layerRow?.color ?? 256
            default: color = ref.color
            }
            let raw = ref.lineType
            let lineType: String
            if let raw, raw.uppercased() == "BYBLOCK" {
                lineType = parent?.lineType ?? "Continuous"
            } else if let raw, raw.uppercased() != "BYLAYER" {
                lineType = raw
            } else {
                lineType = layerRow?.lineTypeName ?? "Continuous"
            }
            return Inherited(layer: layer, color: color, lineType: lineType)
        }

        func lineType(_ raw: String?, _ own: Inherited) -> String? {
            raw?.uppercased() == "BYBLOCK" ? own.lineType : raw
        }

        /// Adds `attribute`, carried through `map`, as a `TEXT`.
        ///
        /// Layer `0` takes `zeroLayer` when there is one, and `BYBLOCK` colour takes `blockColor`.
        func addText(
            _ attribute: DXF.Attribute, by map: DXF.Transform, zeroLayer: String?, blockColor: Int,
            via chain: [String], blocks chainNames: [String]
        ) {
            let moved = attribute.transformed(by: map)
            let layerName = moved.layer == "0" ? (zeroLayer ?? moved.layer) : moved.layer
            let colorIndex = moved.color == 0 ? blockColor : moved.color
            let entity = moved.textEntity.replacing(layer: layerName, color: colorIndex)
            newEntities.append(entity)
            newCounts.record(entity)
            var id = moved.identity
            id.via = chain
            id.blocks = chainNames
            newIdentities.append(id)
            newLineTypes.append(nil)
            newTextContents.append(moved.content)
        }

        func visit(
            _ ref: DXF.BlockReference, outer: DXF.Transform, parent: Inherited?, via: [String],
            names: [String], stack: [String]
        ) {
            let key = ref.name.lowercased()
            guard let block = blockByName[key] else {
                missing[ref.name, default: 0] += 1
                return
            }
            guard !stack.contains(key) else {
                cycles.append(ref.name)
                return
            }
            guard stack.count < maxDepth else {
                tooDeep.append(ref.name)
                return
            }
            if !DXF.Transform.supportsExtrusion(ref.extrusion) { tilted += 1 }
            let own = inherited(by: ref, parent: parent)
            let arrayed = ref.columns > 1 || ref.rows > 1
            let aligned = block.identities.count == block.entities.count
            let lineTypesAligned = block.entityLineTypes.count == block.entities.count
            let textsAligned = block.textContents.count == block.entities.count
            // The constant attributes of the block, and the visible ones of the reference.
            let constants =
                attributes
                ? block.attributeDefinitions.filter { $0.isConstant && !$0.isInvisible } : []
            let carried = attributes ? ref.attributes.filter { !$0.isInvisible } : []
            let home = DXF.Transform(reference: ref, base: block.basePoint, column: 0, row: 0)
            for row in 0..<ref.rows {
                for column in 0..<ref.columns {
                    guard budget > 0 else {
                        truncated = true
                        return
                    }
                    budget -= max(block.entities.count + constants.count + carried.count, 1)
                    let placed = DXF.Transform(
                        reference: ref, base: block.basePoint, column: column, row: row)
                    let t = outer.composed(with: placed)
                    let link =
                        (ref.identity.handle ?? ref.identity.locator)
                        + (arrayed ? "[\(column),\(row)]" : "")
                    let chain = via + [link]
                    let chainNames = names + [block.name]

                    for (i, entity) in block.entities.enumerated() {
                        guard var moved = entity.transformed(by: t) else {
                            dropped[entity.typeName, default: 0] += 1
                            continue
                        }
                        let layerName = entity.layer == "0" ? own.layer : entity.layer
                        let colorIndex = entity.colorIndex == 0 ? own.color : entity.colorIndex
                        moved = moved.replacing(layer: layerName, color: colorIndex)
                        newEntities.append(moved)
                        newCounts.record(moved)
                        var id =
                            aligned
                            ? block.identities[i]
                            : DXF.Identity(locator: "\(block.identity.locator)/\(i)")
                        id.via = chain
                        id.blocks = chainNames
                        newIdentities.append(id)
                        newLineTypes.append(
                            lineType(lineTypesAligned ? block.entityLineTypes[i] : nil, own))
                        newTextContents.append(textsAligned ? block.textContents[i] : nil)
                    }
                    for definition in constants {
                        addText(
                            DXF.Attribute(definition), by: t, zeroLayer: own.layer,
                            blockColor: own.color, via: chain, blocks: chainNames)
                    }
                    if !carried.isEmpty {
                        // The reference's own place in its space, moved to this instance of an
                        // array; the block's base point and scale do not apply to a value. It is
                        // in the enclosing block's space, so layer `0` there takes that block's
                        // reference's layer; BYBLOCK is the reference it belongs to.
                        var shift = DXF.Transform()
                        shift.tx = placed.tx - home.tx
                        shift.ty = placed.ty - home.ty
                        for attribute in carried {
                            addText(
                                attribute, by: outer.composed(with: shift),
                                zeroLayer: parent?.layer, blockColor: own.color, via: chain,
                                blocks: chainNames)
                        }
                    }
                    for (type, byLayer) in block.skippedByLayer {
                        for (layerName, count) in byLayer {
                            let target = layerName == "0" ? own.layer : layerName
                            newSkipped[type, default: 0] += count
                            newSkippedByLayer[type, default: [:]][target, default: 0] += count
                        }
                    }
                    for nested in block.references {
                        visit(
                            nested, outer: t, parent: own, via: chain, names: chainNames,
                            stack: stack + [key])
                    }
                }
            }
        }

        for ref in references {
            let before = missing[ref.name] ?? 0
            visit(ref, outer: DXF.Transform(), parent: nil, via: [], names: [], stack: [])
            if (missing[ref.name] ?? 0) == before {
                Self.decrement(&newSkipped, &newSkippedByLayer, "INSERT", layer: ref.layer)
            }
        }
        entities = newEntities
        identities = newIdentities
        entityLineTypes = newLineTypes
        textContents = newTextContents
        counts = newCounts
        skipped = newSkipped
        skippedByLayer = newSkippedByLayer
        for name in missing.keys.sorted() {
            warnings.append(.missingBlock(name: name, count: missing[name] ?? 0))
        }
        if tilted > 0 { warnings.append(.unsupportedExtrusion(count: tilted)) }
        for name in cycles { warnings.append(.blockCycle(name: name)) }
        for name in tooDeep { warnings.append(.blockNestingTooDeep(name: name)) }
        if truncated { warnings.append(.expansionTruncated(limit: limit)) }
        for type in dropped.keys.sorted() {
            warnings.append(.notTransformed(type: type, count: dropped[type] ?? 0))
        }
    }

    /// Takes one `type` entity on `layer` out of the skipped counts.
    private static func decrement(
        _ skipped: inout [String: Int], _ byLayer: inout [String: [String: Int]], _ type: String,
        layer: String
    ) {
        if let n = skipped[type] { skipped[type] = n > 1 ? n - 1 : nil }
        if var layers = byLayer[type] {
            if let n = layers[layer] { layers[layer] = n > 1 ? n - 1 : nil }
            byLayer[type] = layers.isEmpty ? nil : layers
        }
    }
}
