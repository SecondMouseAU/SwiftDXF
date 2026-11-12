extension DXF.Entity {
    /// A `SPLINE` or `ELLIPSE` as lines and arcs within `tolerance`, or `nil` for any other entity.
    ///
    /// ```swift
    /// if case .spline(let s) = entity {
    ///     let fit = s.fitted(tolerance: 0.001)    // drawing units
    ///     fit.pieces.map(\.segment)                // lines and arcs
    ///     fit.deviation                           // at most 0.001
    /// }
    /// ```
    ///
    /// A spline that is exactly a straight line or a circular arc comes back as that line or arc
    /// (``DXF/CurveFit/isExact``); so does an ellipse with equal axes. Anything else is sampled
    /// and covered greedily by the longest line or arc that stays within the tolerance, the same
    /// fit ``DXF/Drawing/contours(_:)`` makes. Never traps: degenerate input gives no pieces.
    ///
    /// - Parameters:
    ///   - tolerance: The largest distance a piece may stray from the curve, in drawing units.
    ///   - source: The identity to stamp on the fit and on each piece, usually
    ///     ``DXF/Drawing/identity(ofEntityAt:)``.
    /// - Returns: The fit, or `nil` when the entity is not a spline or an ellipse.
    public func fitted(tolerance: Double, source: DXF.Identity? = nil) -> DXF.CurveFit? {
        switch self {
        case .spline, .ellipse: break
        default: return nil
        }
        let tol = tolerance.isFinite ? max(tolerance, 1e-9) : 1e-9
        var extractor = SegmentExtractor(scale: 1, fitTolerance: tol)
        extractor.add(self, layer: 0)
        let pieces = extractor.segments.map {
            DXF.CurveFit.Piece(
                segment: DXF.Contour.Segment(start: $0.a, end: $0.b, bulge: $0.bulge),
                source: source)
        }
        return DXF.CurveFit(
            pieces: pieces, deviation: extractor.fitDeviation,
            isExact: extractor.exactCurves > 0 && !pieces.isEmpty, source: source)
    }
}

extension DXF.Spline {
    /// The spline as lines and arcs within `tolerance` (drawing units); see
    /// ``DXF/Entity/fitted(tolerance:source:)``.
    public func fitted(tolerance: Double, source: DXF.Identity? = nil) -> DXF.CurveFit {
        DXF.Entity.spline(self).fitted(tolerance: tolerance, source: source) ?? DXF.CurveFit()
    }
}

extension DXF.Drawing {
    /// The fit of the spline or ellipse at `index` in ``entities``, stamped with its identity.
    ///
    /// `nil` when `index` is out of range or the entity is neither a spline nor an ellipse.
    public func fittedCurve(at index: Int, tolerance: Double) -> DXF.CurveFit? {
        guard entities.indices.contains(index) else { return nil }
        return entities[index].fitted(tolerance: tolerance, source: identity(ofEntityAt: index))
    }
}
