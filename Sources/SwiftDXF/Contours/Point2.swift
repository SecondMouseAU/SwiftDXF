import Foundation

extension DXF {
    /// A point in the drawing plane.
    ///
    /// Contours are planar, so `z` is dropped.
    public struct Point2: Equatable, Hashable, Sendable {
        public var x: Double
        public var y: Double
        public init(_ x: Double, _ y: Double) {
            self.x = x
            self.y = y
        }

        /// Euclidean distance to `other`.
        public func distance(to other: Point2) -> Double {
            Foundation.hypot(x - other.x, y - other.y)
        }
    }

    /// An axis-aligned box.
    public struct Box2: Equatable, Sendable {
        public var min: Point2
        public var max: Point2
        public init(min: Point2, max: Point2) {
            self.min = min
            self.max = max
        }

        public var width: Double { max.x - min.x }
        public var height: Double { max.y - min.y }

        /// The smallest box containing both boxes.
        public func union(_ other: Box2) -> Box2 {
            Box2(
                min: Point2(Swift.min(min.x, other.min.x), Swift.min(min.y, other.min.y)),
                max: Point2(Swift.max(max.x, other.max.x), Swift.max(max.y, other.max.y)))
        }

        /// Whether `other` lies inside this box, allowing `slack` on every side.
        func contains(_ other: Box2, slack: Double) -> Bool {
            other.min.x >= min.x - slack && other.min.y >= min.y - slack
                && other.max.x <= max.x + slack && other.max.y <= max.y + slack
        }

        func contains(_ p: Point2, slack: Double) -> Bool {
            p.x >= min.x - slack && p.x <= max.x + slack && p.y >= min.y - slack
                && p.y <= max.y + slack
        }
    }
}
