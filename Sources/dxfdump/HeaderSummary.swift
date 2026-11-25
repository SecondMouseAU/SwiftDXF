import Foundation
import SwiftDXF

/// A real number as JSON, which has no infinity or NaN: those are written as text.
private func number(_ x: Double) -> Any { x.isFinite ? x : "\(x)" }

/// A header value as JSON, by what its group code says it is: an integer, a real number or text.
private func typed(_ value: DXF.HeaderVariable.Value) -> Any {
    switch value.code {
    case 60...79, 90...99, 160...179, 270...299, 370...389, 400...409, 420...429, 440...459,
        1060...1071:
        return value.integer ?? value.text
    case 10...59, 110...149, 210...239, 460...469, 1010...1059:
        return value.real.map(number) ?? value.text
    default:
        return value.text
    }
}

private func json(_ point: DXF.Point?) -> Any {
    point.map { [number($0.x), number($0.y), number($0.z)] } ?? NSNull()
}

/// The header of the file as JSON.
///
/// It holds the variables SwiftDXF names, as the drawing has them, and every variable with its
/// first value. The shape is kept identical to `tools/oracle.py --header`.
func headerSummary(for path: String, options: DXF.ReadOptions) -> [String: Any] {
    let url = URL(fileURLWithPath: path)
    do {
        let dwg = try DXF.read(contentsOf: url, options: options)
        let defaults = dwg.dimensionDefaults
        let named: [String: Any] = [
            "version": dwg.version,
            "codePage": dwg.codePage?.name ?? NSNull(),
            "insUnits": dwg.insUnits ?? NSNull(),
            "extMin": json(dwg.extMin),
            "extMax": json(dwg.extMax),
            "measurement": dwg.measurement ?? NSNull(),
            "currentDimensionStyleName": dwg.currentDimensionStyleName ?? NSNull(),
            "dimensionScale": dwg.dimensionScale.map(number) ?? NSNull(),
            "linearUnitFormat": dwg.linearUnitFormat ?? NSNull(),
            "linearUnitPrecision": dwg.linearUnitPrecision ?? NSNull(),
            "dimDec": defaults.decimalPlaces ?? NSNull(),
            "dimZin": defaults.zeroSuppression ?? NSNull(),
            "dimLfac": defaults.linearScale.map(number) ?? NSNull(),
            "dimPost": defaults.unitSuffix ?? NSNull(),
            "dimAUnit": defaults.angleUnitCode ?? NSNull(),
            "dimADec": defaults.angleDecimalPlaces ?? NSNull(),
        ]
        var variables: [String: Any] = [:]
        for (name, variable) in dwg.headerVariables {
            guard let first = variable.values.first else { continue }
            if first.code == 10, let point = variable.point {
                variables[name] = [10, json(point)]
            } else {
                variables[name] = [first.code, typed(first)]
            }
        }
        return [
            "file": url.lastPathComponent, "header": named, "variables": variables,
        ]
    } catch {
        return ["file": url.lastPathComponent, "error": "\(error)"]
    }
}
