import Foundation

extension DXF.Reader {
    func leader(_ f: Fields) -> DXF.Leader {
        DXF.Leader(
            vertices: splinePoints(10, f), hasArrowhead: (ints(71, f) ?? 1) != 0,
            isSpline: ints(72, f) == 1, annotationHandle: handle(f, code: 340),
            styleName: first(3, f).map(trimmed).flatMap { $0.isEmpty ? nil : $0 },
            layer: layer(f), color: color(f))
    }
}
