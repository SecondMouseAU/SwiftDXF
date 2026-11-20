import Foundation

extension DXF.Reader {
    /// The `ATTRIB` records that follow the `INSERT` before `index` (one with group 66 set), and
    /// the `SEQEND` that closes them.
    ///
    /// `index` is the first pair after the `INSERT`, and moves to the one after the `SEQEND`. A
    /// record of any other type ends the run where it stands. The records are named by their
    /// own positions, which start at `firstPosition`; `tilted` counts the ones written on a plane
    /// that is not horizontal.
    func attributes(
        after index: inout Int, firstPosition: Int, locator: (Int) -> String,
        tilted: inout [String: Int]
    ) -> [DXF.Attribute] {
        var out: [DXF.Attribute] = []
        while index < pairs.count, pairs[index].code == 0 {
            let type = trimmed(pairs[index].value)
            guard type == "ATTRIB" else {
                if type == "SEQEND" { index = recordFields(after: index).end }
                break
            }
            let (fields, end) = recordFields(after: index)
            let identity = DXF.Identity(
                handle: handle(fields), locator: locator(firstPosition + out.count))
            let (value, isTilted) = attribute(fields, identity: identity)
            if isTilted { tilted["ATTRIB", default: 0] += 1 }
            out.append(value)
            index = end
        }
        return out
    }

    /// An `ATTRIB` from its fields, and whether it is written on a tilted plane.
    func attribute(_ f: Fields, identity: DXF.Identity) -> (DXF.Attribute, tilted: Bool) {
        let (attribute, _, tilted) = attributeRecord(
            f, subclass: "AcDbAttribute", identity: identity)
        return (attribute, tilted)
    }

    /// An `ATTDEF` from its fields, and whether it is written on a tilted plane.
    func attributeDefinition(_ f: Fields, identity: DXF.Identity) -> (
        DXF.AttributeDefinition, tilted: Bool
    ) {
        let (attribute, prompt, tilted) = attributeRecord(
            f, subclass: "AcDbAttributeDefinition", identity: identity)
        return (DXF.AttributeDefinition(attribute, prompt: prompt), tilted)
    }

    /// The pairs of the subclass `name` of a record: those after its group-100 marker up to the
    /// next marker, or `nil` for a record without it (R12 has no markers).
    private func subclass(_ name: String, in f: Fields) -> Fields? {
        guard let start = f.firstIndex(where: { $0.code == 100 && trimmed($0.value) == name })
        else { return nil }
        let after = f.index(after: start)
        let end = f[after...].firstIndex { $0.code == 100 || $0.code == 101 } ?? f.endIndex
        return Array(f[after..<end])
    }

    /// An `ATTRIB` or `ATTDEF` from its fields, as an attribute, the prompt and whether it is tilted.
    ///
    /// Both are a `TEXT` (the `AcDbText` subclass: position, height, rotation, extrusion, value)
    /// plus the subclass `name`, which holds the tag, the flags and the prompt of a definition.
    ///
    /// R2018 writes a multiline attribute with its `MTEXT` after a group 101, where groups 1, 3,
    /// 10 and 40 mean the `MTEXT`'s; the value is then that text.
    private func attributeRecord(_ f: Fields, subclass name: String, identity: DXF.Identity)
        -> (attribute: DXF.Attribute, prompt: String, tilted: Bool)
    {
        let marker = f.firstIndex { $0.code == 101 }
        let core = marker.map { Array(f[..<$0]) } ?? f
        let embedded = marker.map { Array(f[f.index(after: $0)...]) } ?? []
        let text = subclass("AcDbText", in: core) ?? core
        let own = subclass(name, in: core) ?? core

        let isMultiline = !embedded.isEmpty
        let content =
            (isMultiline ? textContent(type: "MTEXT", embedded) : textContent(type: "TEXT", text))
            ?? DXF.TextContent("", syntax: .text, codePage: codePage)
        var attribute = DXF.Attribute(
            tag: trimmed(first(2, own) ?? ""), content: content, position: point(text),
            height: dbl(40, text), rotation: dbl(50, text), layer: layer(core), color: color(core),
            flags: DXF.AttributeFlags(rawValue: ints(70, own) ?? 0), isMultiline: isMultiline,
            identity: identity)
        let plane = objectPlane(text)
        if plane == .down { attribute = attribute.transformed(by: DXF.ObjectPlane.mirror) }
        return (attribute, first(3, own) ?? "", plane == .tilted)
    }
}
