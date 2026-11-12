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
        public var entities: [Entity]
        /// One identity per entry in ``entities``, in the same order.
        public var identities: [Identity]

        public init(
            name: String, identity: Identity, basePoint: Point = .init(0, 0, 0),
            entities: [Entity] = [], identities: [Identity] = []
        ) {
            self.name = name
            self.identity = identity
            self.basePoint = basePoint
            self.entities = entities
            self.identities = identities
        }

        /// The block's handle (group 5), or `nil` when the file has none.
        public var handle: String? { identity.handle }
    }
}
