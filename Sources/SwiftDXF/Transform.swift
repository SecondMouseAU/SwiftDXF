import Foundation

extension DXF {
    /// An affine map of the drawing plane with a separate z scale and offset.
    ///
    /// `x' = a x + c y + tx`, `y' = b x + d y + ty`.
    struct Transform {
        var a = 1.0
        var b = 0.0
        var c = 0.0
        var d = 1.0
        var tx = 0.0
        var ty = 0.0
        var zScale = 1.0
        var tz = 0.0

        init() {}

        /// Where one instance of a block reference puts the block's own coordinates:
        /// `R S (p - base) + insertion + R (column * spacing, row * spacing)`.
        init(reference r: BlockReference, base: Point, column: Int, row: Int) {
            let (cs, sn) = ArcPieces.cosSin(degrees: r.rotation)
            a = cs * r.scaleX
            b = sn * r.scaleX
            c = -sn * r.scaleY
            d = cs * r.scaleY
            let ox = Double(column) * r.columnSpacing
            let oy = Double(row) * r.rowSpacing
            tx = -(a * base.x + c * base.y) + r.insertion.x + cs * ox - sn * oy
            ty = -(b * base.x + d * base.y) + r.insertion.y + sn * ox + cs * oy
            zScale = r.scaleZ
            tz = r.insertion.z - r.scaleZ * base.z
            if ObjectPlane(extrusion: r.extrusion) == .down {
                // The block is placed in an object coordinate system whose normal is -z, so its
                // x axis maps to -x and z to -z in the world.
                self = ObjectPlane.mirror.composed(with: self)
            }
        }

        /// Whether `extrusion` is a normal this planar map can honour: along z, either way.
        static func supportsExtrusion(_ extrusion: Point) -> Bool {
            ObjectPlane(extrusion: extrusion) != .tilted
        }

        func apply(_ p: Point) -> Point {
            Point(a * p.x + c * p.y + tx, b * p.x + d * p.y + ty, zScale * p.z + tz)
        }

        func apply(_ p: Point2) -> Point2 {
            Point2(a * p.x + c * p.y + tx, b * p.x + d * p.y + ty)
        }

        func applyVector(_ x: Double, _ y: Double) -> (x: Double, y: Double) {
            (a * x + c * y, b * x + d * y)
        }

        /// Whether the map reverses orientation.
        var isMirrored: Bool { a * d - b * c < 0 }

        /// The uniform scale factor when the linear part is a rotation, possibly mirrored, times
        /// a single scale; `nil` otherwise.
        var similarity: Double? {
            let l0 = hypot(a, b)
            let l1 = hypot(c, d)
            guard l0 > 1e-12, abs(l0 - l1) <= 1e-9 * l0, abs(a * c + b * d) <= 1e-9 * l0 * l1
            else { return nil }
            return l0
        }

        /// The angle, in degrees, of the direction that makes `degrees` with the x axis before
        /// this map, in `(-180, 180]`. A mirror turns the angle round rather than adding to it.
        func directionAngle(degrees: Double) -> Double {
            let (cs, sn) = ArcPieces.cosSin(degrees: degrees)
            let v = applyVector(cs, sn)
            return atan2(v.y, v.x) * 180 / .pi
        }

        /// The angle the x axis is turned by, in degrees.
        var rotationDegrees: Double { atan2(b, a) * 180 / .pi }

        /// An arc's angle range with the start moved into `0..<360` and the end moved with it, so
        /// the sweep is unchanged and a full circle stays a full circle.
        ///
        /// An arc that is not a full turn also gets its end in `0..<360`, so a range that wraps
        /// through 0 has an end below its start, as the file writes it.
        static func normalizedArc(_ range: (Double, Double)) -> (Double, Double) {
            let shift = (range.0 / 360).rounded(.down) * 360
            let start = range.0 - shift
            var end = range.1 - shift
            if abs(end - start) < 360 - 1e-9 { end -= (end / 360).rounded(.down) * 360 }
            return (start, end)
        }

        /// This map applied after `inner`.
        func composed(with inner: Transform) -> Transform {
            var r = Transform()
            r.a = a * inner.a + c * inner.b
            r.c = a * inner.c + c * inner.d
            r.b = b * inner.a + d * inner.b
            r.d = b * inner.c + d * inner.d
            r.tx = a * inner.tx + c * inner.ty + tx
            r.ty = b * inner.tx + d * inner.ty + ty
            r.zScale = zScale * inner.zScale
            r.tz = zScale * inner.tz + tz
            return r
        }

        /// An ellipse `center + major cos t + minor sin t` (minor is the major axis turned a
        /// quarter turn, times `ratio`) carried through this map, as the canonical ellipse.
        ///
        /// Parameters are radians. A mirroring map reverses the parameter direction, which is
        /// folded into the returned range so it still runs counter-clockwise.
        func ellipse(
            center: Point2, major: Point2, ratio: Double, start: Double, end: Double
        ) -> (center: Point2, major: Point2, ratio: Double, start: Double, end: Double) {
            let (ax, ay) = applyVector(major.x, major.y)
            let (bx, by) = applyVector(-major.y * ratio, major.x * ratio)
            var t0 = 0.5 * atan2(2 * (ax * bx + ay * by), ax * ax + ay * ay - bx * bx - by * by)
            func axes(_ t: Double) -> (maj: Point2, min: Point2) {
                let (cs, sn) = (cos(t), sin(t))
                return (
                    Point2(ax * cs + bx * sn, ay * cs + by * sn),
                    Point2(-ax * sn + bx * cs, -ay * sn + by * cs)
                )
            }
            var (maj, minor) = axes(t0)
            if hypot(minor.x, minor.y) > hypot(maj.x, maj.y) {
                t0 += .pi / 2
                (maj, minor) = axes(t0)
            }
            var s = start - t0
            var e = end - t0
            if maj.x * minor.y - maj.y * minor.x < 0 { (s, e) = (-e, -s) }
            let full = 2 * Double.pi
            let shift = (s / full).rounded(.down) * full
            s -= shift
            e -= shift
            if e <= s { e += full }
            let ratioOut = hypot(minor.x, minor.y) / hypot(maj.x, maj.y)
            return (apply(center), maj, ratioOut, s, e)
        }
    }
}
