import Foundation

extension DXF.Drawing {
    /// Rebuilds dimensions from the loose pieces of the drawing: value texts, dimension lines,
    /// extension lines and end marks.
    ///
    /// Each text that states a number is matched to the dimension line, circle or arc beside it,
    /// and each layer group gets the scale its values agree on. See ``DimensionRebuild``, and the
    /// README for what counts as a credible scale.
    public func rebuildingDimensions(_ options: DXF.DimensionRebuild.Options = .init())
        -> DXF.DimensionRebuild
    {
        var options = options
        if let scale = options.scale, !(scale.isFinite && scale > 0) { options.scale = nil }
        return DXF.DimensionRebuilder(self, options).run()
    }
}

extension DXF {
    /// What `Drawing.rebuildingDimensions(_:)` runs.
    struct DimensionRebuilder {
        let drawing: Drawing
        let options: DimensionRebuild.Options
        let pieces: RebuildPieces

        init(_ drawing: Drawing, _ options: DimensionRebuild.Options) {
            self.drawing = drawing
            self.options = options
            let pieces = RebuildPieces(
                drawing, tolerance: options.tolerance, numbers: options.numbers)
            self.pieces = pieces
        }

        func run() -> DimensionRebuild {
            var candidates = [[RebuildCandidate]](repeating: [], count: pieces.texts.count)
            // An angle, or a value in another unit, is still listed when a line is beside it. Other
            // texts that cannot be rebuilt (a part number such as `7021N13`) are only listed on
            // the layer of a dimension.
            var beside = Set<Int>()
            for (ti, text) in pieces.texts.enumerated() {
                switch text.value.unsupported {
                case nil:
                    candidates[ti] = linearCandidates(ti) + radialCandidates(ti)
                case .angular?, .unit?:
                    if !linearCandidates(ti).isEmpty || !radialCandidates(ti).isEmpty {
                        beside.insert(ti)
                    }
                default:
                    break
                }
            }

            // The scale of each layer group.
            var groups: [String: [Int]] = [:]
            for (ti, text) in pieces.texts.enumerated() where !candidates[ti].isEmpty {
                groups[Self.group(of: text.layer), default: []].append(ti)
            }
            var scales: [DimensionRebuild.ScaleEstimate] = []
            var scaleOfGroup: [String: Double] = [:]
            for (group, members) in groups.sorted(by: { $0.key < $1.key }) {
                // Only a value that can vote counts for a scale or against it; see `isSubstantial`.
                let voters = members.filter {
                    pieces.texts[$0].value.readings.contains(where: \.isSubstantial)
                }
                let found: (scale: Double, supporting: Int)?
                if let forced = options.scale {
                    let supporting = members.filter {
                        candidates[$0].contains { explains($0, at: forced) != nil }
                    }.count
                    found = (forced, supporting)
                } else {
                    found = inferScale(voters.map { candidates[$0] })
                }
                guard let found, options.scale != nil || accepts(found, of: voters.count) else {
                    continue
                }
                scaleOfGroup[group] = found.scale
                let counted = options.scale == nil ? voters.count : members.count
                scales.append(
                    DimensionRebuild.ScaleEstimate(
                        group: group, scale: found.scale, supporting: found.supporting,
                        contradicting: counted - found.supporting))
            }

            // The candidates a scale explains, nearest first, each text and piece used once.
            var explained:
                [(candidate: RebuildCandidate, reading: DimensionRebuild.Value.Reading)] =
                    []
            var fit: [Double] = []
            for (ti, text) in pieces.texts.enumerated() {
                guard let scale = scaleOfGroup[Self.group(of: text.layer)] else { continue }
                for candidate in candidates[ti] {
                    if let reading = explains(candidate, at: scale) {
                        explained.append((candidate, reading))
                        // Nearness and how far the length is from the length of the value: of
                        // two spans that fit within a unit, the one that fits better.
                        fit.append(
                            candidate.cost + abs(candidate.length - reading.value / scale))
                    }
                }
            }
            explained = explained.indices.sorted { fit[$0] < fit[$1] }.map { explained[$0] }
            var usedTexts = Set<Int>()
            var chosen: [(candidate: RebuildCandidate, reading: DimensionRebuild.Value.Reading)] =
                []
            for item in explained
            where !usedTexts.contains(item.candidate.text)
                && !chosen.contains(where: {
                    $0.candidate.isSameGeometry(as: item.candidate, within: pieces.tolerance)
                })
            {
                usedTexts.insert(item.candidate.text)
                chosen.append(item)
            }
            chosen.sort { $0.candidate.text < $1.candidate.text }

            var warnings: [DimensionRebuild.Warning] = []
            var dimensions: [Dimension] = []
            for item in chosen {
                let text = pieces.texts[item.candidate.text]
                let scale = scaleOfGroup[Self.group(of: text.layer)] ?? 1
                let dimension = build(item.candidate, item.reading, scale: scale)
                // A diameter symbol on a straight dimension is ordinary drafting; a radius symbol
                // on one, or either symbol the circle contradicts, is not.
                let disagrees: Bool
                switch item.candidate.shape {
                case .radial:
                    disagrees = (text.value.symbol == .diameter) != (dimension.kind == .diameter)
                case .linear: disagrees = text.value.symbol == .radius
                }
                if text.value.symbol != nil, disagrees {
                    warnings.append(
                        .symbolDisagrees(
                            text: text.raw, identity: drawing.identity(ofEntityAt: text.entity),
                            geometry: dimension.kind))
                }
                dimensions.append(dimension)
            }

            // Every value that looks like one of the dimensions and is not.
            let rebuiltLayers = Set(chosen.map { pieces.texts[$0.candidate.text].layer })
            for (ti, text) in pieces.texts.enumerated() where !usedTexts.contains(ti) {
                guard
                    !candidates[ti].isEmpty || beside.contains(ti)
                        || rebuiltLayers.contains(text.layer)
                else { continue }
                let reason: DimensionRebuild.Reason
                switch text.value.unsupported {
                case .angular?: reason = .angular
                case .unit?: reason = .unit
                case .severalNumbers?: reason = .severalNumbers
                case .unreadable?: reason = .unreadable
                case nil:
                    reason =
                        scaleOfGroup[Self.group(of: text.layer)] == nil ? .noScale : .noMatch
                }
                warnings.append(
                    .valueNotExplained(
                        text: text.raw, identity: drawing.identity(ofEntityAt: text.entity),
                        reason: reason))
            }
            if let low = scales.map(\.scale).min(), let high = scales.map(\.scale).max(),
                high > low * 1.01
            {
                warnings.append(.scalesDisagree(scales))
            }
            return DimensionRebuild(dimensions: dimensions, scales: scales, warnings: warnings)
        }

        // MARK: the dimension

        private func build(
            _ candidate: RebuildCandidate, _ reading: DimensionRebuild.Value.Reading,
            scale: Double
        ) -> Dimension {
            let text = pieces.texts[candidate.text]
            let identities = ([text.entity] + text.duplicates + candidate.pieces)
                .reduce(into: [Int]()) { if !$0.contains($1) { $0.append($1) } }
                .map { drawing.identity(ofEntityAt: $0) }
            func point(_ p: Point2) -> Point { Point(p.x, p.y) }
            let variables = DimensionStyle.Variables(
                decimalPlaces: reading.decimals, linearScale: scale)
            let rebuilt = Dimension.Rebuilt(pieces: identities, scale: scale)
            switch candidate.shape {
            case .linear(let origin, let unit, let start, let end):
                let a = Point2(origin.x + unit.x * start, origin.y + unit.y * start)
                let b = Point2(origin.x + unit.x * end, origin.y + unit.y * end)
                let angle = (atan2(unit.y, unit.x) * 180 / .pi + 360)
                    .truncatingRemainder(dividingBy: 180)
                let horizontal = min(angle, 180 - angle) <= 0.5
                let vertical = abs(angle - 90) <= 0.5
                return Dimension(
                    kind: horizontal || vertical ? .linear : .aligned,
                    measurement: candidate.length, textOverride: text.raw,
                    textPosition: point(text.center), defPoint: point(b), defPoint2: point(a),
                    defPoint3: point(b), layer: text.layer, color: text.color,
                    rotation: horizontal ? 0 : (vertical ? 90 : nil), styleOverrides: variables,
                    codePage: drawing.codePage, rebuilt: rebuilt)
            case .radial(let kind, let first, let second):
                return Dimension(
                    kind: kind, measurement: candidate.length, textOverride: text.raw,
                    textPosition: point(text.center), defPoint: point(first),
                    defPoint4: point(second), layer: text.layer, color: text.color,
                    styleOverrides: variables, codePage: drawing.codePage, rebuilt: rebuilt)
            }
        }
    }
}
