import Foundation

/// A native-Swift reader for **DXF**, AutoCAD's *Drawing Interchange Format*, the de-facto
/// portable 2D/3D CAD exchange format. `SwiftDXF` reads the **ASCII** DXF variant (group-code /
/// value line pairs) and lifts the model-space geometry into a neutral ``Drawing``.
///
/// The reader is a clean-room implementation of the public DXF group-code reference. It targets the
/// 2D entity set that dominates real-world drawings: `LINE`, `CIRCLE`, `ARC`, `ELLIPSE`, `POINT`,
/// `TEXT` / `MTEXT`, `LWPOLYLINE` / `POLYLINE`, `DIMENSION`, `SPLINE`, `HATCH` and `LEADER`, and
/// skips entities it does not model rather than failing, recording them in
/// ``Drawing/skipped``. Entities come from the `ENTITIES` (model-space) section, matching what a
/// tool like *ezdxf*'s `modelspace()` iterates. The `BLOCKS` section is read for block
/// definitions and `TABLES` for layers, line types and dimension styles. `INSERT` is read into
/// ``Drawing/references`` and flattened into the entities when ``ReadOptions/expandBlocks`` is
/// set.
///
/// ```swift
/// let dwg = try DXF.read(contentsOf: url)
/// print(dwg.entities.count, dwg.bounds as Any)
/// ```
///
/// Text is decoded from the file's code page: a `$DWGCODEPAGE` of `ANSI_932` (or the absence of one,
/// for DXF emitted by Japanese tools such as Jw_cad) is read as **CP932 / Shift-JIS**; UTF-8 DXF is
/// also handled. AutoCAD `\U+XXXX` unicode escapes in text are decoded.
public enum DXF {

    // MARK: Model

    /// A 3D point in the drawing's own units.
    ///
    /// Most 2D DXF geometry sits on the `z == 0` plane.
    public struct Point: Equatable, Sendable {
        public var x: Double
        public var y: Double
        public var z: Double
        public init(_ x: Double, _ y: Double, _ z: Double = 0) {
            self.x = x
            self.y = y
            self.z = z
        }
    }

    /// One model-space drawing entity.
    ///
    /// Angles are in **degrees** where DXF stores degrees (`ARC`), and **radians** where DXF
    /// stores radians (`ELLIPSE` parameters); the doc comments say which. `layer` is the layer
    /// name (DXF group 8); `color` is the AutoCAD Color Index (group 62), or `256` for *BYLAYER*
    /// / `0` for *BYBLOCK* when not explicitly set.
    public enum Entity: Sendable {
        case line(a: Point, b: Point, layer: String, color: Int)
        case circle(center: Point, radius: Double, layer: String, color: Int)
        /// Circular arc. `startDeg`/`endDeg` are absolute CCW angles in degrees (DXF groups 50/51);
        /// the arc sweeps CCW from start to end.
        case arc(
            center: Point, radius: Double, startDeg: Double, endDeg: Double, layer: String,
            color: Int)
        /// Ellipse / elliptical arc. `majorAxis` is the major-axis endpoint **relative to** `center`
        /// (DXF groups 11/21/31); `ratio` is minor/major (group 40); `startParam`/`endParam` are the
        /// arc's parametric bounds in **radians** (groups 41/42; `0…2π` for a full ellipse).
        case ellipse(
            center: Point, majorAxis: Point, ratio: Double, startParam: Double, endParam: Double,
            layer: String, color: Int)
        case point(at: Point, layer: String, color: Int)
        /// `TEXT` or `MTEXT`. `height` is the text height (group 40); `rotationDeg` the rotation in
        /// degrees (group 50); `string` is decoded to Unicode at read time.
        case text(
            at: Point, height: Double, rotationDeg: Double, string: String, layer: String,
            color: Int)
        /// `LWPOLYLINE` or an old-style `POLYLINE`/`VERTEX` run. `closed` reflects the closed flag
        /// (group 70 bit 1). Each vertex carries its **bulge** (group 42), `tan(θ/4)` of the arc to
        /// the next vertex, `0` for a straight segment, so curved polylines survive the read.
        case polyline(vertices: [PolyVertex], closed: Bool, layer: String, color: Int)
        /// `DIMENSION`. Only the semantic measurement is modelled; the rendered arrow/text-block
        /// glyph geometry is skipped, matching what a downstream drawing-to-3D pipeline needs to
        /// bind a dimension to geometry, not draw it.
        case dimension(Dimension)
        /// `SPLINE`: NURBS control data as stored in the file; see ``Spline``.
        case spline(Spline)
        /// `HATCH`: the filled regions and their boundaries; see ``Hatch``.
        case hatch(Hatch)
        /// `LEADER`: the line from an annotation to the feature it refers to; see ``Leader``.
        case leader(Leader)
    }

    /// One polyline vertex: a point plus the bulge of the segment leaving it (`0` = straight).
    public struct PolyVertex: Equatable, Sendable {
        public var point: Point
        public var bulge: Double
        public init(_ point: Point, bulge: Double = 0) {
            self.point = point
            self.bulge = bulge
        }
    }

    public struct Drawing: Sendable {
        /// `$ACADVER` header value (e.g. `AC1009` for R12), or `""` if the header was absent.
        public var version: String
        /// The modelled entities of model space.
        ///
        /// Changing this clears ``identities`` and ``entityLineTypes``, which would no longer line
        /// up. Set them again afterwards when they still do.
        public var entities: [Entity] {
            didSet {
                identities = []
                entityLineTypes = []
            }
        }
        /// Per-type entity counts, for verification against reference tools (ezdxf, IxMilia.Dxf).
        public var counts: Counts
        /// `$INSUNITS` header code (0 = unitless, 1 = inches, 2 = feet, 4 = mm, 5 = cm, 6 = m, …),
        /// or `nil` when the file declares none.
        public var insUnits: Int?
        /// `$EXTMIN` / `$EXTMAX`: the drawing extents declared in the header (may differ from the
        /// computed ``bounds`` of the entities actually read). `nil` when the header omits them.
        public var extMin: Point?
        public var extMax: Point?
        /// Unmodelled entity types in the `ENTITIES` section, with a count of each.
        ///
        /// For example `["INSERT": 3, "SOLID": 1]`; empty when nothing was skipped. Skipping is
        /// never an error.
        public var skipped: [String: Int]
        /// The same skipped entities broken down by layer: type name, then layer name, then count.
        public var skippedByLayer: [String: [String: Int]]
        /// One ``Identity`` per entry in ``entities``, in the same order.
        ///
        /// Empty for a drawing built by hand and after any change to ``entities``;
        /// ``identity(ofEntityAt:)`` then names each entity by its position.
        public var identities: [Identity]
        /// One line type name (group 6, as written) per entry in ``entities``, `nil` when absent.
        ///
        /// Parallel to ``entities`` like ``identities``, and cleared with it. Use
        /// ``effectiveLineType(ofEntityAt:)`` for the line type an entity is drawn with.
        public var entityLineTypes: [String?]
        /// The block definitions of the `BLOCKS` section.
        public var blocks: [Block]
        /// The records of the `LAYER` table.
        public var layers: [Layer]
        /// The records of the `LTYPE` table.
        public var lineTypes: [LineType]
        /// The records of the `DIMSTYLE` table.
        public var dimensionStyles: [DimensionStyle]
        /// The dimension variables the header holds (`$DIMDEC`, `$DIMZIN`, `$DIMLFAC`, `$DIMPOST`).
        ///
        /// These belong to the style that is current when the file is saved, not to any one
        /// dimension; see ``styleVariables(of:)``.
        public var dimensionDefaults: DimensionStyle.Variables
        /// The `INSERT`s of the `ENTITIES` section, whether or not they were expanded.
        ///
        /// With ``ReadOptions/expandBlocks`` set the geometry they place is in ``entities``, and
        /// each expanded entity's ``Identity/via`` names the reference it came through.
        public var references: [BlockReference]
        /// What a reader did that a consumer should not miss, such as a reference to a block the
        /// file does not define.
        public var warnings: [Warning]
        /// Entities of the `ENTITIES` section flagged as paper space (group 67), by type.
        ///
        /// They are in ``entities`` unless ``ReadOptions/skipPaperSpace`` was set.
        public var paperSpace: [String: Int]

        public init(
            version: String = "", entities: [Entity] = [], counts: Counts = .init(),
            insUnits: Int? = nil, extMin: Point? = nil, extMax: Point? = nil,
            skipped: [String: Int] = [:], skippedByLayer: [String: [String: Int]] = [:],
            identities: [Identity] = [], entityLineTypes: [String?] = [], blocks: [Block] = [],
            layers: [Layer] = [],
            lineTypes: [LineType] = [], dimensionStyles: [DimensionStyle] = [],
            dimensionDefaults: DimensionStyle.Variables = .init(),
            references: [BlockReference] = [], warnings: [Warning] = [],
            paperSpace: [String: Int] = [:]
        ) {
            self.version = version
            self.entities = entities
            self.counts = counts
            self.insUnits = insUnits
            self.extMin = extMin
            self.extMax = extMax
            self.skipped = skipped
            self.skippedByLayer = skippedByLayer
            self.identities = identities
            self.entityLineTypes = entityLineTypes
            self.blocks = blocks
            self.layers = layers
            self.lineTypes = lineTypes
            self.dimensionStyles = dimensionStyles
            self.dimensionDefaults = dimensionDefaults
            self.references = references
            self.warnings = warnings
            self.paperSpace = paperSpace
        }

        /// The identity of the entity at `index` in ``entities``.
        ///
        /// Reading a file gives every entity an identity, so this is the entity's handle when the
        /// file has one and its position in the file otherwise. For a drawing assembled by hand
        /// it is the position in ``entities``. A position outside ``entities`` gets a locator too,
        /// so the result is always a usable key; check the index first if it may be out of range.
        public func identity(ofEntityAt index: Int) -> Identity {
            if identities.count == entities.count, identities.indices.contains(index) {
                return identities[index]
            }
            return Identity(locator: "ENTITIES:\(index)")
        }

        public struct Counts: Sendable, Equatable {
            public var line = 0, circle = 0, arc = 0, ellipse = 0, point = 0, text = 0, polyline = 0
            public var dimension = 0, spline = 0, hatch = 0, leader = 0
            public init() {}
            /// Total modelled entities.
            public var total: Int {
                line + circle + arc + ellipse + point + text + polyline + dimension + spline + hatch
                    + leader
            }
        }

        /// Axis-aligned bounds over all entities, or `nil` if empty.
        ///
        /// Curved entities contribute a conservative box (centre ± radius / major-axis length),
        /// not a tight arc extent.
        public var bounds: (min: Point, max: Point)? {
            var lo = Point(
                .greatestFiniteMagnitude, .greatestFiniteMagnitude, .greatestFiniteMagnitude)
            var hi = Point(
                -.greatestFiniteMagnitude, -.greatestFiniteMagnitude, -.greatestFiniteMagnitude)
            var any = false
            func acc(_ p: Point) {
                any = true
                lo.x = min(lo.x, p.x)
                lo.y = min(lo.y, p.y)
                lo.z = min(lo.z, p.z)
                hi.x = max(hi.x, p.x)
                hi.y = max(hi.y, p.y)
                hi.z = max(hi.z, p.z)
            }
            func box(_ c: Point, _ r: Double) {
                acc(Point(c.x - r, c.y - r, c.z))
                acc(Point(c.x + r, c.y + r, c.z))
            }
            for e in entities {
                switch e {
                case .line(let a, let b, _, _):
                    acc(a)
                    acc(b)
                case .circle(let c, let r, _, _): box(c, r)
                case .arc(let c, let r, _, _, _, _): box(c, r)
                case .ellipse(let c, let m, _, _, _, _, _):
                    let r = (m.x * m.x + m.y * m.y).squareRoot()
                    box(c, r)
                case .point(let p, _, _): acc(p)
                case .text(let p, _, _, _, _, _): acc(p)
                case .polyline(let verts, _, _, _):
                    for v in verts { acc(v.point) }
                case .dimension(let d):
                    acc(d.textPosition)
                    acc(d.defPoint)
                    for p in [d.defPoint2, d.defPoint3, d.defPoint4, d.defPoint5] {
                        if let p { acc(p) }
                    }
                case .spline(let s):
                    // The control polygon bounds a spline with positive weights.
                    for p in s.controlPoints.isEmpty ? s.fitPoints : s.controlPoints { acc(p) }
                case .hatch(let h):
                    for p in h.extentPoints { acc(p) }
                case .leader(let l):
                    for p in l.vertices { acc(p) }
                }
            }
            return any ? (lo, hi) : nil
        }
    }

    public enum Error: Swift.Error, Equatable, Sendable {
        case empty
        /// Bytes are not recognisable as a DXF document.
        case notDXF
        /// Binary DXF (the `AutoCAD Binary DXF` sentinel) is not yet supported; convert to ASCII DXF.
        case binaryUnsupported
    }

    // MARK: Entry points

    public static func read(contentsOf url: URL, options: ReadOptions = .init()) throws -> Drawing {
        try read(data: try Data(contentsOf: url), options: options)
    }

    public static func read(data: Data, options: ReadOptions = .init()) throws -> Drawing {
        guard !data.isEmpty else { throw Error.empty }
        if isBinary(data) { throw Error.binaryUnsupported }
        var r = Reader(decode(data), options: options)
        return try r.parse()
    }

    /// Parse an already-decoded DXF string.
    public static func read(text: String, options: ReadOptions = .init()) throws -> Drawing {
        guard !text.isEmpty else { throw Error.empty }
        var r = Reader(text, options: options)
        return try r.parse()
    }

    // MARK: Sniffing / decoding

    /// Binary DXF begins with the 22-byte sentinel `"AutoCAD Binary DXF\r\n\u{1a}\u{0}"`.
    public static func isBinary(_ data: Data) -> Bool {
        let sentinel = Array("AutoCAD Binary DXF".utf8)
        guard data.count >= sentinel.count else { return false }
        return Array(data.prefix(sentinel.count)) == sentinel
    }

    /// Heuristic sniff for ASCII DXF: an early `0`/`SECTION` pair, or a recognisable section name.
    public static func looksLikeDXF(_ data: Data) -> Bool {
        guard !isBinary(data) else { return true }
        let head = String(decoding: data.prefix(4096), as: UTF8.self).uppercased()
        guard head.contains("SECTION") || head.contains("EOF") else { return false }
        return head.contains("ENTITIES") || head.contains("HEADER")
            || head.contains("\n0\nSECTION") || head.hasPrefix("0")
    }

    /// Decode DXF bytes to text.
    ///
    /// ASCII and UTF-8 pass through; otherwise the bytes are treated as **CP932 / Shift-JIS** (the
    /// common code page for DXF exported by Japanese CAD tools). Because CP932 is an ASCII
    /// superset, the group-code/value structure is unaffected either way.
    static func decode(_ data: Data) -> String {
        if let s = String(data: data, encoding: .utf8) { return s }
        return decodeCP932([UInt8](data))
    }

    /// Decode CP932 (Shift-JIS / Windows-31J) bytes to a Swift String, via CoreFoundation on Apple
    /// platforms, falling back to `.shiftJIS` then a lossy UTF-8 decode.
    public static func decodeCP932(_ bytes: [UInt8]) -> String {
        let data = Data(bytes)
        #if canImport(CoreFoundation)
            let cp932 = String.Encoding(
                rawValue: CFStringConvertEncodingToNSStringEncoding(
                    CFStringEncoding(CFStringEncodings.dosJapanese.rawValue)))
            if let s = String(data: data, encoding: cp932) { return s }
        #endif
        return String(data: data, encoding: .shiftJIS) ?? String(decoding: bytes, as: UTF8.self)
    }
}
