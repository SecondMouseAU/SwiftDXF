extension DXF {
    /// The plane an entity's object coordinate system (OCS) lies in, from its extrusion direction
    /// (groups 210, 220, 230).
    ///
    /// Arcs, circles, polylines, text, hatches and the text point of a dimension are written in
    /// their own OCS. For a normal along z the OCS differs from the world by at most a mirror, which
    /// a planar entity can carry; any other normal tips the entity out of the drawing plane.
    enum ObjectPlane: Equatable {
        /// The normal is `+z`, or absent: the OCS is the world.
        case up
        /// The normal is `-z`: the OCS x axis is the world `-x` and its z axis the world `-z`.
        case down
        /// The normal is neither, so a planar entity cannot hold the geometry as written.
        case tilted

        init(extrusion e: Point) {
            let length = (e.x * e.x + e.y * e.y + e.z * e.z).squareRoot()
            guard length.isFinite, length > 1e-12 else {
                self = .up
                return
            }
            if abs(e.x / length) < 1e-9, abs(e.y / length) < 1e-9 {
                self = e.z < 0 ? .down : .up
            } else {
                self = .tilted
            }
        }

        /// The map from a `.down` OCS to the world: `(x, y, z)` becomes `(-x, y, -z)`.
        static var mirror: Transform {
            var t = Transform()
            t.a = -1
            t.zScale = -1
            return t
        }
    }
}
