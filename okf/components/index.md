---
type: component
title: Components index
resource: https://github.com/SecondMouseAU/SwiftDXF
tags: [index]
description: Public modules / API surfaces exposed by SwiftDXF.
timestamp: 2026-10-24
---

# Components

- **`SwiftDXF`** (library): `DXF.read(contentsOf:)` parses an ASCII DXF file into a `Sendable`
  drawing model: the DXF version, entity counts, and the model-space `DXF.Entity` cases
  (line, arc, circle, polyline, text, spline, …) with their layer. `DXF.Dimension` carries
  rotation, style name and overrides, a computed measurement and `DimensionText` parts;
  `Drawing.identities` gives each entity its handle or position; `Drawing.dimensionStyles` is the
  `DIMSTYLE` table. `ReadOptions(expandBlocks:)` flattens `INSERT`s (`BlockExpansion`,
  `Transform`) into entities with provenance in `EntityIdentity.via`; `Drawing.blocks`,
  `references`, `hatches`, `leaders`, `layers`, `lineTypeTable` and `warnings` carry the rest of
  what real drawings hold. Unmodelled entity types
  are tallied in `Drawing.skipped` / `skippedByLayer`; `DXF.Spline.flattened(tolerance:)` turns a
  spline into polyline points.
- **Contour layer** (in `SwiftDXF`, `Sources/SwiftDXF/Contours/`): `drawing.contours(_:)` returns a
  `DXF.Contour.Result` of `Shape`s (a counter-clockwise outer `Loop` plus clockwise hole `Loop`s),
  leftover open `Chain`s and `Warning`s, in millimetres. `Segment` is a line or arc as chord plus
  bulge (never more than a half turn). Pieces: `SegmentExtractor` (entity to segments),
  `CurveFitter` (ellipse and spline to lines and arcs within `fitTolerance`), `ContourChainer`
  (grid-hash endpoint merge, loop tracing), `ContourNesting` with `LoopIndex` (even-odd island
  nesting). Pure Swift and OCCT-free: OCCT consumers belong in OCCTSwiftIO. Known limits are in the
  README (no OCS/extrusion, no `INSERT` expansion).
- **Curve fitting** (`Contours/FittedCurve.swift`): `drawing.fittedCurves(tolerance:)` turns each
  spline and ellipse into lines and arcs within a tolerance, with its source entity and a
  `.line` / `.arc` / `.curve` recognition, reusing `SegmentExtractor` and `CurveFitter`.
- **`dxfdump`** (executable): CLI that reads a `.dxf` and dumps its version, counts, and entities;
  `--contours` prints the contour summary as JSON; `--dimensions`, `--expand` and `--fit TOL` print
  dimension rows, the block-expanded digest and a curve-fit summary.
