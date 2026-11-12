import Foundation

extension DXF {
    /// The parts of a dimension style that decide how a measured value is stated.
    ///
    /// Read from the `DIMSTYLE` table, then overridden per entity by the `ACAD`/`DSTYLE`
    /// extended data some writers attach to a `DIMENSION`. A field the file does not carry is
    /// `nil`, never a guess.
    public struct DimensionStyle: Equatable, Sendable {
        /// The style name (group 2).
        public var name: String
        /// Decimal places of linear values (`DIMDEC`, group 271).
        public var decimals: Int?
        /// Text added to every value (`DIMPOST`, group 3), where `<>` stands for the number, such
        /// as `<> mm` or `mm`.
        public var suffix: String?
        /// Factor applied to the measurement before it is shown (`DIMLFAC`, group 144).
        public var linearScale: Double?

        public init(
            name: String, decimals: Int? = nil, suffix: String? = nil, linearScale: Double? = nil
        ) {
            self.name = name
            self.decimals = decimals
            self.suffix = suffix
            self.linearScale = linearScale
        }

        /// Per-entity overrides of a style, from the entity's `DSTYLE` extended data.
        public struct Overrides: Equatable, Sendable {
            public var decimals: Int?
            public var suffix: String?
            public var linearScale: Double?

            public init(decimals: Int? = nil, suffix: String? = nil, linearScale: Double? = nil) {
                self.decimals = decimals
                self.suffix = suffix
                self.linearScale = linearScale
            }

            /// Whether no override is present.
            public var isEmpty: Bool { self == Overrides() }
        }

        /// This style with `overrides` laid over it.
        public func applying(_ overrides: Overrides) -> DimensionStyle {
            var out = self
            if let d = overrides.decimals { out.decimals = d }
            if let s = overrides.suffix { out.suffix = s }
            if let f = overrides.linearScale { out.linearScale = f }
            return out
        }

        /// The value as the drawing states it: scaled by ``linearScale``, rounded to
        /// ``decimals`` places when known, and wrapped in ``suffix``.
        public func format(_ measurement: Double) -> String {
            let scaled = measurement * (linearScale ?? 1)
            let number: String
            if let decimals, decimals >= 0 {
                number = String(format: "%.\(decimals)f", scaled)
            } else {
                number = "\(scaled)"
            }
            guard let suffix, !suffix.isEmpty else { return number }
            return suffix.contains("<>")
                ? suffix.replacingOccurrences(of: "<>", with: number) : number + suffix
        }
    }
}
