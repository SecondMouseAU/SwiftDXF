import Foundation
import Testing

@testable import SwiftDXF

/// The elevation (group 38) of a SOLID written by R11 and earlier.
///
/// The reference values come from `ezdxf` reading `Fixtures/solid_r12.dxf` and
/// `Fixtures/solid_r2000_elevation.dxf` (`tools/solid_fixtures.py`) after `upright`. `ezdxf` gives
/// the elevation to every corner whose z is 0, in a file of R12 or earlier, and ignores it in a
/// later one (`Solid.load_dxf_attribs`, `elevation_to_z_axis`).
@Suite("SOLID elevation")
struct SolidElevationTests {

    static func solids(_ name: String) throws -> [DXF.Solid] {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "dxf", subdirectory: "Fixtures"))
        return SolidTests.solids(try DXF.read(contentsOf: url))
    }

    /// A flat triangle with elevation 2.5 and no z, in a file that names `version`.
    static func triangleZs(version: String?) throws -> [Double] {
        let record = RawDXF.record(
            "SOLID", (8, "0"), (10, "0"), (20, "0"), (11, "1"), (21, "0"), (12, "0"), (22, "1"),
            (38, "2.5"))
        var sections = [RawDXF.section("ENTITIES", [record])]
        if let version {
            sections.insert(
                RawDXF.section("HEADER", ["9\n$ACADVER\n1\n\(version)"]), at: 0)
        }
        let solid = try #require(
            SolidTests.solids(try DXF.read(text: RawDXF.file(sections))).first)
        return solid.corners.map(\.z)
    }

    @Test("an R12 SOLID with an elevation and no z has it as the z of every corner")
    func flatSolid() throws {
        let solids = try Self.solids("solid_r12")
        #expect(solids.count == 7)
        // ezdxf: (0, 0, 3.5), (4, 0, 3.5), (4, 2, 3.5), (0, 2, 3.5).
        #expect(
            solids[0].corners
                == SolidTests.points([[0, 0, 3.5], [4, 0, 3.5], [4, 2, 3.5], [0, 2, 3.5]]))
    }

    @Test("corners that carry their own z keep it, and the elevation is not added")
    func ownZ() throws {
        let solids = try Self.solids("solid_r12")
        #expect(solids[1].corners.allSatisfy { $0.z == 5 })
        // Per corner, as ezdxf does it: 4, 7, 4, 7 in outline order.
        #expect(solids[6].corners.map(\.z) == [4, 7, 4, 7])
    }

    @Test("a triangle takes the elevation, and a SOLID without one keeps z 0")
    func triangleAndNone() throws {
        let solids = try Self.solids("solid_r12")
        #expect(solids[2].isTriangle)
        #expect(
            solids[2].corners == SolidTests.points([[10, 0, 1.5], [14, 0, 1.5], [12, 3, 1.5]]))
        #expect(solids[3].corners.allSatisfy { $0.z == 0 })
        #expect(solids[4].corners.allSatisfy { $0.z == 0 })
    }

    @Test("the elevation is in the object coordinate system, so a -z plane flips it")
    func flipped() throws {
        let corners = try Self.solids("solid_r12")[5].corners
        // ezdxf after upright: (-1, 1, -2.5), (-3, 1, -2.5), (-3, 2, -2.5), (-1, 2, -2.5).
        SolidTests.expectEqual(
            corners,
            SolidTests.points([[-1, 1, -2.5], [-3, 1, -2.5], [-3, 2, -2.5], [-1, 2, -2.5]]))
    }

    @Test("a file after R12 ignores the elevation, as ezdxf does")
    func later() throws {
        let solids = try Self.solids("solid_r2000_elevation")
        #expect(solids.count == 7)
        #expect(solids[0].corners.allSatisfy { $0.z == 0 })
        #expect(solids[2].corners.allSatisfy { $0.z == 0 })
        // The record with its own z on two corners: the other two stay at 0.
        #expect(solids[6].corners.map(\.z) == [4, 0, 4, 0])
        #expect(solids[1].corners.allSatisfy { $0.z == 5 })
    }

    @Test("a file with no version is read as R12, as ezdxf reads it")
    func noVersion() throws {
        #expect(try Self.triangleZs(version: nil) == [2.5, 2.5, 2.5])
    }

    @Test("every version up to AC1009 takes the elevation, and AC1012 and later do not")
    func versions() throws {
        #expect(try Self.triangleZs(version: "AC1006") == [2.5, 2.5, 2.5])
        #expect(try Self.triangleZs(version: "AC1009") == [2.5, 2.5, 2.5])
        #expect(try Self.triangleZs(version: "AC2.10") == [2.5, 2.5, 2.5])
        #expect(try Self.triangleZs(version: "AC2.22") == [2.5, 2.5, 2.5])
        #expect(try Self.triangleZs(version: "AC1.50") == [2.5, 2.5, 2.5])
        #expect(try Self.triangleZs(version: "AC1012") == [0, 0, 0])
        #expect(try Self.triangleZs(version: "AC1032") == [0, 0, 0])
    }

    @Test("a 3DFACE is not given an elevation")
    func faceUnchanged() throws {
        let record = RawDXF.record(
            "3DFACE", (8, "0"), (10, "0"), (20, "0"), (11, "1"), (21, "0"), (12, "0"), (22, "1"),
            (38, "2.5"))
        let face = try #require(SolidTests.faces(try SolidTests.read([record])).first)
        #expect(face.corners.allSatisfy { $0.z == 0 })
    }
}
