import Foundation

extension DXF.Reader {
    /// The variables of the `HEADER` section by name, each with every value the file writes for it.
    ///
    /// A variable written twice keeps its first, which is the one the named header properties have
    /// always read. A file with no `HEADER` section has none.
    func readHeaderVariables() -> [String: DXF.HeaderVariable] {
        guard let start = sectionStart("HEADER") else { return [:] }
        var out: [String: DXF.HeaderVariable] = [:]
        var current: String?
        for pair in pairs[start...] {
            if pair.code == 0 { break }  // ENDSEC, or the next section when there is none
            if pair.code == 9 {
                let name = trimmed(pair.value)
                current = name.isEmpty || out[name] != nil ? nil : name
                if let current { out[current] = DXF.HeaderVariable() }
            } else if let current {
                out[current]?.values.append(.init(code: pair.code, text: pair.value))
            }
        }
        return out
    }

    /// The value pairs of a HEADER variable, or none when the header lacks it.
    func headerVar(_ name: String) -> [(code: Int, value: String)] {
        headerVariables[name]?.values.map { (code: $0.code, value: $0.text) } ?? []
    }

    /// The integer in group 70 of the header variable `name`, or `nil`.
    func headerInteger(_ name: String) -> Int? {
        headerVariables[name]?.value(70)?.integer
    }

    /// The text in group `code` of the header variable `name`, trimmed, or `nil` when it is empty.
    func headerName(_ name: String, code: Int) -> String? {
        headerVariables[name]?.value(code).map { trimmed($0.text) }.flatMap {
            $0.isEmpty ? nil : $0
        }
    }

    /// The header variables that a `Drawing` names, read from ``readHeaderVariables()``.
    func applyHeaderProperties(to drawing: inout DXF.Drawing) {
        drawing.headerVariables = headerVariables
        drawing.insUnits = headerInteger("$INSUNITS")
        drawing.extMin = headerVariables["$EXTMIN"]?.point
        drawing.extMax = headerVariables["$EXTMAX"]?.point
        drawing.measurement = headerInteger("$MEASUREMENT")
        drawing.currentDimensionStyleName = headerName("$DIMSTYLE", code: 2)
        drawing.dimensionScale = headerVariables["$DIMSCALE"]?.value(40)?.real
        drawing.linearUnitFormat = headerInteger("$LUNITS")
        drawing.linearUnitPrecision = headerInteger("$LUPREC")
        drawing.dimensionDefaults = headerStyleVariables()
    }
}
