import Foundation

extension DXF {
    /// A `TOLERANCE`: a geometric tolerance, the feature control frame of GD&T.
    ///
    /// The frame is the string of group 1, which ``frames`` reads into rows of boxes. Its size is
    /// not stored: it comes from the dimension style named by ``styleName``.
    public struct Tolerance: Equatable, Sendable {
        /// Where the frame is placed: the middle of the left edge of its first row (groups 10, 20,
        /// 30), in the world.
        public var insertion: Point
        /// The direction the frame runs in (groups 11, 21, 31): the x axis of its text, `(1, 0, 0)`
        /// when the file has none.
        ///
        /// A block expansion carries it as a vector, so a scaled block makes it longer.
        public var direction: Point
        /// The dimension style name (group 3), or `nil`.
        public var styleName: String?
        /// The frame string as the file writes it (group 1), such as
        /// `{\Fgdt;i}%%v0.012%%v%%vB%%v%%v`.
        public var text: String
        /// The code page of the drawing the tolerance was read from, which `%%nnn` in the text is
        /// read through; see ``frames``.
        public var codePage: CodePage?
        public var layer: String
        public var color: Int

        public init(
            insertion: Point, direction: Point = Point(1, 0, 0), styleName: String? = nil,
            text: String, codePage: CodePage? = nil, layer: String = "0", color: Int = 256
        ) {
            self.insertion = insertion
            self.direction = direction
            self.styleName = styleName
            self.text = text
            self.codePage = codePage
            self.layer = layer
            self.color = color
        }

        /// The angle of ``direction`` from the x axis, in degrees.
        public var rotationDeg: Double { atan2(direction.y, direction.x) * 180 / .pi }

        /// The frames of ``text``: one per line of the string, each with its characteristic,
        /// tolerance zones and datum references.
        ///
        /// A line is a row of boxes, and a second one is a composite frame. A row with no box
        /// holding anything is left out. The string is read each time this is used, so keep the
        /// result when it is needed more than once.
        public var frames: [Frame] { Self.frames(in: text, codePage: codePage) }

        /// Whether every symbol and box of every frame was read, with nothing kept as written
        /// because it was not understood.
        public var isFullyRead: Bool { frames.allSatisfy(\.isFullyRead) }
    }
}
