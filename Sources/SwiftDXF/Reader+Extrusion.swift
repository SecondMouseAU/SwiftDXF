import Foundation

extension DXF.Reader {
    /// The plane the record's object coordinate system lies in.
    func objectPlane(_ f: Fields) -> DXF.ObjectPlane {
        DXF.ObjectPlane(extrusion: DXF.Point(dbl(210, f, 0), dbl(220, f, 0), dbl(230, f, 1)))
    }

    /// Whether a record of `type` is written in its object coordinate system (OCS).
    ///
    /// `MTEXT`, `POINT`, `SPLINE` and `LEADER` hold world coordinates, and so does a 3D polyline,
    /// polygon mesh or polyface mesh (flags 8, 16 and 64 of `POLYLINE`). An `ELLIPSE` holds its
    /// centre and axis in the world, but its extrusion says which way its parameter runs.
    func usesObjectCoordinates(_ type: String, _ f: Fields) -> Bool {
        switch type {
        case "ARC", "CIRCLE", "LWPOLYLINE", "TEXT", "HATCH", "ELLIPSE", "DIMENSION": return true
        case "POLYLINE": return (ints(70, f) ?? 0) & (8 | 16 | 64) == 0
        default: return false
        }
    }

    /// `entity` carried out of the object coordinate system of the record it was read from.
    ///
    /// Only a `-z` normal changes anything; a tilted one is left as written, and counted by the
    /// caller.
    func inWorld(_ entity: DXF.Entity, _ f: Fields) -> DXF.Entity {
        guard objectPlane(f) == .down else { return entity }
        let mirror = DXF.ObjectPlane.mirror
        switch entity {
        case .ellipse:
            // The centre and the axis are already in the world; see `ellipseRange`.
            return entity
        case .dimension(var d):
            // Only the text point (group 11) and the arc point (group 16) are in the OCS; the
            // definition points are world coordinates.
            d.textPosition = mirror.apply(d.textPosition)
            d.defPoint5 = d.defPoint5.map(mirror.apply)
            return .dimension(d)
        default:
            return entity.transformed(by: mirror) ?? entity
        }
    }

    /// The parameter range of an `ELLIPSE` whose extrusion is `-z`, as the counter-clockwise range
    /// of the same curve.
    ///
    /// The parameter runs the other way round the ellipse seen from `+z`, so the range is
    /// reversed and moved to start in `0..<2 pi`.
    static func mirroredEllipseRange(start: Double, end: Double) -> (Double, Double) {
        let (s, e) = (-end, -start)
        let turn = 2 * Double.pi
        let shift = (s / turn).rounded(.down) * turn
        return (s - shift, e - shift)
    }
}
