import Foundation
import Testing

@testable import SwiftDXF

/// Entity, block and table-record identity.
///
/// The handles in `Fixtures/handles.dxf` are the ones `ezdxf` reads from the same file
/// (`tools/identity_fixtures.py`).
@Suite("Entity identity")
struct IdentityTests {

    static func fixture() throws -> DXF.Drawing {
        let url = try #require(
            Bundle.module.url(
                forResource: "handles", withExtension: "dxf", subdirectory: "Fixtures"))
        return try DXF.read(contentsOf: url)
    }

    @Test("entity handles match ezdxf")
    func entityHandlesMatchEzdxf() throws {
        let dwg = try Self.fixture()
        // ezdxf: LINE 36, INSERT 37 (not modelled), CIRCLE 39, LWPOLYLINE 3A, TEXT 3B.
        #expect(dwg.entities.count == 4)
        #expect(dwg.identities.map(\.handle) == ["36", "39", "3A", "3B"])
        #expect(dwg.identity(ofEntityAt: 1).handle == "39")
    }

    @Test("a skipped entity still takes a position in the locators")
    func locatorsCountSkippedRecords() throws {
        let dwg = try Self.fixture()
        #expect(dwg.skipped == ["INSERT": 1])
        #expect(
            dwg.identities.map(\.locator)
                == ["ENTITIES:0", "ENTITIES:2", "ENTITIES:3", "ENTITIES:4"])
    }

    @Test("block handles, base point and entity handles match ezdxf")
    func blocksMatchEzdxf() throws {
        let dwg = try Self.fixture()
        let part = try #require(dwg.blocks.first { $0.name == "PART" })
        #expect(part.handle == "32")
        #expect(part.basePoint == DXF.Point(1, 2, 0))
        #expect(part.entities.count == 2)
        #expect(part.identities.map(\.handle) == ["34", "35"])
        let index = try #require(dwg.blocks.firstIndex { $0.name == "PART" })
        #expect(part.identities.map(\.locator) == ["BLOCKS:\(index)/0", "BLOCKS:\(index)/1"])
        #expect(part.identity.locator == "BLOCKS:\(index)")
        // The built-in blocks are read too.
        #expect(dwg.blocks.contains { $0.name == "*Model_Space" })
    }

    @Test("layer, line type and dimension style records carry their handles")
    func tableRecordsMatchEzdxf() throws {
        let dwg = try Self.fixture()
        #expect(dwg.layers.first { $0.name == "OUTLINE" }?.handle == "2F")
        #expect(dwg.dimensionStyles.first { $0.name == "MYSTYLE" }?.handle == "30")
        #expect(!dwg.lineTypes.isEmpty)
        #expect(dwg.lineTypes.allSatisfy { $0.handle != nil })
        let outline = try #require(dwg.layers.first { $0.name == "OUTLINE" })
        #expect(outline.identity.locator.hasPrefix("TABLES:LAYER:"))
    }

    @Test("reading the same file twice gives the same identities")
    func readingTwiceIsStable() throws {
        let a = try Self.fixture()
        let b = try Self.fixture()
        #expect(a.identities == b.identities)
        #expect(a.blocks.map(\.identity) == b.blocks.map(\.identity))
        #expect(a.layers.map(\.identity) == b.layers.map(\.identity))
    }

    @Test("a file without handles names each entity by section and position")
    func fileWithoutHandles() throws {
        let text = RawDXF.entities([
            RawDXF.line(), RawDXF.record("SOLID", (8, "0")), RawDXF.line(layer: "B"),
        ])
        let dwg = try DXF.read(text: text)
        #expect(dwg.entities.count == 2)
        #expect(dwg.identities.map(\.handle) == [nil, nil])
        #expect(dwg.identities.map(\.id) == ["ENTITIES:0", "ENTITIES:2"])
        // Reading again gives the same names.
        #expect(try DXF.read(text: text).identities == dwg.identities)
    }

    @Test("a handle is kept as the file writes it, trimmed")
    func handleKeptAsWritten() throws {
        let text = RawDXF.entities([RawDXF.line(handle: " a1f "), RawDXF.line(handle: "")])
        let dwg = try DXF.read(text: text)
        #expect(dwg.identities.map(\.handle) == ["a1f", nil])
        #expect(dwg.identities.map(\.id) == ["a1f", "ENTITIES:1"])
    }

    @Test("an old-style POLYLINE takes one position and its handle, not its vertices'")
    func polylineIsOneRecord() throws {
        let vertex: (String, String) -> String = { handle, x in
            RawDXF.record("VERTEX", (5, handle), (10, x), (20, "0.0"))
        }
        let text = RawDXF.entities([
            RawDXF.record("POLYLINE", (5, "A0"), (70, "0")),
            vertex("A1", "0.0"), vertex("A2", "5.0"),
            RawDXF.record("SEQEND", (5, "A3")),
            RawDXF.line(handle: "A4"),
        ])
        let dwg = try DXF.read(text: text)
        #expect(dwg.entities.count == 2)
        #expect(dwg.identities.map(\.id) == ["A0", "A4"])
        #expect(dwg.identities.map(\.locator) == ["ENTITIES:0", "ENTITIES:1"])
    }

    @Test("a dimension style keeps its handle in group 105")
    func dimensionStyleHandle() throws {
        let tables = RawDXF.section(
            "TABLES",
            [
                RawDXF.table(
                    "DIMSTYLE",
                    [
                        RawDXF.record("DIMSTYLE", (105, "2A"), (2, "ISO-25")),
                        RawDXF.record("DIMSTYLE", (2, "NOHANDLE")),
                    ]),
                RawDXF.table(
                    "LAYER",
                    [RawDXF.record("LAYER", (5, "10"), (2, "WALLS"), (70, "0"))]),
            ])
        let dwg = try DXF.read(text: RawDXF.file([tables, RawDXF.section("ENTITIES", [])]))
        #expect(dwg.dimensionStyles.map(\.name) == ["ISO-25", "NOHANDLE"])
        #expect(dwg.dimensionStyles.map(\.handle) == ["2A", nil])
        #expect(dwg.dimensionStyles[1].identity.id == "TABLES:DIMSTYLE:1")
        #expect(dwg.layers.map(\.handle) == ["10"])
    }

    @Test("blocks keep their entities apart from model space, and nest no counts into it")
    func blockEntitiesAreSeparate() throws {
        let blocks = RawDXF.section(
            "BLOCKS",
            [
                RawDXF.record("BLOCK", (5, "B1"), (2, "SYM"), (10, "3.0"), (20, "4.0")),
                RawDXF.line(handle: "B2"),
                RawDXF.record("INSERT", (5, "B3"), (2, "OTHER")),
                RawDXF.line(handle: "B4"),
                RawDXF.record("ENDBLK", (5, "B5")),
                RawDXF.record("BLOCK", (2, "EMPTY")),
                RawDXF.record("ENDBLK"),
            ])
        let dwg = try DXF.read(
            text: RawDXF.file([blocks, RawDXF.section("ENTITIES", [RawDXF.line(handle: "E1")])]))
        #expect(dwg.entities.count == 1 && dwg.counts.total == 1)
        #expect(dwg.skipped.isEmpty)
        #expect(dwg.blocks.map(\.name) == ["SYM", "EMPTY"])
        let sym = dwg.blocks[0]
        #expect(sym.handle == "B1" && sym.basePoint == DXF.Point(3, 4, 0))
        #expect(sym.identities.map(\.id) == ["B2", "B4"])
        #expect(sym.identities.map(\.locator) == ["BLOCKS:0/0", "BLOCKS:0/2"])
        #expect(dwg.blocks[1].entities.isEmpty && dwg.blocks[1].handle == nil)
    }

    @Test("a drawing built by hand falls back to the entity's position")
    func handBuiltDrawing() {
        let dwg = DXF.Drawing(entities: [
            .point(at: .init(0, 0), layer: "0", color: 256),
            .point(at: .init(1, 1), layer: "0", color: 256),
        ])
        #expect(dwg.identity(ofEntityAt: 1) == DXF.Identity(locator: "ENTITIES:1"))
        #expect(dwg.identity(ofEntityAt: 1).id == "ENTITIES:1")
    }
}
