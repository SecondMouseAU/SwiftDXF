# SwiftDXF

A small, dependency-free **Swift reader for ASCII DXF** — AutoCAD's *Drawing Interchange Format* —
that lifts model-space 2D geometry into a neutral, `Sendable` value model. Clean-room, **MIT**-licensed,
and validated bit-for-bit against the MIT-licensed [`ezdxf`](https://ezdxf.mozman.at/) reference reader.

```swift
import SwiftDXF

let dwg = try DXF.read(contentsOf: url)
print(dwg.version)          // e.g. "AC1009" (R12)
print(dwg.counts.total)     // entities read
for case let .line(a, b, layer, _) in dwg.entities {
    print(layer, a, b)
}
```

## What it reads

The 2D entity set that dominates real-world drawings, from the `ENTITIES` (model-space) section:

| DXF entity | `DXF.Entity` case |
|---|---|
| `LINE` | `.line(a, b, layer, color)` |
| `CIRCLE` | `.circle(center, radius, …)` |
| `ARC` | `.arc(center, radius, startDeg, endDeg, …)` |
| `ELLIPSE` | `.ellipse(center, majorAxis, ratio, startParam, endParam, …)` |
| `POINT` | `.point(at, …)` |
| `TEXT`, `MTEXT` | `.text(at, height, rotationDeg, string, …)` |
| `LWPOLYLINE`, `POLYLINE`/`VERTEX` | `.polyline(points, closed, …)` |

Entities it does not model (e.g. `INSERT`, `SPLINE`, `HATCH`, `DIMENSION`) are **skipped, not fatal**.

### Behaviours worth knowing

- **Encoding.** Files are decoded as UTF-8 when valid, otherwise **CP932 / Shift-JIS** — the common
  code page for DXF exported by Japanese CAD tools (e.g. Jw_cad). Because CP932 is an ASCII superset,
  the group-code structure is unaffected either way. AutoCAD `\U+XXXX` text escapes are decoded.
- **Line endings & padding.** Handles LF / CRLF / CR and R12-style space-padded group codes (`  0`).
- **Ellipse normalisation.** DXF requires `ratio = minor/major ≤ 1`. Files that emit `ratio > 1`
  (a swapped major axis) are normalised to the canonical form — same curve, valid axis — so consumers
  like OCCT's `Geom_Ellipse` (which demands `majorRadius ≥ minorRadius`) get correct geometry. This
  matches `ezdxf`'s normalisation exactly.
- **Binary DXF** is detected and rejected (`Error.binaryUnsupported`) — convert to ASCII DXF first.
- **Model space only.** Mirrors what `ezdxf`'s `modelspace()` iterates; `BLOCKS` definitions are not
  expanded.

## Correctness: tested against an oracle

`tools/oracle.py` runs `ezdxf` over the same files and emits per-file entity counts **and** a
geometry digest (the sum of every defining coordinate scalar, in document order). The `dxfdump`
executable emits the identical shape from SwiftDXF:

```bash
swift run dxfdump drawing.dxf | python3 -m json.tool
```

Across an 11-file corpus (~62,000 entities, mixed R12 drawings incl. Jw_cad exports), SwiftDXF
matches `ezdxf` **exactly** — every entity count and every coordinate scalar, to the bit. The
`Tests/SwiftDXFTests/CorpusOracleTests.swift` suite pins those ezdxf-derived counts as a regression
gate (skipped when the corpus is absent; point `DXF_CORPUS` at a folder of `.dxf` files to run).

## Install

```swift
.package(url: "https://github.com/SecondMouseAU/SwiftDXF.git", from: "0.1.0"),
// target dependency: .product(name: "SwiftDXF", package: "SwiftDXF")
```

## Scope

A focused 2D reader, not a full DXF/DWG toolkit. Out of scope for now: DWG, binary DXF, block/insert
expansion, splines, hatches, dimensions, and writing. (DXF *writing* for the JWW format lives in
[SwiftJWW](https://github.com/SecondMouseAU/SwiftJWW).)

## License

MIT — see [LICENSE](LICENSE).
