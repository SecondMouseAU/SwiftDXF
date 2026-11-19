import Foundation

extension DXF {
    /// A Windows code page that a drawing's text is written in, as `$DWGCODEPAGE` names it.
    ///
    /// A file before DXF R2007 writes its characters above 127 in this code page, and `%%nnn` in
    /// any version is the character numbered nnn in it.
    public struct CodePage: Hashable, Sendable {
        /// The code page number: 874, 932, 936, 949, 950, or 1250 to 1258.
        public let number: Int

        private static let supported: Set<Int> = [
            874, 932, 936, 949, 950, 1250, 1251, 1252, 1253, 1254, 1255, 1256, 1257, 1258,
        ]

        /// The code page a `$DWGCODEPAGE` value names, such as `ANSI_932`, or `nil` for any other
        /// value (`DOS437` and the `ISO8859` pages are not read).
        public init?(name: String) {
            let upper = name.trimmingCharacters(in: .whitespaces).uppercased()
            guard upper.hasPrefix("ANSI_"), let number = Int(upper.dropFirst("ANSI_".count)),
                Self.supported.contains(number)
            else { return nil }
            self.number = number
        }

        private init(_ number: Int) { self.number = number }

        /// The `$DWGCODEPAGE` value, such as `ANSI_932`.
        public var name: String { "ANSI_\(number)" }

        /// Shift-JIS, the page of DXF from Japanese tools such as Jw_cad.
        static let shiftJIS = CodePage(932)

        /// The page `\M+nXXXX` names with its `n`, as `ezdxf` reads it.
        ///
        /// 1 is 932 (Japanese), 2 is 950 (Traditional Chinese), 3 is 949 (Korean Wansung) and 5 is
        /// 936 (Simplified Chinese), whatever the drawing's own page. `nil` for 4 (Korean Johab),
        /// which `ezdxf` reads but the platform does not decode, and for any other `n`.
        static func multibyte(_ n: Int) -> CodePage? {
            switch n {
            case 1: return CodePage(932)
            case 2: return CodePage(950)
            case 3: return CodePage(949)
            case 5: return CodePage(936)
            default: return nil
            }
        }

        /// The characters `bytes` stand for in this code page, or `nil` when they are not valid in
        /// it, or when this platform cannot decode the page.
        func decode(_ bytes: [UInt8]) -> String? {
            guard let encoding else { return nil }
            return String(data: Data(bytes), encoding: encoding)
        }

        /// Whether a character of this page may be two bytes.
        private var isMultibyte: Bool { [932, 936, 949, 950].contains(number) }

        /// `bytes` decoded a line at a time, with each byte that is not a character of the page as
        /// U+FFFD, so that one stray byte does not turn the rest of the file into other characters.
        func decodeLines(_ bytes: [UInt8]) -> String {
            var out = ""
            var start = 0
            for (i, byte) in bytes.enumerated() where byte == 0x0A || i == bytes.count - 1 {
                let line = Array(bytes[start...i])
                out += decode(line) ?? decodeByCharacter(line)
                start = i + 1
            }
            return out
        }

        private func decodeByCharacter(_ line: [UInt8]) -> String {
            var out = ""
            var i = 0
            while i < line.count {
                let byte = line[i]
                if byte < 0x80 {
                    out.unicodeScalars.append(Unicode.Scalar(byte))
                } else if isMultibyte, i + 1 < line.count, let pair = decode([byte, line[i + 1]]) {
                    out += pair
                    i += 1
                } else {
                    out += decode([byte]) ?? "\u{FFFD}"
                }
                i += 1
            }
            return out
        }

        private var encoding: String.Encoding? {
            #if canImport(CoreFoundation)
                let page: CFStringEncoding
                switch number {
                case 874: page = CFStringEncoding(CFStringEncodings.dosThai.rawValue)
                case 932: page = CFStringEncoding(CFStringEncodings.dosJapanese.rawValue)
                case 936: page = CFStringEncoding(CFStringEncodings.dosChineseSimplif.rawValue)
                case 949: page = CFStringEncoding(CFStringEncodings.dosKorean.rawValue)
                case 950: page = CFStringEncoding(CFStringEncodings.dosChineseTrad.rawValue)
                case 1250: page = CFStringEncoding(CFStringEncodings.windowsLatin2.rawValue)
                case 1251: page = CFStringEncoding(CFStringEncodings.windowsCyrillic.rawValue)
                case 1252: page = CFStringBuiltInEncodings.windowsLatin1.rawValue
                case 1253: page = CFStringEncoding(CFStringEncodings.windowsGreek.rawValue)
                case 1254: page = CFStringEncoding(CFStringEncodings.windowsLatin5.rawValue)
                case 1255: page = CFStringEncoding(CFStringEncodings.windowsHebrew.rawValue)
                case 1256: page = CFStringEncoding(CFStringEncodings.windowsArabic.rawValue)
                case 1257: page = CFStringEncoding(CFStringEncodings.windowsBalticRim.rawValue)
                default: page = CFStringEncoding(CFStringEncodings.windowsVietnamese.rawValue)
                }
                return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(page))
            #else
                switch number {
                case 932: return .shiftJIS
                case 1250: return .windowsCP1250
                case 1251: return .windowsCP1251
                case 1252: return .windowsCP1252
                case 1253: return .windowsCP1253
                case 1254: return .windowsCP1254
                default: return nil
                }
            #endif
        }
    }

    /// The `$ACADVER` the file's header names, such as `AC1032`, or `nil`.
    static func headerVersion(in data: Data) -> String? {
        guard let key = data.range(of: Data("$ACADVER".utf8)) else { return nil }
        let tail = data[key.upperBound..<min(data.endIndex, key.upperBound + 48)]
        let lines = String(decoding: tail, as: UTF8.self).split(whereSeparator: \.isNewline)
        guard lines.count >= 2, lines[0].trimmingCharacters(in: .whitespaces) == "1" else {
            return nil
        }
        return lines[1].trimmingCharacters(in: .whitespaces)
    }

    /// The code page the file's `$DWGCODEPAGE` names, read from the bytes of the header.
    ///
    /// The header is ASCII in every supported code page, so it can be read before the rest of the
    /// file is decoded.
    static func headerCodePage(in data: Data) -> CodePage? {
        guard let key = data.range(of: Data("$DWGCODEPAGE".utf8)) else { return nil }
        let tail = data[key.upperBound..<min(data.endIndex, key.upperBound + 48)]
        let lines = String(decoding: tail, as: UTF8.self).split(whereSeparator: \.isNewline)
        guard lines.count >= 2, lines[0].trimmingCharacters(in: .whitespaces) == "3" else {
            return nil
        }
        return CodePage(name: String(lines[1]))
    }
}
