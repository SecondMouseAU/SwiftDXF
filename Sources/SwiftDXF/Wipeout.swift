extension DXF {
    /// A `WIPEOUT`: a masking area that hides what lies beneath it.
    ///
    /// The file stores a WIPEOUT as an image whose clip boundary is the area, in pixels of that
    /// image; the reader carries it into the world, so ``boundary`` is where the mask lies. The
    /// clip mode (group 290), which can invert the mask, is not read.
    public struct Wipeout: Equatable, Sendable {
        /// The corners of the masking polygon, in the order the file lists them, in the world.
        ///
        /// A rectangular clip (two opposite corners in the file) is four corners, and a polygon
        /// does not repeat its first vertex at the end. A WIPEOUT with fewer than two clip
        /// vertices is its whole image rectangle, as `ezdxf` reads it.
        public var boundary: [Point]
        public var layer: String
        public var color: Int

        public init(boundary: [Point], layer: String = "0", color: Int = 256) {
            self.boundary = boundary
            self.layer = layer
            self.color = color
        }
    }
}
