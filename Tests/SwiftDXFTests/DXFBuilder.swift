import Foundation

/// Builds DXF text from group-code pairs, for tests that need tables, blocks and entities.
struct DXFBuilder {
    typealias Record = [(Int, String)]

    var layers: [Record] = []
    var lineTypes: [Record] = []
    var blocks: [(name: String, base: (Double, Double), body: [Record])] = []
    var entities: [Record] = []

    static func lines(_ pairs: Record) -> String {
        pairs.map { "\($0.0)\n\($0.1)" }.joined(separator: "\n") + "\n"
    }

    func text() -> String {
        var out = "0\nSECTION\n2\nHEADER\n9\n$ACADVER\n1\nAC1032\n0\nENDSEC\n"
        out += "0\nSECTION\n2\nTABLES\n"
        out += "0\nTABLE\n2\nLTYPE\n"
        for r in lineTypes { out += "0\nLTYPE\n" + Self.lines(r) }
        out += "0\nENDTAB\n0\nTABLE\n2\nLAYER\n"
        for r in layers { out += "0\nLAYER\n" + Self.lines(r) }
        out += "0\nENDTAB\n0\nENDSEC\n"
        out += "0\nSECTION\n2\nBLOCKS\n"
        for b in blocks {
            out +=
                "0\nBLOCK\n8\n0\n2\n\(b.name)\n70\n0\n10\n\(b.base.0)\n20\n\(b.base.1)\n30\n0.0\n"
            for r in b.body { out += Self.lines(r) }
            out += "0\nENDBLK\n8\n0\n"
        }
        out += "0\nENDSEC\n0\nSECTION\n2\nENTITIES\n"
        for r in entities { out += Self.lines(r) }
        out += "0\nENDSEC\n0\nEOF\n"
        return out
    }

    // MARK: records

    static func line(
        _ a: (Double, Double), _ b: (Double, Double), layer: String = "0", handle: String? = nil,
        color: Int? = nil, lineType: String? = nil
    ) -> Record {
        var r: Record = [(0, "LINE")]
        if let handle { r.append((5, handle)) }
        r.append((8, layer))
        if let lineType { r.append((6, lineType)) }
        if let color { r.append((62, "\(color)")) }
        r += [
            (10, "\(a.0)"), (20, "\(a.1)"), (30, "0.0"), (11, "\(b.0)"), (21, "\(b.1)"),
            (31, "0.0"),
        ]
        return r
    }

    static func insert(
        _ name: String, at p: (Double, Double), scale: (Double, Double) = (1, 1),
        rotation: Double = 0, layer: String = "0", handle: String? = nil, color: Int? = nil,
        lineType: String? = nil, array: (columns: Int, rows: Int, dx: Double, dy: Double)? = nil
    ) -> Record {
        var r: Record = [(0, "INSERT")]
        if let handle { r.append((5, handle)) }
        r.append((8, layer))
        if let lineType { r.append((6, lineType)) }
        if let color { r.append((62, "\(color)")) }
        r += [
            (2, name), (10, "\(p.0)"), (20, "\(p.1)"), (30, "0.0"), (41, "\(scale.0)"),
            (42, "\(scale.1)"), (43, "1.0"), (50, "\(rotation)"),
        ]
        if let array {
            r += [
                (70, "\(array.columns)"), (71, "\(array.rows)"), (44, "\(array.dx)"),
                (45, "\(array.dy)"),
            ]
        }
        return r
    }

    static func circle(_ c: (Double, Double), _ radius: Double, layer: String = "0") -> Record {
        [(0, "CIRCLE"), (8, layer), (10, "\(c.0)"), (20, "\(c.1)"), (30, "0.0"), (40, "\(radius)")]
    }

    static func arc(
        _ c: (Double, Double), _ radius: Double, _ start: Double, _ end: Double,
        layer: String = "0"
    ) -> Record {
        [
            (0, "ARC"), (8, layer), (10, "\(c.0)"), (20, "\(c.1)"), (30, "0.0"), (40, "\(radius)"),
            (50, "\(start)"), (51, "\(end)"),
        ]
    }
}
