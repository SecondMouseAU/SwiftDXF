---
type: component
title: Components index
resource: https://github.com/SecondMouseAU/SwiftDXF
tags: [index]
description: Public modules / API surfaces exposed by SwiftDXF.
timestamp: 2026-11-12
---

# Components

- **`SwiftDXF`** (library): `DXF.read(contentsOf:)` parses an ASCII DXF file into a `Sendable`
  drawing model: the DXF version, entity counts, and the model-space `DXF.Entity` cases
  (line, arc, circle, polyline, text, spline, …) with their layer. `DXF.Dimension` carries
  rotation, style name and overrides, a computed measurement and `DimensionText` parts;
  `Drawing.identities` gives each entity its handle or position; `Drawing.dimensionStyles` is the
  `DIMSTYLE` table. Unmodelled entity types are tallied in `Drawing.skipped` / `skippedByLayer`;
  `DXF.Spline.flattened(tolerance:)` turns a spline into polyline points.
- **Block references** (`BlockReference.swift`, `BlockExpansion.swift`, `Transform.swift`,
  `Entity+Transform.swift`, `Reader+Blocks.swift`): `INSERT` is read into `Drawing.references` and
  `Block.references`. `DXF.read(_:options:)` with `ReadOptions(expandBlocks: true)` flattens every
  reference into the entities (nested blocks, scale, rotation, mirroring, arrays), with the
  references it came through in `Identity.via` and what it could not do in `Drawing.warnings`.
  `ReadOptions(skipPaperSpace:)` leaves out group-67 entities, which `Drawing.paperSpace` counts.
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
- **Dimensions** (`Dimension.swift`, `Dimension+Computed.swift`, `DimensionText.swift`,
  `DimensionStyleVariables.swift`, `Drawing+Dimensions.swift`): `Dimension` carries the stored
  `measurement` (nil when absent, zero or negative), `rotation`, `obliqueAngle`, `styleName` and the
  `styleOverrides` read from the `DSTYLE` extended data. `computedMeasurement` is the geometric value
  (linear, aligned, radius, diameter); `Drawing.styleVariables(of:)` resolves overrides over the
  `DIMSTYLE` record, and `displayedMeasurement(of:)` applies `DIMLFAC`. `DimensionText` splits the
  override into measurement, number, words and line-break parts. Read by `Reader+Dimension.swift`.
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
  README (no OCS/extrusion on entities, `INSERT` flattened only on request).
- **`dxfdump`** (executable): CLI that reads a `.dxf` and dumps its version, counts, and entities;
  `--contours` prints the contour summary as JSON; `--expand` and `--skip-paper-space` read with
  those `ReadOptions`.
