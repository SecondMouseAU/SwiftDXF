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
    /// A file can multiply entities without bound (an array of arrays, or a block that holds ten
    /// references to the next), so expansion stops after about `limit` entities and says so.
    mutating func expandBlockReferences(limit: Int = 2_000_000) {
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
            for row in 0..<ref.rows {
                for column in 0..<ref.columns {
                    guard budget > 0 else {
                        truncated = true
                        return
                    }
                    budget -= max(block.entities.count, 1)
                    let t = outer.composed(
                        with: DXF.Transform(
                            reference: ref, base: block.basePoint, column: column, row: row))
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
