extension DXF.Contour {
    /// Something the caller may want to know about before trusting a result.
    public enum Warning: Equatable, Sendable, CustomStringConvertible {
        /// The file declares no usable units; `assumed` was used.
        case unitlessAssumed(LengthUnit)
        /// `$INSUNITS` holds a code with no modelled unit; `assumed` was used.
        case unknownUnitCode(Int, assumed: LengthUnit)
        /// Entities of an unmodelled type that were not read (never `INSERT`).
        case skippedEntities(type: String, count: Int)
        /// `INSERT` block references are not expanded, so their geometry is missing.
        case blockReferencesNotExpanded(count: Int)
        case ignoredText(count: Int)
        case ignoredDimensions(count: Int)
        case ignoredPoints(count: Int)
        /// Ellipses and splines replaced by lines and arcs, with the largest measured deviation
        /// from the true curve (an upper bound), in millimetres.
        case fittedCurves(count: Int, maxDeviation: Double)
        /// Segments that did not close into a loop.
        case openChains(count: Int, totalLength: Double)
        /// Zero-length, zero-radius or non-finite entities, segments shorter than the join
        /// tolerance, repeated segments, and loops with no area, that were dropped.
        case degenerateGeometry(count: Int)
        /// Loops that repeat another loop exactly and were dropped.
        case coincidentLoops(count: Int)
        /// Loops that cross another loop; they are not nested into it.
        case crossingLoops(count: Int)
        /// Nested loops dropped by ``NestingRule/outermostOnly``.
        case nestedLoopsDropped(count: Int)

        public var description: String {
            switch self {
            case .unitlessAssumed(let u): return "file is unitless, assumed \(u)"
            case .unknownUnitCode(let c, let u): return "unmodelled $INSUNITS \(c), assumed \(u)"
            case .skippedEntities(let t, let n): return "\(n) \(t) entities not read"
            case .blockReferencesNotExpanded(let n): return "\(n) INSERT references not expanded"
            case .ignoredText(let n): return "\(n) text entities ignored"
            case .ignoredDimensions(let n): return "\(n) dimensions ignored"
            case .ignoredPoints(let n): return "\(n) points ignored"
            case .fittedCurves(let n, let d): return "\(n) curves fitted, deviation <= \(d) mm"
            case .openChains(let n, let l): return "\(n) open chains (\(l) mm) did not close"
            case .degenerateGeometry(let n): return "\(n) degenerate or repeated pieces dropped"
            case .coincidentLoops(let n): return "\(n) duplicate loops dropped"
            case .crossingLoops(let n): return "\(n) loops cross another loop"
            case .nestedLoopsDropped(let n): return "\(n) nested loops dropped"
            }
        }
    }

    /// The outcome of ``DXF/Drawing/contours(_:)``.
    ///
    /// All lengths are millimetres.
    public struct Result: Sendable {
        /// Closed regions, largest outer area first.
        public var shapes: [Shape]
        /// Segments that never closed into a loop.
        public var openChains: [Chain]
        public var warnings: [Warning]
        /// The unit the drawing was read in.
        public var unit: LengthUnit
        /// Millimetres per drawing unit that were applied to every coordinate.
        public var unitScale: Double
        /// Largest measured distance between a fitted piece and the curve it replaces.
        public var maxFitDeviation: Double

        public init(
            shapes: [Shape] = [], openChains: [Chain] = [], warnings: [Warning] = [],
            unit: LengthUnit = .millimetre, unitScale: Double = 1, maxFitDeviation: Double = 0
        ) {
            self.shapes = shapes
            self.openChains = openChains
            self.warnings = warnings
            self.unit = unit
            self.unitScale = unitScale
            self.maxFitDeviation = maxFitDeviation
        }

        /// Every loop of every shape.
        public var loops: [Loop] { shapes.flatMap { $0.loops } }

        /// Sum of the shape areas.
        public var area: Double { shapes.reduce(0) { $0 + $1.area } }

        /// Bounds of all shapes and open chains, or `nil` when there are none.
        public var bounds: DXF.Box2? {
            var box: DXF.Box2?
            for s in shapes { box = box.map { $0.union(s.bounds) } ?? s.bounds }
            for c in openChains {
                for seg in c.segments { box = box.map { $0.union(seg.bounds) } ?? seg.bounds }
            }
            return box
        }
    }
}
