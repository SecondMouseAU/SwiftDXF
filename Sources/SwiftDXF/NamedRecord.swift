import Foundation

/// A table record that is looked up by name.
protocol NamedRecord {
    var name: String { get }
}

extension DXF.Layer: NamedRecord {}
extension DXF.LineType: NamedRecord {}
extension DXF.DimensionStyle: NamedRecord {}

extension Sequence where Element: NamedRecord {
    /// The first record called `name`, ignoring case.
    func first(named name: String) -> Element? {
        first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }
}
