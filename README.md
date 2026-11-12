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
| `DIMENSION` | `.dimension(Dimension)`: definition points, rotation, style and text parts; not the rendered arrow/text glyphs |
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

### Dimensions

```swift
for case .dimension(let d) in dwg.entities {
    d.measurement          // the stored value, or nil: group 42 absent, 0 or negative means "not stored"
    d.computedMeasurement  // from the definition points and rotation (linear, aligned, radius, diameter)
    d.measuredValue        // stored if present, else computed
    d.rotation             // group 50, degrees; nil means 0. d.obliqueAngle is group 52
    d.text                 // DimensionText: placeholder, typed numbers, unit, qualifiers, words
    dwg.style(of: d)       // DIMSTYLE precision, suffix and linear scale, with the entity's own overrides
}
```

Writers such as SolidWorks leave the value for the viewer to compute: group 42 is `-1` and the
text is `<>`. `rawMeasurement` keeps the `-1` verbatim; `measurement` reports it as missing, so it
can never be mistaken for a length. `DimensionText` separates a decorated default (`<> mm`), a
label (`<>\PBore Size`), a limit (`67 mm\P(max)`), a range (`40 - 60 mm\P(Adjustable)`) and a
note. Style fields the file does not carry (`decimals`, `suffix`, `linearScale`) are `nil`, not
guessed. Angular and ordinate dimensions have no computed value yet. `dxfdump --dimensions` prints
one JSON row per dimension.

### Blocks, hatches, leaders, layers and line types

```swift
let dwg = try DXF.read(contentsOf: url, options: .init(expandBlocks: true))
dwg.references          // every INSERT of the ENTITIES section: block name, placement, array
dwg.blocks["Title"]     // a block definition: base point, entities, nested references
dwg.hatches             // boundary loops, pattern name, solid or not
dwg.leaders             // vertices, arrowhead, annotation handle (look it up with index(ofHandle:))
dwg.layers              // LAYER table: colour, line type, off, frozen, locked
dwg.lineTypeTable       // LTYPE table: dash pattern
dwg.lineTypeName(at: i) // entity i's line type, resolved through its layer when by-layer
```

With `expandBlocks: true` every reference is flattened into `entities`, `hatches` and `leaders`:
nested blocks, scale, rotation, mirroring, an extrusion of `-z`, and the array form are carried
through. A circle or arc under a non-uniform scale becomes an ellipse; a polyline with bulges
under one is dropped and reported. An entity on layer `0` takes the reference's layer, and
`BYBLOCK` colour and line type take the reference's. `identities[i].via` lists the references an
entity came through (`blocks` their names), so a title block can be kept or dropped by name.
`drawing.warnings` reports missing blocks, cycles, and anything a transform could not carry.

Expansion is off by default: `INSERT` stays in `skipped` and the entities are exactly what they
were. Hatches and leaders are always read, into `hatches` and `leaders`, and stay listed in
`skipped` because they have no `Entity` case. Validated against ezdxf's own recursive flattening
on the McMaster drawings and an external library of block-heavy drawings (per-type counts and a
coordinate digest).

### Entity identity

`dwg.identities[i]` identifies `dwg.entities[i]`: the DXF handle (group 5, upper case) when the
file has one, else the position as `ENTITIES[n]`, where `n` counts every record of the section,
modelled or skipped, so it does not move when a new entity type is modelled. A `POLYLINE` takes the
identity of its header. `EntityIdentity.via` holds the references an entity was expanded from.
Reading the same file twice gives the same identities.

### Fitting splines and ellipses

```swift
for fit in dwg.fittedCurves(tolerance: 0.01) {   // drawing units
    fit.entityIndex, fit.identity, fit.layer     // the entity the pieces came from
    fit.segments                                 // DXF.Contour.Segment: lines and arcs, in order
    fit.deviation                                // upper bound on the distance to the exact curve
    fit.recognized                               // .line, .arc(center:radius:) or .curve
}
```

A spline that is exactly a line or one circle comes out as one piece and is recognised as such.
`Entity.fitted(tolerance:)` does one entity. `dxfdump --fit 0.01 file.dxf` summarises a file.

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
- **Paper space.** Entities flagged group 67 are read into `entities` as they always were, and
  counted in `drawing.paperSpace`; `ReadOptions(skipPaperSpace: true)` leaves them out, as
  `ezdxf`'s `modelspace()` does. A layout title block otherwise lands in the entities.
- **Model space.** `ENTITIES` is read as written; `BLOCKS` definitions are read into
  `Drawing.blocks` and expanded only when asked (see above). OCS extrusion of arcs, circles and
  polylines is not applied (SwiftDXF#21).

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
