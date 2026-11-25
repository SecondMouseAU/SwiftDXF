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

    /// Whether the file is R12 or earlier.
    ///
    /// A file that names no version counts, as `ezdxf` reads it as R12; so do the R2.x names
    /// (`AC2.10`), which `ezdxf` does not. Only such a file's
    /// elevation (group 38) is a z: later versions keep it in the corners.
    var isLegacyVersion: Bool {
        // `AC1002` to `AC1009` and `AC1.50` sort before `AC1009`; `AC2.10` to `AC2.22` (R2.1 to
        // R2.6) are named differently and sort after it, though `ezdxf` reads them as later.
        version <= "AC1009" || version.hasPrefix("AC2.")
    }

    func solid(_ f: Fields) -> DXF.Solid {
        var c = fileCorners(f)
        // R11 and earlier wrote a flat SOLID with its elevation (group 38) and no z (the DXF R10
        // reference: output only if FLATLAND is 1). `ezdxf` gives the elevation to each corner
        // whose z is 0, for a file of R12 or earlier, and ignores it in a later one.
        let elevation = isLegacyVersion ? dbl(38, f) : 0
        if elevation != 0 {
            c = c.map { $0.z == 0 ? DXF.Point($0.x, $0.y, elevation) : $0 }
        }
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
