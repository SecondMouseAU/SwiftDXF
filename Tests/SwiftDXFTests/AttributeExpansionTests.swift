import Foundation
import Testing

@testable import SwiftDXF

@Suite("Attribute expansion")
struct AttributeExpansionTests {
    typealias B = DXFBuilder

    /// The insertion points of the text entities of `d`.
    static func texts(_ d: DXF.Drawing) -> [DXF.Point] {
        d.entities.compactMap { entity in
            if case .text(let p, _, _, _, _, _) = entity { return p }
            return nil
        }
    }

    /// `builder` read with its blocks expanded, and its attributes too unless `attributes` is off.
    static func expanded(_ builder: DXFBuilder, attributes: Bool = true) throws -> DXF.Drawing {
        try AttributeTests.read(
            builder, options: .init(expandBlocks: true, expandAttributes: attributes))
    }

    @Test("attributes stay on the reference unless asked for")
    func notExpandedByDefault() throws {
        var b = AttributeTests.titleBlock()
        b.entities += B.insert(
            "TITLE", at: (10, 0), attributes: [B.attrib("DWG_NO", "D-1", at: (11, 1))])
        let d = try Self.expanded(b, attributes: false)
        #expect(d.entities.count == 1)  // the block's line
        #expect(d.counts.text == 0)
        #expect(d.references[0].attributes.count == 1)
    }

    @Test("visible attributes become text, whose identity names the reference")
    func expandsVisibleAttributes() throws {
        var b = AttributeTests.titleBlock()
        b.entities += B.insert(
            "TITLE", at: (10, 0),
            attributes: [
                B.attrib("DWG_NO", "D-1", at: (11, 1), height: 5, rotation: 10, handle: "A2"),
                B.attrib("SCALE", "1:2", at: (12, 1), handle: "A3", flags: 1),
                B.attrib("NOTE", "hello", at: (13, 1), layer: "TXT", handle: "A4"),
            ], rotation: 90, handle: "A1")
        let d = try Self.expanded(b)

        // The block's line, then the two visible attributes; the invisible one stays out.
        #expect(d.counts.text == 2 && d.entities.count == 3)
        guard case .text(let p, let h, let rotation, let string, let layer, _) = d.entities[1]
        else {
            Issue.record("expected a text")
            return
        }
        // Where the file drew it, not turned by the reference's own 90 degrees.
        #expect(AttributeTests.close(p, 11, 1) && h == 5 && abs(rotation - 10) < 1e-9)
        #expect(string == "D-1" && layer == "0")
        #expect(d.identities[1].handle == "A2" && d.identities[1].via == ["A1"])
        #expect(d.identities[1].blocks == ["TITLE"] && d.identities[1].id == "A1/A2")
        #expect(d.identities[2].id == "A1/A4")
        #expect(d.textContent(ofEntityAt: 1)?.plain == "D-1")
        #expect(d.references[0].attributes.count == 3)  // unchanged
        #expect(d.skipped.isEmpty)
    }

    @Test("a constant attribute comes through from the block, as the block's own entities do")
    func expandsConstantDefinitions() throws {
        var b = DXFBuilder()
        b.blocks = [
            (
                "TITLE", (1, 1),
                [
                    B.attdef(
                        "COMPANY", prompt: "", value: "ACME", at: (3, 2), height: 2, handle: "D1",
                        flags: 2),
                    B.attdef("HIDDEN", prompt: "", value: "no", at: (3, 3), flags: 2 | 1),
                    B.attdef("ASKED", prompt: "", value: "no", at: (3, 4)),
                ]
            )
        ]
        b.entities += B.insert("TITLE", at: (10, 10), attributes: [], scale: (2, 2), handle: "A1")
        let d = try Self.expanded(b)
        #expect(d.entities.count == 1)
        guard case .text(let p, let h, _, let string, _, _) = d.entities[0] else {
            Issue.record("expected a text")
            return
        }
        // (3, 2) minus the base point (1, 1), scaled by 2, plus the insertion point.
        #expect(AttributeTests.close(p, 14, 12) && abs(h - 4) < 1e-9 && string == "ACME")
        #expect(d.identities[0].id == "A1/D1")

        let off = try Self.expanded(b, attributes: false)
        #expect(off.entities.isEmpty)
    }

    @Test("a reference inside a block has its attributes carried by the block's placement only")
    func expandsNestedAttributes() throws {
        var b = AttributeTests.titleBlock()
        b.blocks.append(
            (
                "SHEET", (0, 0),
                B.insert(
                    "TITLE", at: (10, 0), attributes: [B.attrib("DWG_NO", "S-7", at: (15, 2))],
                    scale: (3, 3), rotation: 45, handle: "N1")
            ))
        b.entities = [B.insert("SHEET", at: (100, 0), rotation: 90, handle: "A1")]
        let d = try Self.expanded(b)
        let texts = d.entities.compactMap { entity -> (DXF.Point, Double, Double)? in
            guard case .text(let p, let h, let r, _, _, _) = entity else { return nil }
            return (p, h, r)
        }
        #expect(texts.count == 1)
        // (15, 2) in SHEET, turned 90 degrees about the origin and moved by (100, 0).
        #expect(AttributeTests.close(texts[0].0, 98, 15))
        #expect(abs(texts[0].1 - 2.5) < 1e-9 && abs(texts[0].2 - 90) < 1e-9)
        let index = try #require(
            d.entities.firstIndex { if case .text = $0 { true } else { false } })
        #expect(d.identities[index].via == ["A1", "N1"])
        #expect(d.identities[index].blocks == ["SHEET", "TITLE"])
    }

    @Test("an array moves its attributes to each instance")
    func expandsArrayedAttributes() throws {
        var b = AttributeTests.titleBlock()
        b.entities += B.insert(
            "TITLE", at: (0, 0), attributes: [B.attrib("A", "x", at: (1, 1), handle: "A2")],
            handle: "A1", array: (columns: 2, rows: 2, dx: 10, dy: 20))
        let d = try Self.expanded(b)
        let at = Self.texts(d)
        #expect(at.count == 4)
        #expect(
            Set(at.map { "\($0.x),\($0.y)" }) == ["1.0,1.0", "11.0,1.0", "1.0,21.0", "11.0,21.0"])
        #expect(d.identities.compactMap { $0.handle == "A2" ? $0.via.first : nil }.count == 4)
        #expect(Set(d.identities.map(\.id)).count == d.identities.count)
    }

    @Test("an array follows the reference's rotation, and the mirror of a -z plane")
    func expandsRotatedArrays() throws {
        var b = AttributeTests.titleBlock()
        // Rotated by 90 degrees, the columns run along +y and the rows along -x.
        b.entities += B.insert(
            "TITLE", at: (0, 0), attributes: [B.attrib("A", "x", at: (1, 1))], rotation: 90,
            array: (columns: 2, rows: 2, dx: 10, dy: 20))
        let rotated = Self.texts(try Self.expanded(b))
        #expect(
            Set(rotated.map { "\($0.x),\($0.y)" }) == [
                "1.0,1.0", "1.0,11.0", "-19.0,1.0", "-19.0,11.0",
            ])

        // On a -z plane the block's x axis is the world -x, so the columns run that way.
        var down = AttributeTests.titleBlock()
        var insert = B.insert(
            "TITLE", at: (0, 0), attributes: [B.attrib("A", "x", at: (-1, 1), normal: (0, 0, -1))],
            array: (columns: 2, rows: 1, dx: 10, dy: 0))
        insert[0] += [(210, "0"), (220, "0"), (230, "-1")]
        down.entities += insert
        let mirrored = Self.texts(try Self.expanded(down))
        #expect(Set(mirrored.map { "\($0.x),\($0.y)" }) == ["1.0,1.0", "-9.0,1.0"])
    }

    @Test("an attribute on layer 0 inside a block takes the enclosing reference's layer")
    func inheritsLayer() throws {
        var b = AttributeTests.titleBlock()
        // SHEET is drawn on PARTS, and holds a reference on INNER. The attribute is in SHEET's
        // space, not TITLE's, so it takes PARTS, not INNER.
        b.blocks.append(
            (
                "SHEET", (0, 0),
                B.insert(
                    "TITLE", at: (0, 0), attributes: [B.attrib("A", "x", at: (1, 1))],
                    layer: "INNER")
            ))
        b.entities = [B.insert("SHEET", at: (0, 0), layer: "PARTS")]
        b.entities += B.insert("TITLE", at: (0, 0), attributes: [B.attrib("A", "x", at: (1, 1))])
        let d = try Self.expanded(b)
        let texts = d.entities.filter { if case .text = $0 { true } else { false } }
        #expect(texts.map(\.layer) == ["PARTS", "0"])
    }

    @Test("a reference to a block the file does not define places no attributes")
    func missingBlock() throws {
        var b = AttributeTests.titleBlock()
        b.entities += B.insert("GONE", at: (0, 0), attributes: [B.attrib("A", "x", at: (1, 1))])
        let d = try Self.expanded(b)
        #expect(d.entities.isEmpty && d.skipped == ["INSERT": 1])
        #expect(d.references[0].attributes.count == 1)
        #expect(d.warnings.contains(.missingBlock(name: "GONE", count: 1)))
    }

    @Test("expanding attributes counts against the limit")
    func countsAgainstLimit() throws {
        var b = AttributeTests.titleBlock()
        b.entities += B.insert(
            "TITLE", at: (0, 0), attributes: (0..<20).map { B.attrib("A\($0)", "x", at: (0, 0)) },
            array: (columns: 100, rows: 100, dx: 1, dy: 1))
        var d = try AttributeTests.read(b)
        d.expandBlockReferences(limit: 500, attributes: true)
        #expect(d.entities.count < 1_000)
        #expect(d.warnings.contains(.expansionTruncated(limit: 500)))
    }

    @Test("every attribute of the ezdxf fixture expands, the invisible one aside")
    func expandsEzdxfFixture() throws {
        let d = try AttributeTests.fixture(
            "attributes", options: .init(expandBlocks: true, expandAttributes: true))
        let texts = d.entities.compactMap { entity -> String? in
            if case .text(_, _, _, let string, _, _) = entity { return string }
            return nil
        }
        // TITLE: two visible attributes and the constant COMPANY; SHEET holds one reference to
        // TITLE, whose block adds its own constant COMPANY.
        #expect(texts.filter { $0.hasPrefix("D-1234") }.count == 1)
        #expect(texts.contains("S-7") && !texts.contains("1:2"))
        #expect(texts.filter { $0 == "ACME" }.count == 2)
    }
}
