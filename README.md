# SwiftDXF

[![Swift](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FSecondMouseAU%2FSwiftDXF%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/SecondMouseAU/SwiftDXF)
[![Platforms](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FSecondMouseAU%2FSwiftDXF%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/SecondMouseAU/SwiftDXF)

A small, dependency-free **Swift reader for ASCII DXF**: AutoCAD's *Drawing Interchange Format*,
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
| `LWPOLYLINE`, `POLYLINE`/`VERTEX` | `.polyline(vertices, closed, …)`: each vertex carries its **bulge** |
| `DIMENSION` | `.dimension(Dimension)`: semantic measurement only, not the rendered arrow/text glyphs |
| `SPLINE` | `.spline(Spline)`: degree, flags, control points, knots, weights, fit points; flattens to a polyline |

Entities it does not model (e.g. `INSERT`, `HATCH`, `SOLID`) are **skipped, not fatal**, and
reported on the drawing (see below).

### Skipped entities

```swift
let dwg = try DXF.read(contentsOf: url)
dwg.skipped          // ["INSERT": 3, "HATCH": 1]  type name -> count
dwg.skippedByLayer   // ["INSERT": ["PARTS": 3], "HATCH": ["0": 1]]  type -> layer -> count
```

An empty `skipped` means nothing in `ENTITIES` was dropped. `dxfdump` prints the same table to
stderr and includes both dictionaries in its JSON. The counts match `ezdxf`'s per-type counts for
every type SwiftDXF does not model.

### Splines

```swift
for case .spline(let s) in dwg.entities {
    s.degree, s.isClosed, s.controlPoints, s.knots, s.weights, s.fitPoints
    let pts = s.flattened(tolerance: 0.01)   // [DXF.Point], within 0.01 of the exact curve
    let line = s.asPolyline(tolerance: 0.01) // DXF.Entity.polyline, same layer and colour
}
```

`flattened(tolerance:)` evaluates the rational B-spline exactly (clamped or periodic knots, weights
honoured) and subdivides each knot span until its sampled deviation from the chord is within the
tolerance. Fallbacks, so malformed data never traps:

- Degree is clamped to `1...(controlPoints.count - 1)`.
- A knot vector that is not `count + degree + 1` finite, non-decreasing values with a non-empty
  domain is replaced by a clamped uniform one.
- Weights that are not exactly one positive finite value per control point are ignored.
- With **no control points**, a uniform Catmull-Rom curve through the fit points is used. It passes
  through every fit point but does not reproduce a file's own tangent data.
- A closed spline whose flattened end differs from its start gets the start appended.
- Fewer than two control points returns what is there; `point(at:)` returns `nil`.

`Drawing` also exposes header essentials: `version` (`$ACADVER`), `insUnits` (`$INSUNITS`), and the
declared `extMin` / `extMax` extents (`$EXTMIN` / `$EXTMAX`), plus a computed `bounds` over the
entities actually read.

### Behaviours worth knowing

- **Encoding.** Files are decoded as UTF-8 when valid, otherwise **CP932 / Shift-JIS**: the common
  code page for DXF exported by Japanese CAD tools (e.g. Jw_cad). Because CP932 is an ASCII superset,
  the group-code structure is unaffected either way. AutoCAD `\U+XXXX` text escapes are decoded.
- **Line endings & padding.** Handles LF / CRLF / CR and R12-style space-padded group codes (`  0`).
- **Ellipse normalisation.** DXF requires `ratio = minor/major ≤ 1`. Files that emit `ratio > 1`
  (a swapped major axis) are normalised to the canonical form (same curve, valid axis), so consumers
  like OCCT's `Geom_Ellipse` (which demands `majorRadius ≥ minorRadius`) get correct geometry. This
  matches `ezdxf`'s normalisation exactly.
- **Binary DXF** is detected and rejected (`Error.binaryUnsupported`): convert to ASCII DXF first.
- **Model space only.** Mirrors what `ezdxf`'s `modelspace()` iterates; `BLOCKS` definitions are not
  expanded.

## Contours

`drawing.contours(_:)` turns the loose entities of a drawing into closed regions: the OCCT-free work
every consumer otherwise repeats (joining lines and arcs into loops, nesting islands and holes,
applying units, approximating ellipses and splines). It adds no dependencies and returns plain
`Sendable` values in **millimetres**.

```swift
let result = try DXF.read(contentsOf: url).contours(.init(layers: ["CUT"]))
for shape in result.shapes {            // largest outer area first
    shape.outer                         // counter-clockwise DXF.Contour.Loop
    shape.holes                         // clockwise loops
    shape.area, shape.bounds            // outer minus holes; exact bounds
}
result.openChains                       // segments that never closed
result.warnings                         // see below
```

A `DXF.Contour.Segment` is a line or a circular arc stored as `start`, `end` and a DXF `bulge`
(`tan(sweep / 4)`, positive counter-clockwise), with `center`, `radius`, `startAngle`, `sweep`,
`length` and exact `bounds` (arc extrema included) derived from it. Arcs never sweep more than a
half turn, so a circle is two segments and a 270 degree arc is two. A `Loop` is a closed chain with
`signedArea`, `area`, `bounds`, `length` and the source `layers`.

| Entity | Becomes |
|---|---|
| `LINE`, `ARC`, `CIRCLE` | exact lines and arcs |
| `LWPOLYLINE`, `POLYLINE` | exact lines and arcs from the bulges (`closed` adds the closing segment) |
| `ELLIPSE` with ratio 1 | exact arcs |
| other `ELLIPSE`, `SPLINE` | sampled, then fitted with lines and circular arcs |
| `TEXT`, `DIMENSION`, `POINT` | ignored, with a warning |
| `INSERT` and unmodelled types | not read, with a warning |

Options (`DXF.Contour.Options`), all tolerances in millimetres:

- `layers`, `excludedLayers`: filter by layer name, case-insensitively.
- `joinTolerance` (default `0.01`): endpoints closer than this are one point.
- `fitTolerance` (default `0.01`): how far a fitted line or arc may stray from the curve.
- `units`: force the drawing's units; otherwise `$INSUNITS` is used. `unitlessFallback` (default
  millimetres) applies when the file declares none, and a warning says so.
- `nesting`: `.evenOdd` (default) or `.outermostOnly`.

How it works:

- **Chaining.** Endpoints are merged through a grid hash, so the cost is linear in the segment
  count. Order and direction of the input do not matter, repeated segments collapse, a branch hanging
  off a loop is split off as an open chain, and loops that touch at a point stay separate.
- **Nesting.** A loop is inside another when probe points taken from it lie inside the other by the
  even-odd rule (a loop inside one loop is a hole, inside two is an island, and so on). The test
  handles arcs, skips probes that sit on the other loop's boundary, and uses a per-loop index so a
  30,000 segment outline is not rescanned for every hole.
- **Fitting.** Ellipses and splines are sampled so every chord is within a quarter of
  `fitTolerance`, then covered greedily by the longest line or arc that stays within half of it.
  `result.maxFitDeviation` is an upper bound on the distance to the true curve and never exceeds
  `fitTolerance`; the tests measure the true deviation against the exact curve.
- **Warnings** (`result.warnings`): `unitlessAssumed`, `unknownUnitCode`, `skippedEntities`,
  `blockReferencesNotExpanded`, `ignoredText`, `ignoredDimensions`, `ignoredPoints`,
  `fittedCurves`, `openChains`, `degenerateGeometry`, `coincidentLoops`, `crossingLoops`,
  `nestedLoopsDropped`.

Limits:

- Geometry is projected onto the XY plane; `z` is ignored.
- The extrusion direction (OCS) is not read, so entities on a mirrored plane such as
  `(0, 0, -1)` come out un-mirrored ([#21](https://github.com/SecondMouseAU/SwiftDXF/issues/21)).
- `INSERT` blocks are not expanded ([#5](https://github.com/SecondMouseAU/SwiftDXF/issues/5)).
- Loops are assumed not to cross. Loops that do are reported (`crossingLoops`) and left unnested.
  Collinear segments that overlap only in part are not merged.
- Nesting compares bounding boxes pairwise, so it is quadratic in the number of loops (tens of
  thousands of loops are fine; millions are not).

`dxfdump --contours [--layers A,B] [--units inch|mm] file.dxf` prints the same summary as JSON.

## Correctness: tested against an oracle

`tools/oracle.py` runs `ezdxf` over the same files and emits per-file entity counts **and** a
geometry digest (the sum of every defining coordinate scalar, in document order). The `dxfdump`
executable emits the identical shape from SwiftDXF:

```bash
swift run dxfdump drawing.dxf | python3 -m json.tool
```

SPLINE control data and NURBS evaluation are checked against `ezdxf` on fixtures it wrote
(`Tests/SwiftDXFTests/Fixtures/`, generated by `tools/spline_fixtures.py`): clamped, rational,
3D and periodic cases. Flattening deviation is asserted against dense exact evaluation. The contour layer is tested on
fixtures from `tools/contour_fixtures.py` with analytic areas and bounds, and its fitted ellipses
and splines are measured against the exact curves.

Across an 11-file corpus (~62,000 entities, mixed R12 drawings incl. Jw_cad exports), SwiftDXF
matches `ezdxf` **exactly**: every entity count and every coordinate scalar, to the bit. The
`Tests/SwiftDXFTests/CorpusOracleTests.swift` suite pins those ezdxf-derived counts as a regression
gate (skipped when the corpus is absent; point `DXF_CORPUS` at a folder of `.dxf` files to run).

## Install

```swift
.package(url: "https://github.com/SecondMouseAU/SwiftDXF.git", from: "0.1.0"),
// target dependency: .product(name: "SwiftDXF", package: "SwiftDXF")
```

## Scope

A focused 2D reader, not a full DXF/DWG toolkit. Out of scope for now: DWG, binary DXF, block/insert
expansion, hatches, OCS/extrusion, and writing. (DXF *writing* for the JWW format lives in
[SwiftJWW](https://github.com/SecondMouseAU/SwiftJWW).)

## License

MIT: see [LICENSE](LICENSE).
