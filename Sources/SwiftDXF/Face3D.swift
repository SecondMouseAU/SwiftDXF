extension DXF {
    /// A `3DFACE`: a triangle or quadrilateral of a surface, with its z kept.
    public struct Face3D: Equatable, Sendable {
        /// The four corners in the order the file lists them (groups 10, 11, 12, 13), which is the
        /// order around the outline.
        ///
        /// A triangle repeats the third corner as the fourth (a file that leaves out the fourth
        /// is read the same way); see ``isTriangle``. Edge `i` runs from corner `i` to corner
        /// `i + 1`, and the last from the fourth back to the first.
        public var corners: [Point]
        /// The edges hidden from view, as the file writes them (group 70): bit 1 is the first
        /// edge, 2 the second, 4 the third and 8 the fourth.
        public var invisibleEdges: Int
        public var layer: String
        public var color: Int

        public init(
            corners: [Point], invisibleEdges: Int = 0, layer: String = "0", color: Int = 256
        ) {
            self.corners = corners
            self.invisibleEdges = invisibleEdges
            self.layer = layer
            self.color = color
        }

        /// Whether the fourth corner repeats the third, so the face has three corners.
        public var isTriangle: Bool { corners.count == 4 && corners[3] == corners[2] }

        /// Whether the edge at `index` (0 to 3) is drawn, as opposed to hidden by
        /// ``invisibleEdges``.
        public func isEdgeVisible(_ index: Int) -> Bool {
            guard (0..<4).contains(index) else { return false }
            return invisibleEdges & (1 << index) == 0
        }
    }
}
