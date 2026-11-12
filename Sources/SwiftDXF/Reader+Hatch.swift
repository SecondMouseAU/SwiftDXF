import Foundation

extension DXF.Reader {
    /// A `HATCH`: pattern, fill and boundary paths.
    ///
    /// The paths follow group `91` as a strict sequence, so a read that meets something it does
    /// not expect stops and keeps the paths it has, rather than guessing.
    func hatch(_ f: [(code: Int, value: String)], identity: DXF.EntityIdentity) -> DXF.Hatch {
        var out = DXF.Hatch(
            patternName: nonEmpty(first(2, f)) ?? "", isSolid: ints(70, f) == 1,
            isAssociative: ints(71, f) == 1, layer: layer(f), color: color(f),
            lineType: nonEmpty(first(6, f)), identity: identity)
        guard let start = f.firstIndex(where: { $0.code == 91 }),
            let count = Int(trimmed(f[start].value)), count > 0
        else { return out }

        var k = start + 1
        func peek(_ code: Int) -> String? { k < f.count && f[k].code == code ? f[k].value : nil }
        func takeInt(_ code: Int) -> Int? {
            guard let v = peek(code), let n = Int(trimmed(v)) else { return nil }
            k += 1
            return n
        }
        func takeDouble(_ code: Int) -> Double? {
            guard let v = peek(code), let n = Double(trimmed(v)) else { return nil }
            k += 1
            return n
        }
        func takePoint2(_ x: Int, _ y: Int) -> DXF.Point2? {
            guard let a = takeDouble(x), let b = takeDouble(y) else { return nil }
            return DXF.Point2(a, b)
        }
        /// The source boundary object count and its handles, which follow every path.
        func skipSourceObjects() {
            if let n = takeInt(97) {
                var left = n
                while left > 0, peek(330) != nil {
                    k += 1
                    left -= 1
                }
            }
        }

        for _ in 0..<count {
            guard let flags = takeInt(92) else { return out }
            if flags & 2 != 0 {
                let hasBulge = (takeInt(72) ?? 0) != 0
                let closed = (takeInt(73) ?? 0) != 0
                guard let n = takeInt(93) else { return out }
                var vertices: [DXF.PolyVertex] = []
                for _ in 0..<n {
                    guard let p = takePoint2(10, 20) else { return out }
                    let bulge = hasBulge ? (takeDouble(42) ?? 0) : 0
                    vertices.append(DXF.PolyVertex(DXF.Point(p.x, p.y), bulge: bulge))
                }
                out.loops.append(
                    DXF.Hatch.Loop(
                        flags: flags, content: .polyline(vertices: vertices, closed: closed)))
            } else {
                guard let n = takeInt(93) else { return out }
                var edges: [DXF.Hatch.Edge] = []
                for _ in 0..<n {
                    guard let type = takeInt(72) else { return out }
                    switch type {
                    case 1:
                        guard let a = takePoint2(10, 20), let b = takePoint2(11, 21) else {
                            return out
                        }
                        edges.append(.line(a: a, b: b))
                    case 2:
                        guard let c = takePoint2(10, 20), let r = takeDouble(40),
                            let s = takeDouble(50), let e = takeDouble(51)
                        else { return out }
                        let ccw = (takeInt(73) ?? 1) != 0
                        edges.append(
                            .arc(
                                center: c, radius: r, startDeg: s, endDeg: e, counterClockwise: ccw)
                        )
                    case 3:
                        guard let c = takePoint2(10, 20), let m = takePoint2(11, 21),
                            let ratio = takeDouble(40), let s = takeDouble(50),
                            let e = takeDouble(51)
                        else { return out }
                        let ccw = (takeInt(73) ?? 1) != 0
                        edges.append(
                            .ellipse(
                                center: c, majorAxis: m, ratio: ratio, startDeg: s, endDeg: e,
                                counterClockwise: ccw))
                    case 4:
                        guard let degree = takeInt(94) else { return out }
                        let rational = (takeInt(73) ?? 0) != 0
                        _ = takeInt(74)
                        guard let knotCount = takeInt(95), let controlCount = takeInt(96) else {
                            return out
                        }
                        var knots: [Double] = []
                        for _ in 0..<knotCount {
                            guard let v = takeDouble(40) else { return out }
                            knots.append(v)
                        }
                        var control: [DXF.Point2] = []
                        var weights: [Double] = []
                        for _ in 0..<controlCount {
                            guard let p = takePoint2(10, 20) else { return out }
                            control.append(p)
                            if rational, let w = takeDouble(42) { weights.append(w) }
                        }
                        // Fit points and tangents may follow; they do not change the curve.
                        while k < f.count, ![72, 97, 92, 75, 76].contains(f[k].code) { k += 1 }
                        edges.append(
                            .spline(
                                degree: degree, controlPoints: control, knots: knots,
                                weights: weights.count == control.count ? weights : []))
                    default:
                        return out
                    }
                }
                out.loops.append(DXF.Hatch.Loop(flags: flags, content: .edges(edges)))
            }
            skipSourceObjects()
        }
        return out
    }
}
