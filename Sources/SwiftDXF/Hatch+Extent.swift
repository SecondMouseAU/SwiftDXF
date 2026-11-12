import Foundation

extension DXF.Hatch {
    /// Points whose bounding box contains every boundary path.
    ///
    /// Curved edges contribute a conservative box (centre plus or minus the radius, or the
    /// major-axis length), as ``DXF/Drawing/bounds`` does for arcs and ellipses.
    var extentPoints: [DXF.Point] {
        var out: [DXF.Point] = []
        func box(_ c: DXF.Point2, _ r: Double) {
            out.append(DXF.Point(c.x - r, c.y - r, 0))
            out.append(DXF.Point(c.x + r, c.y + r, 0))
        }
        for path in paths {
            switch path.geometry {
            case .polyline(let vertices, _):
                out.append(contentsOf: vertices.map(\.point))
            case .edges(let edges):
                for edge in edges {
                    switch edge {
                    case .line(let a, let b):
                        out.append(DXF.Point(a.x, a.y, 0))
                        out.append(DXF.Point(b.x, b.y, 0))
                    case .arc(let c, let r, _, _, _): box(c, r)
                    case .ellipse(let c, let m, _, _, _, _): box(c, hypot(m.x, m.y))
                    case .spline(let s):
                        let points = s.controlPoints.isEmpty ? s.fitPoints : s.controlPoints
                        out.append(contentsOf: points)
                    }
                }
            }
        }
        return out
    }
}
