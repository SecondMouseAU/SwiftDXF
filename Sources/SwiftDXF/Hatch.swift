extension DXF {
    /// A `HATCH`: which regions are filled, and the boundaries that enclose them.
    ///
    /// Only the boundary and the fill kind are read, not the individual hatch lines. On a section
    /// view a hatched region is cut material.
    public struct Hatch: Equatable, Sendable {
        /// The pattern name (group 2), for example `SOLID` or `ANSI31`.
        public var patternName: String
        /// `true` for a solid fill (group 70).
        public var isSolid: Bool
        public var paths: [BoundaryPath]
        public var layer: String
        public var color: Int

        public init(
            patternName: String, isSolid: Bool, paths: [BoundaryPath] = [], layer: String = "0",
            color: Int = 256
        ) {
            self.patternName = patternName
            self.isSolid = isSolid
            self.paths = paths
            self.layer = layer
            self.color = color
        }

        /// One closed boundary loop of a hatch.
        public struct BoundaryPath: Equatable, Sendable {
            /// The path type flags (group 92).
            public var flags: Int
            public var geometry: Geometry

            public init(flags: Int, geometry: Geometry) {
                self.flags = flags
                self.geometry = geometry
            }

            /// Flag bit 1: the outer boundary.
            ///
            /// A path without it is an inner loop, an island or a hole.
            public var isExternal: Bool { flags & 1 != 0 }
            /// Flag bit 4: the path was derived from other objects.
            public var isDerived: Bool { flags & 4 != 0 }
            /// Flag bit 16: an outermost island boundary.
            public var isOutermost: Bool { flags & 16 != 0 }
        }

        /// How a boundary path is written in the file.
        public enum Geometry: Equatable, Sendable {
            /// A polyline path: vertices with bulges, so arcs are exact.
            case polyline(vertices: [PolyVertex], closed: Bool)
            /// An edge path: a chain of lines, arcs, ellipse arcs and splines.
            case edges([Edge])
        }

        /// One edge of an edge-type boundary path.
        ///
        /// Angles and parameters run counter-clockwise from start to end. DXF stores a clockwise
        /// edge as the complementary angles (`360 - angle`); the reader converts them, as
        /// `ezdxf` does, and keeps `counterClockwise` to say which way the path travels the edge.
        public enum Edge: Equatable, Sendable {
            case line(start: Point2, end: Point2)
            /// A circular arc, angles in degrees.
            case arc(
                center: Point2, radius: Double, startDeg: Double, endDeg: Double,
                counterClockwise: Bool)
            /// An elliptical arc. `majorAxis` is relative to `center`; the parameters are radians
            /// (`0...2 pi` for a full ellipse), as for the ``DXF/Entity/ellipse(center:majorAxis:ratio:startParam:endParam:layer:color:)`` entity.
            case ellipse(
                center: Point2, majorAxis: Point2, ratio: Double, startParam: Double,
                endParam: Double, counterClockwise: Bool)
            /// A spline edge, in the drawing plane.
            case spline(Spline)
        }
    }
}
