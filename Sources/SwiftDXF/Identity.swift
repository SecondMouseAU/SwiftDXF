extension DXF {
    /// A stable name for one record in a DXF file: its handle, and its section and position.
    public struct Identity: Hashable, Sendable, CustomStringConvertible {
        /// The handle (group 5, or 105 for a dimension style) as the file writes it, or `nil`.
        public var handle: String?
        /// Section and position such as `ENTITIES:12`, present even when the file has no handles.
        ///
        /// Counts every record in the section, including ones that are not modelled.
        public var locator: String
        /// The block references an expanded entity came through, outermost first.
        ///
        /// Each is the reference's own handle, or its locator when it has none, with
        /// `[column,row]` added for a reference that is an array. Empty for an entity that is
        /// where the file put it.
        public var via: [String]
        /// The names of the blocks in ``via``, in the same order.
        public var blocks: [String]

        public init(
            handle: String? = nil, locator: String, via: [String] = [], blocks: [String] = []
        ) {
            self.handle = handle
            self.locator = locator
            self.via = via
            self.blocks = blocks
        }

        /// The handle when there is one, otherwise the locator, after the references it came
        /// through: `8E/31` for the entity `31` expanded from the reference `8E`.
        public var id: String { (via + [handle ?? locator]).joined(separator: "/") }

        public var description: String { id }
    }
}
