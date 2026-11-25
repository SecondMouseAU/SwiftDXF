extension DXF {
    /// A `WIPEOUT`: a masking area that hides what lies beneath it.
    ///
    /// The file stores a WIPEOUT as an image whose clip boundary is the area, in pixels of that
    /// image; the reader carries it into the world, so ``boundary`` is where the clip lies. The
    /// clip mode (group 290) can invert the mask, see ``isInverted``; the clipping state (group
    /// 280) and the kind of clip (group 71) are kept as ``isClipping`` and ``clipType``.
    public struct Wipeout: Equatable, Sendable {
        /// How the file describes the clip boundary (group 71).
        public enum ClipType: Int, Equatable, Sendable {
            /// Two opposite corners of a rectangle (1).
            case rectangular = 1
            /// Three or more vertices of a polygon (2).
            case polygonal = 2
        }

        /// The corners of the masking polygon, in the order the file lists them, in the world.
        ///
        /// A rectangular clip (two opposite corners in the file) is four corners, and a polygon
        /// does not repeat its first vertex at the end. A WIPEOUT with fewer than two clip
        /// vertices is its whole image rectangle, as `ezdxf` reads it.
        public var boundary: [Point]
        public var layer: String
        public var color: Int

        /// Whether the file's clip boundary is a rectangle (two corners) or a polygon (group 71).
        ///
        /// This is group 71 as written, so it can disagree with ``boundary``: a record that says
        /// rectangular and lists three vertices has a three-cornered boundary. ``boundary`` goes
        /// by the vertices, as `ezdxf`'s does. A record that gives no valid type (`1` or `2`)
        /// takes it from its vertices, two being a rectangle, and a record with fewer than two
        /// vertices, which is its whole image, is rectangular whatever group 71 says.
        public var clipType: ClipType

        /// The clipping state (group 280): `true` for on, the value `ezdxf` and AutoCAD write for a
        /// masking area.
        ///
        /// ``boundary`` is the clip boundary the file stores, whatever this says, as `ezdxf`
        /// carries it. A record with no group 280 reads as `false`, as `ezdxf` leaves it unset.
        public var isClipping: Bool

        /// Whether the clip mode (group 290) inverts the mask.
        ///
        /// The file's mode is `0` for the usual mask, which covers the inside of ``boundary``, and
        /// `1` for an inverted one, which covers the image rectangle outside it. Autodesk's DXF
        /// reference names `0` "Outside Mode" and `1` "Inside Mode" without saying what each
        /// hides; `ezdxf` writes `0` for the masks it makes and reads the value without acting on
        /// it. The reading here, that `1` is the inverted clip, rests on that and on a third-party
        /// reader (`acadrust`), not on an AutoCAD-written file with the group set to `1`. The
        /// image rectangle is not kept, so for an inverted mask ``boundary`` is the hole in the
        /// mask, not the mask. A record with no group 290 (any file before R2010) is not inverted.
        public var isInverted: Bool

        /// A masking area with the given boundary and clip.
        ///
        /// - Parameters:
        ///   - boundary: The corners of the masking polygon, in the world.
        ///   - layer: The layer name.
        ///   - color: The colour index, `256` for by layer.
        ///   - clipType: Defaults to `.polygonal`, as `boundary` is a polygon. The reader gives
        ///     `.rectangular` for a record with fewer than two clip vertices (its whole image).
        ///   - isClipping: Defaults to `true`, the value written for a masking area. The reader
        ///     gives `false` for a record with no group 280, and for one with fewer than two clip
        ///     vertices even if group 280 is 1, as `ezdxf` does.
        ///   - isInverted: Defaults to `false`, as the reader does for a record with no group 290.
        ///
        /// These defaults are those of a mask that has a boundary and a clipping state, which is
        /// what is built by hand. The reader's own results for a record that leaves a group out
        /// are `ezdxf`'s, and agreeing with both is not possible for `isClipping`.
        ///
        /// `clipType`, `isClipping` and `isInverted` come last, so a call that omits them compiles
        /// as before.
        public init(
            boundary: [Point], layer: String = "0", color: Int = 256,
            clipType: ClipType = .polygonal, isClipping: Bool = true, isInverted: Bool = false
        ) {
            self.boundary = boundary
            self.layer = layer
            self.color = color
            self.clipType = clipType
            self.isClipping = isClipping
            self.isInverted = isInverted
        }
    }
}
