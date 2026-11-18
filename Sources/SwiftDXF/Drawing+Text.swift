extension DXF.Drawing {
    /// The string of the `TEXT` or `MTEXT` entity at `index`: as written, as it reads, and its
    /// stacks.
    ///
    /// `nil` for an entity that is not text, and for every entity when ``textContents`` does not
    /// line up with ``entities``: after ``entities`` has changed, or in a drawing assembled by
    /// hand without them.
    public func textContent(ofEntityAt index: Int) -> DXF.TextContent? {
        guard textContents.count == entities.count, textContents.indices.contains(index)
        else { return nil }
        return textContents[index]
    }
}
