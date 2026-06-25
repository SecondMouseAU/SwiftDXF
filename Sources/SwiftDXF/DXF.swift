import Foundation

/// A native-Swift reader for **DXF** — AutoCAD's *Drawing Interchange Format*, the de-facto
/// portable 2D/3D CAD exchange format. `SwiftDXF` reads the **ASCII** DXF variant (group-code /
/// value line pairs) and lifts the model-space geometry into a neutral ``Drawing``.
///
/// The reader is a clean-room implementation of the public DXF group-code reference. It targets the
/// 2D entity set that dominates real-world drawings — `LINE`, `CIRCLE`, `ARC`, `ELLIPSE`, `POINT`,
/// `TEXT` / `MTEXT`, and `LWPOLYLINE` / `POLYLINE` — and skips entities it does not model rather than
/// failing. Only the `ENTITIES` (model-space) section is read, matching what a tool like *ezdxf*'s
/// `modelspace()` iterates.
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

    /// A 3D point in the drawing's own units. Most 2D DXF geometry sits on the `z == 0` plane.
    public struct Point: Equatable, Sendable {
        public var x: Double; public var y: Double; public var z: Double
        public init(_ x: Double, _ y: Double, _ z: Double = 0) { self.x = x; self.y = y; self.z = z }
    }

    /// One model-space drawing entity. Angles are in **degrees** where DXF stores degrees (`ARC`),
    /// and **radians** where DXF stores radians (`ELLIPSE` parameters); the doc comments say which.
    /// `layer` is the layer name (DXF group 8); `color` is the AutoCAD Color Index (group 62), or
    /// `256` for *BYLAYER* / `0` for *BYBLOCK* when not explicitly set.
    public enum Entity: Sendable {
        case line(a: Point, b: Point, layer: String, color: Int)
        case circle(center: Point, radius: Double, layer: String, color: Int)
        /// Circular arc. `startDeg`/`endDeg` are absolute CCW angles in degrees (DXF groups 50/51);
        /// the arc sweeps CCW from start to end.
        case arc(center: Point, radius: Double, startDeg: Double, endDeg: Double, layer: String, color: Int)
        /// Ellipse / elliptical arc. `majorAxis` is the major-axis endpoint **relative to** `center`
        /// (DXF groups 11/21/31); `ratio` is minor/major (group 40); `startParam`/`endParam` are the
        /// arc's parametric bounds in **radians** (groups 41/42; `0…2π` for a full ellipse).
        case ellipse(center: Point, majorAxis: Point, ratio: Double, startParam: Double, endParam: Double, layer: String, color: Int)
        case point(at: Point, layer: String, color: Int)
        /// `TEXT` or `MTEXT`. `height` is the text height (group 40); `rotationDeg` the rotation in
        /// degrees (group 50); `string` is decoded to Unicode at read time.
        case text(at: Point, height: Double, rotationDeg: Double, string: String, layer: String, color: Int)
        /// `LWPOLYLINE` or an old-style `POLYLINE`/`VERTEX` run, flattened to its vertices. `closed`
        /// reflects the closed flag (group 70 bit 1). Arc bulges (group 42) are not yet expanded —
        /// segments are treated as straight.
        case polyline(points: [Point], closed: Bool, layer: String, color: Int)
    }

    public struct Drawing: Sendable {
        /// `$ACADVER` header value (e.g. `AC1009` for R12), or `""` if the header was absent.
        public var version: String
        public var entities: [Entity]
        /// Per-type entity counts, for verification against reference tools (ezdxf, IxMilia.Dxf).
        public var counts: Counts

        public init(version: String = "", entities: [Entity] = [], counts: Counts = .init()) {
            self.version = version; self.entities = entities; self.counts = counts
        }

        public struct Counts: Sendable, Equatable {
            public var line = 0, circle = 0, arc = 0, ellipse = 0, point = 0, text = 0, polyline = 0
            public init() {}
            /// Total modelled entities.
            public var total: Int { line + circle + arc + ellipse + point + text + polyline }
        }

        /// Axis-aligned bounds over all entities, or `nil` if empty. Curved entities contribute a
        /// conservative box (centre ± radius / major-axis length), not a tight arc extent.
        public var bounds: (min: Point, max: Point)? {
            var lo = Point(.greatestFiniteMagnitude, .greatestFiniteMagnitude, .greatestFiniteMagnitude)
            var hi = Point(-.greatestFiniteMagnitude, -.greatestFiniteMagnitude, -.greatestFiniteMagnitude)
            var any = false
            func acc(_ p: Point) {
                any = true
                lo.x = min(lo.x, p.x); lo.y = min(lo.y, p.y); lo.z = min(lo.z, p.z)
                hi.x = max(hi.x, p.x); hi.y = max(hi.y, p.y); hi.z = max(hi.z, p.z)
            }
            func box(_ c: Point, _ r: Double) { acc(Point(c.x - r, c.y - r, c.z)); acc(Point(c.x + r, c.y + r, c.z)) }
            for e in entities {
                switch e {
                case let .line(a, b, _, _): acc(a); acc(b)
                case let .circle(c, r, _, _): box(c, r)
                case let .arc(c, r, _, _, _, _): box(c, r)
                case let .ellipse(c, m, _, _, _, _, _): let r = (m.x * m.x + m.y * m.y).squareRoot(); box(c, r)
                case let .point(p, _, _): acc(p)
                case let .text(p, _, _, _, _, _): acc(p)
                case let .polyline(pts, _, _, _): pts.forEach(acc)
                }
            }
            return any ? (lo, hi) : nil
        }
    }

    public enum Error: Swift.Error, Equatable, Sendable {
        case empty
        /// Bytes are not recognisable as a DXF document.
        case notDXF
        /// Binary DXF (the `AutoCAD Binary DXF` sentinel) is not yet supported — convert to ASCII DXF.
        case binaryUnsupported
    }

    // MARK: Entry points

    public static func read(contentsOf url: URL) throws -> Drawing {
        try read(data: try Data(contentsOf: url))
    }

    public static func read(data: Data) throws -> Drawing {
        guard !data.isEmpty else { throw Error.empty }
        if isBinary(data) { throw Error.binaryUnsupported }
        var r = Reader(decode(data)); return try r.parse()
    }

    /// Parse an already-decoded DXF string.
    public static func read(text: String) throws -> Drawing {
        guard !text.isEmpty else { throw Error.empty }
        var r = Reader(text); return try r.parse()
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

    /// Decode DXF bytes to text. ASCII and UTF-8 pass through; otherwise the bytes are treated as
    /// **CP932 / Shift-JIS** (the common code page for DXF exported by Japanese CAD tools). Because
    /// CP932 is an ASCII superset, the group-code/value structure is unaffected either way.
    static func decode(_ data: Data) -> String {
        if let s = String(data: data, encoding: .utf8) { return s }
        return decodeCP932([UInt8](data))
    }

    /// Decode CP932 (Shift-JIS / Windows-31J) bytes to a Swift String, via CoreFoundation on Apple
    /// platforms, falling back to `.shiftJIS` then a lossy UTF-8 decode.
    public static func decodeCP932(_ bytes: [UInt8]) -> String {
        let data = Data(bytes)
        #if canImport(CoreFoundation)
        let cp932 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosJapanese.rawValue)))
        if let s = String(data: data, encoding: cp932) { return s }
        #endif
        return String(data: data, encoding: .shiftJIS) ?? String(decoding: bytes, as: UTF8.self)
    }
}
