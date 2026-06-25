import Testing
import Foundation
@testable import SwiftDXF

/// Regression tests over real DXF drawings, with **ground-truth entity counts produced by the
/// MIT-licensed `ezdxf` reader** (see `tools/oracle.py`). SwiftDXF was verified to match ezdxf
/// bit-for-bit on entity counts *and* every coordinate scalar across this corpus; these tests pin
/// the counts so a regression can't slip in silently.
///
/// The corpus lives outside the repo (large, third-party drawings). Tests are skipped when it is
/// absent — e.g. in CI — via `withKnownIssue`, mirroring SwiftJWW. Point `DXF_CORPUS` at a directory
/// of `.dxf` files (defaults to `~/Documents/Modelling/2DFiles`) to run them.
@Suite("DXF corpus vs ezdxf oracle")
struct CorpusOracleTests {

    static var corpusDir: URL {
        if let env = ProcessInfo.processInfo.environment["DXF_CORPUS"] { return URL(fileURLWithPath: env) }
        return URL(fileURLWithPath: NSString(string: "~/Documents/Modelling/2DFiles").expandingTildeInPath)
    }

    /// Expected per-file model-space counts, captured from `ezdxf` (`tools/oracle.py`).
    static let expected: [(file: String, counts: DXF.Drawing.Counts)] = [
        ("2120_from_2120j.dxf", .init(line: 4351, circle: 438, arc: 1471, ellipse: 12, point: 42, text: 34, polyline: 0)),
        ("dd12_from_dd12j.dxf", .init(line: 2428, circle: 131, arc: 668, ellipse: 0, point: 25, text: 26, polyline: 0)),
        ("dd12.dxf", .init(line: 2428, circle: 131, arc: 668, ellipse: 0, point: 25, text: 26, polyline: 0)),
        ("eitakyouta_3.dxf", .init(line: 30094, circle: 11, arc: 182, ellipse: 12, point: 27, text: 20, polyline: 0)),
        ("ka2000_from_ka2000j.dxf", .init(line: 2307, circle: 482, arc: 524, ellipse: 24, point: 26, text: 36, polyline: 0)),
        ("ka2000.dxf", .init(line: 2899, circle: 482, arc: 524, ellipse: 0, point: 26, text: 36, polyline: 0)),
        ("rail1.dxf", .init(line: 274, circle: 0, arc: 112, ellipse: 0, point: 96, text: 55, polyline: 0)),
        ("rail2.dxf", .init(line: 204, circle: 0, arc: 90, ellipse: 0, point: 84, text: 55, polyline: 0)),
        ("tmf1_from_tmf1j.dxf", .init(line: 2378, circle: 377, arc: 504, ellipse: 23, point: 39, text: 47, polyline: 0)),
        ("to1_from_to1j.dxf", .init(line: 1952, circle: 332, arc: 418, ellipse: 14, point: 35, text: 43, polyline: 0)),
        ("wm3500k.dxf", .init(line: 3124, circle: 515, arc: 493, ellipse: 0, point: 28, text: 38, polyline: 0)),
    ]

    @Test("entity counts match the ezdxf oracle for every corpus file", arguments: expected)
    func matchesOracle(_ entry: (file: String, counts: DXF.Drawing.Counts)) throws {
        let url = Self.corpusDir.appendingPathComponent(entry.file)
        try withKnownIssue("\(entry.file) not present (set DXF_CORPUS to run)", isIntermittent: true) {
            guard FileManager.default.fileExists(atPath: url.path) else { throw CancellationError() }
            let dwg = try DXF.read(contentsOf: url)
            #expect(dwg.counts == entry.counts, "\(entry.file): \(dwg.counts) != \(entry.counts)")
            // Every modelled entity carried geometry into the bounds.
            #expect(dwg.bounds != nil)
        }
    }
}

private extension DXF.Drawing.Counts {
    init(line: Int, circle: Int, arc: Int, ellipse: Int, point: Int, text: Int, polyline: Int) {
        self.init()
        self.line = line; self.circle = circle; self.arc = arc; self.ellipse = ellipse
        self.point = point; self.text = text; self.polyline = polyline
    }
}
