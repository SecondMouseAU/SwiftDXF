extension DXF {
    /// A stable name for one record in a DXF file: its handle, and its section and position.
    public struct Identity: Hashable, Sendable, CustomStringConvertible {
        /// The handle (group 5, or 105 for a dimension style) as the file writes it, or `nil`.
        public var handle: String?
        /// Section and position such as `ENTITIES:12`, present even when the file has no handles.
        ///
        /// Counts every record in the section, including ones that are not modelled.
        public var locator: String

        public init(handle: String? = nil, locator: String) {
            self.handle = handle
            self.locator = locator
        }

        /// The handle when there is one, otherwise the locator.
        public var id: String { handle ?? locator }

        public var description: String { id }
    }
}
