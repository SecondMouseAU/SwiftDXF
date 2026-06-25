import Foundation
import SwiftDXF

// dxfdump — read each DXF file and print a compact JSON summary (one object per file), for diffing
// against a reference tool (e.g. ezdxf). Shape is kept identical to tools/oracle.py.
//
//   dxfdump file1.dxf [file2.dxf ...]

func summary(for path: String) -> [String: Any] {
    let url = URL(fileURLWithPath: path)
    do {
        let dwg = try DXF.read(contentsOf: url)
        let c = dwg.counts
        var obj: [String: Any] = [
            "file": url.lastPathComponent,
            "version": dwg.version,
            "counts": [
                "LINE": c.line, "CIRCLE": c.circle, "ARC": c.arc, "ELLIPSE": c.ellipse,
                "POINT": c.point, "TEXT": c.text, "POLYLINE": c.polyline, "total": c.total,
            ],
        ]
        if let b = dwg.bounds {
            obj["bounds"] = ["min": [b.min.x, b.min.y], "max": [b.max.x, b.max.y]]
        } else {
            obj["bounds"] = NSNull()
        }
        // Geometry digest: sum + count of every defining scalar (rounded), so a coordinate-level diff
        // against the oracle is one number, not a per-entity walk. Scalar lists mirror tools/oracle.py.
        // Full-precision sum in document order; the oracle sums the identical scalars in the same
        // order, so a faithful parse matches to within float rounding. (No decimal rounding here —
        // that would inject a tie-break mismatch vs Python's banker's rounding.)
        var sum = 0.0, n = 0
        var byType: [String: [Double]] = [:]   // type -> [sum, count]
        func add(_ t: String, _ vs: Double...) {
            for v in vs {
                sum += v; n += 1
                byType[t, default: [0, 0]][0] += v; byType[t, default: [0, 0]][1] += 1
            }
        }
        for e in dwg.entities {
            switch e {
            case let .line(a, b, _, _): add("LINE", a.x, a.y, b.x, b.y)
            case let .circle(c, r, _, _): add("CIRCLE", c.x, c.y, r)
            case let .arc(c, r, s, en, _, _): add("ARC", c.x, c.y, r, s, en)
            case let .ellipse(c, m, ratio, s, en, _, _): add("ELLIPSE", c.x, c.y, m.x, m.y, ratio, s, en)
            case let .point(p, _, _): add("POINT", p.x, p.y)
            case let .text(p, h, _, _, _, _): add("TEXT", p.x, p.y, h)
            case let .polyline(pts, _, _, _): for p in pts { add("POLYLINE", p.x, p.y) }
            }
        }
        obj["geom"] = ["sum": sum, "scalars": n]
        obj["geomByType"] = byType.mapValues { ["sum": $0[0], "scalars": Int($0[1])] }
        return obj
    } catch {
        return ["file": url.lastPathComponent, "error": "\(error)"]
    }
}

let paths = Array(CommandLine.arguments.dropFirst())
guard !paths.isEmpty else {
    FileHandle.standardError.write(Data("usage: dxfdump <file.dxf> [...]\n".utf8))
    exit(2)
}

for path in paths {
    let data = try JSONSerialization.data(withJSONObject: summary(for: path), options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
}
