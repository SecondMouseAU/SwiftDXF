extension DXF {
    /// A block definition from the `BLOCKS` section.
    ///
    /// The block's own entities are read, but `INSERT` references to a block are not expanded
    /// (see issue 5). Every drawing also holds the built-in blocks such as `*Model_Space` and the
    /// anonymous `*D` blocks that carry the drawn form of a dimension.
    public struct Block: Sendable {
        public var name: String
        public var identity: Identity
        /// The block's base point (group 10), `0, 0, 0` when absent.
        public var basePoint: Point
        /// Changing this clears ``identities`` and ``entityLineTypes``, which would no longer line
        /// up.
        public var entities: [Entity] {
            didSet {
                identities = []
                entityLineTypes = []
            }
        }
        /// One identity per entry in ``entities``, in the same order.
        public var identities: [Identity]
        /// One line type name (group 6, as written) per entry in ``entities``, `nil` when absent.
        public var entityLineTypes: [String?]

        public init(
            name: String, identity: Identity, basePoint: Point = .init(0, 0, 0),
            entities: [Entity] = [], identities: [Identity] = [], entityLineTypes: [String?] = []
        ) {
            self.name = name
            self.identity = identity
            self.basePoint = basePoint
            self.entities = entities
            self.identities = identities
            self.entityLineTypes = entityLineTypes
        }

        /// The block's handle (group 5), or `nil` when the file has none.
        public var handle: String? { identity.handle }
    }
}
