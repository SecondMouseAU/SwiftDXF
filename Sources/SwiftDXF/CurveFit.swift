extension DXF {
    /// A `SPLINE` or `ELLIPSE` replaced by lines and circular arcs.
    ///
    /// Made by ``Entity/fitted(tolerance:source:)``. The pieces are the ones the contour layer
    /// uses for the same entity, in the drawing's own units.
    public struct CurveFit: Equatable, Sendable {
        /// One line or arc of the fit.
        public struct Piece: Equatable, Sendable {
            /// The line or arc, as a chord and a bulge; an arc never sweeps more than a half turn.
            public var segment: Contour.Segment
            /// The entity the piece came from, when the caller named it.
            public var source: Identity?

            public init(segment: Contour.Segment, source: Identity? = nil) {
                self.segment = segment
                self.source = source
            }
        }

        /// The pieces in order along the curve, each starting where the one before ends.
        ///
        /// Empty when the entity is degenerate (zero size, or not enough points).
        public var pieces: [Piece]
        /// An upper bound on the distance from any piece to the true curve, never above the
        /// tolerance asked for.
        public var deviation: Double
        /// `true` when the curve is exactly a straight line or a circular arc (or circle), so
        /// ``pieces`` are the curve itself and ``deviation`` is rounding error only.
        public var isExact: Bool
        /// The entity the fit was made from, when the caller named it.
        public var source: Identity?

        public init(
            pieces: [Piece] = [], deviation: Double = 0, isExact: Bool = false,
            source: Identity? = nil
        ) {
            self.pieces = pieces
            self.deviation = deviation
            self.isExact = isExact
            self.source = source
        }
    }
}
