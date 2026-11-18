import Foundation

extension DXF {
    /// A way the pieces near a value text could be one dimension, before any scale is known.
    struct RebuildCandidate {
        enum Shape {
            /// A span of a dimension line, from the end at `start` to the end at `end`, measured
            /// along `unit` from `origin`.
            case linear(origin: Point2, unit: Point2, start: Double, end: Double)
            /// A diameter or radius: the two points of its definition (the centre and a point on
            /// the circle for a radius).
            case radial(kind: DimensionType, first: Point2, second: Point2)
        }

        var text: Int
        /// The length the geometry gives in drawing units.
        var length: Double
        /// How far the geometry is from the text: nearer wins when two explain the value.
        var cost: Double
        /// Names the geometry of a radial candidate, so two texts do not take the same one.
        var key: [Int]
        /// The entities the geometry is made of.
        var pieces: [Int]
        var shape: Shape

        /// The ends of a span of a dimension line, or `nil` for a diameter or a radius.
        var span: (DXF.Point2, DXF.Point2)? {
            guard case .linear(let origin, let unit, let start, let end) = shape else { return nil }
            return (
                DXF.Point2(origin.x + unit.x * start, origin.y + unit.y * start),
                DXF.Point2(origin.x + unit.x * end, origin.y + unit.y * end)
            )
        }

        /// Whether `other` is the same geometry: the same span, or the same circle and line.
        func isSameGeometry(as other: RebuildCandidate, within tolerance: Double) -> Bool {
            if let a = span, let b = other.span {
                return (a.0.distance(to: b.0) <= tolerance && a.1.distance(to: b.1) <= tolerance)
                    || (a.0.distance(to: b.1) <= tolerance && a.1.distance(to: b.0) <= tolerance)
            }
            return span == nil && other.span == nil && key == other.key
        }
    }

    /// The segments that lie on one line, found from the angle and offset of each.
    struct CollinearIndex {
        private var buckets: [Int64: [Int]] = [:]
        private let tolerance: Double
        private static let angleSteps = 720

        init(_ segments: [RebuildPieces.Segment], tolerance: Double) {
            self.tolerance = tolerance
            for (index, segment) in segments.enumerated() {
                let (angle, offset) = Self.place(segment.unit, segment.a)
                buckets[
                    Self.key(angle, Int((offset / (4 * tolerance)).rounded(.down))),
                    default: []
                ].append(index)
            }
        }

        /// The key of the angle (a half turn in `angleSteps`) and offset of a line.
        private static func place(_ unit: Point2, _ point: Point2) -> (Int, Double) {
            var (x, y) = (unit.x, unit.y)
            if y < 0 || (y == 0 && x < 0) { (x, y) = (-x, -y) }
            let angle = Int((atan2(y, x) / .pi * Double(angleSteps)).rounded()) % angleSteps
            return (angle, x * point.y - y * point.x)
        }

        private static func key(_ angle: Int, _ offset: Int) -> Int64 {
            Int64(angle) &* 1_000_003 &+ Int64(offset)
        }

        /// The indices of the segments that may lie on the line through `point` along `unit`.
        func near(_ unit: Point2, _ point: Point2) -> [Int] {
            let (angle, offset) = Self.place(unit, point)
            let step = Int((offset / (4 * tolerance)).rounded(.down))
            var found: [Int] = []
            for da in -2...2 {
                let a = (angle + da + Self.angleSteps) % Self.angleSteps
                for dOffset in -1...1 {
                    found += buckets[Self.key(a, step + dOffset)] ?? []
                }
            }
            return found
        }
    }
}

extension DXF.DimensionRebuilder {
    private func cross(_ a: DXF.Point2, _ b: DXF.Point2) -> Double { a.x * b.y - a.y * b.x }
    private func dot(_ a: DXF.Point2, _ b: DXF.Point2) -> Double { a.x * b.x + a.y * b.y }
    private func minus(_ a: DXF.Point2, _ b: DXF.Point2) -> DXF.Point2 {
        DXF.Point2(a.x - b.x, a.y - b.y)
    }

    /// An end of a dimension: where an extension line meets the dimension line, or a mark is.
    private struct End {
        var t: Double
        var exact: [Double] = []
        var marked: [Double] = []
        var entities: [Int] = []
    }

    /// The candidates that read `text` as a span of a dimension line beside it.
    func linearCandidates(_ ti: Int) -> [DXF.RebuildCandidate] {
        let text = pieces.texts[ti]
        let tol = pieces.tolerance
        let reach = 1.5 * text.width + 2 * text.height
        let perpendicular = 3 * text.height
        let radius = perpendicular + reach + text.width
        let window = DXF.Box2(
            min: DXF.Point2(text.center.x - radius, text.center.y - radius),
            max: DXF.Point2(text.center.x + radius, text.center.y + radius))

        // The lines beside the text. The way the text runs is a preference, not a rule: a
        // horizontal text may stand beside a vertical line, and an exporter may write the angle
        // wrongly (Jw_cad writes 5156.62 for 90 degrees).
        var lines: [(unit: DXF.Point2, origin: DXF.Point2, distance: Double, turn: Double)] = []
        for s in pieces.segmentGrid.query(window) {
            let segment = pieces.segments[s]
            guard sameLayer(segment.layer, as: text) else { continue }
            let toCenter = minus(text.center, segment.a)
            let along = dot(segment.unit, toCenter)
            let distance = abs(cross(segment.unit, toCenter))
            guard distance <= perpendicular, max(0, -along, along - segment.length) <= reach
            else { continue }
            if !lines.contains(where: {
                abs(cross($0.unit, minus(segment.a, $0.origin))) <= tol
                    && abs(cross($0.unit, segment.unit)) <= 0.01
            }) {
                lines.append(
                    (segment.unit, segment.a, distance, abs(cross(segment.unit, text.direction))))
            }
        }
        // Lines that run the way the text does, then the nearest, first; a crowd is cut short.
        lines.sort {
            ($0.turn > 0.052 ? 1 : 0, $0.distance) < ($1.turn > 0.052 ? 1 : 0, $1.distance)
        }

        var candidates: [DXF.RebuildCandidate] = []
        for line in lines.prefix(16) {
            var found = spans(
                of: (line.unit, line.origin), text: text, textIndex: ti, reach: reach)
            for k in found.indices { found[k].cost += line.turn * 2 * text.height }
            candidates += found
        }
        candidates.sort { $0.cost < $1.cost }
        return Array(candidates.prefix(60))
    }

    private func sameLayer(_ layer: String, as text: DXF.RebuildPieces.Text) -> Bool {
        options.pieceLayers == .any || layer == text.layer
    }

    private func spans(
        of line: (unit: DXF.Point2, origin: DXF.Point2), text: DXF.RebuildPieces.Text,
        textIndex: Int, reach: Double
    ) -> [DXF.RebuildCandidate] {
        let tol = pieces.tolerance
        let (u, p0) = line
        func t(_ p: DXF.Point2) -> Double { dot(u, minus(p, p0)) }
        func perp(_ p: DXF.Point2) -> Double { abs(cross(u, minus(p, p0))) }

        // The pieces of the dimension line: the segments on this line.
        var carrier: [(entity: Int, lo: Double, hi: Double)] = []
        for s in collinear.near(u, p0) {
            let segment = pieces.segments[s]
            guard sameLayer(segment.layer, as: text), perp(segment.a) <= tol,
                perp(segment.b) <= tol
            else { continue }
            carrier.append(
                (segment.entity, min(t(segment.a), t(segment.b)), max(t(segment.a), t(segment.b))))
        }
        guard !carrier.isEmpty else { return [] }
        carrier.sort { $0.lo < $1.lo }
        var covers: [(lo: Double, hi: Double)] = []
        for piece in carrier {
            if let last = covers.last, piece.lo <= last.hi + tol {
                covers[covers.count - 1].hi = max(last.hi, piece.hi)
            } else {
                covers.append((piece.lo, piece.hi))
            }
        }
        func covered(_ position: Double) -> Bool {
            covers.contains { position >= $0.lo - tol && position <= $0.hi + tol }
        }

        // The ends: where another piece meets the line within what the line covers.
        var ends: [End] = []
        let lo = covers.first!.lo
        let hi = covers.last!.hi
        let a = DXF.Point2(p0.x + u.x * lo, p0.y + u.y * lo)
        let b = DXF.Point2(p0.x + u.x * hi, p0.y + u.y * hi)
        let box = DXF.RebuildPieces.bounds([a, b])
        let wide = DXF.Box2(
            min: DXF.Point2(box.min.x - tol, box.min.y - tol),
            max: DXF.Point2(box.max.x + tol, box.max.y + tol))
        for s in pieces.segmentGrid.query(wide) {
            let other = pieces.segments[s]
            guard sameLayer(other.layer, as: text), abs(cross(u, other.unit)) >= 0.3 else {
                continue
            }
            let d1 = cross(u, minus(other.a, p0))
            let d2 = cross(u, minus(other.b, p0))
            let position: Double
            if abs(d1) <= tol {
                position = t(other.a)
            } else if abs(d2) <= tol {
                position = t(other.b)
            } else if d1 * d2 < 0 {
                let along = d1 / (d1 - d2)
                position = t(
                    DXF.Point2(
                        other.a.x + along * (other.b.x - other.a.x),
                        other.a.y + along * (other.b.y - other.a.y)))
            } else {
                continue
            }
            if covered(position) {
                ends.append(End(t: position, exact: [position], entities: [other.entity]))
            }
        }
        for mark in pieces.marks where sameLayer(mark.layer, as: text) {
            guard perp(mark.at) <= 2 * tol, covered(t(mark.at)) else { continue }
            ends.append(End(t: t(mark.at), marked: [t(mark.at)], entities: mark.entities))
        }
        guard ends.count >= 2 else { return [] }

        // Ends within reach of each other are one.
        ends.sort { $0.t < $1.t }
        var merged: [End] = []
        for end in ends {
            if let last = merged.last, end.t - last.t <= 2 * tol {
                merged[merged.count - 1].exact += end.exact
                merged[merged.count - 1].marked += end.marked
                merged[merged.count - 1].entities += end.entities
            } else {
                merged.append(end)
            }
        }
        for k in merged.indices {
            let found = merged[k].exact.isEmpty ? merged[k].marked : merged[k].exact
            merged[k].t = found.reduce(0, +) / Double(found.count)
        }

        let tc = t(text.center)
        let offset = perp(text.center)
        var candidates: [DXF.RebuildCandidate] = []
        for i in merged.indices {
            for j in (i + 1)..<max(merged.count, i + 1) {
                let (from, to) = (merged[i].t, merged[j].t)
                let length = to - from
                guard length > 4 * tol, max(0, from - tc, tc - to) <= reach else { continue }
                guard spanIsCovered(from, to, covers: covers, around: tc, text: text) else {
                    continue
                }
                var used = Set(merged[i].entities + merged[j].entities)
                for piece in carrier where piece.hi >= from - tol && piece.lo <= to + tol {
                    used.insert(piece.entity)
                }
                candidates.append(
                    DXF.RebuildCandidate(
                        text: textIndex, length: length, cost: abs(tc - (from + to) / 2) + offset,
                        key: [], pieces: used.sorted(),
                        shape: .linear(origin: p0, unit: u, start: from, end: to)))
            }
        }
        return candidates
    }

    /// Whether the dimension line covers `from` to `to`, apart from a gap for the text.
    private func spanIsCovered(
        _ from: Double, _ to: Double, covers: [(lo: Double, hi: Double)], around tc: Double,
        text: DXF.RebuildPieces.Text
    ) -> Bool {
        let tol = pieces.tolerance
        var position = from
        for cover in covers where cover.hi > from {
            if cover.lo > to { break }
            if cover.lo > position + tol, !gapIsForText(position, cover.lo, tc, text) {
                return false
            }
            position = max(position, cover.hi)
            if position >= to - tol { return true }
        }
        return position >= to - tol || gapIsForText(position, to, tc, text)
    }

    private func gapIsForText(
        _ from: Double, _ to: Double, _ tc: Double, _ text: DXF.RebuildPieces.Text
    ) -> Bool {
        let tol = pieces.tolerance
        return to - from <= text.width + 2 * text.height && tc >= from - tol && tc <= to + tol
    }
}
