import Foundation
import Testing

@testable import SwiftDXF

/// The scale of each layer group, and what is not accepted as one.
@Suite("Rebuilding dimensions, scales")
struct RebuildScaleTests {
    typealias Rebuild = RebuildDimensionsTests
    typealias Record = DXFBuilder.Record

    @Test("each layer group has its own scale, and groups that differ are reported, not averaged")
    func disagreeingGroups() throws {
        let (_, result) = try Rebuild.rebuild(
            Rebuild.chain(scale: 50, lengths: [20, 30], layer: "1-0")
                + Rebuild.chain(scale: 100, lengths: [20, 30], y: 100, layer: "2-0"))
        #expect(result.dimensions.count == 4)
        #expect(result.scales.map(\.group) == ["1", "2"])
        #expect(result.scales.map(\.scale) == [50, 100])
        #expect(result.dimensions.map { $0.rebuilt?.scale } == [50, 50, 100, 100])
        #expect(result.warnings == [.scalesDisagree(result.scales)])
    }

    @Test("layers of one Jw_cad layer group share a scale, and groups that agree are not warned of")
    func agreeingGroups() throws {
        let (_, result) = try Rebuild.rebuild(
            Rebuild.chain(scale: 80, lengths: [20], layer: "0-E")
                + Rebuild.chain(scale: 80, lengths: [30], y: 100, layer: "0-F")
                + Rebuild.chain(scale: 80, lengths: [10, 25], y: 200, layer: "3-0"))
        #expect(result.scales.map(\.group) == ["0", "3"])
        #expect(result.scales.map(\.scale) == [80, 80])
        #expect(result.warnings.isEmpty)
        #expect(result.dimensions.count == 4)
    }

    @Test("a value that no geometry explains is a warning, and does not spoil the scale")
    func unexplainedValue() throws {
        var records = Rebuild.chain(scale: 50, lengths: [20, 30, 15])
        records.append(Rebuild.text("777", 5, -9.5))
        let (dwg, result) = try Rebuild.rebuild(records)
        #expect(result.dimensions.count == 3)
        #expect(result.scales == [.init(group: "0", scale: 50, supporting: 3, contradicting: 1)])
        let identity = dwg.identity(ofEntityAt: records.count - 1)
        #expect(
            result.warnings == [
                .valueNotExplained(text: "777", identity: identity, reason: .noMatch)
            ])
    }

    @Test("one value cannot give a scale, unless the scale is stated")
    func oneValue() throws {
        let records = Rebuild.chain(scale: 50, lengths: [20])
        let (dwg, result) = try Rebuild.rebuild(records)
        #expect(result.dimensions.isEmpty && result.scales.isEmpty)
        #expect(
            result.warnings == [
                .valueNotExplained(
                    text: "1000", identity: dwg.identity(ofEntityAt: records.count - 1),
                    reason: .noScale)
            ])
        let stated = dwg.rebuildingDimensions(.init(scale: 50))
        #expect(stated.dimensions.count == 1 && stated.warnings.isEmpty)
        #expect(stated.scales == [.init(group: "0", scale: 50, supporting: 1, contradicting: 0)])
        // A stated scale the geometry does not bear out explains nothing.
        let wrong = dwg.rebuildingDimensions(.init(scale: 60))
        #expect(wrong.dimensions.isEmpty)
    }

    @Test("values that do not agree on any scale are not given one")
    func noConsistentScale() throws {
        var records = Rebuild.chain(scale: 50, lengths: [20, 30, 15])
        // Change the values so no one scale explains them.
        records = records.map { record in
            guard record[0].1 == "TEXT" else { return record }
            var out = record
            let changed = ["1000": "913", "1500": "1777", "750": "421"]
            out[6].1 = changed[out[6].1] ?? out[6].1
            return out
        }
        let (_, result) = try Rebuild.rebuild(records)
        #expect(result.dimensions.isEmpty)
    }

    @Test("a scale that is not round is reported as found, and a round one as round")
    func roundness() throws {
        let odd = try Rebuild.rebuild(Rebuild.chain(scale: 79.5, lengths: [20, 30, 15, 40])).1
        #expect(odd.dimensions.count == 4)
        let found = try #require(odd.scales.first?.scale)
        #expect(abs(found - 79.5) < 0.3 && found != 80, "reported \(found)")
        let small = try Rebuild.rebuild(Rebuild.chain(scale: 3.5, lengths: [20, 30, 15, 40])).1
        #expect(small.dimensions.count == 4 && abs((small.scales.first?.scale ?? 0) - 3.5) < 0.05)
        let enlarged = try Rebuild.rebuild(Rebuild.chain(scale: 0.5, lengths: [20, 30, 15, 40])).1
        #expect(enlarged.scales.first?.scale == 0.5 && enlarged.dimensions.count == 4)
    }

    @Test("values that disagree with the scale outnumber the ones that agree: no scale")
    func majority() throws {
        var records = Rebuild.chain(scale: 50, lengths: [20, 30, 15])
        for (x, value) in [(2.0, "913"), (12.0, "123"), (22.0, "617"), (32.0, "333")] {
            records.append(Rebuild.text(value, x, -9.5))
        }
        let (_, result) = try Rebuild.rebuild(records)
        #expect(result.dimensions.isEmpty && result.scales.isEmpty)
    }

    @Test("a ruler or an axis, whose labels are positions, is not a chain of dimensions")
    func rulerAndAxis() throws {
        // Ticks every 20 units labelled 10 to 100: each label is explained by some number of
        // intervals at the scale 0.5, but a dimension is between neighbouring ends.
        var ruler: [Record] = [Rebuild.line((0, 0), (200, 0))]
        for k in 0...10 { ruler.append(Rebuild.line((Double(k) * 20, 4), (Double(k) * 20, -2))) }
        for k in 1...10 { ruler.append(Rebuild.text("\(k * 10)", Double(k) * 20 - 4, 0.5)) }
        #expect(try Rebuild.rebuild(ruler).1.dimensions.isEmpty)
        // An axis labelled 50 to 400 every 25 units, drawn the same way.
        var axis: [Record] = [Rebuild.line((0, 0), (200, 0))]
        for k in 0...8 { axis.append(Rebuild.line((Double(k) * 25, 4), (Double(k) * 25, -2))) }
        for k in 1...8 { axis.append(Rebuild.text("\(k * 50)", Double(k) * 25 - 4, 0.5)) }
        #expect(try Rebuild.rebuild(axis).1.dimensions.isEmpty)
    }

    @Test("a numbered sequence beside lines is not a scale")
    func sequence() throws {
        // Ten equal spans numbered 1 to 10 fit the scale 1/45, which no drawing is at.
        var records: [Record] = [Rebuild.line((0, 0), (450, 0))]
        for k in 0...10 { records.append(Rebuild.line((Double(k) * 45, 5), (Double(k) * 45, -2))) }
        for k in 1...10 { records.append(Rebuild.text("\(k)", Double(k) * 45 - 25, 0.5)) }
        let (_, result) = try Rebuild.rebuild(records)
        #expect(result.dimensions.isEmpty)
    }

    @Test("a scale from a twentieth to a million is plausible, and no other")
    func plausibleScales() throws {
        for scale in [0.04, 2_000_000.0] {
            let (_, result) = try Rebuild.rebuild(
                Rebuild.chain(scale: scale, lengths: [2000, 3000, 1500]))
            #expect(result.dimensions.isEmpty, "scale \(scale)")
        }
        for scale in [0.05, 100_000.0] {
            let (_, result) = try Rebuild.rebuild(
                Rebuild.chain(scale: scale, lengths: [2000, 3000, 1500]))
            #expect(result.dimensions.count == 3, "scale \(scale)")
        }
    }
}
