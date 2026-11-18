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
}
