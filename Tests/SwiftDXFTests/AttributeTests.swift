import Foundation
import Testing

@testable import SwiftDXF

extension DXFBuilder {
    /// An `ATTRIB` as AutoCAD writes it from R13 on, with its subclass markers.
    static func attrib(
        _ tag: String, _ value: String, at p: (Double, Double), height: Double = 2.5,
        rotation: Double = 0, layer: String = "0", handle: String? = nil, flags: Int = 0,
        normal: (Double, Double, Double) = (0, 0, 1)
    ) -> Record {
        var r: Record = [(0, "ATTRIB")]
        if let handle { r.append((5, handle)) }
        r += [
            (100, "AcDbEntity"), (8, layer), (100, "AcDbText"), (10, "\(p.0)"), (20, "\(p.1)"),
            (30, "0.0"), (40, "\(height)"), (1, value), (50, "\(rotation)"), (71, "4"),
            (72, "0"), (210, "\(normal.0)"), (220, "\(normal.1)"), (230, "\(normal.2)"),
            (100, "AcDbAttribute"),
            (280, "0"), (2, tag), (70, "\(flags)"),
        ]
        return r
    }

    /// An `ATTDEF` as AutoCAD writes it from R13 on.
    static func attdef(
        _ tag: String, prompt: String, value: String, at p: (Double, Double), height: Double = 2.5,
        layer: String = "0", handle: String? = nil, flags: Int = 0
    ) -> Record {
        var r: Record = [(0, "ATTDEF")]
        if let handle { r.append((5, handle)) }
        r += [
            (100, "AcDbEntity"), (8, layer), (100, "AcDbText"), (10, "\(p.0)"), (20, "\(p.1)"),
            (30, "0.0"), (40, "\(height)"), (1, value), (71, "4"), (100, "AcDbAttributeDefinition"),
            (280, "0"), (3, prompt), (2, tag), (70, "\(flags)"),
        ]
        return r
    }

    /// An `INSERT` that its `attributes` follow, and the `SEQEND` after them.
    static func insert(
        _ name: String, at p: (Double, Double), attributes: [Record],
        scale: (Double, Double) = (1, 1),
        rotation: Double = 0, layer: String = "0", handle: String? = nil, seqend: Bool = true,
        array: (columns: Int, rows: Int, dx: Double, dy: Double)? = nil
    ) -> [Record] {
        var head = insert(
            name, at: p, scale: scale, rotation: rotation, layer: layer, handle: handle,
            array: array)
        head.append((66, "1"))
        return [head] + attributes + (seqend ? [[(0, "SEQEND")]] : [])
    }
}

@Suite("Attributes")
struct AttributeTests {
    typealias B = DXFBuilder

    static func read(_ builder: DXFBuilder, options: DXF.ReadOptions = .init()) throws
        -> DXF.Drawing
    {
        try DXF.read(text: builder.text(), options: options)
    }

    static func close(_ p: DXF.Point, _ x: Double, _ y: Double) -> Bool {
        abs(p.x - x) < 1e-9 && abs(p.y - y) < 1e-9
    }

    static func fixture(_ name: String, options: DXF.ReadOptions = .init()) throws -> DXF.Drawing {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "dxf", subdirectory: "Fixtures"))
        return try DXF.read(contentsOf: url, options: options)
    }

    /// A title block of two attribute definitions, filled in by the reference `A1`.
    static func titleBlock() -> DXFBuilder {
        var b = DXFBuilder()
        b.blocks = [
            (
                "TITLE", (0, 0),
                [
                    B.line((0, 0), (10, 0)),
                    B.attdef("DWG_NO", prompt: "Number", value: "NO", at: (1, 1), handle: "D1"),
                ]
            )
        ]
        return b
    }

    // MARK: reading

    @Test("a reference carries its attributes in file order, with handles and positions")
    func readsAttributes() throws {
        var b = Self.titleBlock()
        b.entities += B.insert(
            "TITLE", at: (100, 50),
            attributes: [
                B.attrib(
                    "DWG_NO", "D-1234", at: (101, 51), height: 5, rotation: 90, layer: "TEXT",
                    handle: "A2"),
                B.attrib("SCALE", "1:2", at: (102, 52), handle: "A3", flags: 1),
            ], handle: "A1")
        b.entities.append(B.line((0, 0), (1, 1), handle: "A5"))
        let d = try Self.read(b)

        let reference = try #require(d.references.first)
        #expect(d.references.count == 1 && reference.name == "TITLE")
        #expect(reference.attributes.map(\.tag) == ["DWG_NO", "SCALE"])
        #expect(reference.attributes.map(\.value) == ["D-1234", "1:2"])
        #expect(reference.attributes.map(\.identity.handle) == ["A2", "A3"])
        let first = reference.attributes[0]
        #expect(Self.close(first.position, 101, 51))
        #expect(first.height == 5 && first.rotation == 90 && first.layer == "TEXT")
        #expect(!first.isMultiline && !first.isInvisible)
        #expect(reference.attributes[1].flags == .invisible && reference.attributes[1].isInvisible)

        // The INSERT is still the only thing skipped, and the SEQEND is neither.
        #expect(d.skipped == ["INSERT": 1])
        #expect(d.skippedByLayer["ATTRIB"] == nil)
        #expect(d.entities.count == 1)
    }

    @Test("the records after an INSERT keep their positions, the attributes among them")
    func locatorsKeepCounting() throws {
        var b = Self.titleBlock()
        b.entities += B.insert(
            "TITLE", at: (0, 0),
            attributes: [
                B.attrib("A", "1", at: (0, 0)), B.attrib("B", "2", at: (0, 0)),
            ])
        b.entities.append(B.line((0, 0), (1, 1)))
        let d = try Self.read(b)
        // INSERT is 0, its attributes 1 and 2, the line 3: as when each was a skipped record.
        #expect(d.references[0].identity.locator == "ENTITIES:0")
        #expect(d.references[0].attributes.map(\.identity.locator) == ["ENTITIES:1", "ENTITIES:2"])
        #expect(d.identities.map(\.locator) == ["ENTITIES:3"])
    }

    @Test("an attribute is read without its SEQEND, and a stray one stays skipped")
    func missingSeqendAndStrayAttribute() throws {
        var b = Self.titleBlock()
        b.entities += B.insert(
            "TITLE", at: (0, 0), attributes: [B.attrib("A", "1", at: (0, 0))], seqend: false)
        b.entities.append(B.line((0, 0), (1, 1)))
        // No group 66, so the ATTRIB does not belong to the INSERT.
        b.entities.append(B.insert("TITLE", at: (5, 5)))
        b.entities.append(B.attrib("STRAY", "x", at: (0, 0)))
        let d = try Self.read(b)
        #expect(d.references.map { $0.attributes.map(\.tag) } == [["A"], []])
        #expect(d.entities.count == 1)
        #expect(d.skipped == ["INSERT": 2, "ATTRIB": 1])
    }

    @Test("an INSERT that says attributes follow but has none")
    func noAttributes() throws {
        var b = Self.titleBlock()
        b.entities += B.insert("TITLE", at: (0, 0), attributes: [])
        let d = try Self.read(b)
        #expect(d.references[0].attributes.isEmpty)
        #expect(d.skipped == ["INSERT": 1])
    }

    @Test("an R12 attribute has no subclass markers")
    func legacyRecord() throws {
        var b = Self.titleBlock()
        b.version = "AC1009"
        let legacy: DXFBuilder.Record = [
            (0, "ATTRIB"), (5, "L1"), (8, "TXT"), (10, "3"), (20, "4"), (30, "0"), (40, "2"),
            (1, "R12 value"), (2, "TAG"), (70, "2"), (74, "3"),
        ]
        b.entities += B.insert("TITLE", at: (0, 0), attributes: [legacy])
        let d = try Self.read(b)
        let attribute = try #require(d.references.first?.attributes.first)
        #expect(attribute.tag == "TAG" && attribute.value == "R12 value")
        #expect(Self.close(attribute.position, 3, 4) && attribute.height == 2)
        #expect(attribute.layer == "TXT" && attribute.flags == .constant)
    }

    @Test("a reference inside a block carries its attributes too")
    func nestedReference() throws {
        var b = Self.titleBlock()
        b.blocks.append(
            (
                "SHEET", (0, 0),
                B.insert(
                    "TITLE", at: (10, 10), attributes: [B.attrib("DWG_NO", "S-7", at: (15, 40))],
                    handle: "N1")
            ))
        let d = try Self.read(b)
        let sheet = try #require(d.blocks.first { $0.name == "SHEET" })
        #expect(sheet.references.count == 1)
        #expect(sheet.references[0].attributes.map(\.value) == ["S-7"])
        #expect(sheet.skippedByLayer.isEmpty)
    }

    @Test("a block lists its attribute definitions")
    func readsDefinitions() throws {
        var b = DXFBuilder()
        b.blocks = [
            (
                "TITLE", (0, 0),
                [
                    B.line((0, 0), (10, 0)),
                    B.attdef(
                        "DWG_NO", prompt: "Drawing number", value: "NO-0", at: (1, 2), height: 5,
                        layer: "TEXT", handle: "D1"),
                    B.attdef(
                        "COMPANY", prompt: "Company", value: "ACME", at: (1, 8), handle: "D2",
                        flags: 2 | 4),
                    B.attdef("SCALE", prompt: "", value: "1:1", at: (1, 9), flags: 1 | 8),
                ]
            )
        ]
        // A definition in model space is not a block's, so it stays skipped.
        b.entities = [B.attdef("LOOSE", prompt: "", value: "", at: (0, 0))]
        let d = try Self.read(b)
        let block = try #require(d.blocks.first { $0.name == "TITLE" })
        #expect(block.entities.count == 1)
        #expect(block.attributeDefinitions.map(\.tag) == ["DWG_NO", "COMPANY", "SCALE"])
        #expect(block.attributeDefinitions.map(\.prompt) == ["Drawing number", "Company", ""])
        #expect(block.attributeDefinitions.map(\.defaultValue) == ["NO-0", "ACME", "1:1"])
        #expect(block.attributeDefinitions.map(\.identity.handle) == ["D1", "D2", nil])
        let number = block.attributeDefinitions[0]
        #expect(Self.close(number.position, 1, 2) && number.height == 5)
        #expect(number.layer == "TEXT" && number.flags.isEmpty)
        let company = block.attributeDefinitions[1]
        #expect(company.flags == [.constant, .verify] && company.isConstant)
        #expect(block.attributeDefinitions[2].flags == [.invisible, .preset])
        #expect(
            block.attributeDefinitions[2].isInvisible && !block.attributeDefinitions[2].isConstant)
        #expect(block.skippedByLayer.isEmpty)
        #expect(d.skipped == ["ATTDEF": 1])
    }

    @Test("the codes in a value are decoded, `%%nnn` through the drawing's code page")
    func decodesText() throws {
        var b = Self.titleBlock()
        b.codePage = "ANSI_1251"
        b.entities += B.insert(
            "TITLE", at: (0, 0),
            attributes: [B.attrib("A", "45%%d %%c20 %%233 \\U+00B1", at: (0, 0))])
        let d = try Self.read(b)
        let attribute = try #require(d.references.first?.attributes.first)
        #expect(attribute.value == "45\u{B0} \u{2300}20 \u{439} \u{B1}")
        #expect(attribute.content.raw == "45%%d %%c20 %%233 \\U+00B1")
        #expect(attribute.content.syntax == .text)
    }

    @Test("an attribute on a -z plane is read in the world, one on a tilted plane is counted")
    func extrusion() throws {
        var b = Self.titleBlock()
        b.entities += B.insert(
            "TITLE", at: (0, 0),
            attributes: [
                B.attrib("A", "x", at: (3, 4), rotation: 30, normal: (0, 0, -1)),
                B.attrib("B", "y", at: (1, 1), normal: (1, 0, 0)),
            ])
        let d = try Self.read(b)
        let attributes = try #require(d.references.first?.attributes)
        #expect(Self.close(attributes[0].position, -3, 4))
        #expect(abs(attributes[0].rotation - 150) < 1e-9)
        #expect(Self.close(attributes[1].position, 1, 1))
        #expect(d.warnings.contains(.extrusionNotApplied(type: "ATTRIB", count: 1)))
    }

    @Test("a paper-space reference takes its attributes with it when those are left out")
    func paperSpace() throws {
        var b = Self.titleBlock()
        var paper = B.insert(
            "TITLE", at: (0, 0), attributes: [B.attrib("A", "1", at: (0, 0))], handle: "P1")
        paper[0].append((67, "1"))
        b.entities += paper
        b.entities.append(B.line((0, 0), (1, 1)))
        let kept = try Self.read(b)
        #expect(kept.references[0].attributes.count == 1)
        #expect(kept.paperSpace == ["INSERT": 1])

        let left = try Self.read(b, options: .init(skipPaperSpace: true))
        #expect(left.references.isEmpty && left.skipped.isEmpty)
        #expect(left.identities.map(\.locator) == ["ENTITIES:2"])
    }

    // MARK: ezdxf

    @Test("a title block written by ezdxf reads as ezdxf reads it")
    func matchesEzdxfR2000() throws {
        // `tools/attrib_fixtures.py` writes the file, and `attrib_oracle.py` reads it with ezdxf.
        let d = try Self.fixture("attributes")
        #expect(d.version == "AC1015")
        #expect(d.skipped == ["INSERT": 2])
        #expect(d.references.count == 2)

        let title = try #require(d.references.first { $0.name == "TITLE" })
        #expect(title.identity.handle == "3F")
        #expect(title.attributes.map(\.tag) == ["DWG_NO", "TITLE", "SCALE"])
        #expect(
            title.attributes.map(\.value) == ["D-1234 \u{B0}5", "Plate \u{2300}20 hole", "1:2"])
        #expect(title.attributes.map(\.identity.handle) == ["41", "42", "43"])
        #expect(title.attributes.map(\.height) == [5, 3.5, 2.5])
        #expect(title.attributes.map(\.layer) == ["TEXT", "TEXT", "0"])
        #expect(title.attributes.map(\.rotation) == [90, 90, 90])
        #expect(title.attributes.map(\.flags.rawValue) == [0, 0, 1])
        #expect(Self.close(title.attributes[0].position, 95, 105))
        #expect(Self.close(title.attributes[2].position, 112, 110))

        let block = try #require(d.blocks.first { $0.name == "TITLE" })
        #expect(block.attributeDefinitions.map(\.tag) == ["DWG_NO", "TITLE", "SCALE", "COMPANY"])
        #expect(
            block.attributeDefinitions.map(\.prompt) == [
                "Drawing number", "Title", "Scale", "Company",
            ])
        #expect(
            block.attributeDefinitions.map(\.defaultValue) == ["NO-0", "UNTITLED", "1:1", "ACME"])
        #expect(block.attributeDefinitions.map(\.identity.handle) == ["34", "35", "36", "37"])
        #expect(block.attributeDefinitions.map(\.flags.rawValue) == [0, 0, 1, 2])
        #expect(block.skippedByLayer.isEmpty)

        let sheet = try #require(d.blocks.first { $0.name == "SHEET" })
        #expect(sheet.references.first?.attributes.map(\.value) == ["S-7"])
        #expect(sheet.references.first?.identity.handle == "3C")
    }

    @Test("a multiline attribute of R2018 reads its embedded MTEXT, as ezdxf does")
    func matchesEzdxfMultiline() throws {
        let d = try Self.fixture("attributes_mtext")
        let attribute = try #require(d.references.first?.attributes.first)
        #expect(attribute.tag == "NOTE" && attribute.isMultiline)
        #expect(attribute.value == "Bore \u{2300} 20\nDepth 15 \u{B0}")
        #expect(attribute.content.syntax == .mtext)
        #expect(attribute.identity.handle == "36")
        #expect(Self.close(attribute.position, 12, 10) && attribute.height == 2.5)

        let definition = try #require(
            d.blocks.first { $0.name == "NOTE" }?.attributeDefinitions.first)
        #expect(definition.isMultiline && definition.defaultValue == "First line\nSecond line")
        #expect(definition.prompt == "Note" && definition.identity.handle == "33")
    }

}
