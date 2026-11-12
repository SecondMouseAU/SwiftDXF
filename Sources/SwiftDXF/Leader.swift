extension DXF {
    /// A `LEADER`: the line from a note or dimension to the feature it refers to.
    public struct Leader: Equatable, Sendable {
        /// The leader path, starting at the arrowhead end (groups 10, 20, 30).
        public var vertices: [Point]
        /// Whether the leader has an arrowhead (group 71).
        public var hasArrowhead: Bool
        /// `true` when the path is a spline through the vertices, `false` for straight segments
        /// (group 72).
        public var isSpline: Bool
        /// The handle of the annotation the leader is attached to (group 340), or `nil`.
        ///
        /// Matches the ``Identity/handle`` of the text, tolerance or block reference it names.
        public var annotationHandle: String?
        /// The dimension style name (group 3), or `nil`.
        public var styleName: String?
        public var layer: String
        public var color: Int

        public init(
            vertices: [Point], hasArrowhead: Bool = true, isSpline: Bool = false,
            annotationHandle: String? = nil, styleName: String? = nil, layer: String = "0",
            color: Int = 256
        ) {
            self.vertices = vertices
            self.hasArrowhead = hasArrowhead
            self.isSpline = isSpline
            self.annotationHandle = annotationHandle
            self.styleName = styleName
            self.layer = layer
            self.color = color
        }
    }
}
