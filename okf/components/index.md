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
  (line, arc, circle, polyline, text, spline, …) with their layer. Unmodelled entity types
  are tallied in `Drawing.skipped` / `skippedByLayer`; `DXF.Spline.flattened(tolerance:)` turns a
  spline into polyline points.
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
- **Contour layer** (in `SwiftDXF`, `Sources/SwiftDXF/Contours/`): `drawing.contours(_:)` returns a
  `DXF.Contour.Result` of `Shape`s (a counter-clockwise outer `Loop` plus clockwise hole `Loop`s),
  leftover open `Chain`s and `Warning`s, in millimetres. `Segment` is a line or arc as chord plus
  bulge (never more than a half turn). Pieces: `SegmentExtractor` (entity to segments),
  `CurveFitter` (ellipse and spline to lines and arcs within `fitTolerance`), `ContourChainer`
  (grid-hash endpoint merge, loop tracing), `ContourNesting` with `LoopIndex` (even-odd island
  nesting). Pure Swift and OCCT-free: OCCT consumers belong in OCCTSwiftIO. Known limits are in the
  README (no OCS/extrusion, no `INSERT` expansion).
- **`dxfdump`** (executable): CLI that reads a `.dxf` and dumps its version, counts, and entities;
  `--contours` prints the contour summary as JSON.
