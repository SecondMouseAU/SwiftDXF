import Foundation

extension DXF {
    /// Where an entity came from in the file, stable across reads of the same file.
    ///
    /// The ``handle`` (group 5) is the identity when the file has one. Without a handle the
    /// position stands in: the ``section`` and the ``index`` of the record among every record of
    /// that section, modelled or not, so skipping or modelling a new entity type never moves it.
    /// An entity that came out of an expanded block reference carries the identity of each
    /// reference in ``via``, outermost first.
    public struct EntityIdentity: Hashable, Sendable, CustomStringConvertible {
        /// The DXF handle (group 5), upper case, or `nil` when the record has none.
        public var handle: String?
        /// The section or block the record sits in, such as `ENTITIES` or `BLOCKS:Title`.
        public var section: String
        /// Zero-based position of the record among the records of its section.
        public var index: Int
        /// The identities (``id`` strings) of the block references this entity was expanded from.
        public var via: [String]

        public init(handle: String?, section: String, index: Int, via: [String] = []) {
            self.handle = handle
            self.section = section
            self.index = index
            self.via = via
        }

        /// The entity's own identity without its references: `#2F` or `ENTITIES[12]`.
        public var local: String {
            handle.map { "#\($0)" } ?? "\(section)[\(index)]"
        }

        /// The full identity, references first: `#8E/#31` for an entity expanded from `#8E`.
        public var id: String { (via + [local]).joined(separator: "/") }

        public var description: String { id }
    }
}
