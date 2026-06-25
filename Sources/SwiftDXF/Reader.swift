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
                guard let code = Int(codeField) else { i += 1; continue }   // resync on a stray line
                out.append((code, String(lines[i + 1])))
                i += 2
            }
            pairs = out
        }

        // MARK: field accessors (over one entity's tag bag)

        private func first(_ code: Int, _ f: [(code: Int, value: String)]) -> String? {
            f.first { $0.code == code }?.value
        }
        private func dbl(_ code: Int, _ f: [(code: Int, value: String)], _ fallback: Double = 0) -> Double {
            guard let s = first(code, f) else { return fallback }
            return Double(s.trimmingCharacters(in: .whitespaces)) ?? fallback
        }
        private func ints(_ code: Int, _ f: [(code: Int, value: String)]) -> Int? {
            guard let s = first(code, f) else { return nil }
            return Int(s.trimmingCharacters(in: .whitespaces))
        }
        private func allDbl(_ code: Int, _ f: [(code: Int, value: String)]) -> [Double] {
            f.compactMap { $0.code == code ? Double($0.value.trimmingCharacters(in: .whitespaces)) : nil }
        }
        private func layer(_ f: [(code: Int, value: String)]) -> String {
            first(8, f).map { $0.trimmingCharacters(in: .whitespaces) } ?? "0"
        }
        /// AutoCAD Color Index (group 62); 256 = BYLAYER when absent.
        private func color(_ f: [(code: Int, value: String)]) -> Int { ints(62, f) ?? 256 }
        private func point(_ f: [(code: Int, value: String)]) -> Point {
            Point(dbl(10, f), dbl(20, f), dbl(30, f))
        }

        // MARK: parse

        mutating func parse() throws -> Drawing {
            guard !pairs.isEmpty else { throw Error.notDXF }
            guard pairs.contains(where: { $0.code == 0 && trimmed($0.value) == "SECTION" })
                || pairs.contains(where: { $0.code == 0 && trimmed($0.value) == "EOF" })
            else { throw Error.notDXF }

            // $ACADVER from the HEADER section, if present.
            for k in pairs.indices.dropLast() where pairs[k].code == 9 && trimmed(pairs[k].value) == "$ACADVER" {
                version = trimmed(pairs[k + 1].value); break
            }

            var dwg = Drawing(version: version)
            guard let start = entitiesStart() else { return dwg }   // valid DXF, just no model space

            var i = start
            while i < pairs.count {
                let p = pairs[i]
                guard p.code == 0 else { i += 1; continue }
                let type = trimmed(p.value)
                if type == "ENDSEC" || type == "EOF" { break }

                // Collect this entity's fields up to the next 0-tag.
                var j = i + 1
                var fields: [(code: Int, value: String)] = []
                while j < pairs.count && pairs[j].code != 0 { fields.append(pairs[j]); j += 1 }

                switch type {
                case "LINE":
                    let a = point(fields)
                    let b = Point(dbl(11, fields), dbl(21, fields), dbl(31, fields))
                    dwg.entities.append(.line(a: a, b: b, layer: layer(fields), color: color(fields)))
                    dwg.counts.line += 1

                case "CIRCLE":
                    dwg.entities.append(.circle(center: point(fields), radius: dbl(40, fields),
                                                layer: layer(fields), color: color(fields)))
                    dwg.counts.circle += 1

                case "ARC":
                    dwg.entities.append(.arc(center: point(fields), radius: dbl(40, fields),
                                             startDeg: dbl(50, fields), endDeg: dbl(51, fields),
                                             layer: layer(fields), color: color(fields)))
                    dwg.counts.arc += 1

                case "ELLIPSE":
                    var major = Point(dbl(11, fields), dbl(21, fields), dbl(31, fields))
                    var ratio = dbl(40, fields, 1)
                    var startP = dbl(41, fields, 0), endP = dbl(42, fields, 2 * .pi)
                    // The DXF spec requires ratio = minor/major ≤ 1. Some writers emit ratio > 1
                    // (a swapped major axis). Normalise to the canonical form — rotate the major axis
                    // +90° and scale by ratio, invert the ratio, shift the params by −π/2 — so the curve
                    // is unchanged but downstream consumers (e.g. OCCT's Geom_Ellipse, which demands
                    // majorRadius ≥ minorRadius) get a valid axis. Matches ezdxf's normalisation.
                    if ratio > 1 {
                        major = Point(-major.y * ratio, major.x * ratio, major.z)
                        ratio = 1 / ratio
                        func shift(_ a: Double) -> Double {
                            let m = (a - .pi / 2).truncatingRemainder(dividingBy: 2 * .pi)
                            return m < 0 ? m + 2 * .pi : m
                        }
                        startP = shift(startP); endP = shift(endP)
                    }
                    dwg.entities.append(.ellipse(center: point(fields), majorAxis: major,
                                                 ratio: ratio, startParam: startP, endParam: endP,
                                                 layer: layer(fields), color: color(fields)))
                    dwg.counts.ellipse += 1

                case "POINT":
                    dwg.entities.append(.point(at: point(fields), layer: layer(fields), color: color(fields)))
                    dwg.counts.point += 1

                case "TEXT", "MTEXT":
                    dwg.entities.append(.text(at: point(fields), height: dbl(40, fields, 0),
                                              rotationDeg: dbl(50, fields, 0), string: textValue(fields),
                                              layer: layer(fields), color: color(fields)))
                    dwg.counts.text += 1

                case "LWPOLYLINE":
                    let xs = allDbl(10, fields), ys = allDbl(20, fields)
                    let pts = zip(xs, ys).map { Point($0, $1) }
                    let closed = (ints(70, fields) ?? 0) & 1 == 1
                    dwg.entities.append(.polyline(points: pts, closed: closed, layer: layer(fields), color: color(fields)))
                    dwg.counts.polyline += 1

                case "POLYLINE":
                    // Old-style: a POLYLINE header followed by VERTEX entities and a terminating SEQEND.
                    let closed = (ints(70, fields) ?? 0) & 1 == 1
                    let lay = layer(fields), col = color(fields)
                    var pts: [Point] = []
                    while j < pairs.count && pairs[j].code == 0 && trimmed(pairs[j].value) == "VERTEX" {
                        var m = j + 1
                        var vf: [(code: Int, value: String)] = []
                        while m < pairs.count && pairs[m].code != 0 { vf.append(pairs[m]); m += 1 }
                        pts.append(point(vf))
                        j = m
                    }
                    if j < pairs.count && pairs[j].code == 0 && trimmed(pairs[j].value) == "SEQEND" {
                        var m = j + 1
                        while m < pairs.count && pairs[m].code != 0 { m += 1 }
                        j = m
                    }
                    dwg.entities.append(.polyline(points: pts, closed: closed, layer: lay, color: col))
                    dwg.counts.polyline += 1

                default:
                    break   // unmodelled entity (INSERT, SPLINE, HATCH, …) — skip
                }
                i = j
            }
            return dwg
        }

        /// Index of the first pair *after* a `2`/`ENTITIES` tag inside a `SECTION`.
        private func entitiesStart() -> Int? {
            var k = 0
            while k + 1 < pairs.count {
                if pairs[k].code == 0, trimmed(pairs[k].value) == "SECTION",
                   pairs[k + 1].code == 2, trimmed(pairs[k + 1].value) == "ENTITIES" {
                    return k + 2
                }
                k += 1
            }
            return nil
        }

        private func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespaces) }

        /// Text payload for TEXT/MTEXT: concatenate MTEXT continuation groups (3) then the final
        /// group (1), and decode AutoCAD inline escapes.
        private func textValue(_ f: [(code: Int, value: String)]) -> String {
            let continued = f.filter { $0.code == 3 }.map(\.value).joined()
            let main = first(1, f) ?? ""
            return unescape(continued + main)
        }

        /// Decode the inline escapes that matter for plain text: `\U+XXXX` unicode, and `\P` newline.
        private func unescape(_ s: String) -> String {
            guard s.contains("\\") else { return s }
            var out = ""
            var it = s.makeIterator()
            var pending: Character? = nil
            func next() -> Character? { if let p = pending { pending = nil; return p }; return it.next() }
            while let c = next() {
                guard c == "\\" else { out.append(c); continue }
                guard let n = next() else { out.append(c); break }
                if n == "U", let plus = next(), plus == "+" {
                    var hex = ""
                    for _ in 0..<4 { if let h = next(), h.isHexDigit { hex.append(h) } else { break } }
                    if let v = UInt32(hex, radix: 16), let u = Unicode.Scalar(v) { out.unicodeScalars.append(u) }
                } else if n == "P" || n == "p" {
                    out.append("\n")
                } else {
                    out.append(n)   // drop the backslash, keep the escaped char
                }
            }
            return out
        }
    }
}
