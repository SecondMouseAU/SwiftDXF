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
| `HATCH` | `.hatch(Hatch)`: pattern name, solid fill, and the boundary paths (polyline and edge types) |
| `LEADER` | `.leader(Leader)`: vertices, arrowhead, and the handle of the annotation it points at |

Entities it does not model (e.g. `INSERT`, `SOLID`) are **skipped, not fatal**, and
reported on the drawing (see below).

### Skipped entities

```swift
let dwg = try DXF.read(contentsOf: url)
dwg.skipped          // ["INSERT": 3, "SOLID": 1]  type name -> count
dwg.skippedByLayer   // ["INSERT": ["PARTS": 3], "SOLID": ["0": 1]]  type -> layer -> count
```

An empty `skipped` means nothing in `ENTITIES` was dropped. `dxfdump` prints the same table to
stderr and includes both dictionaries in its JSON. The counts match `ezdxf`'s per-type counts for
every type SwiftDXF does not model.

### Identity

```swift
let dwg = try DXF.read(contentsOf: url)
for (i, entity) in dwg.entities.enumerated() {
    let id = dwg.identity(ofEntityAt: i)
    id.handle    // "3A": the DXF handle (group 5) as the file writes it, or nil
    id.locator   // "ENTITIES:4": section and position, always present
    id.id        // the handle when there is one, otherwise the locator
}
```

`dwg.identities` holds one `DXF.Identity` per entry in `dwg.entities`, in the same order. Reading the
same file twice gives the same identities, and the handles are the ones `ezdxf` reports, so an
entity can be named in a ledger and found again in the original file or in another program.

The locator counts **every** record in its section, including the ones SwiftDXF skips, so an
entity keeps its locator when a later release starts reading another type. A file with no handles
(some R12 files) is still fully identified by its locators. An old-style `POLYLINE` is one record:
its handle and position are the header's, not its `VERTEX` records'.

Blocks and tables carry identities too:

| Property | Holds |
|---|---|
| `dwg.blocks` | each `BLOCKS` definition: `name`, `handle`, `basePoint`, and its own `entities` with `identities` (locators read `BLOCKS:<block>/<n>`) |
| `dwg.layers`, `dwg.lineTypes` | the `LAYER` and `LTYPE` records: `name` and `handle` |
| `dwg.dimensionStyles` | the `DIMSTYLE` records: `name` and `handle` (group 105) |

`INSERT` references are still not expanded ([#5](https://github.com/SecondMouseAU/SwiftDXF/issues/5)).

### Hatches, leaders, line types and layers

What an outline *means* on an engineering drawing: a hatched region in a section view is cut
material, a hidden or centre line is not an edge you can see, a leader ties a note to a feature,
and a layer that is off is not part of the drawing.

```swift
for case .hatch(let h) in dwg.entities {
    h.patternName, h.isSolid                  // "ANSI31", false
    for path in h.paths {
        path.isExternal                       // outer boundary; inner loops are islands or holes
        switch path.geometry {
        case .polyline(let vertices, let closed): break     // vertices carry bulges
        case .edges(let edges): break    // .line, .arc, .ellipse, .spline
        }
    }
}
for case .leader(let l) in dwg.entities {
    l.vertices, l.hasArrowhead
    l.annotationHandle                        // the Identity.handle of the text it is attached to
}
```

Hatch boundary paths are read, not the hatch lines. A clockwise arc or ellipse edge is stored in
the file as complementary angles; the reader converts it to counter-clockwise angles, as `ezdxf`
does, and keeps `counterClockwise` for the direction the path travels it. An ellipse edge is
given as `startParam` / `endParam` in radians, like an `ELLIPSE` entity. A spline edge is a
`DXF.Spline`, so it flattens like one. Malformed counts never trap: the paths that are present are
returned.

Line types and layers come from the `LTYPE` and `LAYER` tables:

```swift
dwg.lineType(named: "HIDDEN")?.pattern      // [0.25, -0.125]: dash, then gap
dwg.layer(named: "walls")?.isVisible        // false when the layer is off or frozen
dwg.lineTypeName(ofEntityAt: i)             // group 6 as written, nil when absent
dwg.effectiveLineType(ofEntityAt: i)        // "HIDDEN": BYLAYER and BYBLOCK resolved
dwg.isVisible(entityAt: i)                  // on a layer that is on and not frozen
```

`effectiveLineType` takes an entity with no line type, or `BYLAYER`, from its layer. `BYBLOCK` is
`Continuous` in model space, which has no block to take it from. A `Layer` carries `color`,
`lineTypeName`, `isOff` (a negative colour), `isFrozen` and `isLocked`. A `LineType` carries
`pattern` (positive dash, negative gap, zero dot), `patternLength` and `description`. A block's
entities keep their line type names in `Block.entityLineTypes`.

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
| `TEXT`, `DIMENSION`, `POINT`, `HATCH`, `LEADER` | ignored, with a warning |
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
  `ignoredHatches`, `ignoredLeaders`, `fittedCurves`, `openChains`, `degenerateGeometry`,
  `coincidentLoops`, `crossingLoops`, `nestedLoopsDropped`.

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
expansion, OCS/extrusion, and writing. (DXF *writing* for the JWW format lives in
[SwiftJWW](https://github.com/SecondMouseAU/SwiftJWW).)

## License

MIT: see [LICENSE](LICENSE).
