import Foundation
import Testing

@testable import SwiftDXF

/// Input that is not what it should be: noise, absurd values, and options that are not numbers.
@Suite("Rebuilding dimensions, odd input")
struct RebuildRobustnessTests {
    typealias Rebuild = RebuildDimensionsTests
    typealias Record = DXFBuilder.Record

    @Test("pieces of one line that tilt either way by a hair are still one dimension line")
    func tiltedPieces() throws {
        for tilt in [1e-9, -1e-9, 1e-12, -1e-12] {
            var records: [Record] = []
            for x in [0.0, 20, 50, 65] { records.append(Rebuild.line((x, 0), (x, -12))) }
            records.append(Rebuild.line((0, -10), (20, -10)))
            records.append(Rebuild.line((20, -10), (50, -10 - tilt * 30)))
            records.append(Rebuild.line((50, -10), (65, -10 + tilt * 15)))
            for (x, string) in [(7.0, "1000"), (32.0, "1500"), (55.0, "750")] {
                records.append(Rebuild.text(string, x, -10.5))
            }
            let (_, result) = try Rebuild.rebuild(records)
            #expect(result.dimensions.count == 3, "tilt \(tilt)")
        }
    }

    @Test("a slanted dimension line broken around its text is found far from the origin")
    func farFromTheOrigin() throws {
        for degrees in [20.0, 30, 45, 60, 135] {
            for origin in [0.0, 1e4, 1e5] {
                let angle = degrees * .pi / 180
                let (c, s) = (cos(angle), sin(angle))
                func at(_ t: Double, _ offset: Double) -> (Double, Double) {
                    let x = origin + t * c - offset * s
                    let y = origin + t * s + offset * c
                    return ((x * 1000).rounded() / 1000, (y * 1000).rounded() / 1000)
                }
                var records: [Record] = []
                for t in [0.0, 20, 50] { records.append(Rebuild.line(at(t, 12), at(t, -2))) }
                // Four pieces of one line, with a gap for each text, at 3 decimals.
                for (from, to) in [(0.0, 7.0), (13, 20), (20, 32), (38, 50)] {
                    records.append(Rebuild.line(at(from, 10), at(to, 10)))
                }
                for (from, to, string) in [(0.0, 20.0, "1000"), (20, 50, "1500")] {
                    let corner = at((from + to) / 2 - 3, 10.5)
                    records.append(Rebuild.text(string, corner.0, corner.1, rotation: degrees))
                }
                let (_, result) = try Rebuild.rebuild(records)
                #expect(result.dimensions.count == 2, "\(degrees) degrees at \(origin)")
            }
        }
    }

    @Test("an angle beside a dimension line is listed even where nothing was rebuilt")
    func angleBesideALine() throws {
        var records = Rebuild.chain(scale: 50, lengths: [20, 30, 15], layer: "0-E")
        // A line with ends on another layer group, and an angle beside it.
        records += [
            Rebuild.line((0, 100), (20, 100), layer: "9-9"),
            Rebuild.line((0, 110), (0, 98), layer: "9-9"),
            Rebuild.line((20, 110), (20, 98), layer: "9-9"),
            Rebuild.text("45\u{B0}", 5, 100.5, layer: "9-9"),
        ]
        let (_, result) = try Rebuild.rebuild(records)
        let reasons = result.warnings.compactMap { warning -> DXF.DimensionRebuild.Reason? in
            guard case .valueNotExplained(_, _, let reason) = warning else { return nil }
            return reason
        }
        #expect(result.dimensions.count == 3 && reasons == [.angular])
    }

    @Test("a gap beyond the dimension line is not the text's gap")
    func gapBeyondTheLine() throws {
        // An extension line, or a mark, past the end of the line, and the value of the span to it.
        for piece in [Rebuild.line((70, 0), (70, -12)), Rebuild.point(70, -10)] {
            var records = Rebuild.chain(scale: 50, lengths: [20, 30, 15])
            records.append(piece)
            records.append(Rebuild.text("250", 66, -10.5))
            let (_, result) = try Rebuild.rebuild(records)
            #expect(result.dimensions.map(\.textOverride) == ["1000", "1500", "750"])
            #expect(result.warnings.count == 1)
        }
    }

    @Test("a length may differ from the value by the tolerance, scaled, and no more")
    func slack() throws {
        func rebuilt(_ length: Double) throws -> Int {
            let records: [Record] = [
                Rebuild.line((0, 0), (0, -12)), Rebuild.line((length, 0), (length, -12)),
                Rebuild.line((0, -10), (length, -10)), Rebuild.text("1000", length / 2 - 3, -9.5),
            ]
            return try Rebuild.rebuild(records, .init(scale: 50)).1.dimensions.count
        }
        // The tolerance is 3% of the height of 2.5, so 0.075: twice it times 50 is 7.5, and the
        // value is stated to one unit.
        let near = [try rebuilt(20.0), try rebuilt(20.12)]
        let far = [try rebuilt(20.2), try rebuilt(19.8)]
        #expect(near == [1, 1] && far == [0, 0])
    }

    @Test("a dimension carries the code page of its drawing")
    func codePage() throws {
        var builder = DXFBuilder()
        builder.codePage = "ANSI_1252"
        builder.entities = Rebuild.chain(scale: 50, lengths: [20, 30, 15])
        let result = try DXF.read(text: builder.text()).rebuildingDimensions()
        #expect(result.dimensions.count == 3)
        #expect(result.dimensions.allSatisfy { $0.codePage?.number == 1252 })
    }

    @Test("near-overflow input is not a crash")
    func nearOverflow() throws {
        let records = Rebuild.chain(scale: 50, lengths: [20, 30, 15])
        for tolerance in [1e300, 9e307, 1.7e308] {
            let (_, result) = try Rebuild.rebuild(records, .init(tolerance: tolerance))
            #expect(result.dimensions.count == 3, "tolerance \(tolerance)")
        }
        let tall: Record = [
            (0, "TEXT"), (8, "0"), (10, "0"), (20, "0"), (30, "0"), (40, "1e308"), (1, "12 34"),
        ]
        _ = try Rebuild.rebuild(records + [tall])
    }

    @Test("a tolerance that is a number is used: marks off the line by 0.3 meet it at 0.2")
    func toleranceIsUsed() throws {
        let records = Rebuild.chain(scale: 50, lengths: [20, 30, 15], ends: .points).map {
            record -> Record in
            guard record[0].1 == "POINT" else { return record }
            return record.map { $0.0 == 20 ? (20, "-10.3") : $0 }
        }
        #expect(try Rebuild.rebuild(records).1.dimensions.isEmpty)
        #expect(try Rebuild.rebuild(records, .init(tolerance: 0.2)).1.dimensions.count == 3)
    }

    @Test("pieces on any layer are used for a diameter too")
    func radialOnAnyLayer() throws {
        let records: [Record] = [
            Rebuild.circle(0, 0, 10), Rebuild.line((-10, 0), (10, 0), layer: "X"),
            Rebuild.text("40", -3, 1), Rebuild.circle(40, 0, 5),
            Rebuild.line((35, 0), (45, 0), layer: "X"), Rebuild.text("20", 37, 1),
        ]
        #expect(try Rebuild.rebuild(records).1.dimensions.isEmpty)
        let any = try Rebuild.rebuild(records, .init(pieceLayers: .any)).1
        #expect(any.dimensions.map(\.kind) == [.diameter, .diameter])
    }

    @Test("identities are numbered on from the highest the drawing holds")
    func identitiesFromTheHighest() throws {
        let (dwg, result) = try Rebuild.rebuild(Rebuild.chain(scale: 50, lengths: [20, 30, 15]))
        var held = result.applied(to: dwg)
        // A drawing that holds REBUILT:1 and REBUILT:2 only.
        held.identities = (0..<held.entities.count).map {
            let identity = held.identity(ofEntityAt: $0)
            return identity.locator == "REBUILT:0" ? .init(locator: "ENTITIES:99") : identity
        }
        let more = result.applied(to: held)
        let locators = (0..<more.entities.count).map { more.identity(ofEntityAt: $0).locator }
            .filter { $0.hasPrefix("REBUILT:") }
        #expect(Set(locators).count == locators.count)
        #expect(locators.suffix(3) == ["REBUILT:3", "REBUILT:4", "REBUILT:5"])
    }

    @Test("applying a result twice does not repeat the identities")
    func appliedTwice() throws {
        let (dwg, result) = try Rebuild.rebuild(Rebuild.chain(scale: 50, lengths: [20, 30, 15]))
        let twice = result.applied(to: result.applied(to: dwg))
        let rebuilt = (0..<twice.entities.count).map { twice.identity(ofEntityAt: $0).locator }
            .filter { $0.hasPrefix("REBUILT:") }
        #expect(rebuilt == (0..<6).map { "REBUILT:\($0)" })
    }

    @Test("a tolerance or scale that is not a positive number is none, not a crash")
    func invalidOptions() throws {
        let records = Rebuild.chain(scale: 50, lengths: [20, 30, 15])
        for tolerance in [0.0, -1, .nan, .infinity, -.infinity] {
            let (_, result) = try Rebuild.rebuild(records, .init(tolerance: tolerance))
            #expect(result.dimensions.count == 3, "tolerance \(tolerance)")
        }
        for scale in [0.0, -5, .nan, .infinity] {
            let (_, result) = try Rebuild.rebuild(records, .init(scale: scale))
            #expect(result.dimensions.count == 3 && result.scales.first?.scale == 50)
        }
    }

    @Test("pieces at absurd coordinates, and very long lines, do not stop the rest")
    func absurdPieces() throws {
        var records = Rebuild.chain(scale: 50, lengths: [20, 30, 15])
        // Beyond what is read, and within it but vast: none may crash the rebuild or slow it.
        records.append(Rebuild.line((0, 0), (1e30, 1e30)))
        records.append(Rebuild.line((-1e300, 5), (1e300, 5)))
        records.append(Rebuild.point(1e30, -1e30))
        records.append(Rebuild.circle(1e30, 0, 1e30))
        records.append(Rebuild.text("500", 1e30, 0))
        records.append(Rebuild.line((-1e12, -1e12), (1e12, 1e12)))
        records.append(Rebuild.line((-1e11, 5), (1e11, 5)))
        records.append(Rebuild.line((0, 0), (1e5, 1e5)))
        records.append(Rebuild.point(1e11, -1e11))
        records.append(Rebuild.circle(0, 0, 1e11))
        records.append(Rebuild.text("500", 5, 5))
        // A text 4e9 times as tall as the others puts every window across a vast number of cells.
        records.append([
            (0, "TEXT"), (8, "0"), (10, "0"), (20, "0"), (30, "0"), (40, "1e10"), (1, "100"),
        ])
        let start = Date()
        let (_, result) = try Rebuild.rebuild(records)
        let found = Set(result.dimensions.compactMap(\.textOverride))
        #expect(found.isSuperset(of: ["1000", "1500", "750"]))
        #expect(Date().timeIntervalSince(start) < 20)
    }

    @Test("hundreds of values on one layer are rebuilt in reasonable time")
    func manyValues() throws {
        let start = Date()
        let (_, result) = try Rebuild.rebuild(
            Rebuild.chain(scale: 50, lengths: [Double](repeating: 10, count: 300)))
        #expect(result.dimensions.count == 300)
        #expect(Date().timeIntervalSince(start) < 30)
    }

    @Test("a long dashed line with labels along it does not cost the square of its dashes")
    func dashedLine() throws {
        var records: [Record] = []
        for k in 0..<1500 { records.append(Rebuild.line((Double(k), -10), (Double(k) + 0.8, -10))) }
        for k in 0..<60 { records.append(Rebuild.text("\(100 + k)", Double(k) * 25, -9.5)) }
        let start = Date()
        _ = try Rebuild.rebuild(records)
        #expect(Date().timeIntervalSince(start) < 20)
    }

    @Test("a value written in an MTEXT is read as one in a TEXT")
    func mtextValue() throws {
        let records = Rebuild.chain(scale: 50, lengths: [20, 30, 15]).map { record -> Record in
            guard record[0].1 == "TEXT" else { return record }
            // An MTEXT is anchored at its top left, so the point is the TEXT's plus its height.
            let x = record.first { $0.0 == 10 }!.1
            let y = Double(record.first { $0.0 == 20 }!.1)! + 2.5
            let layer = record.first { $0.0 == 8 }!.1
            let string = record.first { $0.0 == 1 }!.1
            return [
                (0, "MTEXT"), (8, layer), (10, x), (20, "\(y)"), (30, "0"), (40, "2.5"),
                (1, string),
            ]
        }
        let (_, result) = try Rebuild.rebuild(records)
        #expect(result.dimensions.map(\.textOverride) == ["1000", "1500", "750"])
    }

    @Test("Jw_cad writes the angle of a vertical text as 5156.62, and the dimension is still found")
    func jwcadRotation() throws {
        var records = Rebuild.chain(scale: 80, lengths: [20, 30], layer: "14")
        records += [
            Rebuild.line((0, 100), (0, 120), layer: "14"),
            Rebuild.line((0, 120), (0, 150), layer: "14"),
            Rebuild.line((-2, 100), (8, 100), layer: "14"),
            Rebuild.line((-2, 120), (8, 120), layer: "14"),
            Rebuild.line((-2, 150), (8, 150), layer: "14"),
            Rebuild.point(0, 100, layer: "14"), Rebuild.point(0, 120, layer: "14"),
            Rebuild.point(0, 150, layer: "14"),
            Rebuild.text("1600", 1.0, 107.0, rotation: 5156.6203, layer: "14"),
            Rebuild.text("2400", 1.0, 131.0, rotation: 5156.6203, layer: "14"),
        ]
        let (_, result) = try Rebuild.rebuild(records)
        #expect(result.dimensions.count == 4 && result.warnings.isEmpty)
        #expect(result.scales == [.init(group: "14", scale: 80, supporting: 4, contradicting: 0)])
        let vertical = result.dimensions.filter { $0.rotation == 90 }
        #expect(vertical.map(\.textOverride) == ["1600", "2400"])
    }
}
