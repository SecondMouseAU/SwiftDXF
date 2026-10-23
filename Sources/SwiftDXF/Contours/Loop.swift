import Foundation

extension DXF.Contour {
    /// A closed chain of segments: each segment starts exactly where the previous one ends, and the
    /// last ends where the first starts.
    public struct Loop: Equatable, Sendable {
        public private(set) var segments: [Segment]
        /// Source layers of the entities that make up the loop, sorted.
        public private(set) var layers: [String]
        /// Positive for a counter-clockwise loop, negative for a clockwise one.
        public private(set) var signedArea: Double
        /// Exact bounds, including arc extrema.
        public private(set) var bounds: DXF.Box2

        /// Builds a loop from consecutive segments that already close.
        public init(segments: [Segment], layers: [String] = []) {
            self.segments = segments
            self.layers = layers
            self.signedArea = segments.reduce(0) { $0 + $1.areaTerm }
            var box: DXF.Box2?
            for segment in segments {
                box = box.map { $0.union(segment.bounds) } ?? segment.bounds
            }
            self.bounds = box ?? DXF.Box2(min: DXF.Point2(0, 0), max: DXF.Point2(0, 0))
        }

        /// Absolute enclosed area.
        public var area: Double { abs(signedArea) }

        public var isCounterClockwise: Bool { signedArea > 0 }

        /// Total path length.
        public var length: Double { segments.reduce(0) { $0 + $1.length } }

        /// The same loop traversed the other way.
        public func reversed() -> Loop {
            Loop(segments: segments.reversed().map { $0.reversed() }, layers: layers)
        }
    }

    /// An outer boundary with the holes cut into it.
    ///
    /// `outer` is counter-clockwise and every hole is clockwise, so the signed areas of the loops
    /// sum to the shape's area. An island sitting inside a hole is a separate `Shape`.
    public struct Shape: Equatable, Sendable {
        public var outer: Loop
        public var holes: [Loop]

        public init(outer: Loop, holes: [Loop] = []) {
            self.outer = outer
            self.holes = holes
        }

        /// Outer area minus the holes.
        public var area: Double { outer.area - holes.reduce(0) { $0 + $1.area } }

        public var bounds: DXF.Box2 { outer.bounds }

        /// The outer loop followed by the holes.
        public var loops: [Loop] { [outer] + holes }
    }

    /// Segments that joined end to end but never closed.
    public struct Chain: Equatable, Sendable {
        public var segments: [Segment]
        public var layers: [String]

        public init(segments: [Segment], layers: [String] = []) {
            self.segments = segments
            self.layers = layers
        }

        public var start: DXF.Point2? { segments.first?.start }
        public var end: DXF.Point2? { segments.last?.end }
        public var length: Double { segments.reduce(0) { $0 + $1.length } }
    }
}
