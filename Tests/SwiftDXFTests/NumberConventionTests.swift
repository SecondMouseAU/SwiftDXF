import Foundation
import Testing

@testable import SwiftDXF

/// How a drawing writes numbers: `10,439` is ten thousand four hundred and thirty-nine on a
/// Jw_cad drawing and `0,125` is one eighth where a comma is the decimal mark (SwiftDXF#39).
@Suite("Number conventions")
struct NumberConventionTests {
    typealias Rebuild = RebuildDimensionsTests
    typealias Convention = DXF.DimensionText.NumberConvention

    static func numbers(_ raw: String, _ convention: Convention) -> [Double] {
        DXF.DimensionText(raw, numbers: convention).typedNumbers
    }

    // MARK: DimensionText

    @Test("by default a comma is not part of a number, as before")
    func plain() {
        #expect(DXF.DimensionText("10,439").typedNumbers == [10, 439])
        #expect(DXF.DimensionText("10,439", numbers: .plain).typedNumbers == [10, 439])
        #expect(DXF.DimensionText("0,125").typedNumbers == [0, 125])
        #expect(DXF.DimensionText("10,439").parts.last == .number(439, text: "439"))
        #expect(DXF.DimensionText("10,439").plain == "10,439")
    }

    @Test("where a comma separates thousands, it counts inside a number written in groups of three")
    func thousands() {
        func read(_ raw: String) -> [Double] { Self.numbers(raw, .commaSeparatesThousands) }
        #expect(read("10,439") == [10439])
        #expect(read("1,930") == [1930])
        #expect(read("12,345,678") == [12_345_678])
        #expect(read("5,186.6") == [5186.6])
        #expect(read("100,000.25") == [100_000.25])
        #expect(read("-1,234") == [-1234])
        #expect(read("10,439 mm") == [10439])
        #expect(read("559") == [559])
        #expect(read("12.5") == [12.5])
        // Anything else is as written: a range, a group of four, a leading zero, a lone digit.
        #expect(read("40,60") == [40, 60])
        #expect(read("1,2345") == [1, 2345])
        #expect(read("1234,567") == [1234, 567])
        #expect(read("0,125") == [0, 125])
        #expect(read("01,234") == [1, 234])
        #expect(read("1,234,56") == [1234, 56])
        #expect(read("1,") == [1])
        #expect(read("1,234,") == [1234])
        // The number keeps the characters it was written with.
        let text = DXF.DimensionText("L 10,439 mm", numbers: .commaSeparatesThousands)
        #expect(text.parts == [.words("L "), .number(10439, text: "10,439"), .words(" mm")])
        #expect(text.plain == "L 10,439 mm")
        #expect(text.words == ["L", "mm"])
    }

    @Test("where a comma is the decimal mark, a comma between digits is one")
    func decimalMark() {
        func read(_ raw: String) -> [Double] { Self.numbers(raw, .commaIsDecimalMark) }
        #expect(read("0,125") == [0.125])
        #expect(read("10,439") == [10.439])
        #expect(read("5,5") == [5.5])
        #expect(read("-0,5") == [-0.5])
        #expect(read("12.5") == [12.5])
        #expect(read("12,5 mm") == [12.5])
        // A second mark ends the number, and a comma with no digit after it is not part of one.
        #expect(read("1,2,3") == [1.2, 3])
        #expect(read("12,") == [12])
        #expect(
            DXF.DimensionText("0,125", numbers: .commaIsDecimalMark).parts == [
                .number(0.125, text: "0,125")
            ])
    }

    @Test("full-width digits, the point and the comma read as their ordinary forms")
    func fullWidth() {
        let ten = "\u{FF11}\u{FF10}\u{FF0C}\u{FF14}\u{FF13}\u{FF19}"  // １０，４３９
        #expect(Self.numbers(ten, .commaSeparatesThousands) == [10439])
        #expect(Self.numbers(ten, .commaIsDecimalMark) == [10.439])
        #expect(Self.numbers(ten, .plain) == [10, 439])
        #expect(DXF.DimensionText(ten).typedNumbers == [10, 439])
        #expect(DXF.DimensionText("\u{FF11}\u{FF12}\u{FF0E}\u{FF15}").typedNumbers == [12.5])
        // What was written stays in the part, and in the text as it reads.
        let text = DXF.DimensionText(ten, numbers: .commaSeparatesThousands)
        #expect(text.parts == [.number(10439, text: ten)] && text.plain == ten)
        // A full-width letter is still a word.
        #expect(DXF.DimensionText("\u{FF21}\u{FF11}").typedNumbers == [1])
        #expect(DXF.DimensionText("\u{FF21}\u{FF11}").words == ["\u{FF21}"])
    }

    @Test("a digit with a combining mark is not a digit")
    func combiningMark() {
        #expect(DXF.DimensionText("1\u{0301}").typedNumbers.isEmpty)
        #expect(Self.numbers("1\u{0301}", .commaSeparatesThousands).isEmpty)
    }

    @Test("a dimension reads its text as the drawing writes numbers")
    func dimensionText() {
        let dimension = DXF.Dimension(
            kind: .linear, measurement: nil, textOverride: "10,439", textPosition: .init(0, 0),
            defPoint: .init(0, 0), layer: "0", color: 7, codePage: .shiftJIS)
        #expect(dimension.text.typedNumbers == [10, 439])
        #expect(dimension.text(numbers: .commaSeparatesThousands).typedNumbers == [10439])
        #expect(dimension.text(numbers: .commaIsDecimalMark).typedNumbers == [10.439])
        #expect(dimension.text(numbers: .plain) == dimension.text)
    }

    // MARK: rebuilding dimensions

    @Test("a value reads as the drawing writes numbers, or every way a comma can be read")
    func values() {
        typealias Value = DXF.DimensionRebuild.Value
        func read(_ s: String, _ numbers: Convention?) -> Value? { Value.read(s, numbers: numbers) }
        #expect(
            read("1,829", nil)?.readings == [
                .init(value: 1.829, decimals: 3), .init(value: 1829, decimals: 0),
            ])
        #expect(
            read("1,829", .commaSeparatesThousands)?.readings == [.init(value: 1829, decimals: 0)])
        #expect(read("1,829", .commaIsDecimalMark)?.readings == [.init(value: 1.829, decimals: 3)])
        #expect(
            read("10,439", .commaSeparatesThousands)?.readings == [.init(value: 10439, decimals: 0)]
        )
        #expect(
            read("5,186.6", .commaSeparatesThousands)?.readings == [
                .init(value: 5186.6, decimals: 1)
            ])
        #expect(
            read("\u{2300}1,500", .commaSeparatesThousands)?.readings == [
                .init(value: 1500, decimals: 0)
            ])
        #expect(read("\u{2300}1,500", .commaSeparatesThousands)?.symbol == .diameter)
        #expect(
            read("\u{FF11}\u{FF10}\u{FF0C}\u{FF14}\u{FF13}\u{FF19}", .commaSeparatesThousands)?
                .readings == [.init(value: 10439, decimals: 0)])
        #expect(read("26 mm", .commaSeparatesThousands)?.unsupported == nil)
        // What a convention does not read as one number is several, and is listed as that.
        #expect(read("40,60", .commaSeparatesThousands)?.unsupported == .severalNumbers)
        #expect(read("0,125", .commaSeparatesThousands)?.unsupported == .severalNumbers)
        #expect(read("10,439", .plain)?.unsupported == .severalNumbers)
        #expect(read("10,439", .plain)?.readings == [.init(value: 10, decimals: 0)])
        #expect(read("45\u{B0}", .commaSeparatesThousands)?.unsupported == .angular)
        #expect(read("1,5 m", .commaIsDecimalMark)?.unsupported == .unit)
        #expect(read("Radius", .commaSeparatesThousands) == nil)
        #expect(read("", .commaIsDecimalMark) == nil)
    }

    /// A chain whose texts are `1,829`, `1,981` and `2,210`, drawn 1:1000 or, as 1.829 and the
    /// rest, 1:1: a tie that the geometry cannot break.
    static let ambiguous = Rebuild.chain(
        scale: 1, lengths: [1.829, 1.981, 2.21], decimals: 3, comma: true)

    @Test("the convention decides what the geometry cannot")
    func ambiguousChain() throws {
        let unsaid = try Rebuild.rebuild(Self.ambiguous)
        let strings = ["1,829", "1,981", "2,210"]
        #expect(unsaid.1.dimensions.map(\.textOverride) == strings)
        let thousands = try Rebuild.rebuild(
            Self.ambiguous, .init(numbers: .commaSeparatesThousands))
        #expect(thousands.1.dimensions.map(\.textOverride) == strings)
        #expect(thousands.1.scales.map(\.scale) == [1000])
        #expect(thousands.1.warnings.isEmpty)
        let decimal = try Rebuild.rebuild(Self.ambiguous, .init(numbers: .commaIsDecimalMark))
        #expect(decimal.1.dimensions.map(\.textOverride) == strings)
        #expect(decimal.1.scales.map(\.scale) == [1])
        #expect(decimal.1.warnings.isEmpty)
        let shown = decimal.1.dimensions.compactMap { decimal.0.displayedMeasurement(of: $0) }
        #expect(zip(shown, [1.829, 1.981, 2.21]).allSatisfy { abs($0 - $1) < 1e-6 })
    }

    @Test("a Jw_cad drawing reads 10,439 as 10439, and never as 10.439")
    func jwCad() throws {
        // Drawn at 1:80, as the 2120 is: 130.4875 drawn units, 10,439.
        let records = Rebuild.chain(scale: 80, lengths: [130.4875, 22.8625, 24.7625], comma: true)
        let (dwg, result) = try Rebuild.rebuild(records, .init(numbers: .commaSeparatesThousands))
        #expect(result.dimensions.map(\.textOverride) == ["10,439", "1,829", "1,981"])
        #expect(result.scales.map(\.scale) == [80])
        #expect(result.warnings.isEmpty)
        let shown = result.dimensions.compactMap { dwg.displayedMeasurement(of: $0) }
        #expect(zip(shown, [10439.0, 1829, 1981]).allSatisfy { abs($0 - $1) < 0.05 })
        // Read as a decimal mark, the same drawing does not give 1:80.
        let decimal = try Rebuild.rebuild(records, .init(numbers: .commaIsDecimalMark)).1
        #expect(decimal.scales.map(\.scale) != [80])
    }

    @Test("a comma is not part of a number where the convention says so")
    func plainRebuild() throws {
        let records = Rebuild.chain(scale: 80, lengths: [22.8625, 24.7625, 27.625], comma: true)
        let (_, result) = try Rebuild.rebuild(records, .init(numbers: .plain))
        #expect(result.dimensions.isEmpty)
    }

    @Test("without a convention the rebuild reads a comma as it did, and the options compare")
    func unchanged() {
        #expect(DXF.DimensionRebuild.Options().numbers == nil)
        #expect(
            DXF.DimensionRebuild.Options() != .init(numbers: .commaSeparatesThousands))
        #expect(
            DXF.DimensionRebuild.Options(numbers: .plain)
                == .init(scale: nil, tolerance: nil, pieceLayers: .sameAsText, numbers: .plain))
    }

    // MARK: the real drawing

    /// The 2120's 29 dimensions as SwiftJWW recovers them (`jww2dxf --recover-dimensions`): set
    /// `DXF_NUMBERS_FILE` to the DXF. 17 of the values carry a thousands comma.
    @Test(
        "the 2120's dimensions read as whole numbers where a comma separates thousands",
        .enabled(if: ProcessInfo.processInfo.environment["DXF_NUMBERS_FILE"] != nil))
    func realDrawing() throws {
        let path = try #require(ProcessInfo.processInfo.environment["DXF_NUMBERS_FILE"])
        let dwg = try DXF.read(contentsOf: URL(fileURLWithPath: path))
        let dimensions = dwg.entities.compactMap { entity -> DXF.Dimension? in
            if case .dimension(let dimension) = entity { return dimension } else { return nil }
        }
        #expect(dimensions.count == 29)
        var withComma = 0
        for dimension in dimensions {
            let written = try #require(dimension.textOverride)
            let value = try #require(Double(written.replacingOccurrences(of: ",", with: "")))
            #expect(dimension.text(numbers: .commaSeparatesThousands).typedNumbers == [value])
            if written.contains(",") {
                withComma += 1
                #expect(dimension.text.typedNumbers.count == 2, "\(written) by default")
            }
        }
        #expect(withComma == 17)
    }

    /// The README's figures for the 2120 (a Jw_cad export, 1:80): set `DXF_REBUILD_FILE`.
    @Test(
        "the 2120 rebuilds as the README says under each convention",
        .enabled(if: ProcessInfo.processInfo.environment["DXF_REBUILD_FILE"] != nil))
    func realRebuild() throws {
        let path = try #require(ProcessInfo.processInfo.environment["DXF_REBUILD_FILE"])
        let dwg = try DXF.read(contentsOf: URL(fileURLWithPath: path))
        let thousands = dwg.rebuildingDimensions(.init(numbers: .commaSeparatesThousands))
        #expect(thousands.dimensions.count == 29 && thousands.scales.map(\.scale) == [80])
        #expect(thousands.warnings.isEmpty)
        let decimal = dwg.rebuildingDimensions(.init(numbers: .commaIsDecimalMark))
        #expect(decimal.dimensions.count == 17)
        #expect(decimal.scales.map { abs($0.scale - 0.08) < 1e-3 } == [true])
        #expect(dwg.rebuildingDimensions(.init(numbers: .plain)).dimensions.count == 12)
        // Without a convention it is what it was before the setting.
        #expect(dwg.rebuildingDimensions().dimensions.count == 29)
    }
}
