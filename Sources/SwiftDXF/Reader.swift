import Foundation

/// ASCII-DXF tokeniser + model-space entity parser. DXF is a flat stream of *group code* / *value*
/// line pairs; this walks the `ENTITIES` section and dispatches each `0`-tagged entity.
extension DXF {
    struct Reader {
        /// (group code, raw value) pairs, in file order. `\r` already stripped from values.
        let pairs: [(code: Int, value: String)]
        var version = ""

        init(_ text: String) {
            var out: [(Int, String)] = []
            out.reserveCapacity(text.count / 16)
            // Split on any newline. Swift folds CRLF into a single `\r\n` grapheme, so `\.isNewline`
            // consumes LF, CR, and CRLF line endings uniformly without leaving stray carriage returns.
            let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            var i = 0
            while i + 1 < lines.count {
                let codeField = lines[i].trimmingCharacters(in: .whitespaces)
                guard let code = Int(codeField) else {
                    i += 1
                    continue
                }  // resync on a stray line
                out.append((code, String(lines[i + 1])))
                i += 2
            }
            pairs = out
        }

        // MARK: field accessors (over one entity's tag bag)

        func first(_ code: Int, _ f: [(code: Int, value: String)]) -> String? {
            f.first { $0.code == code }?.value
        }
        func dbl(_ code: Int, _ f: [(code: Int, value: String)], _ fallback: Double = 0)
            -> Double
        {
            guard let s = first(code, f) else { return fallback }
            return Double(s.trimmingCharacters(in: .whitespaces)) ?? fallback
        }
        func ints(_ code: Int, _ f: [(code: Int, value: String)]) -> Int? {
            guard let s = first(code, f) else { return nil }
            return Int(s.trimmingCharacters(in: .whitespaces))
        }
        func dblOpt(_ code: Int, _ f: [(code: Int, value: String)]) -> Double? {
            guard let s = first(code, f) else { return nil }
            return Double(s.trimmingCharacters(in: .whitespaces))
        }
        /// A point whose base group code (and `+10`/`+20` for y/z) may be entirely absent, e.g.
        /// DIMENSION's per-type definition points (13/14/15/16). `nil`, not a zero point, when unset.
        func pointOpt(_ base: Int, _ f: [(code: Int, value: String)]) -> Point? {
            guard first(base, f) != nil else { return nil }
            return Point(dbl(base, f), dbl(base + 10, f), dbl(base + 20, f))
        }
        func allDbl(_ code: Int, _ f: [(code: Int, value: String)]) -> [Double] {
            f.compactMap {
                $0.code == code ? Double($0.value.trimmingCharacters(in: .whitespaces)) : nil
            }
        }
        func layer(_ f: [(code: Int, value: String)]) -> String {
            first(8, f).map { $0.trimmingCharacters(in: .whitespaces) } ?? "0"
        }
        /// AutoCAD Color Index (group 62); 256 = BYLAYER when absent.
        func color(_ f: [(code: Int, value: String)]) -> Int { ints(62, f) ?? 256 }
        func point(_ f: [(code: Int, value: String)]) -> Point {
            Point(dbl(10, f), dbl(20, f), dbl(30, f))
        }
        /// LWPOLYLINE vertices in field order: each `10` opens a vertex, `20` is its y, `42` its bulge.
        func lwVertices(_ f: [(code: Int, value: String)]) -> [PolyVertex] {
            var verts: [PolyVertex] = []
            var x: Double?
            var y: Double = 0
            var bulge: Double = 0
            func flush() {
                if let x { verts.append(PolyVertex(Point(x, y), bulge: bulge)) }
                x = nil
                y = 0
                bulge = 0
            }
            for (code, value) in f {
                let v = Double(value.trimmingCharacters(in: .whitespaces))
                switch code {
                case 10:
                    if x != nil { flush() }
                    x = v
                case 20: y = v ?? 0
                case 42: bulge = v ?? 0
                default: break
                }
            }
            flush()
            return verts
        }

        /// SPLINE points for base code 10 (control) or 11 (fit): each base-code tag opens a point,
        /// the `+10`/`+20` tags that follow fill its y and z.
        func splinePoints(_ base: Int, _ f: [(code: Int, value: String)]) -> [Point] {
            var pts: [Point] = []
            var cur: Point?
            for (code, value) in f {
                let v = Double(value.trimmingCharacters(in: .whitespaces)) ?? 0
                switch code {
                case base:
                    if let cur { pts.append(cur) }
                    cur = Point(v, 0, 0)
                case base + 10: cur?.y = v
                case base + 20: cur?.z = v
                default: break
                }
            }
            if let cur { pts.append(cur) }
            return pts
        }

        // MARK: parse

        mutating func parse() throws -> Drawing {
            guard !pairs.isEmpty else { throw Error.notDXF }
            guard
                pairs.contains(where: { $0.code == 0 && trimmed($0.value) == "SECTION" })
                    || pairs.contains(where: { $0.code == 0 && trimmed($0.value) == "EOF" })
            else { throw Error.notDXF }

            // $ACADVER from the HEADER section, if present.
            for k in pairs.indices.dropLast()
            where pairs[k].code == 9 && trimmed(pairs[k].value) == "$ACADVER" {
                version = trimmed(pairs[k + 1].value)
                break
            }

            var dwg = Drawing(version: version)
            dwg.insUnits = ints(70, headerVar("$INSUNITS"))
            let mn = headerVar("$EXTMIN")
            if mn.contains(where: { $0.code == 10 }) { dwg.extMin = point(mn) }
            let mx = headerVar("$EXTMAX")
            if mx.contains(where: { $0.code == 10 }) { dwg.extMax = point(mx) }
            dwg.layers = layers()
            dwg.lineTypes = lineTypes()
            dwg.dimensionStyles = dimensionStyles()
            dwg.dimensionDefaults = headerStyleVariables()
            dwg.blocks = blocks()
            guard let start = sectionStart("ENTITIES") else { return dwg }  // no model space

            let run = readEntities(from: start, stopAt: ["ENDSEC", "EOF"]) { "ENTITIES:\($0)" }
            dwg.entities = run.entities
            dwg.identities = run.identities
            dwg.entityLineTypes = run.lineTypes
            dwg.counts = run.counts
            dwg.skipped = run.skipped
            dwg.skippedByLayer = run.skippedByLayer
            return dwg
        }

        /// The value pairs of a HEADER variable (`9`/`$NAME`), up to the next `9` or section `0`.
        func headerVar(_ name: String) -> [(code: Int, value: String)] {
            guard let start = pairs.firstIndex(where: { $0.code == 9 && trimmed($0.value) == name })
            else { return [] }
            var out: [(code: Int, value: String)] = []
            var k = start + 1
            while k < pairs.count, pairs[k].code != 9, pairs[k].code != 0 {
                out.append(pairs[k])
                k += 1
            }
            return out
        }

        func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespaces) }

        /// Text payload for TEXT/MTEXT: concatenate MTEXT continuation groups (3) then the final
        /// group (1), and decode AutoCAD inline escapes.
        func textValue(_ f: [(code: Int, value: String)]) -> String {
            let continued = f.filter { $0.code == 3 }.map(\.value).joined()
            let main = first(1, f) ?? ""
            return unescape(continued + main)
        }

        /// Decode the inline escapes that matter for plain text: `\U+XXXX` unicode, and `\P` newline.
        func unescape(_ s: String) -> String {
            guard s.contains("\\") else { return s }
            var out = ""
            var it = s.makeIterator()
            var pending: Character? = nil
            func next() -> Character? {
                if let p = pending {
                    pending = nil
                    return p
                }
                return it.next()
            }
            while let c = next() {
                guard c == "\\" else {
                    out.append(c)
                    continue
                }
                guard let n = next() else {
                    out.append(c)
                    break
                }
                if n == "U", let plus = next(), plus == "+" {
                    var hex = ""
                    for _ in 0..<4 {
                        if let h = next(), h.isHexDigit { hex.append(h) } else { break }
                    }
                    if let v = UInt32(hex, radix: 16), let u = Unicode.Scalar(v) {
                        out.unicodeScalars.append(u)
                    }
                } else if n == "P" || n == "p" {
                    out.append("\n")
                } else {
                    out.append(n)  // drop the backslash, keep the escaped char
                }
            }
            return out
        }
    }
}
