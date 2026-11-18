import Foundation

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
        var lines: [(seed: Int, distance: Double, turn: Double)] = []
        for s in pieces.segmentGrid.query(window) {
            let segment = pieces.segments[s]
            guard sameLayer(segment.layer, as: text) else { continue }
            let toCenter = minus(text.center, segment.a)
            let along = dot(segment.unit, toCenter)
            let distance = abs(cross(segment.unit, toCenter))
            guard distance <= perpendicular, max(0, -along, along - segment.length) <= reach
            else { continue }
            if !lines.contains(where: {
                let other = pieces.segments[$0.seed]
                return abs(cross(other.unit, minus(segment.a, other.a))) <= tol
                    && abs(cross(other.unit, segment.unit)) <= 0.01
            }) {
                lines.append((s, distance, abs(cross(segment.unit, text.direction))))
            }
        }
        // Lines that run the way the text does, then the nearest, first; a crowd is cut short.
        lines.sort {
            ($0.turn > 0.052 ? 1 : 0, $0.distance) < ($1.turn > 0.052 ? 1 : 0, $1.distance)
        }

        var candidates: [DXF.RebuildCandidate] = []
        for line in lines.prefix(16) {
            var found = spans(seed: line.seed, text: text, textIndex: ti, reach: reach)
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
        seed: Int, text: DXF.RebuildPieces.Text, textIndex: Int, reach: Double
    ) -> [DXF.RebuildCandidate] {
        let tol = pieces.tolerance
        let (u, p0) = (pieces.segments[seed].unit, pieces.segments[seed].a)
        func t(_ p: DXF.Point2) -> Double { dot(u, minus(p, p0)) }
        func perp(_ p: DXF.Point2) -> Double { abs(cross(u, minus(p, p0))) }

        // The pieces of the dimension line: the segments on this line, found by growing from the
        // one beside the text across gaps no wider than the text. The line is measured from the
        // seed, not from the origin, so the drawing may be anywhere.
        var carrier: [(entity: Int, lo: Double, hi: Double)] = []
        var members = Set<Int>()
        var first = Double.infinity
        var last = -Double.infinity
        func admit(_ s: Int) -> Bool {
            let segment = pieces.segments[s]
            guard !members.contains(s), sameLayer(segment.layer, as: text),
                perp(segment.a) <= tol, perp(segment.b) <= tol
            else { return false }
            members.insert(s)
            let (ta, tb) = (t(segment.a), t(segment.b))
            carrier.append((segment.entity, min(ta, tb), max(ta, tb)))
            first = min(first, ta, tb)
            last = max(last, ta, tb)
            return true
        }
        _ = admit(seed)
        let gap = text.width + 2 * text.height + 2 * tol
        var grew = true
        var rounds = 0
        while grew, rounds < 1000 {
            grew = false
            rounds += 1
            let window = DXF.RebuildPieces.bounds([
                DXF.Point2(p0.x + u.x * (first - gap), p0.y + u.y * (first - gap)),
                DXF.Point2(p0.x + u.x * (last + gap), p0.y + u.y * (last + gap)),
            ])
            let wide = DXF.Box2(
                min: DXF.Point2(window.min.x - tol, window.min.y - tol),
                max: DXF.Point2(window.max.x + tol, window.max.y + tol))
            for s in pieces.segmentGrid.query(wide) where admit(s) { grew = true }
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
        // A span is up to eight ends of the line, or the whole of it, so that a line with
        // hundreds of ends is not tried in every pair.
        for i in merged.indices {
            if merged[i].t - tc > reach { break }
            var others = Array((i + 1)..<max(min(i + 9, merged.count), i + 1))
            if i == 0, merged.count > 9 { others.append(merged.count - 1) }
            for j in others {
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
