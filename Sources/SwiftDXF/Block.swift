extension DXF {
    /// A block definition from the `BLOCKS` section.
    ///
    /// The block's own entities are read. `INSERT` references to a block are read too, and
    /// expanded into the drawing when ``ReadOptions/expandBlocks`` is set. Every drawing also
    /// holds the built-in blocks such as `*Model_Space` and the anonymous `*D` blocks that carry
    /// the drawn form of a dimension.
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
        /// The `INSERT`s inside the block, which an expansion carries through with the block.
        public var references: [BlockReference]
        /// Entities of unmodelled types inside the block, by type then layer. `INSERT` is not
        /// counted, as ``references`` holds it.
        public var skippedByLayer: [String: [String: Int]]

        public init(
            name: String, identity: Identity, basePoint: Point = .init(0, 0, 0),
            entities: [Entity] = [], identities: [Identity] = [], entityLineTypes: [String?] = [],
            references: [BlockReference] = [], skippedByLayer: [String: [String: Int]] = [:]
        ) {
            self.name = name
            self.identity = identity
            self.basePoint = basePoint
            self.entities = entities
            self.identities = identities
            self.entityLineTypes = entityLineTypes
            self.references = references
            self.skippedByLayer = skippedByLayer
        }

        /// The block's handle (group 5), or `nil` when the file has none.
        public var handle: String? { identity.handle }
    }
}
