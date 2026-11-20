---
type: component
title: Components index
resource: https://github.com/SecondMouseAU/SwiftDXF
tags: [index]
description: Public modules / API surfaces exposed by SwiftDXF.
timestamp: 2026-11-19
---

# Components

- **`SwiftDXF`** (library): `DXF.read(contentsOf:)` parses an ASCII DXF file into a `Sendable`
  drawing model: the DXF version, entity counts, and the model-space `DXF.Entity` cases
  (line, arc, circle, polyline, text, spline, …) with their layer, text decoded.
  `DXF.Dimension` carries rotation, style name and overrides, a computed measurement and
  `DimensionText` parts; `Drawing.identities` gives each entity its handle or position;
  `Drawing.dimensionStyles` is the `DIMSTYLE` table. Unmodelled entity types are tallied in
  `Drawing.skipped` / `skippedByLayer`; `DXF.Spline.flattened(tolerance:)` turns a spline into
  polyline points.
- **Extrusion** (`ObjectPlane.swift`, `Reader+Extrusion.swift`): an entity written in an object
  coordinate system with a `-z` normal is read as its world geometry (`Entity.transformed(by:)` with
  `ObjectPlane.mirror`; an `ELLIPSE` only reverses its parameter range). A normal that is not along z
  is read as written and reported as `Warning.extrusionNotApplied`. `tools/ocs_fixtures.py` builds
  the fixture and the `ezdxf.upright` reference values.
- **Block references** (`BlockReference.swift`, `BlockExpansion.swift`, `Transform.swift`,
  `Entity+Transform.swift`, `Reader+Blocks.swift`): `INSERT` is read into `Drawing.references` and
  `Block.references`. `DXF.read(_:options:)` with `ReadOptions(expandBlocks: true)` flattens every
  reference into the entities (nested blocks, scale, rotation, mirroring, arrays), with the
  references it came through in `Identity.via` and what it could not do in `Drawing.warnings`.
  `ReadOptions(skipPaperSpace:)` leaves out group-67 entities, which `Drawing.paperSpace` counts.
- **Attributes** (`Attribute.swift`, `Reader+Attributes.swift`): the `ATTRIB`s that follow an
  `INSERT` with group 66 are `BlockReference.attributes` (tag, value as `TextContent`, position,
  height, rotation, layer, `AttributeFlags`, `Identity`), the `ATTDEF`s of a block are
  `Block.attributeDefinitions` (plus prompt and default); neither is in `skipped` any more. The
  reader slices a record by its `100` markers (`AcDbText`, `AcDbAttribute` or
  `AcDbAttributeDefinition`) and reads the R2018 embedded `MTEXT` after a `101` as the value.
  `ReadOptions(expandAttributes:)`, with `expandBlocks`, adds each visible attribute and each
  constant definition to the entities as `.text` (identity `via` names the reference). An attribute
  is already placed in its container's space, so expansion applies only the transform of the block
  it sits in, plus the array offset.
  `tools/attrib_oracle.py` (`--compare`) is the ezdxf reference for `dxfdump --attributes`, and
  `tools/attrib_fixtures.py` builds the fixtures.
- **Identity** (`Identity.swift`, `Block.swift`, `Tables.swift`): `Drawing.identities` holds a
  `DXF.Identity` (the file's handle plus a section-and-position locator) for each entity, index
  aligned with `entities`; `Drawing.blocks`, `layers`, `lineTypes` and `dimensionStyles` carry the
  records of `BLOCKS` and the tables with their handles. The reader that builds them is split into
  `Reader+Entities.swift`, `Reader+Sections.swift` and `Reader+Tables.swift`.
- **Hatch, leader, line types and layers** (`Hatch.swift`, `Leader.swift`, `Tables.swift`,
  `Drawing+LineTypes.swift`): `.hatch` carries the pattern name, solid flag and boundary paths
  (polyline and edge types); `.leader` the vertices, arrowhead and annotation handle. `Layer` and
  `LineType` carry the table fields, and `Drawing.effectiveLineType(ofEntityAt:)` resolves BYLAYER
  and BYBLOCK. Read by `Reader+Hatch.swift` and `Reader+Tables.swift`.
- **Text** (`TextContent.swift`, `StackedText.swift`, `TextCodes.swift`, `CodePage.swift`,
  `Drawing+Text.swift`): the
  `string` of `.text` is the text as it reads. `Drawing.textContent(ofEntityAt:)` gives a
  `DXF.TextContent`: the string as written (`raw`), its `syntax` (`TEXT` or `MTEXT`), its `parts`
  and `plain` text, and its `stacks`. `%%c`, `%%d`, `%%p` and `%%nnn` are decoded in both, `%%nnn`
  through the drawing's `DXF.CodePage`
  (`Drawing.codePage`, from `$DWGCODEPAGE`), which also reads the bytes of a file that is not UTF-8,
  and `\M+nXXXX` through the multibyte page `n` names; in
  `MTEXT` the formatting codes and groups are removed and a `\S` stack is a `DXF.StackedText`
  (upper, lower, tolerance or fraction). `Drawing.textContents` and `Block.textContents` are
  parallel to the entities. `TextCodes` is the one scanner, shared with `DimensionText`;
  `tools/text_oracle.py` is the ezdxf reference for `dxfdump --texts`.
- **Dimensions** (`Dimension.swift`, `Dimension+Computed.swift`, `DimensionText.swift`,
  `DimensionStyleVariables.swift`, `Drawing+Dimensions.swift`): `Dimension` carries the stored
  `measurement` (nil when absent, zero or negative), `rotation`, `obliqueAngle`, `styleName` and the
  `styleOverrides` read from the `DSTYLE` extended data. `computedMeasurement` is the geometric value
  (linear, aligned, radius, diameter); `Drawing.styleVariables(of:)` resolves overrides over the
  `DIMSTYLE` record, and `displayedMeasurement(of:)` applies `DIMLFAC`. `DimensionText` splits the
  override into measurement, number, words, line-break and stack parts, with the codes decoded as
  in `MTEXT`. Read by `Reader+Dimension.swift`.
- **Rebuilding dimensions** (`Sources/SwiftDXF/Rebuild/`): `Drawing.rebuildingDimensions(_:)`
  rebuilds `.dimension`s from loose pieces (`Drawing+RebuildDimensions.swift`), starting from each
  value text: `RebuildValue.swift` reads the number (a comma as a decimal mark or thousands
  separator), `RebuildPieces.swift` collects the texts, segments, circles and end marks,
  `RebuildLinear.swift` finds the spans of a dimension line beside a text, `RebuildRadial.swift`
  the diameters and radii, and the scale is inferred per layer group. The result is a
  `DXF.DimensionRebuild` (dimensions with `Dimension.rebuilt` set, `ScaleEstimate`s, `Warning`s)
  that `applied(to:)` adds to the drawing; `dxfdump --rebuild` prints it, and
  `tools/rebuild_corpus.py` summarises a folder of drawings.
- **Curve fit** (`CurveFit.swift`, `CurveFit+Fitting.swift`): `Entity.fitted(tolerance:source:)`,
  `Spline.fitted(tolerance:source:)` and `Drawing.fittedCurve(at:tolerance:)` turn one `SPLINE` or
  `ELLIPSE` into a `DXF.CurveFit` of `Contour.Segment` pieces (each stamped with the entity's
  `Identity`) plus the deviation achieved. It runs the contour layer's `SegmentExtractor`, so the
  two agree; `Contours/SplineRecognition.swift` recognises a spline that is exactly a line or arc.
- **Contour layer** (in `SwiftDXF`, `Sources/SwiftDXF/Contours/`): `drawing.contours(_:)` returns a
  `DXF.Contour.Result` of `Shape`s (a counter-clockwise outer `Loop` plus clockwise hole `Loop`s),
  leftover open `Chain`s and `Warning`s, in millimetres. `Segment` is a line or arc as chord plus
  bulge (never more than a half turn). Pieces: `SegmentExtractor` (entity to segments),
  `CurveFitter` (ellipse and spline to lines and arcs within `fitTolerance`; the circle through
  three points is `Circumcircle`), `ContourChainer`
  (grid-hash endpoint merge, loop tracing), `ContourNesting` with `LoopIndex` (even-odd island
  nesting). Pure Swift and OCCT-free: OCCT consumers belong in OCCTSwiftIO. Known limits are in the
  README (entities on a tilted plane are read as written, `INSERT` flattened only on request).
- **`dxfdump`** (executable): CLI that reads a `.dxf` and dumps its version, counts, and entities;
  `--contours` prints the contour summary as JSON; `--texts` prints each text string as it reads,
  with its stacks; `--rebuild [--scale N]` prints the dimensions rebuilt from loose pieces, the
  scales and the warnings; `--expand`, `--expand-attributes` and `--skip-paper-space` read with
  those `ReadOptions`; `--attributes` prints the attributes and definitions, for
  `tools/attrib_oracle.py`.
