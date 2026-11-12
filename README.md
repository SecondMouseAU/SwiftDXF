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
| `DIMENSION` | `.dimension(Dimension)`: what it measures and how it is stated, not the rendered arrow/text glyphs |
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
entity keeps its locator when a later release starts reading another type (unless that type owns
the records after it, as a `POLYLINE` owns its `VERTEX` records). A file with no handles
(some R12 files) is still fully identified by its locators. An old-style `POLYLINE` is one record:
its handle and position are the header's, not its `VERTEX` records'.

Blocks and tables carry identities too:

| Property | Holds |
|---|---|
| `dwg.blocks` | each `BLOCKS` definition: `name`, `handle`, `basePoint`, and its own `entities` with `identities` (locators read `BLOCKS:<block>/<n>`) |
| `dwg.layers`, `dwg.lineTypes` | the `LAYER` and `LTYPE` records: `name` and `handle` |
| `dwg.dimensionStyles` | the `DIMSTYLE` records: `name` and `handle` (group 105) |

An entity that came out of an expanded block reference (see below) also carries `via`, the
references it came through, and `blocks`, their names. Its `id` then reads like `8E/31`: the
reference `8E`, then the entity `31` inside the block.

`identities` and `entityLineTypes` run parallel to `entities`, so changing `entities` clears
them: `identity(ofEntityAt:)` then names each entity by its position and
`lineTypeName(ofEntityAt:)` returns `nil`, rather than hand back a stale entry. Set them again
afterwards if they still line up. A position outside `entities` gets a locator too.

### Block references and paper space

```swift
let dwg = try DXF.read(contentsOf: url, options: .init(expandBlocks: true, skipPaperSpace: true))
dwg.references   // every INSERT of ENTITIES: name, insertion, scale, rotation, array, extrusion
dwg.warnings     // [.missingBlock(name: "GONE", count: 1), ...]
dwg.paperSpace   // ["LINE": 12, "TEXT": 3]  entities flagged as paper space (group 67), by type
```

`INSERT` is always read into `dwg.references` (and `Block.references` inside a block). By default
nothing is flattened: the geometry a reference places stays out of `entities`, and the `INSERT`
stays in `dwg.skipped`, as before. With `expandBlocks: true` every top-level reference is flattened
into `dwg.entities`:

- Nested blocks, scale (also non-uniform), rotation, mirroring (a negative scale, or an extrusion
  of `(0, 0, -1)`) and the array form (`columns`, `rows`, spacing along the rotated axes) are
  carried through. A circle or arc under a non-uniform scale becomes an ellipse.
- An entity on layer `0` takes the reference's layer, and `BYBLOCK` colour and line type take the
  reference's. `entityLineTypes` holds the result.
- Each expanded entity's `identity.via` names the references it came through, outermost first (the
  handle, or the locator when there is none, with `[column,row]` for an array), and
  `identity.blocks` their names. A block drawn twice gives two entities with different identities.
- Expanded references leave `dwg.skipped`; what a block holds that has no entity form (a `SOLID`)
  is added to it once per instance. A reference to a block the file does not define stays in
  `skipped`.
- `counts`, `bounds`, `identities` and `entityLineTypes` follow the expanded entities.

`dwg.warnings` says what an expansion could not do: `missingBlock`, `blockCycle` (a block that
contains itself; the inner reference is dropped), `blockNestingTooDeep` (more than 32 levels),
`unsupportedExtrusion` (an extrusion that is not along z, expanded as if it were),
`expansionTruncated` (a file can multiply entities without bound, so expansion stops after about two
million) and `notTransformed` (a polyline or hatch path with bulges cannot pass a non-uniform scale, because its
arcs would become ellipses; it is dropped and counted).

Entities flagged as paper space (group 67) are counted in `dwg.paperSpace` and read into `entities`
as before. `skipPaperSpace: true` leaves them out, as `ezdxf`'s `modelspace()` does, and keeps the
locators of the rest. Expansion was checked against `ezdxf` on a drawing with nested, arrayed,
rotated, mirrored and non-uniformly scaled references: every one of the 56 expanded entities is the
same curve.

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

### Fitting one curve

A consumer that reads entities, not contours, can turn one `SPLINE` or `ELLIPSE` into lines and
arcs it can build with:

```swift
if case .spline(let s) = dwg.entities[i] {
    let fit = s.fitted(tolerance: 0.001)    // drawing units
    for piece in fit.pieces {
        piece.segment                       // DXF.Contour.Segment: a line, or an arc as chord + bulge
        piece.source                        // the entity's Identity, when you name it
    }
    fit.deviation                           // the tolerance or less, for a smooth curve
    fit.isExact                             // the curve is a line or arc, so the pieces are it
}
let named = dwg.fittedCurve(at: i, tolerance: 0.001)   // stamped with dwg.identity(ofEntityAt: i)
```

`entity.fitted(tolerance:source:)` returns `nil` for anything but a spline or an ellipse. The
tolerance is in the drawing's units (millimetres for a drawing in millimetres). This is the fit
`drawing.contours(_:)` makes, so pieces from a drawing's splines close into the same regions the
contour layer finds.

- **Exact lines and arcs.** Many exporters write a straight line or a circle as a spline. A spline
  whose samples all lie on one line (running along it without doubling back), or on one circle
  (turning one way, at most a full turn), within a billionth of its size, comes back as that line
  or arc, with `isExact` set and a deviation that is only rounding. A rational circle or a 270
  degree arc comes back as half-turn arcs. An `ELLIPSE` with equal axes is the same.
- **Everything else** is sampled and covered greedily by the longest line or arc that stays within
  half the tolerance of the samples. The result is then checked against the exact curve at extra
  points between the samples, and sampled again, finer, until it is within the tolerance (at most
  five attempts). `deviation` is the larger of the fit's own bound and what that check measured.
  It can exceed the tolerance if the fit gave up refining, and a fold narrower than a quarter of
  a knot span can escape the check (see Splines), so compare it with the tolerance asked for.
- Degenerate input (fewer than two points, a zero-size ellipse) gives no pieces and does not trap.
  A tolerance that is not positive and finite is clamped to a billionth.

### Dimensions

A `DIMENSION` says what it measures, and how the number is to be stated:

```swift
for case .dimension(let d) in dwg.entities {
    d.measurement                         // the stored value (group 42); nil when absent, 0 or -1
    d.computedMeasurement                 // the value the geometry gives, in drawing units
    d.rotation, d.obliqueAngle            // groups 50 and 52, in degrees
    dwg.displayedMeasurement(of: d)       // computed value times the style's linear scale
    let style = dwg.styleVariables(of: d)
    style.decimalPlaces                   // DIMDEC: 1 if stated to one place, nil if unstated
    style.suppressesTrailingZeros         // DIMZIN: "8.1" may be 8.100 with its zeros hidden
    style.linearScale, style.unitSuffix   // DIMLFAC and DIMPOST
    d.text.showsMeasurement               // does the text show the measured value?
}
```

- **`measurement` is `nil`, not `-1`.** Many writers (every McMaster-Carr sheet checked) store
  `-1` in group 42 and `<>` as the text. A value of zero or below reads as missing.
- **`computedMeasurement`** is the same number for every consumer: for a linear dimension the
  distance between the two extension-line origins along `rotation` (horizontal when absent), for an
  aligned one the distance between them, for a radius or diameter the distance between its two
  definition points. Angular and ordinate dimensions have none. It matches `ezdxf`'s
  `Dimension.get_measurement()`, which also applies no scale. Group 50 absent means horizontal, as
  the DXF default says, and agreed with the direction worked out from the dimension-line point on
  every one of 339 real dimensions checked.
- **Style variables** come from the entity's own overrides in its extended data (`ACAD` /
  `DSTYLE`), then the `DIMSTYLE` record it names. A variable neither states is `nil`: SolidWorks
  styles often leave `DIMDEC` out, and the reader does not guess it. The header's own current
  values are in `dwg.dimensionDefaults` for a caller that wants them as a fallback; they belong to
  whichever style was current when the file was saved, so they are not applied for you. A negative
  `DIMLFAC` applies to paper space only and is ignored.
- **The text** is split into parts: `<>` (the measured value), numbers typed into it, plain words,
  and `\P` line breaks. `<> mm`, `<>\PBore Size`, `67 mm\P(max)`, `40 - 60 mm\P(Adjustable)` and
  `Length is representative\PProduct sold by Length` come out as a decorated value, a label, a
  limit, a range and a note. `d.text.typedNumbers` and `d.text.words` give the pieces;
  `isSuppressed` is the single space that hides the text.

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
- Flattening judges each span from three samples, so a sharp fold or cusp narrower than a quarter
  of a span, such as a control polygon that doubles back on its own line, can fall between them
  and be rounded off.
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
- **Model space.** The `ENTITIES` section is what `ezdxf`'s `modelspace()` iterates. Paper-space
  entities are counted and can be left out, and `BLOCKS` definitions are read and flattened into the
  entities only on request (see *Block references and paper space*).

### Upgrading from 0.3

- **`DXF.Entity` has two new cases**, `.hatch` and `.leader`, so an exhaustive `switch` needs them
  (as `.spline` did in 0.3.0). `HATCH` and `LEADER` no longer appear in `dwg.skipped`.
- **`Dimension.measurement` is `nil`** where the file stores zero or a negative number. SolidWorks
  and McMaster drawings store `-1`, which used to come back as a length. Use
  `computedMeasurement` for the value.
- **Contour warnings.** `.ignoredHatches` and `.ignoredLeaders` are new cases; those entities were
  `.skippedEntities` before. The deviation in `.fittedCurves` is now measured against the exact
  curve, so it can be larger than before, when it was not always a true bound. A spline that is
  exactly a line or arc is emitted as that line or arc.
- **`bounds` and `counts.total` include hatches and leaders**, so the extents of a drawing whose
  `HATCH` lies outside its other geometry grow.
- **`Drawing`, `Block` and the table records** gain stored properties, all defaulted in `init`.
- **`Identity` gains `via` and `blocks`** (empty unless a block was expanded), and `id` includes
  `via`. `DXF.read` gains an `options:` parameter, defaulted so existing calls are unchanged: with
  the defaults the reader returns the same entities as before. `Drawing` gains `references`,
  `warnings` and `paperSpace`, and `Block` gains `references` and `skippedByLayer`.

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
| `SPLINE` that is exactly a line or arc | that line or arc |
| other `ELLIPSE`, `SPLINE` | sampled, then fitted with lines and circular arcs |
| `TEXT`, `DIMENSION`, `POINT`, `HATCH`, `LEADER` | ignored, with a warning |
| `INSERT` | flattened first when the drawing was read with `expandBlocks: true`; otherwise not read, with a warning |
| unmodelled types | not read, with a warning |

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
- **Fitting.** A spline that is exactly a line or arc comes out as that line or arc. Other ellipses
  and splines are sampled so every chord is within a quarter of `fitTolerance`, then covered
  greedily by the longest line or arc that stays within half of it. Each fit is checked against the
  exact curve at extra points between the samples and sampled finer if it strays beyond
  `fitTolerance`. `result.maxFitDeviation` is the larger of the fit's own bound and the measured
  deviation: at most `fitTolerance` for a smooth curve, and the number to compare with it (see
  *Fitting one curve*). The tests measure the true deviation against the exact curve. An ellipse
  so large that `fitTolerance` would need over a million samples is dropped as degenerate. The same
  fit is available for one entity.
- **Warnings** (`result.warnings`): `unitlessAssumed`, `unknownUnitCode`, `skippedEntities`,
  `blockReferencesNotExpanded`, `ignoredText`, `ignoredDimensions`, `ignoredPoints`,
  `ignoredHatches`, `ignoredLeaders`, `fittedCurves`, `openChains`, `degenerateGeometry`,
  `coincidentLoops`, `crossingLoops`, `nestedLoopsDropped`.

Limits:

- Geometry is projected onto the XY plane; `z` is ignored.
- The extrusion direction (OCS) of `ARC`, `CIRCLE` and `LWPOLYLINE` is not read, so such entities
  on a mirrored plane such as `(0, 0, -1)` come out un-mirrored
  ([#21](https://github.com/SecondMouseAU/SwiftDXF/issues/21)). An `INSERT`'s extrusion is read.
- `INSERT` blocks are flattened only when the drawing was read with `expandBlocks: true`.
- Loops are assumed not to cross. Loops that do are reported (`crossingLoops`) and left unnested.
  Collinear segments that overlap only in part are not merged.
- Nesting compares bounding boxes pairwise, so it is quadratic in the number of loops (tens of
  thousands of loops are fine; millions are not).

`dxfdump --contours [--layers A,B] [--units inch|mm] file.dxf` prints the same summary as JSON.
`--expand` and `--skip-paper-space` read with those options, for the digest and for `--contours`.

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
The single-curve fit has a second gate: point `DXF_SPLINE_FILE` at a drawing with splines to check
every spline in it fits within 0.001 and chains into the contour layer's regions.

## Install

```swift
.package(url: "https://github.com/SecondMouseAU/SwiftDXF.git", from: "0.1.0"),
// target dependency: .product(name: "SwiftDXF", package: "SwiftDXF")
```

## Scope

A focused 2D reader, not a full DXF/DWG toolkit. Out of scope for now: DWG, binary DXF, OCS/extrusion
on entities other than `INSERT`, and writing. (DXF *writing* for the JWW format lives in
[SwiftJWW](https://github.com/SecondMouseAU/SwiftJWW).)

## License

MIT: see [LICENSE](LICENSE).
