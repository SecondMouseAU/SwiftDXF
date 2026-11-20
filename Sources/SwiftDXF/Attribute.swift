extension DXF {
    /// The flags of an attribute or attribute definition (group 70).
    public struct AttributeFlags: OptionSet, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        /// The attribute is not shown.
        public static let invisible = AttributeFlags(rawValue: 1)
        /// Every reference of the block has the definition's value, and carries no `ATTRIB`.
        public static let constant = AttributeFlags(rawValue: 2)
        /// AutoCAD asks for the value to be entered twice.
        public static let verify = AttributeFlags(rawValue: 4)
        /// AutoCAD does not prompt for the value when the block is inserted.
        public static let preset = AttributeFlags(rawValue: 8)
    }

    /// An `ATTRIB`: a value a block reference carries, such as a title block's drawing number.
    ///
    /// The position, height and rotation are where the value is drawn, in the coordinates of the
    /// space the reference is in (the world for a reference in model space), not in the block's.
    /// Like ``Entity/text(at:height:rotationDeg:string:layer:color:)`` they are in the world for an
    /// attribute written on a `-z` plane; justification and the text style are not read.
    public struct Attribute: Equatable, Sendable {
        /// The tag (group 2), which names the value.
        public var tag: String
        /// The value (group 1), with its codes decoded.
        ///
        /// A multiline attribute (R2018, an embedded `MTEXT`) has the syntax of `MTEXT`.
        public var content: TextContent
        /// The insertion point (groups 10, 20, 30).
        public var position: Point
        /// The text height (group 40).
        public var height: Double
        /// The rotation in degrees (group 50).
        public var rotation: Double
        public var layer: String
        public var color: Int
        public var flags: AttributeFlags
        /// Whether the value is an embedded `MTEXT`, which can span lines.
        public var isMultiline: Bool
        /// The handle (group 5) and the position of the record in its section.
        public var identity: Identity

        /// The value as it reads, with a line break as `"\n"`.
        public var value: String { content.plain }
        public var isInvisible: Bool { flags.contains(.invisible) }

        public init(
            tag: String, content: TextContent, position: Point, height: Double = 0,
            rotation: Double = 0, layer: String = "0", color: Int = 256,
            flags: AttributeFlags = [], isMultiline: Bool = false, identity: Identity
        ) {
            self.tag = tag
            self.content = content
            self.position = position
            self.height = height
            self.rotation = rotation
            self.layer = layer
            self.color = color
            self.flags = flags
            self.isMultiline = isMultiline
            self.identity = identity
        }
    }

    /// An `ATTDEF`: the definition of an attribute in a block, which a reference gives a value.
    ///
    /// Its position, height and rotation are in the block's coordinates.
    public struct AttributeDefinition: Equatable, Sendable {
        /// The tag (group 2), which an ``Attribute`` of a reference repeats.
        public var tag: String
        /// What AutoCAD asks when the block is inserted (group 3), as written.
        public var prompt: String
        /// The default value (group 1), with its codes decoded.
        ///
        /// For a constant attribute (``AttributeFlags/constant``) it is the value every reference
        /// has.
        public var content: TextContent
        public var position: Point
        public var height: Double
        public var rotation: Double
        public var layer: String
        public var color: Int
        public var flags: AttributeFlags
        /// Whether the default is an embedded `MTEXT`, which can span lines.
        public var isMultiline: Bool
        public var identity: Identity

        /// The default value as it reads, with a line break as `"\n"`.
        public var defaultValue: String { content.plain }
        public var isInvisible: Bool { flags.contains(.invisible) }
        public var isConstant: Bool { flags.contains(.constant) }

        public init(
            tag: String, prompt: String = "", content: TextContent, position: Point,
            height: Double = 0, rotation: Double = 0, layer: String = "0", color: Int = 256,
            flags: AttributeFlags = [], isMultiline: Bool = false, identity: Identity
        ) {
            self.tag = tag
            self.prompt = prompt
            self.content = content
            self.position = position
            self.height = height
            self.rotation = rotation
            self.layer = layer
            self.color = color
            self.flags = flags
            self.isMultiline = isMultiline
            self.identity = identity
        }
    }
}

extension DXF.Attribute {
    /// The attribute as a `TEXT` entity, which is what an expansion makes of it.
    var textEntity: DXF.Entity {
        .text(
            at: position, height: height, rotationDeg: rotation, string: value, layer: layer,
            color: color)
    }

    /// This attribute with its position, height and rotation carried through `t`, as a `TEXT` is.
    func transformed(by t: DXF.Transform) -> DXF.Attribute {
        guard case .text(let at, let height, let rotation, _, _, _)? = textEntity.transformed(by: t)
        else { return self }
        var moved = self
        moved.position = at
        moved.height = height
        moved.rotation = rotation
        return moved
    }

    /// The same value as a definition would have it, with no prompt.
    init(_ definition: DXF.AttributeDefinition) {
        self.init(
            tag: definition.tag, content: definition.content, position: definition.position,
            height: definition.height, rotation: definition.rotation, layer: definition.layer,
            color: definition.color, flags: definition.flags, isMultiline: definition.isMultiline,
            identity: definition.identity)
    }
}

extension DXF.AttributeDefinition {
    /// `attribute` read as a definition, with the prompt group 3 holds.
    init(_ attribute: DXF.Attribute, prompt: String) {
        self.init(
            tag: attribute.tag, prompt: prompt, content: attribute.content,
            position: attribute.position, height: attribute.height, rotation: attribute.rotation,
            layer: attribute.layer, color: attribute.color, flags: attribute.flags,
            isMultiline: attribute.isMultiline, identity: attribute.identity)
    }
}
