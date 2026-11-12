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
    func blocks() -> [DXF.Block] {
        guard var k = sectionStart("BLOCKS") else { return [] }
        var out: [DXF.Block] = []
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
            var fields: [(code: Int, value: String)] = []
            var j = k + 1
            while j < pairs.count && pairs[j].code != 0 {
                fields.append(pairs[j])
                j += 1
            }
            let index = out.count
            let name = (first(2, fields) ?? first(3, fields)).map(trimmed) ?? ""
            let run = readEntities(from: j, stopAt: ["ENDBLK", "ENDSEC", "EOF"]) {
                "BLOCKS:\(index)/\($0)"
            }
            out.append(
                DXF.Block(
                    name: name,
                    identity: DXF.Identity(handle: handle(fields), locator: "BLOCKS:\(index)"),
                    basePoint: point(fields), entities: run.entities,
                    identities: run.identities, entityLineTypes: run.lineTypes))
            k = run.end
            // Step over the ENDBLK so the next BLOCK is found, not the ENDBLK again.
            if k < pairs.count, trimmed(pairs[k].value) == "ENDBLK" { k += 1 }
        }
        return out
    }
}
