import Foundation
import SwiftDXF

// dxfdump: read each DXF file and print a compact JSON summary (one object per file), for diffing
// against a reference tool (e.g. ezdxf). Shape is kept identical to tools/oracle.py.
//
//   dxfdump file1.dxf [file2.dxf ...]
//   dxfdump --contours [--layers A,B] [--units inch|mm|...] file.dxf [...]
//   dxfdump [--expand] [--skip-paper-space] file.dxf [...]
//   dxfdump --texts file.dxf [...]
//
// --expand flattens INSERT block references into the entities; --skip-paper-space leaves out
// entities flagged as paper space. Both work with the digest and with --contours.
// --contours prints a JSON summary of the closed regions found (shapes, holes, areas, bounds in
// millimetres, open chains, warnings) instead of the entity digest.
// --texts prints each TEXT and MTEXT string and each dimension's text override as it reads, with
// its stacks, for diffing against tools/text_oracle.py (with --skip-paper-space, as ezdxf's
// modelspace() reads). It cannot be combined with --contours.

/// How the files are read, set by `--expand` and `--skip-paper-space`.
var readOptions = DXF.ReadOptions()

func summary(for path: String) -> [String: Any] {
    let url = URL(fileURLWithPath: path)
    do {
        let dwg = try DXF.read(contentsOf: url, options: readOptions)
        let c = dwg.counts
        var obj: [String: Any] = [
            "file": url.lastPathComponent,
            "version": dwg.version,
            "counts": [
                "LINE": c.line, "CIRCLE": c.circle, "ARC": c.arc, "ELLIPSE": c.ellipse,
                "POINT": c.point, "TEXT": c.text, "POLYLINE": c.polyline,
                "DIMENSION": c.dimension, "SPLINE": c.spline, "HATCH": c.hatch, "LEADER": c.leader,
                "total": c.total,
            ],
            "skipped": dwg.skipped,
            "skippedByLayer": dwg.skippedByLayer,
            "references": dwg.references.count,
            "paperSpace": dwg.paperSpace,
            "warnings": dwg.warnings.map { "\($0)" },
        ]
        // One entry per entity, in order: the file's handle, or null when it has none.
        obj["handles"] = dwg.identities.map { $0.handle ?? NSNull() as Any }
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
                if let m = d.measurement { add("DIMENSION", m) }
                for p in [d.defPoint2, d.defPoint3, d.defPoint4, d.defPoint5] {
                    if let p { add("DIMENSION", p.x, p.y) }
                }
                if let r = d.rotation { add("DIMENSION", r) }
                if let o = d.obliqueAngle { add("DIMENSION", o) }
            case .spline(let s):
                for p in s.controlPoints { add("SPLINE", p.x, p.y) }
                for p in s.fitPoints { add("SPLINE", p.x, p.y) }
            case .leader(let l):
                for p in l.vertices { add("LEADER", p.x, p.y) }
            case .hatch(let h):
                for path in h.paths {
                    switch path.geometry {
                    case .polyline(let vertices, _):
                        for v in vertices { add("HATCH", v.point.x, v.point.y, v.bulge) }
                    case .edges(let edges):
                        for edge in edges {
                            switch edge {
                            case .line(let a, let b): add("HATCH", a.x, a.y, b.x, b.y)
                            case .arc(let c, let r, let s, let e, _):
                                add("HATCH", c.x, c.y, r, s, e)
                            case .ellipse(let c, let m, let ratio, _, _, _):
                                add("HATCH", c.x, c.y, m.x, m.y, ratio)
                            case .spline(let sp):
                                for p in sp.controlPoints { add("HATCH", p.x, p.y) }
                            }
                        }
                    }
                }
            }
        }
        // The geometric measurement of each DIMENSION in order (null where there is none), for
        // diffing against ezdxf's Dimension.get_measurement().
        obj["dimensions"] = dwg.entities.compactMap { e -> Any? in
            guard case .dimension(let d) = e else { return nil }
            return d.computedMeasurement ?? NSNull()
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
        let result = try DXF.read(contentsOf: url, options: readOptions).contours(options)
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

/// Each TEXT and MTEXT string of the file, and each dimension's text override, in entity order.
func textSummary(for path: String) -> [String: Any] {
    let url = URL(fileURLWithPath: path)
    do {
        let dwg = try DXF.read(contentsOf: url, options: readOptions)
        func stacks(_ list: [DXF.StackedText]) -> [[String]] {
            list.map { [$0.upper, $0.lower, "\($0.kind)"] }
        }
        var texts: [[String: Any]] = []
        for (i, entity) in dwg.entities.enumerated() {
            switch entity {
            case .text:
                guard let content = dwg.textContent(ofEntityAt: i) else { continue }
                texts.append([
                    "type": content.syntax == .mtext ? "MTEXT" : "TEXT", "plain": content.plain,
                    "stacks": stacks(content.stacks),
                ])
            case .dimension(let d):
                guard d.textOverride != nil else { continue }
                texts.append([
                    "type": "DIMENSION", "plain": d.text.plain, "stacks": stacks(d.text.stacks),
                ])
            default:
                continue
            }
        }
        return ["file": url.lastPathComponent, "texts": texts]
    } catch {
        return ["file": url.lastPathComponent, "error": "\(error)"]
    }
}

var arguments = Array(CommandLine.arguments.dropFirst())
if let flag = arguments.firstIndex(of: "--expand") {
    arguments.remove(at: flag)
    readOptions.expandBlocks = true
}
if let flag = arguments.firstIndex(of: "--skip-paper-space") {
    arguments.remove(at: flag)
    readOptions.skipPaperSpace = true
}
var listTexts = false
if let flag = arguments.firstIndex(of: "--texts") {
    arguments.remove(at: flag)
    listTexts = true
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
if listTexts, contourOptions != nil {
    FileHandle.standardError.write(Data("--texts and --contours cannot be used together\n".utf8))
    exit(2)
}
let paths = arguments
guard !paths.isEmpty else {
    FileHandle.standardError.write(
        Data(
            ("usage: dxfdump [--expand] [--skip-paper-space]"
                + " [--contours [--layers A,B] [--units inch|mm] | --texts] <file.dxf> [...]\n")
                .utf8)
    )
    exit(2)
}

if listTexts {
    // Slashes unescaped, as Python's json writes them, so the two outputs diff line for line.
    var options: JSONSerialization.WritingOptions = [.sortedKeys]
    if #available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *) {
        options.insert(.withoutEscapingSlashes)
    }
    for path in paths {
        let data = try JSONSerialization.data(
            withJSONObject: textSummary(for: path), options: options)
        print(String(decoding: data, as: UTF8.self))
    }
    exit(0)
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
    if let dwg = try? DXF.read(contentsOf: URL(fileURLWithPath: path), options: readOptions),
        !dwg.skipped.isEmpty
    {
        FileHandle.standardError.write(Data(skippedTable(dwg).utf8))
    }
}
