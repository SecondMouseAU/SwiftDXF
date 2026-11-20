import Foundation
import SwiftDXF

/// What an attribute and an attribute definition have in common, for `--attributes`.
private protocol AttributeFields {
    var tag: String { get }
    var text: String { get }
    var position: DXF.Point { get }
    var height: Double { get }
    var rotation: Double { get }
    var layer: String { get }
    var flags: DXF.AttributeFlags { get }
    var isMultiline: Bool { get }
    var identity: DXF.Identity { get }
}

extension DXF.Attribute: AttributeFields {
    fileprivate var text: String { value }
}

extension DXF.AttributeDefinition: AttributeFields {
    fileprivate var text: String { defaultValue }
}

/// The attributes of each block reference and the attribute definitions of each block.
///
/// Only the references and blocks that have any are listed. With `--skip-paper-space`, as ezdxf's
/// `modelspace()` reads. With `--expand-attributes`, also the texts the attributes became.
func attributeSummary(for path: String, options: DXF.ReadOptions) -> [String: Any] {
    let url = URL(fileURLWithPath: path)
    do {
        let dwg = try DXF.read(contentsOf: url, options: options)
        func fields(_ a: some AttributeFields) -> [String: Any] {
            [
                "tag": a.tag, "text": a.text, "x": a.position.x, "y": a.position.y,
                "height": a.height, "rotation": a.rotation, "layer": a.layer,
                "flags": a.flags.rawValue, "multiline": a.isMultiline,
                "handle": a.identity.handle ?? NSNull() as Any,
            ]
        }
        func references(_ list: [DXF.BlockReference]) -> [[String: Any]] {
            list.filter { !$0.attributes.isEmpty }.map { ref in
                [
                    "name": ref.name, "handle": ref.identity.handle ?? NSNull() as Any,
                    "attributes": ref.attributes.map { fields($0) },
                ]
            }
        }
        let blocks: [[String: Any]] = dwg.blocks.compactMap { block in
            let nested = references(block.references)
            guard !nested.isEmpty || !block.attributeDefinitions.isEmpty else { return nil }
            return [
                "name": block.name, "references": nested,
                "definitions": block.attributeDefinitions.map {
                    var out = fields($0)
                    out["prompt"] = $0.prompt
                    return out
                },
            ]
        }
        var out: [String: Any] = [
            "file": url.lastPathComponent, "references": references(dwg.references),
            "blocks": blocks,
        ]
        if options.expandAttributes {
            // The texts an attribute became: the entities that carry an attribute's handle.
            let attributes = dwg.references + dwg.blocks.flatMap(\.references)
            let handles = Set(attributes.flatMap(\.attributes).compactMap(\.identity.handle))
            out["expanded"] = dwg.entities.enumerated().compactMap {
                (i, entity) -> [String: Any]? in
                guard case .text(let at, let height, let rotation, let text, _, _) = entity,
                    let handle = dwg.identity(ofEntityAt: i).handle, handles.contains(handle)
                else { return nil }
                return [
                    "text": text, "x": at.x, "y": at.y, "height": height, "rotation": rotation,
                ]
            }
        }
        return out
    } catch {
        return ["file": url.lastPathComponent, "error": "\(error)"]
    }
}
