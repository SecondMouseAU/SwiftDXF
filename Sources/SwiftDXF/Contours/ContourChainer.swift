import Foundation

/// Joins loose segments into closed loops and open chains.
///
/// Endpoints within the join tolerance are merged into one node through a grid hash, so the work is
/// linear in the number of segments. Loops are then traced through the node graph.
struct ContourChainer {
    /// A traced run of segments with the source layer index of each.
    struct Run {
        var segments: [DXF.Contour.Segment]
        var layers: Set<Int>
    }

    struct Output {
        var loops: [Run] = []
        var chains: [Run] = []
        /// Segments dropped for collapsing to a point, or for repeating another segment.
        var degenerate = 0
    }

    private struct Edge {
        var a: Int
        var b: Int
        var bulge: Double
        var layer: Int
    }

    private struct Cell: Hashable {
        var x: Int
        var y: Int
    }

    let tolerance: Double

    func chain(_ raw: [RawSegment]) -> Output {
        var output = Output()
        let (nodes, edges, dropped) = buildGraph(raw)
        output.degenerate = dropped
        guard !edges.isEmpty else { return output }

        var incident = [[Int]](repeating: [], count: nodes.count)
        for (e, edge) in edges.enumerated() {
            incident[edge.a].append(e)
            incident[edge.b].append(e)
        }
        var alive = [Bool](repeating: true, count: edges.count)
        var leftover: [Int] = []
        prune(edges, incident, &alive, &leftover)

        func segment(_ e: Int, forward: Bool) -> DXF.Contour.Segment {
            let edge = edges[e]
            let s = DXF.Contour.Segment(
                start: nodes[edge.a], end: nodes[edge.b], bulge: edge.bulge)
            return forward ? s : s.reversed()
        }
        func sharpestRight(
            _ options: [Int], from node: Int, after incoming: Double
        ) -> Int {
            let back = incoming + Double.pi
            var best = options[0]
            var bestAngle = Double.infinity
            for o in options {
                let out = segment(o, forward: edges[o].a == node).startDirection
                var phi = DXF.Contour.Segment.wrap(out - back)
                if phi < 1e-9 { phi = 2 * Double.pi }
                if phi < bestAngle {
                    bestAngle = phi
                    best = o
                }
            }
            return best
        }
        func other(_ e: Int, from node: Int) -> Int { edges[e].a == node ? edges[e].b : edges[e].a }

        var used = [Bool](repeating: false, count: edges.count)
        for seed in 0..<edges.count where alive[seed] && !used[seed] {
            var path: [(edge: Int, forward: Bool)] = [(seed, true)]
            var at: [Int: Int] = [edges[seed].a: 0, edges[seed].b: 1]
            used[seed] = true
            var current = edges[seed].b
            while true {
                if let k = at[current], k < path.count {
                    let run = path[k...]
                    output.loops.append(
                        Run(
                            segments: run.map { segment($0.edge, forward: $0.forward) },
                            layers: Set(run.map { edges[$0.edge].layer })))
                    for entry in run.dropFirst() {
                        at[entry.forward ? edges[entry.edge].a : edges[entry.edge].b] = nil
                    }
                    path.removeSubrange(k...)
                    at[current] = k
                }
                let options = incident[current].filter { alive[$0] && !used[$0] }
                guard !options.isEmpty else { break }
                let pick: Int
                if options.count == 1 || path.isEmpty {
                    pick = options[0]
                } else {
                    let last = path[path.count - 1]
                    let incoming = segment(last.edge, forward: last.forward).endDirection
                    pick = sharpestRight(options, from: current, after: incoming)
                }
                used[pick] = true
                let forward = edges[pick].a == current
                path.append((pick, forward))
                current = other(pick, from: current)
                if at[current] == nil { at[current] = path.count }
            }
            leftover.append(contentsOf: path.map { $0.edge })
        }

        output.chains = openChains(leftover, edges, nodes, incident)
        return output
    }

    // MARK: Graph

    private func buildGraph(_ raw: [RawSegment]) -> ([DXF.Point2], [Edge], Int) {
        let tol = max(tolerance, 1e-9)
        var points: [DXF.Point2] = []
        points.reserveCapacity(raw.count * 2)
        for s in raw {
            points.append(s.a)
            points.append(s.b)
        }
        func cell(_ p: DXF.Point2) -> Cell {
            func index(_ v: Double) -> Int { Int(max(-1e15, min(1e15, (v / tol).rounded(.down)))) }
            return Cell(x: index(p.x), y: index(p.y))
        }
        // Leader clustering: a point joins the nearest existing node within the tolerance, else
        // becomes a node itself. Unlike chaining points transitively, a curve sampled finer than
        // the tolerance is thinned, not collapsed to one point, and coordinates stay exact.
        var nodes: [DXF.Point2] = []
        var grid: [Cell: [Int]] = [:]
        var map = [Int](repeating: 0, count: points.count)
        for (i, p) in points.enumerated() {
            let c = cell(p)
            var best = -1
            var bestDistance = Double.infinity
            for dx in -1...1 {
                for dy in -1...1 {
                    guard let members = grid[Cell(x: c.x + dx, y: c.y + dy)] else { continue }
                    for n in members {
                        let d = nodes[n].distance(to: p)
                        if d <= tol && d < bestDistance {
                            best = n
                            bestDistance = d
                        }
                    }
                }
            }
            if best < 0 {
                best = nodes.count
                nodes.append(p)
                grid[c, default: []].append(best)
            }
            map[i] = best
        }
        struct Key: Hashable {
            var a: Int
            var b: Int
            var bulge: Int
        }
        var seen = Set<Key>()
        var edges: [Edge] = []
        var dropped = 0
        for (i, s) in raw.enumerated() {
            let a = map[2 * i]
            let b = map[2 * i + 1]
            if a == b {
                dropped += 1
                continue
            }
            let key =
                a < b
                ? Key(a: a, b: b, bulge: Int((s.bulge * 1e9).rounded()))
                : Key(a: b, b: a, bulge: Int((-s.bulge * 1e9).rounded()))
            if !seen.insert(key).inserted {
                dropped += 1
                continue
            }
            edges.append(Edge(a: a, b: b, bulge: s.bulge, layer: s.layer))
        }
        return (nodes, edges, dropped)
    }

    /// Removes edges hanging off degree-one nodes, repeatedly, so spurs cannot hide a loop.
    private func prune(
        _ edges: [Edge], _ incident: [[Int]], _ alive: inout [Bool], _ out: inout [Int]
    ) {
        var degree = incident.map { $0.count }
        var queue = degree.indices.filter { degree[$0] == 1 }
        while let node = queue.popLast() {
            guard degree[node] == 1, let e = incident[node].first(where: { alive[$0] }) else {
                continue
            }
            alive[e] = false
            out.append(e)
            degree[node] -= 1
            let far = edges[e].a == node ? edges[e].b : edges[e].a
            degree[far] -= 1
            if degree[far] == 1 { queue.append(far) }
        }
    }

    private func openChains(
        _ leftover: [Int], _ edges: [Edge], _ nodes: [DXF.Point2], _ incident: [[Int]]
    ) -> [Run] {
        guard !leftover.isEmpty else { return [] }
        var adjacent: [Int: [Int]] = [:]
        for e in leftover {
            adjacent[edges[e].a, default: []].append(e)
            adjacent[edges[e].b, default: []].append(e)
        }
        var visited = Set<Int>()
        var runs: [Run] = []
        func walk(from node: Int) {
            var current = node
            var segments: [DXF.Contour.Segment] = []
            var layers = Set<Int>()
            while let e = adjacent[current]?.first(where: { !visited.contains($0) }) {
                visited.insert(e)
                let edge = edges[e]
                let forward = edge.a == current
                let s = DXF.Contour.Segment(
                    start: nodes[edge.a], end: nodes[edge.b], bulge: edge.bulge)
                segments.append(forward ? s : s.reversed())
                layers.insert(edge.layer)
                current = forward ? edge.b : edge.a
            }
            if !segments.isEmpty { runs.append(Run(segments: segments, layers: layers)) }
        }
        for node in adjacent.keys.sorted() where adjacent[node]?.count != 2 { walk(from: node) }
        for e in leftover where !visited.contains(e) { walk(from: edges[e].a) }
        return runs
    }
}
