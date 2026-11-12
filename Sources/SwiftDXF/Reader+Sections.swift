import Foundation

extension DXF.Reader {
    /// Index of the first pair *after* the `2`/`name` tag of the `SECTION` called `name`.
    func sectionStart(_ name: String) -> Int? {
        var k = 0
        while k + 1 < pairs.count {
            if pairs[k].code == 0, trimmed(pairs[k].value) == "SECTION",
                pairs[k + 1].code == 2, trimmed(pairs[k + 1].value) == name
            {
                return k + 2
            }
            k += 1
        }
        return nil
    }

    /// The block definitions of the `BLOCKS` section, in file order.
    ///
    /// A block runs from its `BLOCK` record to the `ENDBLK` that closes it. Its entities are read
    /// the same way model space is, and each carries a locator of the form `BLOCKS:<block>/<n>`.
    ///
    /// Also returns, by record type, how many entities of the blocks have an extrusion that is not
    /// along z.
    func blocks() -> (blocks: [DXF.Block], tilted: [String: Int]) {
        guard var k = sectionStart("BLOCKS") else { return ([], [:]) }
        var out: [DXF.Block] = []
        var tilted: [String: Int] = [:]
        while k < pairs.count {
            guard pairs[k].code == 0 else {
                k += 1
                continue
            }
            let type = trimmed(pairs[k].value)
            if type == "ENDSEC" || type == "EOF" { break }
            guard type == "BLOCK" else {
                k += 1
                continue
            }
            let (fields, j) = recordFields(after: k)
            let index = out.count
            let name = (first(2, fields) ?? first(3, fields)).map(trimmed) ?? ""
            let run = readEntities(from: j, stopAt: ["ENDBLK", "BLOCK", "ENDSEC", "EOF"]) {
                "BLOCKS:\(index)/\($0)"
            }
            tilted.merge(run.tilted, uniquingKeysWith: +)
            var skipped = run.skippedByLayer
            skipped["INSERT"] = nil
            out.append(
                DXF.Block(
                    name: name,
                    identity: DXF.Identity(handle: handle(fields), locator: "BLOCKS:\(index)"),
                    basePoint: point(fields), entities: run.entities,
                    identities: run.identities, entityLineTypes: run.lineTypes,
                    references: run.references, skippedByLayer: skipped))
            k = run.end
            // Step over the ENDBLK so the next BLOCK is found, not the ENDBLK again.
            if k < pairs.count, trimmed(pairs[k].value) == "ENDBLK" { k += 1 }
        }
        return (out, tilted)
    }
}
