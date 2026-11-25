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
    var isLegacyVersion: Bool { Self.isLegacyVersion(version) }

    /// Whether `$ACADVER` `version` names R12 (`AC1009`) or an earlier release, which is the
    /// files whose elevation (group 38) is a z.
    ///
    /// The number after `AC` is compared: `AC1002` to `AC1009` are R2.5 to R12, and a dotted name
    /// (`AC1.40`, `AC1.50`, `AC2.10` to `AC2.22`) is a release before R9. A file that names no
    /// version counts as legacy, as `ezdxf` reads it as R12. A name that is not `AC` and a number
    /// (in either case) does not, so its group 38 is left alone. `ezdxf` compares the names as text, which puts
    /// the `AC2.x` names after `AC1009`; the reference puts them before it.
    static func isLegacyVersion(_ version: String) -> Bool {
        let name = version.trimmingCharacters(in: .whitespaces).uppercased()
        if name.isEmpty { return true }
        guard name.hasPrefix("AC") else { return false }
        let number = name.dropFirst(2)
        if let dot = number.firstIndex(of: ".") {
            // Only `AC1.x` and `AC2.x` were ever written.
            let minor = number[number.index(after: dot)...]
            return ["1", "2"].contains(number[..<dot])
                && !minor.isEmpty && minor.allSatisfy { $0.isASCII && $0.isNumber }
        }
        guard !number.isEmpty, number.allSatisfy({ $0.isASCII && $0.isNumber }),
            let release = Int(number)
        else { return false }
        return release <= 1009
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
