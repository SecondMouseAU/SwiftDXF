import Foundation

extension DXF {
    /// One variable of the `HEADER` section: the group-coded values that follow its name.
    ///
    /// `$MEASUREMENT` is one value (group 70), `$EXTMIN` is three (groups 10, 20 and 30), and a
    /// variable this package does not name is still here, in ``Drawing/headerVariables``.
    public struct HeaderVariable: Equatable, Sendable {
        /// One group-coded value of a header variable, as the file writes it.
        public struct Value: Equatable, Sendable {
            /// The group code, which says what the value is: 70 is an integer, 40 a real number,
            /// 1, 2 and 3 are text, and 10, 20 and 30 are the x, y and z of a point.
            public var code: Int
            /// The value as the file writes it, read through the drawing's code page.
            ///
            /// Whitespace is kept, and `%%` codes in a string are not decoded.
            public var text: String

            public init(code: Int, text: String) {
                self.code = code
                self.text = text
            }

            /// ``text`` as an integer, or `nil` when it is not one.
            public var integer: Int? { Int(text.trimmingCharacters(in: .whitespaces)) }

            /// ``text`` as a real number, or `nil` when it is not one.
            public var real: Double? { Double(text.trimmingCharacters(in: .whitespaces)) }
        }

        /// The values in file order.
        public var values: [Value]

        public init(values: [Value] = []) {
            self.values = values
        }

        /// The first value written with group `code`, or `nil`.
        public func value(_ code: Int) -> Value? {
            values.first { $0.code == code }
        }

        /// The point written as groups 10, 20 and 30, or `nil` when there is no group 10.
        ///
        /// A coordinate that is missing or not a number is `0`, so a 2D point has `z == 0`.
        public var point: Point? {
            guard let x = value(10) else { return nil }
            return Point(x.real ?? 0, value(20)?.real ?? 0, value(30)?.real ?? 0)
        }
    }
}
