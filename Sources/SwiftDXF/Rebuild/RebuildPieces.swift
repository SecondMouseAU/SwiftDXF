import Foundation

extension DXF {
    /// The pieces of a drawing a dimension is rebuilt from, in one plane and indexed for search.
    struct RebuildPieces {
        /// A value text: a `.text` entity that starts with a number.
        struct Text {
            var entity: Int
            /// Other entities that are the same text stored again at the same place.
            var duplicates: [Int] = []
            var string: String
            var raw: String
            var layer: String
            var color: Int
            var height: Double
            var direction: Point2
            var center: Point2
            var width: Double
            var value: DimensionRebuild.Value
        }

        /// A straight piece: a `LINE`, or one edge of a polyline.
        struct Segment {
            var a: Point2
            var b: Point2
            var entity: Int
            var layer: String
            var length: Double
            var unit: Point2
        }

        /// A `CIRCLE`, or an `ARC` when `span` is set (start and end angle in degrees).
        struct Circle {
            var center: Point2
            var radius: Double
            var entity: Int
            var layer: String
            var span: (start: Double, end: Double)?
        }

        /// A small shape at the end of a dimension line: a point, a dot, an arrowhead or a tick.
        struct Mark {
            var at: Point2
            var entities: [Int]
            var layer: String
        }

        var texts: [Text] = []
        var segments: [Segment] = []
        var circles: [Circle] = []
        var marks: [Mark] = []
        var segmentGrid = Grid(cell: 1)
        /// The distance within which two pieces meet.
        var tolerance = 0.0
        /// The largest extent of a mark.
        var markSize = 0.0

        /// A uniform grid of boxes, to find what is near a place.
        struct Grid {
            var cell: Double
            var cells: [Int64: [Int]] = [:]

            init(cell: Double) { self.cell = max(cell, 1e-6) }

            private func range(_ lo: Double, _ hi: Double) -> ClosedRange<Int> {
                Int((lo / cell).rounded(.down))...Int((hi / cell).rounded(.down))
            }

            private static func key(_ x: Int, _ y: Int) -> Int64 {
                Int64(x) &* 4_194_304 &+ Int64(y)
            }

            mutating func insert(_ index: Int, _ box: Box2) {
                for x in range(box.min.x, box.max.x) {
                    for y in range(box.min.y, box.max.y) {
                        cells[Self.key(x, y), default: []].append(index)
                    }
                }
            }

            /// The indices inserted with a box that may meet `box`, each once, in ascending order.
            func query(_ box: Box2) -> [Int] {
                var found = Set<Int>()
                for x in range(box.min.x, box.max.x) {
                    for y in range(box.min.y, box.max.y) {
                        if let list = cells[Self.key(x, y)] { found.formUnion(list) }
                    }
                }
                return found.sorted()
            }
        }

        init(_ drawing: Drawing, tolerance requested: Double?) {
            var heights: [Double] = []
            var rawTexts: [(Int, Text)] = []
            for (index, entity) in drawing.entities.enumerated() {
                guard
                    case .text(let at, let height, let rotation, let string, let layer, let color) =
                        entity, height > 0
                else { continue }
                let content = drawing.textContent(ofEntityAt: index)
                let radians = rotation * .pi / 180
                let direction = Point2(cos(radians), sin(radians))
                // A TEXT is anchored at the left of its baseline; an MTEXT at the top left.
                let up = content?.syntax == .mtext ? -height / 2 : height / 2
                // Values a text assembler ran together, `200 629`, are read as the values they are.
                let split = Self.numbers(in: string)
                let tokens =
                    split.isEmpty ? [(text: string, offset: 0)] : split
                for token in tokens {
                    let value =
                        split.isEmpty
                        ? (content.flatMap(DimensionRebuild.Value.read)
                            ?? (content == nil ? DimensionRebuild.Value.read(string) : nil))
                        : DimensionRebuild.Value.read(token.text)
                    guard let value else { continue }
                    let advance = height * 0.6
                    let width = Double(token.text.count) * advance
                    let along = (Double(token.offset) * advance) + width / 2
                    let center = Point2(
                        at.x + direction.x * along - direction.y * up,
                        at.y + direction.y * along + direction.x * up)
                    heights.append(height)
                    rawTexts.append(
                        (
                            index,
                            Text(
                                entity: index, string: token.text,
                                raw: split.isEmpty ? (content?.raw ?? string) : token.text,
                                layer: layer, color: color, height: height,
                                direction: direction, center: center, width: width, value: value)
                        ))
                }
            }
            heights.sort()
            let median = heights.isEmpty ? 1 : heights[heights.count / 2]
            tolerance = requested ?? 0.03 * median
            markSize = 2 * median

            var seen: [String: [Int]] = [:]
            for (_, text) in rawTexts {
                let key = text.layer + "\u{0}" + text.string
                if let first = seen[key]?.first(where: {
                    texts[$0].center.distance(to: text.center) <= tolerance
                }) {
                    if !texts[first].duplicates.contains(text.entity),
                        texts[first].entity != text.entity
                    {
                        texts[first].duplicates.append(text.entity)
                    }
                } else {
                    seen[key, default: []].append(texts.count)
                    texts.append(text)
                }
            }

            segmentGrid = Grid(cell: max(10 * median, 1))
            var small: [(entity: Int, box: Box2, layer: String)] = []
            for (index, entity) in drawing.entities.enumerated() {
                switch entity {
                case .line(let a, let b, let layer, _):
                    add(Point2(a.x, a.y), Point2(b.x, b.y), index, layer)
                    noteSmall(&small, index, [Point2(a.x, a.y), Point2(b.x, b.y)], layer)
                case .polyline(let vertices, let closed, let layer, _):
                    let points = vertices.map { Point2($0.point.x, $0.point.y) }
                    for k in 0..<points.count where vertices[k].bulge == 0 {
                        if k + 1 < points.count {
                            add(points[k], points[k + 1], index, layer)
                        } else if closed, points.count > 2 {
                            add(points[k], points[0], index, layer)
                        }
                    }
                    if closed, let apex = Self.arrowTip(vertices, within: markSize) {
                        marks.append(Mark(at: apex, entities: [index], layer: layer))
                    } else {
                        noteSmall(&small, index, points, layer)
                    }
                case .circle(let center, let radius, let layer, _):
                    circles.append(
                        Circle(
                            center: Point2(center.x, center.y), radius: radius, entity: index,
                            layer: layer, span: nil))
                    noteSmall(&small, index, Self.box(center, radius), layer)
                case .arc(let center, let radius, let start, let end, let layer, _):
                    circles.append(
                        Circle(
                            center: Point2(center.x, center.y), radius: radius, entity: index,
                            layer: layer, span: (start, end)))
                    noteSmall(&small, index, Self.box(center, radius), layer)
                case .spline(let spline):
                    let points = spline.controlPoints.map { Point2($0.x, $0.y) }
                    noteSmall(&small, index, points, spline.layer)
                case .point(let at, let layer, _):
                    marks.append(Mark(at: Point2(at.x, at.y), entities: [index], layer: layer))
                default:
                    break
                }
            }
            addClusters(of: small)
        }

        /// The numbers of a string such as `200 629`, with the character each starts at.
        ///
        /// Empty unless the string is made only of numbers and spaces and holds at least two.
        static func numbers(in string: String) -> [(text: String, offset: Int)] {
            var found: [(text: String, offset: Int)] = []
            var start: Int?
            let characters = Array(string)
            for i in 0...characters.count {
                let c: Character = i < characters.count ? characters[i] : " "
                if c == " " || c == "\u{3000}" {
                    if let from = start {
                        found.append((String(characters[from..<i]), from))
                        start = nil
                    }
                } else if c.isASCII, c.isNumber || c == "." || c == "," {
                    if start == nil { start = i }
                } else {
                    return []
                }
            }
            return found.count >= 2 && found.allSatisfy({ $0.text.first!.isNumber }) ? found : []
        }

        private static func box(_ c: Point, _ r: Double) -> [Point2] {
            [Point2(c.x - r, c.y - r), Point2(c.x + r, c.y + r)]
        }

        private mutating func add(_ a: Point2, _ b: Point2, _ entity: Int, _ layer: String) {
            let length = a.distance(to: b)
            guard length > 1e-9, a.x.isFinite, a.y.isFinite, b.x.isFinite, b.y.isFinite else {
                return
            }
            let index = segments.count
            segments.append(
                Segment(
                    a: a, b: b, entity: entity, layer: layer, length: length,
                    unit: Point2((b.x - a.x) / length, (b.y - a.y) / length)))
            segmentGrid.insert(index, Self.bounds([a, b]))
        }

        static func bounds(_ points: [Point2]) -> Box2 {
            var lo = Point2(.infinity, .infinity)
            var hi = Point2(-.infinity, -.infinity)
            for p in points {
                lo = Point2(min(lo.x, p.x), min(lo.y, p.y))
                hi = Point2(max(hi.x, p.x), max(hi.y, p.y))
            }
            return Box2(min: lo, max: hi)
        }

        private func noteSmall(
            _ small: inout [(entity: Int, box: Box2, layer: String)], _ entity: Int,
            _ points: [Point2], _ layer: String
        ) {
            guard !points.isEmpty, points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
                return
            }
            let box = Self.bounds(points)
            if hypot(box.width, box.height) <= markSize {
                small.append((entity, box, layer))
            }
        }

        /// The tip of a closed polyline that is a triangle shaped like an arrowhead, or `nil`:
        /// the corner opposite its shortest side, when that side is under 60% of the longest.
        static func arrowTip(_ vertices: [PolyVertex], within size: Double) -> Point2? {
            var corners = vertices.map { Point2($0.point.x, $0.point.y) }
            if corners.count == 4, corners[0] == corners[3] { corners.removeLast() }
            guard corners.count == 3, vertices.allSatisfy({ $0.bulge == 0 }) else { return nil }
            let sides = (0..<3).map { corners[$0].distance(to: corners[($0 + 1) % 3]) }
            guard let longest = sides.max(), let shortest = sides.min(), longest <= size,
                shortest < 0.6 * longest, let base = sides.firstIndex(of: shortest)
            else { return nil }
            // Side `base` joins corners `base` and `base + 1`; the tip is the other one.
            return corners[(base + 2) % 3]
        }

        private static func meet(_ a: Box2, _ b: Box2) -> Bool {
            a.min.x <= b.max.x && b.min.x <= a.max.x && a.min.y <= b.max.y && b.min.y <= a.max.y
        }

        /// Marks from the small shapes that touch: a dot drawn as four curves, a tick, an arrowhead.
        ///
        /// Each group on one layer with a small extent is a mark at the centre of its box.
        private mutating func addClusters(of small: [(entity: Int, box: Box2, layer: String)]) {
            guard !small.isEmpty else { return }
            var parent = Array(0..<small.count)
            func find(_ i: Int) -> Int {
                var i = i
                while parent[i] != i {
                    parent[i] = parent[parent[i]]
                    i = parent[i]
                }
                return i
            }
            var grid = Grid(cell: max(markSize, 1e-3))
            for (i, item) in small.enumerated() { grid.insert(i, item.box) }
            for (i, item) in small.enumerated() {
                let wide = Box2(
                    min: Point2(item.box.min.x - tolerance, item.box.min.y - tolerance),
                    max: Point2(item.box.max.x + tolerance, item.box.max.y + tolerance))
                for j in grid.query(wide) where j > i {
                    let other = small[j]
                    guard item.layer == other.layer, Self.meet(wide, other.box) else { continue }
                    parent[find(j)] = find(i)
                }
            }
            var groups: [Int: [Int]] = [:]
            for i in small.indices { groups[find(i), default: []].append(i) }
            for (_, members) in groups.sorted(by: { $0.key < $1.key }) {
                var box = small[members[0]].box
                for m in members.dropFirst() { box = box.union(small[m].box) }
                guard hypot(box.width, box.height) <= markSize else { continue }
                marks.append(
                    Mark(
                        at: Point2((box.min.x + box.max.x) / 2, (box.min.y + box.max.y) / 2),
                        entities: members.map { small[$0].entity },
                        layer: small[members[0]].layer))
            }
        }
    }
}
