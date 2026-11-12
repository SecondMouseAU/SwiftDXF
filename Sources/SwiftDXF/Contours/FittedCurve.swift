import Foundation

extension DXF {
    /// A spline or ellipse replaced by lines and circular arcs within a tolerance.
    ///
    /// The pieces are in drawing units, in curve order, and each one is a ``Contour/Segment``:
    /// a chord plus a bulge, never more than a half turn.
    public struct FittedCurve: Equatable, Sendable {
        /// What the curve turned out to be.
        public enum Recognized: Equatable, Sendable {
            /// One straight line: many CAD exporters write a plain line as a spline.
            case line
            /// One circle: every piece lies on the same circle, within the tolerance.
            case arc(center: Point2, radius: Double)
            /// Neither: a free-form curve, fitted by several pieces.
            case curve
        }

        /// The index in ``Drawing/entities`` of the entity the pieces came from.
        public var entityIndex: Int
        /// That entity's identity, when the drawing carries identities.
        public var identity: EntityIdentity?
        public var layer: String
        public var segments: [Contour.Segment]
        /// An upper bound on the distance from the pieces to the exact curve.
        public var deviation: Double
        public var recognized: Recognized

        public init(
            entityIndex: Int, identity: EntityIdentity?, layer: String,
            segments: [Contour.Segment], deviation: Double, recognized: Recognized
        ) {
            self.entityIndex = entityIndex
            self.identity = identity
            self.layer = layer
            self.segments = segments
            self.deviation = deviation
            self.recognized = recognized
        }
    }
}

extension DXF.Entity {
    /// A spline or ellipse as lines and arcs within `tolerance` (drawing units), or `nil` for any
    /// other entity or a degenerate curve.
    ///
    /// The result's `entityIndex` and `identity` are filled in by ``DXF/Drawing/fittedCurves(tolerance:layers:)``.
    public func fitted(tolerance: Double) -> DXF.FittedCurve? {
        switch self {
        case .spline, .ellipse: break
        default: return nil
        }
        let tol = tolerance.isFinite && tolerance > 0 ? tolerance : 1e-6
        var extractor = SegmentExtractor(scale: 1, fitTolerance: tol)
        extractor.add(self, layer: 0)
        let segments = extractor.segments.map {
            DXF.Contour.Segment(start: $0.a, end: $0.b, bulge: $0.bulge)
        }
        guard !segments.isEmpty else { return nil }
        return DXF.FittedCurve(
            entityIndex: -1, identity: nil, layer: layer, segments: segments,
            deviation: extractor.fitDeviation, recognized: Self.recognize(segments, tol))
    }

    private static func recognize(
        _ segments: [DXF.Contour.Segment], _ tolerance: Double
    ) -> DXF.FittedCurve.Recognized {
        if segments.count == 1, !segments[0].isArc { return .line }
        guard let first = segments.first, let c = first.center, let r = first.radius,
            segments.allSatisfy({ $0.isArc })
        else { return .curve }
        for s in segments {
            guard let sc = s.center, let sr = s.radius, sc.distance(to: c) <= tolerance,
                abs(sr - r) <= tolerance
            else { return .curve }
        }
        return .arc(center: c, radius: r)
    }
}

extension DXF.Drawing {
    /// Every spline and ellipse as lines and arcs within `tolerance` (drawing units), with the
    /// entity each came from.
    ///
    /// - Parameters:
    ///   - tolerance: The largest distance from the pieces to the exact curve, in drawing units.
    ///   - layers: Only entities on these layers (case-insensitive); `nil` for all.
    /// - Returns: One fit per spline or ellipse, in entity order.
    public func fittedCurves(tolerance: Double, layers: Set<String>? = nil) -> [DXF.FittedCurve] {
        let wanted = layers.map { Set($0.map { $0.lowercased() }) }
        var out: [DXF.FittedCurve] = []
        for (index, entity) in entities.enumerated() {
            if let wanted, !wanted.contains(entity.layer.lowercased()) { continue }
            guard var fit = entity.fitted(tolerance: tolerance) else { continue }
            fit.entityIndex = index
            fit.identity = identities.indices.contains(index) ? identities[index] : nil
            out.append(fit)
        }
        return out
    }
}
