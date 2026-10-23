import Foundation

extension DXF.Drawing {
    /// Extracts closed regions from the drawing's lines, arcs, circles, polylines, ellipses and
    /// splines, in millimetres.
    ///
    /// ```swift
    /// let result = try DXF.read(contentsOf: url).contours(.init(layers: ["CUT"]))
    /// for shape in result.shapes { print(shape.area, shape.holes.count) }
    /// ```
    ///
    /// Never traps: degenerate or non-finite geometry is dropped and counted in
    /// ``DXF/Contour/Result/warnings``.
    public func contours(_ options: DXF.Contour.Options = .init()) -> DXF.Contour.Result {
        var warnings: [DXF.Contour.Warning] = []
        let (unit, unitWarning) = resolveUnits(options)
        if let unitWarning { warnings.append(unitWarning) }
        let scale = unit.millimetres

        func included(_ layer: String) -> Bool {
            let key = layer.lowercased()
            if let only = options.layers, !only.contains(where: { $0.lowercased() == key }) {
                return false
            }
            return !options.excludedLayers.contains { $0.lowercased() == key }
        }

        var layerNames: [String] = []
        var layerIndex: [String: Int] = [:]
        var extractor = SegmentExtractor(
            scale: scale, fitTolerance: max(options.fitTolerance, 1e-9))
        var text = 0
        var dimensions = 0
        var points = 0
        for entity in entities {
            let layer = entity.layer
            guard included(layer) else { continue }
            switch entity {
            case .text: text += 1
            case .dimension: dimensions += 1
            case .point: points += 1
            default:
                let index =
                    layerIndex[layer]
                    ?? {
                        layerNames.append(layer)
                        layerIndex[layer] = layerNames.count - 1
                        return layerNames.count - 1
                    }()
                extractor.add(entity, layer: index)
            }
        }

        for (type, total) in skipped.sorted(by: { $0.key < $1.key }) {
            let count: Int
            if options.layers == nil && options.excludedLayers.isEmpty {
                count = total
            } else {
                count = (skippedByLayer[type] ?? [:]).filter { included($0.key) }
                    .reduce(0) { $0 + $1.value }
            }
            guard count > 0 else { continue }
            warnings.append(
                type == "INSERT"
                    ? .blockReferencesNotExpanded(count: count)
                    : .skippedEntities(type: type, count: count))
        }
        if text > 0 { warnings.append(.ignoredText(count: text)) }
        if dimensions > 0 { warnings.append(.ignoredDimensions(count: dimensions)) }
        if points > 0 { warnings.append(.ignoredPoints(count: points)) }

        let join = max(options.joinTolerance, 0)
        let chained = ContourChainer(tolerance: join).chain(extractor.segments)
        func names(_ layers: Set<Int>) -> [String] { layers.map { layerNames[$0] }.sorted() }

        var degenerate = extractor.degenerate + chained.degenerate
        var loops: [DXF.Contour.Loop] = []
        for run in chained.loops {
            let loop = DXF.Contour.Loop(segments: run.segments, layers: names(run.layers))
            if loop.area <= join * loop.length * 1e-3 {
                degenerate += 1
            } else {
                loops.append(loop)
            }
        }
        let chains = chained.chains.map {
            DXF.Contour.Chain(segments: $0.segments, layers: names($0.layers))
        }

        let nested = ContourNesting(tolerance: join, rule: options.nesting).nest(loops)

        if extractor.fittedCurves > 0 {
            warnings.append(
                .fittedCurves(count: extractor.fittedCurves, maxDeviation: extractor.fitDeviation))
        }
        if !chains.isEmpty {
            let total = chains.reduce(0) { $0 + $1.length }
            warnings.append(.openChains(count: chains.count, totalLength: total))
        }
        if degenerate > 0 { warnings.append(.degenerateGeometry(count: degenerate)) }
        if nested.coincident > 0 { warnings.append(.coincidentLoops(count: nested.coincident)) }
        if nested.crossing > 0 { warnings.append(.crossingLoops(count: nested.crossing)) }
        if nested.dropped > 0 { warnings.append(.nestedLoopsDropped(count: nested.dropped)) }

        return DXF.Contour.Result(
            shapes: nested.shapes, openChains: chains, warnings: warnings, unit: unit,
            unitScale: scale, maxFitDeviation: extractor.fitDeviation)
    }

    private func resolveUnits(_ options: DXF.Contour.Options) -> (
        DXF.Contour.LengthUnit, DXF.Contour.Warning?
    ) {
        if let forced = options.units { return (forced, nil) }
        if let code = insUnits, let unit = DXF.Contour.LengthUnit(insUnits: code) {
            return (unit, nil)
        }
        if let code = insUnits, code != 0 {
            return (
                options.unitlessFallback, .unknownUnitCode(code, assumed: options.unitlessFallback)
            )
        }
        return (options.unitlessFallback, .unitlessAssumed(options.unitlessFallback))
    }
}

extension DXF.Entity {
    /// The layer name (DXF group 8).
    var layer: String {
        switch self {
        case .line(_, _, let l, _), .circle(_, _, let l, _), .arc(_, _, _, _, let l, _),
            .ellipse(_, _, _, _, _, let l, _), .point(_, let l, _),
            .text(_, _, _, _, let l, _), .polyline(_, _, let l, _):
            return l
        case .dimension(let d): return d.layer
        case .spline(let s): return s.layer
        }
    }
}
