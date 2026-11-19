import Foundation
import Testing

@testable import SwiftDXF

/// What a value text states: the number, its readings, and the texts that are not rebuilt.
@Suite("Rebuilding dimensions, values")
struct RebuildValueTests {
    typealias Rebuild = RebuildDimensionsTests
    typealias Record = DXFBuilder.Record

    @Test("a comma is a decimal mark or a thousands separator, whichever the geometry bears out")
    func commas() throws {
        let decimal = try Rebuild.rebuild(
            Rebuild.chain(scale: 1, lengths: [2.5, 3.5, 6.5], decimals: 1, comma: true))
        #expect(decimal.1.dimensions.map(\.textOverride) == ["2,5", "3,5", "6,5"])
        #expect(decimal.1.scales.first?.scale == 1)
        let thousands = try Rebuild.rebuild(
            Rebuild.chain(scale: 80, lengths: [22.8625, 24.7625, 27.625], comma: true))
        #expect(thousands.1.dimensions.map(\.textOverride) == ["1,829", "1,981", "2,210"])
        #expect(thousands.1.scales.first?.scale == 80)
    }

    @Test("what a text states: symbols, commas, tolerances and the texts that are not rebuilt")
    func values() {
        typealias Value = DXF.DimensionRebuild.Value
        func read(_ s: String) -> Value? { Value.read(s) }
        #expect(read("12.5")?.readings == [.init(value: 12.5, decimals: 1)])
        #expect(
            read("1,829")?.readings == [
                .init(value: 1.829, decimals: 3), .init(value: 1829, decimals: 0),
            ])
        #expect(read("0,011")?.readings == [.init(value: 0.011, decimals: 3)])
        #expect(read("1,5")?.readings == [.init(value: 1.5, decimals: 1)])
        #expect(read("1,234.5")?.readings == [.init(value: 1234.5, decimals: 1)])
        #expect(read("1,234,567")?.readings == [.init(value: 1_234_567, decimals: 0)])
        #expect(read("\u{FF15}\u{FF10}\u{FF10}")?.readings == [.init(value: 500, decimals: 0)])
        #expect(read("\u{2300}26")?.symbol == .diameter && read("R7.5")?.symbol == .radius)
        #expect(read("R 7.5")?.symbol == .radius && read("26 mm")?.unsupported == nil)
        #expect(read("45\u{B0}")?.unsupported == .angular)
        #expect(read("2x45")?.unsupported == .severalNumbers)
        #expect(read("5m")?.unsupported == .unit && read("3\"")?.unsupported == .unit)
        #expect(read("Radius") == nil && read("L=100") == nil && read("") == nil)
        let stacked = DXF.TextContent(#"36{\H2.4;\S+0,011^ -0,005;}"#, syntax: .mtext)
        #expect(Value.read(stacked)?.readings == [.init(value: 36, decimals: 0)])
    }

    @Test("values a text assembler ran together are separate values")
    func runTogether() throws {
        let records =
            Rebuild.chain(scale: 80, lengths: [30, 25], from: 20, y: 40)
            + [
                Rebuild.line((0, 0), (0, 10)), Rebuild.line((2.5, 0), (2.5, 10)),
                Rebuild.line((10.4, 0), (10.4, 10)), Rebuild.line((0, 3), (10.4, 3)),
                Rebuild.text("200 632", -1, 3.5),
            ]
        let (_, result) = try Rebuild.rebuild(records)
        #expect(result.dimensions.map(\.textOverride).suffix(2) == ["200", "632"])
        #expect(result.warnings.isEmpty)
    }

    @Test("European grouping is read, and a number that cannot be is listed")
    func europeanNumbers() throws {
        typealias Value = DXF.DimensionRebuild.Value
        #expect(Value.read("1.234,5")?.readings == [.init(value: 1234.5, decimals: 1)])
        #expect(Value.read("12.345,67")?.readings == [.init(value: 12345.67, decimals: 2)])
        #expect(Value.read("1.234.567")?.readings == [.init(value: 1_234_567, decimals: 0)])
        #expect(
            Value.read("1.234")?.readings == [
                .init(value: 1.234, decimals: 3), .init(value: 1234, decimals: 0),
            ])
        #expect(Value.read("0.125")?.readings == [.init(value: 0.125, decimals: 3)])
        #expect(Value.read("1.2.3")?.unsupported == .unreadable)
        #expect(Value.read("1,23,456")?.unsupported == .unreadable)
        // A value must be ten units of its last place to be evidence for a scale.
        #expect(Value.read("9")?.readings.first?.isSubstantial == false)
        #expect(Value.read("10")?.readings.first?.isSubstantial == true)
        #expect(Value.read("0.9")?.readings.first?.isSubstantial == false)
        #expect(Value.read("1.0")?.readings.first?.isSubstantial == true)
        #expect(Value.read("2.5")?.readings.first?.isSubstantial == true)
        var records = Rebuild.chain(scale: 50, lengths: [20, 30, 15])
        records.append(Rebuild.text("1.2.3", 5, -9.5))
        let (_, result) = try Rebuild.rebuild(records)
        let reasons = result.warnings.compactMap { warning -> DXF.DimensionRebuild.Reason? in
            guard case .valueNotExplained(_, _, let reason) = warning else { return nil }
            return reason
        }
        #expect(reasons == [.unreadable])
    }
}
