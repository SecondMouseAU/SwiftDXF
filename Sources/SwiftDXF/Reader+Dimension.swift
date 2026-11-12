import Foundation

extension DXF.Reader {
    func dimension(_ f: Fields) -> DXF.Dimension {
        let textRaw = first(1, f)
        return DXF.Dimension(
            kind: DXF.DimensionType(group70: ints(70, f) ?? 0),
            // Zero or negative means "none": some writers store -1.
            measurement: dblOpt(42, f).flatMap { $0 > 0 ? $0 : nil },
            textOverride: (textRaw?.isEmpty == false) ? textRaw : nil,
            textPosition: DXF.Point(dbl(11, f), dbl(21, f), dbl(31, f)),
            defPoint: point(f),
            defPoint2: pointOpt(13, f), defPoint3: pointOpt(14, f),
            defPoint4: pointOpt(15, f), defPoint5: pointOpt(16, f),
            layer: layer(f), color: color(f), rotation: dblOpt(50, f),
            obliqueAngle: dblOpt(52, f),
            styleName: first(3, f).map(trimmed).flatMap { $0.isEmpty ? nil : $0 },
            styleOverrides: styleOverrides(f))
    }

    /// The variables a `DIMSTYLE` record states, by their group codes.
    func styleVariables(_ f: Fields) -> DXF.DimensionStyle.Variables {
        DXF.DimensionStyle.Variables(
            decimalPlaces: ints(271, f), zeroSuppression: ints(78, f), linearScale: dblOpt(144, f),
            unitSuffix: nonEmpty(first(3, f)))
    }

    /// The header's current dimension variables (`$DIMDEC`, `$DIMZIN`, `$DIMLFAC`, `$DIMPOST`).
    func headerStyleVariables() -> DXF.DimensionStyle.Variables {
        DXF.DimensionStyle.Variables(
            decimalPlaces: ints(70, headerVar("$DIMDEC")),
            zeroSuppression: ints(70, headerVar("$DIMZIN")),
            linearScale: dblOpt(40, headerVar("$DIMLFAC")),
            unitSuffix: nonEmpty(first(1, headerVar("$DIMPOST"))))
    }

    /// The overrides in the `ACAD` / `DSTYLE` extended data of a dimension.
    ///
    /// Shaped `1001 ACAD`, `1000 DSTYLE`, `1002 {`, then pairs of a `1070` variable code and its
    /// value (`1070`, `1040` or `1000`), then `1002 }`.
    func styleOverrides(_ f: Fields) -> DXF.DimensionStyle.Variables {
        guard let app = f.firstIndex(where: { $0.code == 1001 && trimmed($0.value) == "ACAD" })
        else { return .init() }
        var raw: [Int: String] = [:]
        var i = app + 1
        var inside = false
        scan: while i < f.count {
            let (code, value) = f[i]
            switch code {
            case 1001: break scan
            case 1002 where trimmed(value) == "{": inside = true
            case 1002 where trimmed(value) == "}": if inside { break scan }
            case 1070 where inside:
                guard let variable = Int(trimmed(value)), i + 1 < f.count else { break scan }
                raw[variable] = f[i + 1].value
                i += 1
            default: break
            }
            i += 1
        }
        func real(_ s: String?) -> Double? { s.flatMap { Double(trimmed($0)) } }
        return DXF.DimensionStyle.Variables(
            decimalPlaces: raw[271].flatMap { Int(trimmed($0)) },
            zeroSuppression: raw[78].flatMap { Int(trimmed($0)) }, linearScale: real(raw[144]),
            unitSuffix: nonEmpty(raw[3]))
    }

    private func nonEmpty(_ s: String?) -> String? { s.flatMap { $0.isEmpty ? nil : $0 } }
}
