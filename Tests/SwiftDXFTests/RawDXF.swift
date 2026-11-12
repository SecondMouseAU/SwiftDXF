/// Builds small ASCII-DXF documents for tests, so a case states only the records it is about.
enum RawDXF {
    /// One record: a `0` tag naming the type, then the given group-code and value pairs.
    static func record(_ type: String, _ tags: (Int, String)...) -> String {
        record(type, tags)
    }

    static func record(_ type: String, _ tags: [(Int, String)]) -> String {
        var lines = ["0", type]
        for (code, value) in tags {
            lines.append(String(code))
            lines.append(value)
        }
        return lines.joined(separator: "\n")
    }

    /// A `SECTION` holding `records`.
    static func section(_ name: String, _ records: [String]) -> String {
        ([record("SECTION", (2, name))] + records + [record("ENDSEC")]).joined(separator: "\n")
    }

    /// A table such as `LAYER`, holding `records`.
    static func table(_ name: String, _ records: [String]) -> String {
        ([record("TABLE", (2, name))] + records + [record("ENDTAB")]).joined(separator: "\n")
    }

    /// A whole document from its sections, ending with `EOF`.
    static func file(_ sections: [String]) -> String {
        (sections + [record("EOF")]).joined(separator: "\n") + "\n"
    }

    /// A document with only an `ENTITIES` section.
    static func entities(_ records: [String]) -> String {
        file([section("ENTITIES", records)])
    }

    static func line(
        handle: String? = nil, layer: String = "0", from a: (Double, Double) = (0, 0),
        to b: (Double, Double) = (1, 0)
    ) -> String {
        var tags: [(Int, String)] = []
        if let handle { tags.append((5, handle)) }
        tags += [
            (8, layer), (10, "\(a.0)"), (20, "\(a.1)"), (30, "0.0"), (11, "\(b.0)"),
            (21, "\(b.1)"), (31, "0.0"),
        ]
        return record("LINE", tags)
    }
}
