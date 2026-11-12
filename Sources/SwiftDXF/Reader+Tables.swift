import Foundation

extension DXF.Reader {
    /// One record of a table, with its fields and its position in the table.
    typealias TableRecord = (fields: [(code: Int, value: String)], index: Int)

    /// The records of the `TABLES`-section table called `name` (`LAYER`, `LTYPE`, …), in file order.
    func tableRecords(_ name: String) -> [TableRecord] {
        var k = 0
        while k + 1 < pairs.count {
            if pairs[k].code == 0, trimmed(pairs[k].value) == "TABLE",
                pairs[k + 1].code == 2, trimmed(pairs[k + 1].value) == name
            {
                return records(of: name, from: k + 2)
            }
            k += 1
        }
        return []
    }

    private func records(of name: String, from start: Int) -> [TableRecord] {
        var out: [TableRecord] = []
        var k = start
        while k < pairs.count {
            guard pairs[k].code == 0 else {
                k += 1
                continue
            }
            let type = trimmed(pairs[k].value)
            if type == "ENDTAB" || type == "ENDSEC" || type == "EOF" { break }
            var fields: [(code: Int, value: String)] = []
            var j = k + 1
            while j < pairs.count && pairs[j].code != 0 {
                fields.append(pairs[j])
                j += 1
            }
            if type == name { out.append((fields, out.count)) }
            k = j
        }
        return out
    }

    private func identity(
        _ record: TableRecord, table: String, handleCode: Int = 5
    ) -> DXF.Identity {
        DXF.Identity(
            handle: handle(record.fields, code: handleCode),
            locator: "TABLES:\(table):\(record.index)")
    }

    private func name(_ record: TableRecord) -> String {
        first(2, record.fields).map(trimmed) ?? ""
    }

    func layers() -> [DXF.Layer] {
        tableRecords("LAYER").map {
            DXF.Layer(name: name($0), identity: identity($0, table: "LAYER"))
        }
    }

    func lineTypes() -> [DXF.LineType] {
        tableRecords("LTYPE").map {
            DXF.LineType(name: name($0), identity: identity($0, table: "LTYPE"))
        }
    }

    /// Dimension styles keep their handle in group 105, not 5.
    func dimensionStyles() -> [DXF.DimensionStyle] {
        tableRecords("DIMSTYLE").map {
            DXF.DimensionStyle(
                name: name($0), identity: identity($0, table: "DIMSTYLE", handleCode: 105))
        }
    }
}
