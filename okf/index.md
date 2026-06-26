---
type: repo
title: SwiftDXF
resource: https://github.com/SecondMouseAU/SwiftDXF
tags: [dxf, autocad, 2d, import, drawing, swift]
description: Native-Swift reader for ASCII DXF — 2D model-space geometry into a neutral Sendable model.
timestamp: 2026-06-26
---

# SwiftDXF

A small, dependency-free **native-Swift reader for ASCII DXF** — AutoCAD's *Drawing Interchange
Format* — that lifts model-space 2D geometry (lines, arcs, circles, polylines, text, …) from the
`ENTITIES` section into a neutral, `Sendable` value model, plus a **`dxfdump`** CLI. Clean-room,
MIT-licensed, and validated bit-for-bit against the `ezdxf` reference reader.

## Role in the ecosystem

- **Cluster:** kernel
- **Depends on:** nothing (leaf — pure Swift)
- **Feeds products:** 2D DXF import for the OCCTSwift CAD I/O stack (sibling of SwiftJWW on the
  drawing-import side).

## Components

See [`components/`](components/index.md) for the public surface.

## References

See [`references/`](references/index.md) for the DXF format and reference reader.

## Policies

- [Query `context` first for OCCT / OCCTSwift docs](policies/context-first.md)
