import Foundation

extension DXF {
    /// The value of the header variable `name` (`$ACADVER`) from the bytes of the file, read from
    /// the group `code` that follows it, or `nil`.
    ///
    /// The header is ASCII in every code page a file may be in, so it can be read before the
    /// rest of the file is decoded.
    static func headerValue(_ name: String, code: String, in data: Data) -> String? {
        guard let key = data.range(of: Data(name.utf8)) else { return nil }
        let tail = data[key.upperBound..<min(data.endIndex, key.upperBound + 48)]
        let lines = String(decoding: tail, as: UTF8.self).split(whereSeparator: \.isNewline)
        guard lines.count >= 2, lines[0].trimmingCharacters(in: .whitespaces) == code else {
            return nil
        }
        return lines[1].trimmingCharacters(in: .whitespaces)
    }

    /// The `$ACADVER` the header names, such as `AC1032`, or `nil`.
    static func headerVersion(in data: Data) -> String? {
        headerValue("$ACADVER", code: "1", in: data)
    }

    /// The code page the header's `$DWGCODEPAGE` names, or `nil` when it names none that is read.
    static func headerCodePage(in data: Data) -> CodePage? {
        headerValue("$DWGCODEPAGE", code: "3", in: data).flatMap { CodePage(name: $0) }
    }
}
