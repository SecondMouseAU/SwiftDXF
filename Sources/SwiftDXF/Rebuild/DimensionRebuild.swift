import Foundation

extension DXF {
    /// Dimensions rebuilt from the loose pieces of a drawing: value texts, dimension lines,
    /// extension lines, and the marks at the ends of a dimension line.
    ///
    /// Made by ``Drawing/rebuildingDimensions(_:)``. A drawing from a Jw_cad export, a vector PDF
    /// or a scan holds a dimension as separate pieces, with nothing that says which belong
    /// together or at what scale they were drawn. The rebuild starts from each value text, finds
    /// the dimension line beside it and the ends it spans, and infers the scale from the values
    /// against the drawn lengths. It is an inference: every dimension says what it was built from,
    /// and every value text it could not explain is a warning.
    public struct DimensionRebuild: Sendable {
        /// The rebuilt dimensions, in the order of their value texts in the drawing.
        ///
        /// Each has ``Dimension/rebuilt`` set, its text as written in ``Dimension/textOverride``,
        /// the length the geometry gives in ``Dimension/measurement``, and the scale as
        /// ``DimensionStyle/Variables/linearScale``, so that
        /// ``Drawing/displayedMeasurement(of:)`` is the value the text states.
        public var dimensions: [Dimension]
        /// The scale found for each layer group that has value texts, and what supports it.
        public var scales: [ScaleEstimate]
        /// What the rebuild could not do, or did that deserves a second look.
        public var warnings: [Warning]

        public init(
            dimensions: [Dimension] = [], scales: [ScaleEstimate] = [], warnings: [Warning] = []
        ) {
            self.dimensions = dimensions
            self.scales = scales
            self.warnings = warnings
        }

        /// What the rebuild may be told.
        public struct Options: Equatable, Sendable {
            /// A scale to use for every layer group, instead of inferring one: the real value per
            /// drawn unit, so `80` for a drawing at 1:80.
            public var scale: Double?
            /// How far apart two pieces may be and still meet, in drawing units. `nil` takes 3%
            /// of the height of the value texts.
            public var tolerance: Double?
            /// Which pieces may belong to a value text.
            public var pieceLayers: PieceLayers

            /// The layers the pieces of one dimension are on.
            public enum PieceLayers: Equatable, Sendable {
                /// The layer of the value text, as for an exploded dimension, a Jw_cad export, and
                /// a PDF, which has one layer.
                case sameAsText
                /// Any layer.
                case any
            }

            public init(
                scale: Double? = nil, tolerance: Double? = nil,
                pieceLayers: PieceLayers = .sameAsText
            ) {
                self.scale = scale
                self.tolerance = tolerance
                self.pieceLayers = pieceLayers
            }
        }

        /// The scale of one layer group: the one that explains the most values.
        public struct ScaleEstimate: Equatable, Sendable {
            /// The layer group: the group of a Jw_cad layer name (`0` for `0-E`), otherwise the
            /// layer name.
            public var group: String
            /// The real value per drawn unit, `80` for a drawing at 1:80.
            public var scale: Double
            /// The value texts this scale explains.
            public var supporting: Int
            /// The value texts of the group that have a dimension line beside them but that this
            /// scale does not explain.
            public var contradicting: Int

            public init(group: String, scale: Double, supporting: Int, contradicting: Int) {
                self.group = group
                self.scale = scale
                self.supporting = supporting
                self.contradicting = contradicting
            }
        }

        /// Why a value text was not rebuilt.
        public enum Reason: Equatable, Sendable {
            /// No dimension line, circle or arc at the stated distance.
            case noMatch
            /// Too few values in its layer group to infer a scale.
            case noScale
            /// An angle, which is not rebuilt.
            case angular
            /// A unit other than millimetres.
            case unit
            /// More than one number in the text.
            case severalNumbers
        }

        public enum Warning: Equatable, Sendable, CustomStringConvertible {
            /// A value text that no dimension explains.
            case valueNotExplained(text: String, identity: Identity, reason: Reason)
            /// The layer groups do not agree on the scale. Each keeps its own; none is averaged.
            case scalesDisagree([ScaleEstimate])
            /// A diameter or radius symbol that the geometry does not bear out. The dimension
            /// is the kind the geometry gives.
            case symbolDisagrees(text: String, identity: Identity, geometry: DimensionType)

            public var description: String {
                switch self {
                case .valueNotExplained(let text, let identity, let reason):
                    return "value \(text) (\(identity)) is not explained: \(reason)"
                case .scalesDisagree(let scales):
                    let list = scales.map { "\($0.group): 1:\($0.scale)" }.joined(separator: ", ")
                    return "the layer groups disagree on the scale (\(list))"
                case .symbolDisagrees(let text, let identity, let geometry):
                    return "the symbol of \(text) (\(identity)) disagrees with its geometry, "
                        + "a \(geometry) dimension"
                }
            }
        }

        /// The drawing with the rebuilt dimensions added after its entities.
        ///
        /// The pieces they were built from stay, and each dimension's ``Dimension/rebuilt`` names
        /// them. The new entities have identities `REBUILT:n`, and the drawing's other parallel
        /// arrays are kept.
        public func applied(to drawing: Drawing) -> Drawing {
            var out = drawing
            let identities = drawing.identities.count == drawing.entities.count
            let lineTypes = drawing.entityLineTypes.count == drawing.entities.count
            let texts = drawing.textContents.count == drawing.entities.count
            let before = drawing.entities.count
            var newIdentities = (0..<before).map { drawing.identity(ofEntityAt: $0) }
            out.entities = drawing.entities + dimensions.map { .dimension($0) }
            for n in dimensions.indices {
                newIdentities.append(Identity(locator: "REBUILT:\(n)"))
            }
            if identities { out.identities = newIdentities }
            if lineTypes {
                out.entityLineTypes = drawing.entityLineTypes + dimensions.map { _ in nil }
            }
            if texts { out.textContents = drawing.textContents + dimensions.map { _ in nil } }
            out.counts.dimension += dimensions.count
            return out
        }
    }
}

extension DXF.Dimension {
    /// What a dimension was rebuilt from; see ``DXF/DimensionRebuild``.
    public struct Rebuilt: Equatable, Sendable {
        /// The identities of the entities it was built from: the value text, then the dimension
        /// line pieces, extension lines and end marks, or the circle or arc.
        public var pieces: [DXF.Identity]
        /// The real value per drawn unit the value was explained at.
        public var scale: Double

        public init(pieces: [DXF.Identity], scale: Double) {
            self.pieces = pieces
            self.scale = scale
        }
    }
}
