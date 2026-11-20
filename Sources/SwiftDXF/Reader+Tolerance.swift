import Foundation

extension DXF.Reader {
    func tolerance(_ f: Fields) -> DXF.Tolerance {
        DXF.Tolerance(
            insertion: point(f), direction: pointOpt(11, f) ?? DXF.Point(1, 0, 0),
            styleName: first(3, f).map(trimmed).flatMap { $0.isEmpty ? nil : $0 },
            text: first(1, f) ?? "", codePage: codePage, layer: layer(f), color: color(f))
    }
}
