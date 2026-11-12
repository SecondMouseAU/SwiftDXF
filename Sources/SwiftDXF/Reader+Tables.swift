import Foundation

extension DXF.Reader {
    /// The record handle (group 5), trimmed and upper case, or `nil` when absent or empty.
    func handle(_ fields: [(code: Int, value: String)]) -> String? {
        nonEmpty(first(5, fields)).map { $0.uppercased() }
    }

    /// The trimmed string, or `nil` when it is absent or empty.
    func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let t = trimmed(value)
        return t.isEmpty ? nil : t
    }

    /// The records of a named `TABLES` table: each `0`-tagged record of `type` with its fields.
    func tableRecords(_ type: String) -> [[(code: Int, value: String)]] {
        var out: [[(code: Int, value: String)]] = []
        var k = 0
        var inTables = false
        while k < pairs.count {
            let p = pairs[k]
            if p.code == 0, trimmed(p.value) == "SECTION", k + 1 < pairs.count,
                pairs[k + 1].code == 2
            {
                inTables = trimmed(pairs[k + 1].value) == "TABLES"
                k += 2
                continue
            }
            if p.code == 0, trimmed(p.value) == "ENDSEC" { inTables = false }
            if inTables, p.code == 0, trimmed(p.value) == type {
                var fields: [(code: Int, value: String)] = []
                var m = k + 1
                while m < pairs.count, pairs[m].code != 0 {
                    fields.append(pairs[m])
                    m += 1
                }
                out.append(fields)
                k = m
                continue
            }
            k += 1
        }
        return out
    }

    /// The `DIMSTYLE` table by style name.
    ///
    /// Fields a style does not carry stay `nil`.
    func dimensionStyles() -> [String: DXF.DimensionStyle] {
        var out: [String: DXF.DimensionStyle] = [:]
        for fields in tableRecords("DIMSTYLE") {
            guard let name = nonEmpty(first(2, fields)) else { continue }
            out[name] = DXF.DimensionStyle(
                name: name, decimals: ints(271, fields), suffix: nonEmpty(first(3, fields)),
                linearScale: dblOpt(144, fields))
        }
        return out
    }

    /// The `DSTYLE` overrides in an entity's extended data.
    ///
    /// They follow `1001 ACAD`, `1000 DSTYLE`, `1002 {` as pairs of a `1070` variable number and
    /// its value, up to `1002 }`.
    func styleOverrides(_ fields: [(code: Int, value: String)]) -> DXF.DimensionStyle.Overrides {
        var out = DXF.DimensionStyle.Overrides()
        guard
            let start = fields.indices.first(where: {
                fields[$0].code == 1000 && trimmed(fields[$0].value) == "DSTYLE"
            })
        else { return out }
        var k = start + 1
        if k < fields.count, fields[k].code == 1002, trimmed(fields[k].value) == "{" { k += 1 }
        while k + 1 < fields.count {
            if fields[k].code == 1002 { break }
            guard fields[k].code == 1070, let variable = Int(trimmed(fields[k].value)) else {
                k += 1
                continue
            }
            let value = fields[k + 1].value
            switch variable {
            case 271: out.decimals = Int(trimmed(value))
            case 3: out.suffix = nonEmpty(value)
            case 144: out.linearScale = Double(trimmed(value))
            default: break
            }
            k += 2
        }
        return out
    }
}
