import Foundation

extension DXF {
    /// An `INSERT`: a placement of a named ``Block``, possibly as a rectangular array.
    public struct BlockReference: Equatable, Sendable {
        public var name: String
        public var insertion: Point
        public var scaleX: Double
        public var scaleY: Double
        public var scaleZ: Double
        /// Rotation about the insertion point, in degrees (group 50).
        public var rotation: Double
        /// Array columns (group 70), at least 1.
        public var columns: Int
        /// Array rows (group 71), at least 1.
        public var rows: Int
        /// Distance between columns (group 44), along the rotated x axis.
        public var columnSpacing: Double
        /// Distance between rows (group 45), along the rotated y axis.
        public var rowSpacing: Double
        public var layer: String
        public var color: Int
        /// The line type as written (group 6), or `nil` for by-layer.
        public var lineType: String?
        /// The extrusion direction (groups 210, 220, 230), the normal of the plane the insertion
        /// point and rotation are written in. `(0, 0, -1)` mirrors the block's x axis.
        public var extrusion: Point
        public var identity: EntityIdentity

        public init(
            name: String, insertion: Point, scaleX: Double = 1, scaleY: Double = 1,
            scaleZ: Double = 1, rotation: Double = 0, columns: Int = 1, rows: Int = 1,
            columnSpacing: Double = 0, rowSpacing: Double = 0, layer: String = "0",
            color: Int = 256, lineType: String? = nil, extrusion: Point = Point(0, 0, 1),
            identity: EntityIdentity
        ) {
            self.extrusion = extrusion
            self.name = name
            self.insertion = insertion
            self.scaleX = scaleX
            self.scaleY = scaleY
            self.scaleZ = scaleZ
            self.rotation = rotation
            self.columns = columns
            self.rows = rows
            self.columnSpacing = columnSpacing
            self.rowSpacing = rowSpacing
            self.layer = layer
            self.color = color
            self.lineType = lineType
            self.identity = identity
        }
    }

    /// A named block definition from the `BLOCKS` section.
    public struct Block: Sendable {
        public var name: String
        /// The block's base point (group 10), which lands on each reference's insertion point.
        public var basePoint: Point
        public var entities: [Entity]
        /// One identity per entry of ``entities``.
        public var identities: [EntityIdentity]
        /// One line type name per entry of ``entities``, as written (`nil` is by-layer).
        public var entityLineTypes: [String?]
        public var hatches: [Hatch]
        public var leaders: [Leader]
        /// References to other blocks, expanded recursively with the block.
        public var references: [BlockReference]
        /// Entities of types with no entity form (such as `SOLID`) found in the block, by type
        /// then layer.
        public var skippedByLayer: [String: [String: Int]]

        public init(name: String, basePoint: Point = Point(0, 0, 0)) {
            self.name = name
            self.basePoint = basePoint
            entities = []
            identities = []
            entityLineTypes = []
            hatches = []
            leaders = []
            references = []
            skippedByLayer = [:]
        }
    }

    /// Settings for reading a DXF.
    public struct ReadOptions: Equatable, Sendable {
        /// Flatten every top-level `INSERT` into ``Drawing/entities``, ``Drawing/hatches`` and
        /// ``Drawing/leaders``, with the reference recorded in each identity's ``EntityIdentity/via``.
        ///
        /// Off by default: a title block then stays out of the entities, and `INSERT` stays in
        /// ``Drawing/skipped``.
        public var expandBlocks: Bool

        public init(expandBlocks: Bool = false) { self.expandBlocks = expandBlocks }
    }

    /// Something a reader did to a file that a consumer should not miss.
    public enum Warning: Equatable, Sendable, CustomStringConvertible {
        /// A reference names a block the file does not define.
        case missingBlock(name: String, count: Int)
        /// A block contains itself, directly or through other blocks; the inner reference was dropped.
        case blockCycle(name: String)
        /// Expansion stopped at the nesting limit.
        case blockNestingTooDeep(name: String)
        /// References whose extrusion is not along z, which a planar drawing cannot carry; they
        /// were expanded as if it were.
        case unsupportedExtrusion(count: Int)
        /// Entities dropped by an expansion because a non-uniform scale cannot carry them
        /// exactly, by entity type.
        case notTransformed(type: String, count: Int)

        public var description: String {
            switch self {
            case .missingBlock(let name, let count):
                return "\(count) references to missing block \(name)"
            case .blockCycle(let name): return "block \(name) contains itself"
            case .blockNestingTooDeep(let name): return "block \(name) nests too deeply"
            case .unsupportedExtrusion(let count):
                return "\(count) references with an extrusion not along z were expanded flat"
            case .notTransformed(let type, let count):
                return "\(count) \(type) entities not carried through a non-uniform scale"
            }
        }
    }
}
