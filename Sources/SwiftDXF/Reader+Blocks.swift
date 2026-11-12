extension DXF.Reader {
    /// An `INSERT` from its fields.
    func blockReference(
        _ f: [(code: Int, value: String)], identity: DXF.Identity
    ) -> DXF.BlockReference {
        DXF.BlockReference(
            name: nonEmpty(first(2, f).map(trimmed)) ?? "", insertion: point(f),
            scaleX: dbl(41, f, 1), scaleY: dbl(42, f, 1), scaleZ: dbl(43, f, 1),
            rotation: dbl(50, f), columns: max(ints(70, f) ?? 1, 1), rows: max(ints(71, f) ?? 1, 1),
            columnSpacing: dbl(44, f), rowSpacing: dbl(45, f), layer: layer(f), color: color(f),
            lineType: nonEmpty(first(6, f).map(trimmed)),
            extrusion: DXF.Point(dbl(210, f, 0), dbl(220, f, 0), dbl(230, f, 1)),
            identity: identity)
    }
}
