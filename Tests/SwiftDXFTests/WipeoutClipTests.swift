import Foundation
import Testing

@testable import SwiftDXF

/// The clip state, clip type and clip mode of a WIPEOUT.
///
/// The reference values come from `ezdxf` reading `Fixtures/wipeout_clip.dxf`
/// (`tools/solid_fixtures.py`): `boundary_path_wcs()`, and `clipping` (group 280),
/// `clipping_boundary_type` (71) and `clip_mode` (290), which `ezdxf` keeps without acting on.
@Suite("WIPEOUT clip")
struct WipeoutClipTests {

    static func fixture(_ name: String = "wipeout_clip") throws -> [DXF.Wipeout] {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "dxf", subdirectory: "Fixtures"))
        return SolidTests.wipeouts(try DXF.read(contentsOf: url))
    }

    /// A WIPEOUT record of a 10 x 10 image with the given clip groups, in AutoCAD's order.
    static func record(
        state: Int? = 1, type: Int? = 2, mode: Int? = nil,
        clip: [(Double, Double)] = [(0, 0), (9, 0), (9, 9)]
    ) -> String {
        var tags: [(Int, String)] = [
            (8, "0"), (10, "0"), (20, "0"), (30, "0"), (11, "1"), (21, "0"), (31, "0"),
            (12, "0"), (22, "1"), (32, "0"), (13, "10"), (23, "10"),
        ]
        if let state { tags.append((280, "\(state)")) }
        if let type { tags.append((71, "\(type)")) }
        tags.append((91, "\(clip.count)"))
        for point in clip { tags += [(14, "\(point.0)"), (24, "\(point.1)")] }
        if let mode { tags.append((290, "\(mode)")) }
        return RawDXF.record("WIPEOUT", tags)
    }

    static func read(_ record: String) throws -> DXF.Wipeout {
        try #require(SolidTests.wipeouts(try SolidTests.read([record])).first)
    }

    // MARK: The fixture, against ezdxf

    @Test("the clip type, state and mode are those ezdxf reads, and the boundary is unchanged")
    func fixtureAgainstEzdxf() throws {
        let wipeouts = try Self.fixture()
        #expect(wipeouts.count == 6)
        // ezdxf: (clipping_boundary_type, clipping, clip_mode) of each, in file order.
        let expected: [(DXF.Wipeout.ClipType, Bool, Bool)] = [
            (.polygonal, true, false), (.polygonal, true, true), (.rectangular, true, true),
            (.rectangular, true, false), (.polygonal, false, false),
            (.rectangular, false, false),
        ]
        for (w, e) in zip(wipeouts, expected) {
            #expect(w.clipType == e.0 && w.isClipping == e.1 && w.isInverted == e.2)
        }
        // ezdxf: boundary_path_wcs() is the same whatever the mode, so an inverted polygon
        // is placed as a plain one is.
        let polygon: [[Double]] = [[0, 0, 0], [10, 0, 0], [10, 6, 0], [5, 9, 0], [0, 6, 0]]
        SolidTests.expectEqual(wipeouts[0].boundary, SolidTests.points(polygon))
        SolidTests.expectEqual(
            wipeouts[1].boundary, SolidTests.points(polygon.map { [$0[0] + 20, $0[1], $0[2]] }))
        SolidTests.expectEqual(
            wipeouts[2].boundary,
            SolidTests.points([[40, 0, 0], [48, 0, 0], [48, 6, 0], [40, 6, 0]]))
        // The rectangles, inverted or not, and the polygon with clipping off.
        SolidTests.expectEqual(
            wipeouts[3].boundary,
            SolidTests.points([[60, 0, 0], [68, 0, 0], [68, 6, 0], [60, 6, 0]]))
        SolidTests.expectEqual(
            wipeouts[4].boundary,
            SolidTests.points(polygon.map { [$0[0] + 80, $0[1], $0[2]] }))
        SolidTests.expectEqual(
            wipeouts[5].boundary,
            SolidTests.points([[100, 3, 0], [104, 3, 0], [104, 0, 0], [100, 0, 0]]))
    }

    @Test("a record with no clip vertices is its whole image, with clipping off, as in ezdxf")
    func noClipVertices() throws {
        let bare = try #require(try Self.fixture().last)
        // ezdxf: a 4 x 3 image at (100, 0); the clip is reset to the rectangle and clipping to 0.
        SolidTests.expectEqual(
            bare.boundary,
            SolidTests.points([[100, 3, 0], [104, 3, 0], [104, 0, 0], [100, 0, 0]]))
        #expect(bare.clipType == .rectangular && !bare.isClipping && !bare.isInverted)
    }

    // MARK: Records

    @Test("group 290 of 1 inverts the clip, and 0 or no group does not")
    func mode() throws {
        #expect(try Self.read(Self.record(mode: 1)).isInverted)
        #expect(!(try Self.read(Self.record(mode: 0)).isInverted))
        // A file before R2010 has no group 290.
        #expect(!(try Self.read(Self.record(mode: nil)).isInverted))
    }

    @Test("an inverted clip keeps its boundary where the file places it")
    func invertedBoundary() throws {
        let plain = try Self.read(Self.record(mode: 0))
        let inverted = try Self.read(Self.record(mode: 1))
        #expect(plain.boundary == inverted.boundary && inverted.boundary.count == 3)
    }

    @Test("group 71 of 2 with two vertices is polygonal in type and a rectangle in boundary")
    func polygonalTwoVertices() throws {
        let w = try Self.read(Self.record(type: 2, clip: [(-0.5, -0.5), (9.5, 9.5)]))
        #expect(w.clipType == .polygonal)
        SolidTests.expectEqual(
            w.boundary, SolidTests.points([[0, 10, 0], [10, 10, 0], [10, 0, 0], [0, 0, 0]]))
    }

    @Test("group 71 is read, and a value that is not 1 or 2 is judged by the vertices")
    func type() throws {
        #expect(try Self.read(Self.record(type: 2)).clipType == .polygonal)
        #expect(
            try Self.read(Self.record(type: 1, clip: [(-0.5, -0.5), (9.5, 9.5)])).clipType
                == .rectangular)
        // Two vertices are a rectangle and more are a polygon when the group is missing or wrong.
        #expect(try Self.read(Self.record(type: nil)).clipType == .polygonal)
        #expect(try Self.read(Self.record(type: 7)).clipType == .polygonal)
        #expect(
            try Self.read(Self.record(type: nil, clip: [(-0.5, -0.5), (9.5, 9.5)])).clipType
                == .rectangular)
        // The boundary goes by the vertices, as ezdxf's does, not by this group.
        let lying = try Self.read(Self.record(type: 1))
        #expect(lying.clipType == .rectangular && lying.boundary.count == 3)
    }

    @Test("a record with group 71 of 2 but no clip vertices is the rectangular whole image")
    func typeWithoutVertices() throws {
        let w = try Self.read(Self.record(type: 2, clip: []))
        #expect(w.clipType == .rectangular && w.boundary.count == 4 && !w.isClipping)
    }

    @Test("no clip vertices switch the clipping off even when group 280 says on, as in ezdxf")
    func stateOverridden() throws {
        let w = try Self.read(Self.record(state: 1, type: 2, clip: []))
        #expect(!w.isClipping && w.clipType == .rectangular)
    }

    @Test("a closing vertex is dropped when it is the first to within rounding, and not beyond it")
    func closingVertex() throws {
        let corner: [(Double, Double)] = [(1, 1), (8, 1), (8, 8)]
        // Equal, and a rounding away, at a small and a large coordinate: closed, three corners.
        #expect(try Self.read(Self.record(clip: corner + [(1, 1)])).boundary.count == 3)
        #expect(try Self.read(Self.record(clip: corner + [(1 + 1e-11, 1)])).boundary.count == 3)
        // At 100000 pixels `ezdxf` would take 5e-6 as closed (1e-9 of the coordinate is 1e-4); the
        // tolerance is capped at 1e-6 here, so it is a fourth vertex.
        let far: [(Double, Double)] = [(100_000, 100_000), (200_000, 100_000), (200_000, 200_000)]
        #expect(try Self.read(Self.record(clip: far + [(100_000, 100_000)])).boundary.count == 3)
        #expect(
            try Self.read(Self.record(clip: far + [(100_000.000005, 100_000)])).boundary.count == 4)
    }

    @Test("group 280 is the clipping state, and a missing one reads as off, as in ezdxf")
    func state() throws {
        #expect(try Self.read(Self.record(state: 1)).isClipping)
        #expect(!(try Self.read(Self.record(state: 0)).isClipping))
        #expect(!(try Self.read(Self.record(state: nil)).isClipping))
    }

    // MARK: Additive API

    @Test("the new fields are defaulted last, so an existing call compiles and reads as before")
    func defaults() {
        let w = DXF.Wipeout(boundary: [DXF.Point(0, 0, 0)], layer: "L", color: 3)
        #expect(w.clipType == .polygonal && w.isClipping && !w.isInverted)
        #expect(w.layer == "L" && w.color == 3)
    }

    @Test("a transform keeps the clip flags")
    func transformKeepsFlags() throws {
        let w = DXF.Wipeout(
            boundary: [DXF.Point(0, 0, 0), DXF.Point(1, 0, 0), DXF.Point(1, 1, 0)],
            clipType: .rectangular, isClipping: false, isInverted: true)
        let moved = try #require(DXF.Entity.wipeout(w).transformed(by: DXF.ObjectPlane.mirror))
        guard case .wipeout(let m) = moved else {
            Issue.record("not a wipeout")
            return
        }
        #expect(m.boundary == [DXF.Point(0, 0, 0), DXF.Point(-1, 0, 0), DXF.Point(-1, 1, 0)])
        #expect(m.clipType == .rectangular && !m.isClipping && m.isInverted)
    }

    // MARK: What consumes a WIPEOUT

    @Test("the contour layer ignores an inverted WIPEOUT exactly as it ignores a plain one")
    func contoursIgnoreInverted() throws {
        let plain = try SolidTests.read([Self.record(mode: 0)]).contours()
        let inverted = try SolidTests.read([Self.record(mode: 1)]).contours()
        let ignored = DXF.Contour.Warning.ignoredEntities(type: "WIPEOUT", count: 1)
        #expect(plain.warnings.contains(ignored))
        #expect(inverted.warnings == plain.warnings)
        #expect(inverted.shapes.isEmpty && inverted.openChains.isEmpty)
    }

    @Test("bounds take the boundary of an inverted WIPEOUT, as of a plain one")
    func boundsOfInverted() throws {
        let plain = try #require(try SolidTests.read([Self.record(mode: 0)]).bounds)
        let inverted = try #require(try SolidTests.read([Self.record(mode: 1)]).bounds)
        #expect(plain.min == inverted.min && plain.max == inverted.max)
        // The clip (0, 0), (9, 0), (9, 9) of a 10 x 10 image is the pixels' centres, 1/2 in.
        #expect(inverted.min == DXF.Point(0.5, 0.5, 0) && inverted.max == DXF.Point(9.5, 9.5, 0))
    }
}
