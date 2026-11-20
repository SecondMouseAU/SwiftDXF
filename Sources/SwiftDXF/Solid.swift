extension DXF {
    /// A `SOLID`: a filled triangle or quadrilateral, often an arrowhead or a filled mark.
    public struct Solid: Equatable, Sendable {
        /// The corners in the order that walks the outline: three for a triangle, four for a
        /// quadrilateral.
        ///
        /// The file lists the corners 1, 2, 4, 3 around the outline (groups 10, 11, 12, 13), so
        /// the third and fourth are swapped here; a file that repeats the third corner as the
        /// fourth, or leaves out the fourth, is a triangle. The corners are in the world (a record
        /// on a `-z` plane is converted), and keep their z.
        public var corners: [Point]
        public var layer: String
        public var color: Int

        public init(corners: [Point], layer: String = "0", color: Int = 256) {
            self.corners = corners
            self.layer = layer
            self.color = color
        }

        /// Whether the fill has three corners.
        public var isTriangle: Bool { corners.count == 3 }
    }
}
