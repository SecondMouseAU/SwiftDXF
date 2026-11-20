import Foundation

extension DXF.Reader {
    /// The corners of a `SOLID` or `3DFACE` as the file lists them: groups 10, 11, 12 and 13, the
    /// fourth being the third when the record has none.
    private func fileCorners(_ f: Fields) -> [DXF.Point] {
        let third = DXF.Point(dbl(12, f), dbl(22, f), dbl(32, f))
        return [
            point(f), DXF.Point(dbl(11, f), dbl(21, f), dbl(31, f)), third,
            pointOpt(13, f) ?? third,
        ]
    }

    func solid(_ f: Fields) -> DXF.Solid {
        let c = fileCorners(f)
        // The file lists a quadrilateral as 1, 2, 4, 3; a triangle repeats the third corner.
        let corners = c[3] == c[2] ? [c[0], c[1], c[2]] : [c[0], c[1], c[3], c[2]]
        return DXF.Solid(corners: corners, layer: layer(f), color: color(f))
    }

    func face3D(_ f: Fields) -> DXF.Face3D {
        DXF.Face3D(
            corners: fileCorners(f), invisibleEdges: ints(70, f) ?? 0, layer: layer(f),
            color: color(f))
    }
}
