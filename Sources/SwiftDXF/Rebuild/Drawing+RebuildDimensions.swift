import Foundation

extension DXF.Drawing {
    /// Rebuilds dimensions from the loose pieces of the drawing: value texts, dimension lines,
    /// extension lines, and the marks at their ends.
    ///
    /// For each text that states a number, it finds the dimension line beside it and the ends of
    /// the span, or the circle or arc it dimensions, and infers the scale of each layer group from
    /// the values against the drawn lengths. A scale counts only when at least two values
    /// support it, and a group that disagrees with another is reported, not averaged. A diameter
    /// or radius is read from the geometry, not from its symbol; a symbol that disagrees is
    /// reported.
    ///
    /// A drawing with `DIMENSION` entities and no loose pieces gets nothing. Read a drawing with
    /// ``ReadOptions/expandBlocks`` when its pieces are in blocks.
    public func rebuildingDimensions(_ options: DXF.DimensionRebuild.Options = .init())
        -> DXF.DimensionRebuild
    {
        DXF.DimensionRebuilder(self, options).run()
    }
}

extension DXF {
    /// What `Drawing.rebuildingDimensions(_:)` runs.
    struct DimensionRebuilder {
        let drawing: Drawing
        let options: DimensionRebuild.Options
        let pieces: RebuildPieces
        let collinear: CollinearIndex

        init(_ drawing: Drawing, _ options: DimensionRebuild.Options) {
            self.drawing = drawing
            self.options = options
            let pieces = RebuildPieces(drawing, tolerance: options.tolerance)
            self.pieces = pieces
            collinear = CollinearIndex(pieces.segments, tolerance: pieces.tolerance)
        }

        /// The layer group of a layer: `0` for the Jw_cad layer `0-E`, otherwise the layer name.
        static func group(of layer: String) -> String {
            let parts = layer.split(separator: "-", omittingEmptySubsequences: false)
            if parts.count == 2, parts.allSatisfy({ $0.count == 1 && $0.first!.isHexDigit }) {
                return parts[0].uppercased()
            }
            return layer
        }

        /// The reading of the text of `candidate` that its length explains at `scale`, if any.
        func explains(_ candidate: RebuildCandidate, at scale: Double)
            -> DimensionRebuild.Value.Reading?
        {
            let slack = 2 * pieces.tolerance * scale
            return pieces.texts[candidate.text].value.readings.first {
                abs(candidate.length * scale - $0.value) <= $0.tolerance + slack
            }
        }

        func run() -> DimensionRebuild {
            var candidates = [[RebuildCandidate]](repeating: [], count: pieces.texts.count)
            for (ti, text) in pieces.texts.enumerated() where text.value.unsupported == nil {
                candidates[ti] = linearCandidates(ti) + radialCandidates(ti)
            }

            // The scale of each layer group.
            var groups: [String: [Int]] = [:]
            for (ti, text) in pieces.texts.enumerated() where !candidates[ti].isEmpty {
                groups[Self.group(of: text.layer), default: []].append(ti)
            }
            var scales: [DimensionRebuild.ScaleEstimate] = []
            var scaleOfGroup: [String: Double] = [:]
            for (group, members) in groups.sorted(by: { $0.key < $1.key }) {
                let found: (scale: Double, supporting: Int)?
                if let forced = options.scale, forced > 0 {
                    let supporting = members.filter {
                        candidates[$0].contains { explains($0, at: forced) != nil }
                    }.count
                    found = (forced, supporting)
                } else {
                    found = inferScale(members.map { candidates[$0] })
                }
                guard let found, options.scale != nil || accepts(found, of: members.count) else {
                    continue
                }
                scaleOfGroup[group] = found.scale
                scales.append(
                    DimensionRebuild.ScaleEstimate(
                        group: group, scale: found.scale, supporting: found.supporting,
                        contradicting: members.count - found.supporting))
            }

            // The candidates a scale explains, nearest first, each text and piece used once.
            var explained:
                [(candidate: RebuildCandidate, reading: DimensionRebuild.Value.Reading)] =
                    []
            for (ti, text) in pieces.texts.enumerated() {
                guard let scale = scaleOfGroup[Self.group(of: text.layer)] else { continue }
                for candidate in candidates[ti] {
                    if let reading = explains(candidate, at: scale) {
                        explained.append((candidate, reading))
                    }
                }
            }
            explained.sort { $0.candidate.cost < $1.candidate.cost }
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
                if let symbol = text.value.symbol, case .radial = item.candidate.shape,
                    (symbol == .diameter) != (dimension.kind == .diameter)
                {
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
                guard !candidates[ti].isEmpty || rebuiltLayers.contains(text.layer) else {
                    continue
                }
                let reason: DimensionRebuild.Reason
                switch text.value.unsupported {
                case .angular?: reason = .angular
                case .unit?: reason = .unit
                case .severalNumbers?: reason = .severalNumbers
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

        // MARK: the scale

        /// Whether a scale found for a group of `values` texts is credible: a plausible scale
        /// that explains at least three of them and as many as it leaves, or two when it is a
        /// round scale and nothing in the group disagrees.
        ///
        /// A numbered sequence beside lines (the ports of a panel, a scale bar, the references of
        /// a border) is explained by some scale too; these checks leave it unexplained.
        func accepts(_ found: (scale: Double, supporting: Int), of values: Int) -> Bool {
            guard (0.05...10_000).contains(found.scale), found.supporting >= 2,
                found.supporting >= values - found.supporting
            else { return false }
            let round =
                found.scale >= 1
                ? found.scale == found.scale.rounded()
                : found.scale == 1 / (1 / found.scale).rounded()
            return found.supporting >= 3 || (round && found.supporting == values)
        }

        /// The scale that explains the most of the texts, whose candidates are `texts`, and how
        /// many it explains; `nil` when no scale explains two.
        ///
        /// Every candidate and reading implies a scale, the value over the length. Each is tried
        /// and the one that explains the most texts is refined to the least-squares scale of the
        /// ones it explains, then made a round scale (80, or 1/2) when that is within 0.3% and
        /// explains as many.
        func inferScale(_ texts: [[RebuildCandidate]]) -> (scale: Double, supporting: Int)? {
            func support(_ scale: Double) -> (count: Int, residual: Double) {
                var count = 0
                var residual = 0.0
                for candidates in texts {
                    var best = Double.infinity
                    for candidate in candidates {
                        guard let reading = explains(candidate, at: scale) else { continue }
                        best = min(best, abs(candidate.length * scale - reading.value))
                    }
                    if best < .infinity {
                        count += 1
                        residual += best
                    }
                }
                return (count, residual)
            }
            var tried = Set<Int>()
            var best: (scale: Double, count: Int, residual: Double)?
            for candidates in texts {
                for candidate in candidates where candidate.length > 10 * pieces.tolerance {
                    for reading in pieces.texts[candidate.text].value.readings {
                        let scale = reading.value / candidate.length
                        guard scale.isFinite, scale > 0,
                            tried.insert(Int((log(scale) * 10_000).rounded())).inserted
                        else { continue }
                        let found = support(scale)
                        if found.count > (best?.count ?? 0)
                            || (found.count == best?.count && found.residual < best!.residual)
                        {
                            best = (scale, found.count, found.residual)
                        }
                    }
                }
            }
            guard var current = best, current.count >= 2 else { return nil }
            // Refine to the least-squares scale of the values explained.
            for _ in 0..<6 {
                var sumLengthValue = 0.0
                var sumLengthSquared = 0.0
                for candidates in texts {
                    var nearest: (length: Double, value: Double, miss: Double)?
                    for candidate in candidates {
                        guard let reading = explains(candidate, at: current.scale) else {
                            continue
                        }
                        let miss = abs(candidate.length * current.scale - reading.value)
                        if miss < (nearest?.miss ?? .infinity) {
                            nearest = (candidate.length, reading.value, miss)
                        }
                    }
                    if let nearest {
                        sumLengthValue += nearest.length * nearest.value
                        sumLengthSquared += nearest.length * nearest.length
                    }
                }
                guard sumLengthSquared > 0 else { break }
                let refined = sumLengthValue / sumLengthSquared
                let found = support(refined)
                guard found.count >= current.count else { break }
                let moved = abs(refined - current.scale) / current.scale
                current = (refined, found.count, found.residual)
                if moved < 1e-9 { break }
            }
            // A round scale replaces it when it lies within what the values can tell apart: 0.3%,
            // or twice the tolerance of a value over the root of the lengths squared.
            var squares = 0.0
            var tolerances = 0.0
            var counted = 0.0
            for candidates in texts {
                var nearest: (length: Double, tolerance: Double, miss: Double)?
                for candidate in candidates {
                    guard let reading = explains(candidate, at: current.scale) else { continue }
                    let miss = abs(candidate.length * current.scale - reading.value)
                    if miss < (nearest?.miss ?? .infinity) {
                        nearest = (candidate.length, reading.tolerance, miss)
                    }
                }
                if let nearest {
                    squares += nearest.length * nearest.length
                    tolerances += nearest.tolerance
                    counted += 1
                }
            }
            let round =
                current.scale >= 1 ? current.scale.rounded() : 1 / (1 / current.scale).rounded()
            let resolution = squares > 0 ? 2 * (tolerances / counted) / squares.squareRoot() : 0
            if round.isFinite, round > 0, round != current.scale,
                abs(round - current.scale) <= max(0.003 * current.scale, resolution),
                support(round).count >= current.count
            {
                current.scale = round
            }
            return (current.scale, current.count)
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
