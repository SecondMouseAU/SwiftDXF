import Foundation

extension DXF {
    /// A `HATCH`: the closed regions it fills and its pattern, not the individual hatch lines.
    public struct Hatch: Equatable, Sendable {
        /// The pattern name (group 2), such as `SOLID` or `ANSI31`.
        public var patternName: String
        /// Whether the fill is solid (group 70).
        public var isSolid: Bool
        /// Whether the hatch follows its boundary objects (group 71).
        public var isAssociative: Bool
        public var loops: [Loop]
        public var layer: String
        public var color: Int
        /// The line type as written (group 6), or `nil` for by-layer.
        public var lineType: String?
        public var identity: EntityIdentity

        public init(
            patternName: String, isSolid: Bool, isAssociative: Bool = false, loops: [Loop] = [],
            layer: String = "0", color: Int = 256, lineType: String? = nil,
            identity: EntityIdentity
        ) {
            self.patternName = patternName
            self.isSolid = isSolid
            self.isAssociative = isAssociative
            self.loops = loops
            self.layer = layer
            self.color = color
            self.lineType = lineType
            self.identity = identity
        }

        /// One boundary path.
        public struct Loop: Equatable, Sendable {
            /// The path type flags (group 92).
            public var flags: Int
            public var content: Content

            public init(flags: Int, content: Content) {
                self.flags = flags
                self.content = content
            }

            /// Flag bit 1: an external boundary.
            public var isExternal: Bool { flags & 1 != 0 }
            /// Flag bit 16: the outermost boundary.
            public var isOutermost: Bool { flags & 16 != 0 }
        }

        /// A boundary path is either a polyline or a chain of edges.
        public enum Content: Equatable, Sendable {
            case polyline(vertices: [PolyVertex], closed: Bool)
            case edges([Edge])
        }

        /// One edge of a boundary path.
        ///
        /// Angles are in degrees, as the file stores them.
        public enum Edge: Equatable, Sendable {
            case line(a: Point2, b: Point2)
            /// Sweeps from start to end counter-clockwise, or clockwise when `counterClockwise`
            /// is false.
            case arc(
                center: Point2, radius: Double, startDeg: Double, endDeg: Double,
                counterClockwise: Bool)
            /// `majorAxis` is relative to `center`; `startDeg`/`endDeg` are the parameter range.
            case ellipse(
                center: Point2, majorAxis: Point2, ratio: Double, startDeg: Double,
                endDeg: Double, counterClockwise: Bool)
            case spline(degree: Int, controlPoints: [Point2], knots: [Double], weights: [Double])
        }
    }

    /// A `LEADER`: the arrow from a note or dimension to the feature it refers to.
    public struct Leader: Equatable, Sendable {
        public var vertices: [Point]
        /// Whether an arrowhead is drawn at the first vertex (group 71).
        public var hasArrowhead: Bool
        /// Whether the path is a spline rather than straight segments (group 72).
        public var isSpline: Bool
        public var annotation: Annotation
        /// The handle of the annotation entity (group 340), to look up in ``Drawing/identities``.
        public var annotationHandle: String?
        /// The dimension style name (group 3).
        public var styleName: String?
        public var layer: String
        public var color: Int
        /// The line type as written (group 6), or `nil` for by-layer.
        public var lineType: String?
        public var identity: EntityIdentity

        public enum Annotation: Equatable, Sendable {
            case text
            case tolerance
            case blockReference
            case none
        }

        public init(
            vertices: [Point], hasArrowhead: Bool = true, isSpline: Bool = false,
            annotation: Annotation = .none, annotationHandle: String? = nil,
            styleName: String? = nil, layer: String = "0", color: Int = 256,
            lineType: String? = nil, identity: EntityIdentity
        ) {
            self.vertices = vertices
            self.hasArrowhead = hasArrowhead
            self.isSpline = isSpline
            self.annotation = annotation
            self.annotationHandle = annotationHandle
            self.styleName = styleName
            self.layer = layer
            self.color = color
            self.lineType = lineType
            self.identity = identity
        }
    }
}
