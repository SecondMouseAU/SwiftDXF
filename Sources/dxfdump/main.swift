import Foundation
import SwiftDXF

// dxfdump: read each DXF file and print a compact JSON summary (one object per file), for diffing
// against a reference tool (e.g. ezdxf). Shape is kept identical to tools/oracle.py.
//
//   dxfdump file1.dxf [file2.dxf ...]
//   dxfdump --contours [--layers A,B] [--units inch|mm|...] file.dxf [...]
//   dxfdump --dimensions file.dxf [...]
//   dxfdump --expand file.dxf [...]
//
// --contours prints a JSON summary of the closed regions found (shapes, holes, areas, bounds in
// millimetres, open chains, warnings) instead of the entity digest.

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
                "POINT": c.point, "TEXT": c.text, "POLYLINE": c.polyline,
                "DIMENSION": c.dimension, "SPLINE": c.spline, "total": c.total,
            ],
            "skipped": dwg.skipped,
            "skippedByLayer": dwg.skippedByLayer,
        ]
        if let b = dwg.bounds {
            obj["bounds"] = ["min": [b.min.x, b.min.y], "max": [b.max.x, b.max.y]]
        } else {
            obj["bounds"] = NSNull()
        }
        // Geometry digest: sum + count of every defining scalar (rounded), so a coordinate-level diff
        // against the oracle is one number, not a per-entity walk. Scalar lists mirror tools/oracle.py.
        // Full-precision sum in document order; the oracle sums the identical scalars in the same
        // order, so a faithful parse matches to within float rounding. (No decimal rounding here;
        // that would inject a tie-break mismatch vs Python's banker's rounding.)
        var sum = 0.0
        var n = 0
        var byType: [String: [Double]] = [:]  // type -> [sum, count]
        func add(_ t: String, _ vs: Double...) {
            for v in vs {
                sum += v
                n += 1
                byType[t, default: [0, 0]][0] += v
                byType[t, default: [0, 0]][1] += 1
            }
        }
        for e in dwg.entities {
            switch e {
            case .line(let a, let b, _, _): add("LINE", a.x, a.y, b.x, b.y)
            case .circle(let c, let r, _, _): add("CIRCLE", c.x, c.y, r)
            case .arc(let c, let r, let s, let en, _, _): add("ARC", c.x, c.y, r, s, en)
            case .ellipse(let c, let m, let ratio, let s, let en, _, _):
                add("ELLIPSE", c.x, c.y, m.x, m.y, ratio, s, en)
            case .point(let p, _, _): add("POINT", p.x, p.y)
            case .text(let p, let h, _, _, _, _): add("TEXT", p.x, p.y, h)
            case .polyline(let verts, _, _, _):
                for v in verts { add("POLYLINE", v.point.x, v.point.y) }
            case .dimension(let d):
                add("DIMENSION", d.textPosition.x, d.textPosition.y, d.defPoint.x, d.defPoint.y)
                if let m = d.rawMeasurement { add("DIMENSION", m) }
                for p in [d.defPoint2, d.defPoint3, d.defPoint4, d.defPoint5] {
                    if let p { add("DIMENSION", p.x, p.y) }
                }
            case .spline(let s):
                for p in s.controlPoints { add("SPLINE", p.x, p.y) }
                for p in s.fitPoints { add("SPLINE", p.x, p.y) }
            }
        }
        obj["geom"] = ["sum": sum, "scalars": n]
        obj["geomByType"] = byType.mapValues { ["sum": $0[0], "scalars": Int($0[1])] }
        return obj
    } catch {
        return ["file": url.lastPathComponent, "error": "\(error)"]
    }
}

/// Human-readable skip table, written to stderr so stdout stays one JSON object per file.
func skippedTable(_ dwg: DXF.Drawing) -> String {
    var text = "skipped (unmodelled) entities:\n"
    for (type, count) in dwg.skipped.sorted(by: { $0.key < $1.key }) {
        let layers = (dwg.skippedByLayer[type] ?? [:]).sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value)" }.joined(separator: ", ")
        text +=
            "  \(type.padding(toLength: 12, withPad: " ", startingAt: 0)) \(count)  [\(layers)]\n"
    }
    return text
}

func box(_ b: DXF.Box2) -> [String: [Double]] {
    ["min": [b.min.x, b.min.y], "max": [b.max.x, b.max.y]]
}

func contourSummary(for path: String, options: DXF.Contour.Options) -> [String: Any] {
    let url = URL(fileURLWithPath: path)
    do {
        let result = try DXF.read(contentsOf: url).contours(options)
        func loop(_ l: DXF.Contour.Loop) -> [String: Any] {
            [
                "segments": l.segments.count, "arcs": l.segments.filter { $0.isArc }.count,
                "area": l.area, "length": l.length, "bounds": box(l.bounds), "layers": l.layers,
            ]
        }
        var obj: [String: Any] = [
            "file": url.lastPathComponent,
            "unit": "\(result.unit)",
            "unitScale": result.unitScale,
            "shapes": result.shapes.map { shape -> [String: Any] in
                [
                    "area": shape.area, "bounds": box(shape.bounds), "outer": loop(shape.outer),
                    "holes": shape.holes.map(loop),
                ]
            },
            "area": result.area,
            "openChains": result.openChains.map {
                ["segments": $0.segments.count, "length": $0.length, "layers": $0.layers]
            },
            "maxFitDeviation": result.maxFitDeviation,
            "warnings": result.warnings.map { "\($0)" },
        ]
        obj["bounds"] = result.bounds.map(box) ?? NSNull()
        return obj
    } catch {
        return ["file": url.lastPathComponent, "error": "\(error)"]
    }
}

/// One JSON row per DIMENSION: identity, kind, stored and computed value, rotation, style, text.
func dimensionRows(for path: String) -> [String: Any] {
    let url = URL(fileURLWithPath: path)
    do {
        let dwg = try DXF.read(contentsOf: url)
        var rows: [[String: Any]] = []
        for (index, entity) in dwg.entities.enumerated() {
            guard case .dimension(let d) = entity else { continue }
            let style = dwg.style(of: d)
            let text = d.text
            rows.append([
                "id": index < dwg.identities.count ? dwg.identities[index].id : "",
                "kind": "\(d.kind)",
                "stored": d.measurement as Any? ?? NSNull(),
                "computed": d.computedMeasurement as Any? ?? NSNull(),
                "rotation": d.rotation as Any? ?? NSNull(),
                "oblique": d.obliqueAngle as Any? ?? NSNull(),
                "style": d.styleName as Any? ?? NSNull(),
                "decimals": style.decimals as Any? ?? NSNull(),
                "suffix": style.suffix as Any? ?? NSNull(),
                "text": d.textOverride as Any? ?? NSNull(),
                "showsMeasurement": text.showsMeasurement,
                "typedNumbers": text.typedNumbers,
                "qualifiers": text.qualifiers,
                "words": text.words,
            ])
        }
        return [
            "file": url.lastPathComponent, "insUnits": dwg.insUnits as Any? ?? NSNull(),
            "dimensions": rows,
        ]
    } catch {
        return ["file": url.lastPathComponent, "error": "\(error)"]
    }
}

/// Per-type counts and a coordinate digest of the drawing with block references expanded.
func expandedSummary(for path: String) -> [String: Any] {
    let url = URL(fileURLWithPath: path)
    do {
        let dwg = try DXF.read(contentsOf: url, options: .init(expandBlocks: true))
        var counts: [String: Int] = [:]
        var lineSum = 0.0
        var lineScalars = 0
        var circleSum = 0.0
        for e in dwg.entities {
            switch e {
            case .line(let a, let b, _, _):
                counts["LINE", default: 0] += 1
                lineSum += a.x + a.y + b.x + b.y
                lineScalars += 4
            case .circle(let c, let r, _, _):
                counts["CIRCLE", default: 0] += 1
                circleSum += c.x + c.y + r
            case .arc: counts["ARC", default: 0] += 1
            case .ellipse: counts["ELLIPSE", default: 0] += 1
            case .point: counts["POINT", default: 0] += 1
            case .text: counts["TEXT", default: 0] += 1
            case .polyline: counts["POLYLINE", default: 0] += 1
            case .dimension: counts["DIMENSION", default: 0] += 1
            case .spline: counts["SPLINE", default: 0] += 1
            }
        }
        return [
            "file": url.lastPathComponent, "counts": counts, "lineSum": lineSum,
            "lineScalars": lineScalars, "circleSum": circleSum, "hatches": dwg.hatches.count,
            "leaders": dwg.leaders.count, "references": dwg.references.count,
            "warnings": dwg.warnings.map { "\($0)" }, "skipped": dwg.skipped,
        ]
    } catch {
        return ["file": url.lastPathComponent, "error": "\(error)"]
    }
}

var arguments = Array(CommandLine.arguments.dropFirst())
if let flag = arguments.firstIndex(of: "--expand") {
    arguments.remove(at: flag)
    for path in arguments {
        let data = try JSONSerialization.data(
            withJSONObject: expandedSummary(for: path), options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
    exit(0)
}
if let flag = arguments.firstIndex(of: "--dimensions") {
    arguments.remove(at: flag)
    for path in arguments {
        let data = try JSONSerialization.data(
            withJSONObject: dimensionRows(for: path), options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
    exit(0)
}
var contourOptions: DXF.Contour.Options?
if let flag = arguments.firstIndex(of: "--contours") {
    arguments.remove(at: flag)
    var options = DXF.Contour.Options()
    while let i = arguments.firstIndex(where: { $0 == "--layers" || $0 == "--units" }),
        i + 1 < arguments.count
    {
        let value = arguments[i + 1]
        if arguments[i] == "--layers" {
            options.layers = Set(value.split(separator: ",").map(String.init))
        } else {
            let names: [String: DXF.Contour.LengthUnit] = [
                "inch": .inch, "in": .inch, "foot": .foot, "mm": .millimetre,
                "cm": .centimetre, "m": .metre,
            ]
            guard let unit = names[value.lowercased()] else {
                FileHandle.standardError.write(
                    Data("unknown --units '\(value)' (use inch, in, foot, mm, cm, m)\n".utf8))
                exit(2)
            }
            options.units = unit
        }
        arguments.removeSubrange(i...(i + 1))
    }
    contourOptions = options
}
let paths = arguments
guard !paths.isEmpty else {
    FileHandle.standardError.write(
        Data("usage: dxfdump [--contours [--layers A,B] [--units inch|mm]] <file.dxf> [...]\n".utf8)
    )
    exit(2)
}

if let contourOptions {
    for path in paths {
        let data = try JSONSerialization.data(
            withJSONObject: contourSummary(for: path, options: contourOptions),
            options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
    exit(0)
}

for path in paths {
    let data = try JSONSerialization.data(
        withJSONObject: summary(for: path), options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
    if let dwg = try? DXF.read(contentsOf: URL(fileURLWithPath: path)), !dwg.skipped.isEmpty {
        FileHandle.standardError.write(Data(skippedTable(dwg).utf8))
    }
}
