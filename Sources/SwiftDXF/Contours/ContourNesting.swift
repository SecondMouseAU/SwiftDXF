import Foundation

/// Sorts closed loops into shapes: outer boundaries with their holes.
struct ContourNesting {
    struct Output {
        var shapes: [DXF.Contour.Shape] = []
        var coincident = 0
        var crossing = 0
        var dropped = 0
    }

    let tolerance: Double
    let rule: DXF.Contour.NestingRule

    func nest(_ loops: [DXF.Contour.Loop]) -> Output {
        var output = Output()
        let order = loops.indices.sorted { loops[$0].area > loops[$1].area }
        var parent = [Int?](repeating: nil, count: loops.count)
        var depth = [Int](repeating: 0, count: loops.count)
        var removed = Set<Int>()
        var indexes = [LoopIndex?](repeating: nil, count: loops.count)
        for (rank, i) in order.enumerated() {
            var crossesOne = false
            for candidate in order[..<rank].reversed() where !removed.contains(candidate) {
                let outer = loops[candidate]
                let contained = outer.bounds.contains(loops[i].bounds, slack: tolerance)
                guard contained || overlaps(outer.bounds, loops[i].bounds) else { continue }
                if indexes[candidate] == nil { indexes[candidate] = LoopIndex(outer) }
                let found = relation(of: loops[i], inside: indexes[candidate]!)
                // Only a loop whose box lies in the other's box can be inside it.
                switch contained ? found : (found == .crossing ? found : .outside) {
                case .inside:
                    parent[i] = candidate
                case .outside:
                    continue
                case .coincident:
                    removed.insert(i)
                    output.coincident += 1
                case .crossing:
                    crossesOne = true
                    continue
                }
                break
            }
            if crossesOne { output.crossing += 1 }
            if let p = parent[i] { depth[i] = depth[p] + 1 }
        }

        var shapeOf: [Int: Int] = [:]
        for i in order where !removed.contains(i) {
            switch rule {
            case .evenOdd:
                if depth[i] % 2 == 0 {
                    shapeOf[i] = output.shapes.count
                    output.shapes.append(.init(outer: oriented(loops[i], counterClockwise: true)))
                } else if let p = parent[i], let s = shapeOf[p] {
                    output.shapes[s].holes.append(oriented(loops[i], counterClockwise: false))
                }
            case .outermostOnly:
                if depth[i] == 0 {
                    output.shapes.append(.init(outer: oriented(loops[i], counterClockwise: true)))
                } else {
                    output.dropped += 1
                }
            }
        }
        return output
    }

    private func oriented(_ loop: DXF.Contour.Loop, counterClockwise: Bool) -> DXF.Contour.Loop {
        loop.isCounterClockwise == counterClockwise ? loop : loop.reversed()
    }

    private func overlaps(_ a: DXF.Box2, _ b: DXF.Box2) -> Bool {
        a.min.x <= b.max.x && b.min.x <= a.max.x && a.min.y <= b.max.y && b.min.y <= a.max.y
    }

    private enum Relation {
        case inside, outside, coincident, crossing
    }

    /// Classifies `inner` against `outer`.
    ///
    /// Up to three probe points come from `inner`'s own segments; probes on `outer`'s boundary
    /// (touching loops) are skipped.
    private func relation(of inner: DXF.Contour.Loop, inside outer: LoopIndex) -> Relation {
        let segs = inner.segments
        var picks = [segs.count / 2, 0, segs.count - 1]
        picks.append(contentsOf: 1..<segs.count)
        var results: [Bool] = []
        var seen = Set<Int>()
        for index in picks where seen.insert(index).inserted {
            // Several positions per segment, so a segment lying on `outer`'s boundary at its
            // midpoint (a circle tangent to a wall) can still supply an interior probe.
            for t in [0.5, 0.3, 0.7, 0.1, 0.9] {
                let probe = outer.classify(segs[index].point(at: t), reach: tolerance)
                guard probe.distance > tolerance else { continue }
                results.append(probe.inside)
                break
            }
            if results.count == 3 { break }
        }
        if results.isEmpty { return .coincident }
        if results.allSatisfy({ $0 }) { return .inside }
        if results.allSatisfy({ !$0 }) { return .outside }
        return .crossing
    }

    /// Whether the ray from `p` towards +x crosses the segment, with half-open rules at vertices.
    static func crosses(_ p: DXF.Point2, _ s: DXF.Contour.Segment) -> Bool {
        guard let c = s.center, let r = s.radius, let a0 = s.startAngle else {
            return crossesLine(p, s.start, s.end)
        }
        // Cut the arc where it turns in y (at the top and bottom of the circle), so each piece is
        // monotone in y and lies in the left or right half of the circle.
        let sweep = s.sweep
        var cuts: [(angle: Double, point: DXF.Point2)] = [(0, s.start)]
        let ccw = sweep > 0
        for (axis, y) in [(Double.pi / 2, c.y + r), (3 * Double.pi / 2, c.y - r)] {
            let delta =
                ccw ? DXF.Contour.Segment.wrap(axis - a0) : DXF.Contour.Segment.wrap(a0 - axis)
            if delta > 0, delta < abs(sweep) {
                cuts.append((ccw ? delta : -delta, DXF.Point2(c.x, y)))
            }
        }
        cuts.sort { abs($0.angle) < abs($1.angle) }
        cuts.append((sweep, s.end))
        var toggled = false
        for k in 0..<(cuts.count - 1) {
            let lo = cuts[k]
            let hi = cuts[k + 1]
            guard (lo.point.y > p.y) != (hi.point.y > p.y) else { continue }
            let dy = p.y - c.y
            let offset = max(0, r * r - dy * dy).squareRoot()
            let mid = a0 + (lo.angle + hi.angle) / 2
            let x = cos(mid) >= 0 ? c.x + offset : c.x - offset
            if x > p.x { toggled.toggle() }
        }
        return toggled
    }

    private static func crossesLine(_ p: DXF.Point2, _ a: DXF.Point2, _ b: DXF.Point2) -> Bool {
        guard (a.y > p.y) != (b.y > p.y) else { return false }
        let x = a.x + (p.y - a.y) * (b.x - a.x) / (b.y - a.y)
        return x > p.x
    }

    /// Distance from `p` to the segment.
    static func distance(_ p: DXF.Point2, _ s: DXF.Contour.Segment) -> Double {
        guard let c = s.center, let r = s.radius, let a0 = s.startAngle else {
            let dx = s.end.x - s.start.x
            let dy = s.end.y - s.start.y
            let len2 = dx * dx + dy * dy
            let t =
                len2 > 0
                ? max(0, min(1, ((p.x - s.start.x) * dx + (p.y - s.start.y) * dy) / len2)) : 0
            return p.distance(to: DXF.Point2(s.start.x + dx * t, s.start.y + dy * t))
        }
        let angle = atan2(p.y - c.y, p.x - c.x)
        let delta =
            s.sweep > 0
            ? DXF.Contour.Segment.wrap(angle - a0) : DXF.Contour.Segment.wrap(a0 - angle)
        if delta <= abs(s.sweep) { return abs(p.distance(to: c) - r) }
        return min(p.distance(to: s.start), p.distance(to: s.end))
    }
}
