import Foundation

extension DXF.DimensionRebuilder {
    /// The candidates that read `text` as a diameter or a radius, from the geometry alone.
    ///
    /// A line through the centre of a circle or arc that ends on it at both ends is a diameter. One
    /// that ends on it at one end only, from the centre or along a leader, is a radius. The symbol
    /// of the text is not used here; it is checked against the result.
    func radialCandidates(_ ti: Int) -> [DXF.RebuildCandidate] {
        let text = pieces.texts[ti]
        let tol = pieces.tolerance
        let reach = 6 * text.height + text.width
        let window = DXF.Box2(
            min: DXF.Point2(text.center.x - reach, text.center.y - reach),
            max: DXF.Point2(text.center.x + reach, text.center.y + reach))
        let nearby = pieces.segmentGrid.query(window)
        var candidates: [DXF.RebuildCandidate] = []
        for (ci, circle) in pieces.circles.enumerated()
        where circle.center.distance(to: text.center) <= circle.radius + reach {
            for s in nearby {
                let segment = pieces.segments[s]
                guard options.pieceLayers == .any || segment.layer == text.layer else { continue }
                let toCenter = DXF.Point2(
                    circle.center.x - segment.a.x, circle.center.y - segment.a.y)
                guard abs(segment.unit.x * toCenter.y - segment.unit.y * toCenter.x) <= 2 * tol
                else { continue }
                let nearest = nearestPoint(on: segment, to: text.center)
                let distance = nearest.distance(to: text.center)
                guard distance <= reach else { continue }
                let onA = lies(segment.a, on: circle)
                let onB = lies(segment.b, on: circle)
                let shape: DXF.RebuildCandidate.Shape
                let length: Double
                if onA && onB {
                    length = segment.a.distance(to: segment.b)
                    guard abs(length - 2 * circle.radius) <= 4 * tol else { continue }
                    shape = .radial(kind: .diameter, first: segment.a, second: segment.b)
                } else if onA != onB {
                    length = circle.radius
                    shape = .radial(
                        kind: .radius, first: circle.center, second: onA ? segment.a : segment.b)
                } else {
                    continue
                }
                candidates.append(
                    DXF.RebuildCandidate(
                        text: ti, length: length, cost: distance, key: [1, ci, s],
                        pieces: [segment.entity, circle.entity], shape: shape))
            }
        }
        candidates.sort { $0.cost < $1.cost }
        return Array(candidates.prefix(20))
    }

    private func nearestPoint(on segment: DXF.RebuildPieces.Segment, to p: DXF.Point2)
        -> DXF.Point2
    {
        let along = (p.x - segment.a.x) * segment.unit.x + (p.y - segment.a.y) * segment.unit.y
        let t = min(max(along, 0), segment.length)
        return DXF.Point2(segment.a.x + segment.unit.x * t, segment.a.y + segment.unit.y * t)
    }

    /// Whether `p` is on the circle or on the arc, within the tolerance.
    private func lies(_ p: DXF.Point2, on circle: DXF.RebuildPieces.Circle) -> Bool {
        let tol = 2 * pieces.tolerance
        guard abs(p.distance(to: circle.center) - circle.radius) <= tol else { return false }
        guard let span = circle.span else { return true }
        let degrees = atan2(p.y - circle.center.y, p.x - circle.center.x) * 180 / .pi
        let raw = span.end - span.start
        let sweep = raw >= 360 - 1e-9 ? 360 : (raw + 720).truncatingRemainder(dividingBy: 360)
        let from = (degrees - span.start + 720).truncatingRemainder(dividingBy: 360)
        // Allow for the tolerance on either side of the ends of the arc.
        let slack = tol / max(circle.radius, 1e-9) * 180 / .pi
        return from <= sweep + slack || from >= 360 - slack
    }
}
