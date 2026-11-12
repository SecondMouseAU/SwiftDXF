import Foundation
import Testing

@testable import SwiftDXF

@Suite("Entity identity")
struct IdentityTests {

    static func entity(_ type: String, handle: String?, extra: [(Int, String)] = []) -> String {
        var pairs: [(Int, String)] = [(0, type)]
        if let handle { pairs.append((5, handle)) }
        pairs += [(8, "L")] + extra
        return pairs.map { "\($0.0)\n\($0.1)" }.joined(separator: "\n")
    }

    static let line: [(Int, String)] = [(10, "0"), (20, "0"), (11, "1"), (21, "1")]

    @Test("the handle is the identity, upper case")
    func handles() throws {
        let body = [
            Self.entity("LINE", handle: "2f", extra: Self.line),
            Self.entity("CIRCLE", handle: "30", extra: [(10, "0"), (20, "0"), (40, "1")]),
        ].joined(separator: "\n")
        let drawing = try DXF.read(text: SwiftDXFTests.doc(body))
        #expect(drawing.identities.count == drawing.entities.count)
        #expect(drawing.identities.map(\.handle) == ["2F", "30"])
        #expect(drawing.identities.map(\.id) == ["#2F", "#30"])
    }

    @Test("without a handle the position stands in, counting skipped records too")
    func positions() throws {
        let body = [
            Self.entity("LINE", handle: nil, extra: Self.line),
            Self.entity("HATCH", handle: nil),
            Self.entity("LINE", handle: nil, extra: Self.line),
        ].joined(separator: "\n")
        let drawing = try DXF.read(text: SwiftDXFTests.doc(body))
        #expect(drawing.entities.count == 2)
        #expect(drawing.identities.map(\.id) == ["ENTITIES[0]", "ENTITIES[2]"])
        #expect(drawing.skipped["HATCH"] == 1)
    }

    @Test("a POLYLINE takes the identity of its header, and its vertices do not shift the next")
    func polylineIdentity() throws {
        let body = [
            Self.entity("POLYLINE", handle: "A1", extra: [(70, "0")]),
            Self.entity("VERTEX", handle: "A2", extra: [(10, "0"), (20, "0")]),
            Self.entity("VERTEX", handle: "A3", extra: [(10, "1"), (20, "1")]),
            "0\nSEQEND\n5\nA4\n8\nL",
            Self.entity("LINE", handle: "B1", extra: Self.line),
        ].joined(separator: "\n")
        let drawing = try DXF.read(text: SwiftDXFTests.doc(body))
        #expect(drawing.identities.map(\.id) == ["#A1", "#B1"])
        #expect(drawing.identities[1].index == 1)
    }

    @Test("reading the same text twice gives the same identities")
    func repeatable() throws {
        let body = [
            Self.entity("LINE", handle: "2F", extra: Self.line),
            Self.entity("LINE", handle: nil, extra: Self.line),
        ].joined(separator: "\n")
        let text = SwiftDXFTests.doc(body)
        let first = try DXF.read(text: text).identities
        let second = try DXF.read(text: text).identities
        #expect(first == second)
    }

    @Test("a reference chain prefixes the entity's own identity")
    func viaChain() {
        let id = DXF.EntityIdentity(
            handle: "31", section: "BLOCKS:Title", index: 4, via: ["#8E", "#90"])
        #expect(id.id == "#8E/#90/#31")
        #expect(id.local == "#31")
    }
}
