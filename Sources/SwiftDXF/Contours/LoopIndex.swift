import Foundation

/// Buckets a loop's segments by y so a point query touches a handful of segments, not all of them.
struct LoopIndex {
    private let segments: [DXF.Contour.Segment]
    private let bounds: DXF.Box2
    private let bucketHeight: Double
    private var buckets: [[Int32]]

    init(_ loop: DXF.Contour.Loop) {
        segments = loop.segments
        bounds = loop.bounds
        let count = max(1, min(segments.count / 4, 4096))
        let height = max(bounds.height, 1e-300) / Double(count)
        bucketHeight = height
        buckets = [[Int32]](repeating: [], count: count)
        for (i, s) in segments.enumerated() {
            let box = s.bounds
            let lo = Self.bucket(box.min.y, bounds.min.y, height, count)
            let hi = Self.bucket(box.max.y, bounds.min.y, height, count)
            for b in lo...hi { buckets[b].append(Int32(i)) }
        }
    }

    private static func bucket(_ y: Double, _ origin: Double, _ height: Double, _ count: Int) -> Int
    {
        let raw = ((y - origin) / height).rounded(.down)
        return raw.isFinite ? max(0, min(count - 1, Int(raw))) : 0
    }

    /// Even-odd containment of `p` and the distance to the nearest segment within `reach`
    /// (infinity when nothing is that close).
    func classify(_ p: DXF.Point2, reach: Double) -> (inside: Bool, distance: Double) {
        guard bounds.contains(p, slack: reach) else { return (false, .infinity) }
        let count = buckets.count
        var inside = false
        for i in buckets[Self.bucket(p.y, bounds.min.y, bucketHeight, count)] {
            if ContourNesting.crosses(p, segments[Int(i)]) { inside.toggle() }
        }
        let lo = Self.bucket(p.y - reach, bounds.min.y, bucketHeight, count)
        let hi = Self.bucket(p.y + reach, bounds.min.y, bucketHeight, count)
        var nearest = Double.infinity
        for b in lo...hi {
            for i in buckets[b] {
                nearest = min(nearest, ContourNesting.distance(p, segments[Int(i)]))
            }
        }
        return (inside, nearest)
    }
}
