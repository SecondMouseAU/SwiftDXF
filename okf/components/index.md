---
type: component
title: Components index
resource: https://github.com/SecondMouseAU/SwiftDXF
tags: [index]
description: Public modules / API surfaces exposed by SwiftDXF.
timestamp: 2026-06-26
---

# Components

- **`SwiftDXF`** (library) — `DXF.read(contentsOf:)` parses an ASCII DXF file into a `Sendable`
  drawing model: the DXF version, entity counts, and the model-space `DXF.Entity` cases
  (line, arc, circle, polyline, text, spline, …) with their layer. Unmodelled entity types
  are tallied in `Drawing.skipped` / `skippedByLayer`; `DXF.Spline.flattened(tolerance:)` turns a
  spline into polyline points.
- **`dxfdump`** (executable) — CLI that reads a `.dxf` and dumps its version, counts, and entities.
