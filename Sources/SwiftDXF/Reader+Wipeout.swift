import Foundation

extension DXF.Reader {
    /// A `WIPEOUT`, with its clip boundary carried from the image into the world.
    ///
    /// The record is an image: an insertion point (10), the world vector of one pixel along the
    /// bottom (11) and along the left side (12), and the size in pixels (13). The clip vertices
    /// (14) are pixel positions measured from the top left corner of the image, and two of them
    /// are opposite corners of a rectangle. A pixel `(x, y)` is at
    /// `insertion + u (x + 1/2) + v (height - y - 1/2)`, as `ezdxf` places it. The clipping state
    /// (280), the clip type (71) and the clip mode (290) are kept beside the boundary.
    func wipeout(_ f: Fields) -> DXF.Wipeout {
        let origin = point(f)
        let u = pointOpt(11, f) ?? DXF.Point(1, 0, 0)
        let v = pointOpt(12, f) ?? DXF.Point(0, 1, 0)
        let width = dbl(13, f, 1)
        let height = dbl(23, f, 1)
        var clip = splinePoints(14, f).map { DXF.Point2($0.x, $0.y) }
        // A record with no group 280 reads as off, as `ezdxf` leaves it; `DXF.Wipeout.init`
        // defaults to on, for a mask built by hand (see its documentation).
        var isClipping = ints(280, f).map { $0 != 0 } ?? false
        let given = clip.count
        if clip.count < 2 {
            // No usable boundary: the whole image. `ezdxf` resets the clip to that rectangle and
            // switches clipping off, overriding any explicit group 280 value, a 1 included.
            // The reader does the same, and `DXF.Wipeout.isClipping` documents it.
            isClipping = false
            clip = [DXF.Point2(-0.5, -0.5), DXF.Point2(width - 0.5, height - 0.5)]
        }
        if clip.count == 2 {
            clip = [
                clip[0], DXF.Point2(clip[1].x, clip[0].y), clip[1],
                DXF.Point2(clip[0].x, clip[1].y),
            ]
        } else if let last = clip.last, clip.count > 2, Self.isClose(last, clip[0]) {
            clip.removeLast()
        }
        let boundary = clip.map { p -> DXF.Point in
            let along = p.x + 0.5
            let up = height - p.y - 0.5
            return DXF.Point(
                origin.x + u.x * along + v.x * up, origin.y + u.y * along + v.y * up,
                origin.z + u.z * along + v.z * up)
        }
        // This is group 71 as written, so it can disagree with the vertex count (see
        // `DXF.Wipeout.clipType`); the boundary above goes by the vertices. Anything that is not
        // 1 or 2 is judged by the vertices.
        // With no vertices the clip is the whole image, a rectangle, and `ezdxf` resets it to one.
        let clipType =
            given < 2
            ? .rectangular
            : ints(71, f).flatMap(DXF.Wipeout.ClipType.init(rawValue:))
                ?? (given > 2 ? .polygonal : .rectangular)
        return DXF.Wipeout(
            boundary: boundary, layer: layer(f), color: color(f), clipType: clipType,
            isClipping: isClipping, isInverted: (ints(290, f) ?? 0) != 0)
    }

    /// Whether two pixel positions are the same to within rounding, as `ezdxf` decides whether a
    /// polygon is already closed.
    ///
    /// The tolerance is `ezdxf`'s (relative, `1e-9`, with an absolute floor of `1e-12`), capped at
    /// `1e-6` so that it cannot merge two distinct vertices at large coordinates. `ezdxf` has no
    /// cap, so the two differ only for a closing vertex between `1e-6` and `1e-5` away at
    /// coordinates beyond a thousand pixels, which this keeps as a vertex.
    private static func isClose(_ a: DXF.Point2, _ b: DXF.Point2) -> Bool {
        func close(_ x: Double, _ y: Double) -> Bool {
            abs(x - y) <= min(max(1e-9 * max(abs(x), abs(y)), 1e-12), 1e-6)
        }
        return close(a.x, b.x) && close(a.y, b.y)
    }
}
