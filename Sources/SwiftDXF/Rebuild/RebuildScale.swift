import Foundation

extension DXF.DimensionRebuilder {
    /// The layer group of a layer: `0` for the Jw_cad layer `0-E`, otherwise the layer name.
    static func group(of layer: String) -> String {
        let parts = layer.split(separator: "-", omittingEmptySubsequences: false)
        if parts.count == 2, parts.allSatisfy({ $0.count == 1 && $0.first!.isHexDigit }) {
            return parts[0].uppercased()
        }
        return layer
    }

    /// The scales a drawing may be at: from a twentieth to a million times its values (a drawing
    /// in metres at 1:1000 with values in millimetres is a million).
    static let plausibleScales = 0.05...1_000_000.0

    /// The reading of the text of `candidate` that its length explains at `scale`, if any.
    ///
    /// The length may be off by twice the tolerance, as each end is, and the value by one unit of
    /// its last place.
    ///
    /// With `voting`, only a reading that is substantial counts; see
    /// ``DXF/DimensionRebuild/Value/Reading/isSubstantial``.
    func explains(_ candidate: DXF.RebuildCandidate, at scale: Double, voting: Bool = false)
        -> DXF.DimensionRebuild.Value.Reading?
    {
        let slack = 2 * pieces.tolerance * scale
        return pieces.texts[candidate.text].value.readings.first {
            (!voting || $0.isSubstantial)
                && abs(candidate.length * scale - $0.value) <= $0.tolerance + slack
        }
    }

    /// Whether a scale found for a group of `values` texts is credible: a plausible scale that
    /// explains at least three of them and more than it leaves, or two when it is a round scale
    /// and nothing in the group disagrees.
    ///
    /// A numbered sequence beside lines (the ports of a panel, a scale bar, the references of a
    /// border) is explained by some scale too; these checks leave it unexplained.
    func accepts(_ found: (scale: Double, supporting: Int), of values: Int) -> Bool {
        guard Self.plausibleScales.contains(found.scale), found.supporting >= 2,
            found.supporting > values - found.supporting
        else { return false }
        let round =
            found.scale >= 1
            ? found.scale == found.scale.rounded()
            : found.scale == 1 / (1 / found.scale).rounded()
        return found.supporting >= 3 || (round && found.supporting == values)
    }

    /// The scale that explains the most of the texts, whose candidates are `texts`, and how many it
    /// explains; `nil` when no scale explains two.
    ///
    /// Each candidate and reading explains the scales from `(value - tolerance) / (length + slack)`
    /// to `(value + tolerance) / (length - slack)`. A sweep over those intervals finds where the
    /// most texts are explained at once. That scale is refined to the least-squares scale of the
    /// ones it explains, then made a round scale (80, or 1/2) when that is within what the values
    /// can tell apart and explains as many.
    func inferScale(_ texts: [[DXF.RebuildCandidate]]) -> (scale: Double, supporting: Int)? {
        /// How many texts `scale` explains, how far their nearest explaining geometry is from
        /// them, and by how much it misses: the geometry beside the text is the likelier one.
        func support(_ scale: Double) -> (count: Int, distance: Double, residual: Double) {
            var count = 0
            var distance = 0.0
            var residual = 0.0
            for candidates in texts {
                var nearest = Double.infinity
                var miss = Double.infinity
                for candidate in candidates {
                    guard let reading = explains(candidate, at: scale, voting: true) else {
                        continue
                    }
                    if candidate.cost < nearest {
                        nearest = candidate.cost
                        miss = abs(candidate.length * scale - reading.value)
                    }
                }
                if nearest < .infinity {
                    count += 1
                    distance += nearest
                    residual += miss
                }
            }
            return (count, distance, residual)
        }

        // The sweep: the scales each text may be explained at, as events along the scale axis.
        struct Event {
            var at: Double
            var opens: Bool
            var text: Int
        }
        var events: [Event] = []
        let tolerance = pieces.tolerance
        for (index, candidates) in texts.enumerated() {
            for candidate in candidates where candidate.length > 10 * tolerance {
                for reading in pieces.texts[candidate.text].value.readings
                where reading.isSubstantial {
                    let low = max(
                        (reading.value - reading.tolerance) / (candidate.length + 2 * tolerance),
                        Self.plausibleScales.lowerBound)
                    let high = min(
                        (reading.value + reading.tolerance) / (candidate.length - 2 * tolerance),
                        Self.plausibleScales.upperBound)
                    guard low.isFinite, high.isFinite, low <= high else { continue }
                    events.append(Event(at: low, opens: true, text: index))
                    events.append(Event(at: high, opens: false, text: index))
                }
            }
        }
        events.sort { ($0.at, $0.opens ? 0 : 1) < ($1.at, $1.opens ? 0 : 1) }
        var active = [Int](repeating: 0, count: texts.count)
        var distinct = 0
        var most = 0
        var places: [Double] = []
        for (k, event) in events.enumerated() {
            if event.opens {
                active[event.text] += 1
                if active[event.text] == 1 { distinct += 1 }
            } else {
                active[event.text] -= 1
                if active[event.text] == 0 { distinct -= 1 }
            }
            // The count just after this event holds up to the next one.
            guard event.opens, k + 1 < events.count else { continue }
            let next = events[k + 1].at
            if distinct > most {
                most = distinct
                places = []
            }
            if distinct == most, places.count < 64 { places.append((event.at + next) / 2) }
        }
        guard most >= 2 else { return nil }
        // Of the scales that explain the most, the one whose geometry is nearest its texts, then a
        // reduction rather than an enlargement (drawings are reduced far more often, so `1,829`
        // at 1:80 is not 1.829 at 12.5 to 1), then the nearest to 1, then the closest fit.
        func rank(_ scale: Double, _ found: (count: Int, distance: Double, residual: Double))
            -> (Int, Double, Int, Double, Double)
        {
            (found.count, -found.distance, scale >= 1 ? 1 : 0, -abs(log(scale)), -found.residual)
        }
        var best: (scale: Double, count: Int, rank: (Int, Double, Int, Double, Double))?
        for scale in places {
            let found = support(scale)
            let ranked = rank(scale, found)
            if best == nil || ranked > best!.rank { best = (scale, found.count, ranked) }
        }
        guard let first = best, first.count >= 2 else { return nil }
        var current = (scale: first.scale, count: first.count)

        // Refine to the least-squares scale of the values explained.
        for _ in 0..<6 {
            var sumLengthValue = 0.0
            var sumLengthSquared = 0.0
            for candidates in texts {
                var nearest: (length: Double, value: Double, miss: Double)?
                for candidate in candidates {
                    guard let reading = explains(candidate, at: current.scale, voting: true) else {
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
            current = (refined, found.count)
            if moved < 1e-9 { break }
        }

        // A round scale replaces it when it lies within what the values can tell apart: 0.3%, or
        // twice the tolerance of a value over the root of the lengths squared.
        var squares = 0.0
        var tolerances = 0.0
        var counted = 0.0
        for candidates in texts {
            var nearest: (length: Double, tolerance: Double, miss: Double)?
            for candidate in candidates {
                guard let reading = explains(candidate, at: current.scale, voting: true) else {
                    continue
                }
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
            current = (round, support(round).count)
        }
        return (current.scale, current.count)
    }
}
