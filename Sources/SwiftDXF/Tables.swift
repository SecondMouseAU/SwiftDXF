extension DXF {
    /// A record of the `LAYER` table.
    public struct Layer: Equatable, Sendable {
        public var name: String
        public var identity: Identity

        public init(name: String, identity: Identity) {
            self.name = name
            self.identity = identity
        }

        /// The record's handle (group 5), or `nil` when the file has none.
        public var handle: String? { identity.handle }
    }

    /// A record of the `LTYPE` table.
    public struct LineType: Equatable, Sendable {
        public var name: String
        public var identity: Identity

        public init(name: String, identity: Identity) {
            self.name = name
            self.identity = identity
        }

        /// The record's handle (group 5), or `nil` when the file has none.
        public var handle: String? { identity.handle }
    }

    /// A record of the `DIMSTYLE` table.
    public struct DimensionStyle: Equatable, Sendable {
        public var name: String
        public var identity: Identity

        public init(name: String, identity: Identity) {
            self.name = name
            self.identity = identity
        }

        /// The record's handle (group 105), or `nil` when the file has none.
        public var handle: String? { identity.handle }
    }
}
