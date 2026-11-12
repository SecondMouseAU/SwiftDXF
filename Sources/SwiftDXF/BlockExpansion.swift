import Foundation

extension DXF.Drawing {
    /// Flattens every top-level block reference into ``entities``, ``hatches`` and ``leaders``.
    ///
    /// Nested references, scale, rotation, mirroring and the array form are carried through. An
    /// expanded entity on layer `0` takes the reference's layer, `BYBLOCK` colour and line type
    /// take the reference's, and the identity of each expanded entity lists the references it came
    /// through. The expanded `INSERT`s leave ``skipped``; what a block holds that has no entity
    /// form is added to it instead.
    mutating func expandBlockReferences() {
        let blockByName = Dictionary(
            blocks.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { first, _ in first })
        let layerTable = Dictionary(
            layers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { first, _ in first })
        var missing: [String: Int] = [:]
        var cycles: [String] = []
        var tooDeep: [String] = []
        var dropped: [String: Int] = [:]
        var tilted = 0
        let maxDepth = 32

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
                lineType = layerRow?.lineType ?? "Continuous"
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
            let arrayed = ref.columns * ref.rows > 1
            for row in 0..<ref.rows {
                for column in 0..<ref.columns {
                    let t = outer.composed(
                        with: DXF.Transform(
                            reference: ref, base: block.basePoint, column: column, row: row))
                    let link = ref.identity.local + (arrayed ? "[\(column),\(row)]" : "")
                    let chain = via + [link]
                    let chainNames = names + [block.name]

                    for (i, entity) in block.entities.enumerated() {
                        guard var moved = entity.transformed(by: t) else {
                            dropped[Self.typeName(of: entity), default: 0] += 1
                            continue
                        }
                        let layerName = entity.layer == "0" ? own.layer : entity.layer
                        let colorIndex = entity.colorIndex == 0 ? own.color : entity.colorIndex
                        moved = moved.replacing(layer: layerName, color: colorIndex)
                        entities.append(moved)
                        var id = block.identities[i]
                        id.via = chain
                        id.blocks = chainNames
                        identities.append(id)
                        entityLineTypes.append(lineType(block.entityLineTypes[i], own))
                    }
                    for hatch in block.hatches {
                        guard var moved = hatch.transformed(by: t) else {
                            dropped["HATCH", default: 0] += 1
                            continue
                        }
                        if moved.layer == "0" { moved.layer = own.layer }
                        if moved.color == 0 { moved.color = own.color }
                        moved.lineType = lineType(moved.lineType, own)
                        moved.identity.via = chain
                        moved.identity.blocks = chainNames
                        hatches.append(moved)
                    }
                    for leader in block.leaders {
                        var moved = leader.transformed(by: t)
                        if moved.layer == "0" { moved.layer = own.layer }
                        if moved.color == 0 { moved.color = own.color }
                        moved.lineType = lineType(moved.lineType, own)
                        moved.identity.via = chain
                        moved.identity.blocks = chainNames
                        leaders.append(moved)
                    }
                    for (type, byLayer) in block.skippedByLayer {
                        for (layerName, count) in byLayer {
                            let target = layerName == "0" ? own.layer : layerName
                            skipped[type, default: 0] += count
                            skippedByLayer[type, default: [:]][target, default: 0] += count
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

        var expanded = 0
        for ref in references {
            let before = missing[ref.name] ?? 0
            visit(ref, outer: DXF.Transform(), parent: nil, via: [], names: [], stack: [])
            if (missing[ref.name] ?? 0) == before {
                expanded += 1
                decrementSkipped("INSERT", layer: ref.layer)
            }
        }
        for name in missing.keys.sorted() {
            warnings.append(.missingBlock(name: name, count: missing[name] ?? 0))
        }
        if tilted > 0 { warnings.append(.unsupportedExtrusion(count: tilted)) }
        for name in cycles { warnings.append(.blockCycle(name: name)) }
        for name in tooDeep { warnings.append(.blockNestingTooDeep(name: name)) }
        for type in dropped.keys.sorted() {
            warnings.append(.notTransformed(type: type, count: dropped[type] ?? 0))
        }
    }

    private mutating func decrementSkipped(_ type: String, layer: String) {
        if let n = skipped[type] { skipped[type] = n > 1 ? n - 1 : nil }
        if var byLayer = skippedByLayer[type] {
            if let n = byLayer[layer] { byLayer[layer] = n > 1 ? n - 1 : nil }
            skippedByLayer[type] = byLayer.isEmpty ? nil : byLayer
        }
    }

    private static func typeName(of entity: DXF.Entity) -> String {
        switch entity {
        case .polyline: return "POLYLINE"
        case .line: return "LINE"
        case .circle: return "CIRCLE"
        case .arc: return "ARC"
        case .ellipse: return "ELLIPSE"
        case .point: return "POINT"
        case .text: return "TEXT"
        case .dimension: return "DIMENSION"
        case .spline: return "SPLINE"
        }
    }
}
