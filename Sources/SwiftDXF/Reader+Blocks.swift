import Foundation

extension DXF.Reader {
    /// Records the `INSERT`, `HATCH` and `LEADER` forms of a record that also stays in `skipped`.
    func recordExtras(
        _ type: String, _ f: [(code: Int, value: String)], section: String, index: Int,
        into dwg: inout DXF.Drawing
    ) {
        let identity = DXF.EntityIdentity(handle: handle(f), section: section, index: index)
        switch type {
        case "INSERT":
            dwg.references.append(blockReference(f, identity: identity))
        case "HATCH":
            dwg.hatches.append(hatch(f, identity: identity))
        case "LEADER":
            dwg.leaders.append(leader(f, identity: identity))
        default:
            break
        }
    }

    func blockReference(
        _ f: [(code: Int, value: String)], identity: DXF.EntityIdentity
    ) -> DXF.BlockReference {
        DXF.BlockReference(
            name: nonEmpty(first(2, f)) ?? "", insertion: point(f), scaleX: dbl(41, f, 1),
            scaleY: dbl(42, f, 1), scaleZ: dbl(43, f, 1), rotation: dbl(50, f),
            columns: max(ints(70, f) ?? 1, 1), rows: max(ints(71, f) ?? 1, 1),
            columnSpacing: dbl(44, f), rowSpacing: dbl(45, f), layer: layer(f), color: color(f),
            lineType: nonEmpty(first(6, f)),
            extrusion: DXF.Point(dbl(210, f, 0), dbl(220, f, 0), dbl(230, f, 1)),
            identity: identity)
    }

    func leader(_ f: [(code: Int, value: String)], identity: DXF.EntityIdentity) -> DXF.Leader {
        let annotation: DXF.Leader.Annotation
        switch ints(73, f) ?? 3 {
        case 0: annotation = .text
        case 1: annotation = .tolerance
        case 2: annotation = .blockReference
        default: annotation = .none
        }
        return DXF.Leader(
            vertices: splinePoints(10, f), hasArrowhead: (ints(71, f) ?? 1) == 1,
            isSpline: (ints(72, f) ?? 0) == 1, annotation: annotation,
            annotationHandle: nonEmpty(first(340, f)).map { $0.uppercased() },
            styleName: nonEmpty(first(3, f)), layer: layer(f), color: color(f),
            lineType: nonEmpty(first(6, f)), identity: identity)
    }

    /// Reads the `BLOCKS` section into ``Drawing/blocks``.
    mutating func readBlocks(into dwg: inout DXF.Drawing) {
        var k = 0
        var start: Int?
        while k + 1 < pairs.count {
            if pairs[k].code == 0, trimmed(pairs[k].value) == "SECTION", pairs[k + 1].code == 2,
                trimmed(pairs[k + 1].value) == "BLOCKS"
            {
                start = k + 2
                break
            }
            k += 1
        }
        guard var i = start else { return }
        while i < pairs.count {
            guard pairs[i].code == 0 else {
                i += 1
                continue
            }
            let type = trimmed(pairs[i].value)
            if type == "ENDSEC" || type == "EOF" { return }
            guard type == "BLOCK" else {
                i += 1
                continue
            }
            var j = i + 1
            var header: [(code: Int, value: String)] = []
            while j < pairs.count, pairs[j].code != 0 {
                header.append(pairs[j])
                j += 1
            }
            let name = nonEmpty(first(2, header)) ?? ""
            var contents = DXF.Drawing()
            let end = readRecords(
                from: j, section: "BLOCKS:\(name)", terminators: ["ENDBLK", "ENDSEC", "EOF"],
                into: &contents)
            let lowered = name.lowercased()
            if !name.isEmpty, !lowered.hasPrefix("*model_space"),
                !lowered.hasPrefix("*paper_space")
            {
                var block = DXF.Block(name: name, basePoint: point(header))
                block.entities = contents.entities
                block.identities = contents.identities
                block.entityLineTypes = contents.entityLineTypes
                block.hatches = contents.hatches
                block.leaders = contents.leaders
                block.references = contents.references
                var skipped = contents.skippedByLayer
                skipped["INSERT"] = nil
                block.skippedByLayer = skipped
                dwg.blocks[name] = block
            }
            i = end
            if end < pairs.count, trimmed(pairs[end].value) == "ENDBLK" { i = end + 1 }
            if end < pairs.count, ["ENDSEC", "EOF"].contains(trimmed(pairs[end].value)) { return }
        }
    }
}
