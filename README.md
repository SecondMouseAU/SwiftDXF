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
| `TEXT`, `MTEXT` | `.text(at, height, rotationDeg, string, …)`: `string` as it reads, its codes decoded (see *Text*) |
| `LWPOLYLINE`, `POLYLINE`/`VERTEX` | `.polyline(vertices, closed, …)`: each vertex carries its **bulge** |
| `DIMENSION` | `.dimension(Dimension)`: what it measures and how it is stated, not the rendered arrow/text glyphs |
| `SPLINE` | `.spline(Spline)`: degree, flags, control points, knots, weights, fit points; flattens to a polyline |
| `HATCH` | `.hatch(Hatch)`: pattern name, solid fill, and the boundary paths (polyline and edge types) |
| `LEADER` | `.leader(Leader)`: vertices, arrowhead, and the handle of the annotation it points at |
| `TOLERANCE` | `.tolerance(Tolerance)`: a feature control frame, its string read into rows of characteristic, tolerance and datums (see *Geometric tolerances*) |
| `SOLID` | `.solid(Solid)`: the three or four corners of a filled triangle or quadrilateral, in outline order |
| `WIPEOUT` | `.wipeout(Wipeout)`: the masking boundary, in the world |
| `3DFACE` | `.face3D(Face3D)`: four corners with their z, and the invisible edges |

Entities it does not model (e.g. `INSERT`, `TRACE`) are **skipped, not fatal**, and
reported on the drawing (see below).

### Skipped entities

```swift
let dwg = try DXF.read(contentsOf: url)
dwg.skipped          // ["INSERT": 3, "TRACE": 1]  type name -> count
dwg.skippedByLayer   // ["INSERT": ["PARTS": 3], "TRACE": ["0": 1]]  type -> layer -> count
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
| `dwg.blocks` | each `BLOCKS` definition: `name`, `handle`, `basePoint`, and its own `entities` with `identities` (locators read `BLOCKS:<block>/<n>`), and its `attributeDefinitions` |
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
- Expanded references leave `dwg.skipped`; what a block holds that has no entity form (a `TRACE`)
  is added to it once per instance. A reference to a block the file does not define stays in
  `skipped`.
- `counts`, `bounds`, `identities` and `entityLineTypes` follow the expanded entities.

`dwg.warnings` says what the reader could not do: at read time `extrusionNotApplied` (see
*Extrusion*), and for an expansion `missingBlock`, `blockCycle` (a block that
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

### Attributes

The values a block reference carries, such as the drawing number, title and scale a title block is
filled in with, are `ATTRIB` records that follow the `INSERT`. They are read onto the reference, and
the `ATTDEF` records of a block onto the block:

```swift
let dwg = try DXF.read(contentsOf: url)
for reference in dwg.references {
    for attribute in reference.attributes {   // in file order
        attribute.tag                         // "DWG_NO" (group 2)
        attribute.value                       // "D-1234": group 1, its codes decoded
        attribute.position, attribute.height, attribute.rotation, attribute.layer
        attribute.flags                       // .invisible, .constant, .verify, .preset (group 70)
        attribute.identity                    // the handle (group 5), and its place in ENTITIES
    }
}
for block in dwg.blocks {
    for definition in block.attributeDefinitions {   // each ATTDEF
        definition.tag, definition.prompt, definition.defaultValue, definition.flags
    }
}
```

- An attribute belongs to an `INSERT` only when the `INSERT` says so (group 66), as in `ezdxf`;
  `ATTRIB` is then no longer in `dwg.skipped`. A stray `ATTRIB` stays there, and so does an `ATTDEF`
  in model space, which defines nothing. In a block the `ATTDEF`s are `attributeDefinitions`
  and the nested `INSERT`s are `Block.references`, with their attributes.
- The value goes through the drawing's code page like any text (`%%d`, `%%c`, `%%nnn`, `\U+XXXX`);
  `attribute.content` is the `TextContent`, with the string as written. An R2018 multiline
  attribute, which stores an `MTEXT` as an embedded object after the `AcDbAttribute` group, reads
  that text, with `isMultiline` set and the `MTEXT` syntax.
- An attribute's position, height and rotation are where the file drew it: in the world for a
  reference in model space, in the block's coordinates for one inside a block. Like a `TEXT`, an
  attribute on a `-z` plane is mirrored into the world, and one on a tilted plane is read as
  written and counted in `extrusionNotApplied`. Justification and the text style are not read.
- An attribute definition's position is in the block's coordinates.

Expansion with `expandBlocks` leaves the attributes on their references, so `entities` still holds
what the blocks draw. With `ReadOptions(expandAttributes: true)`, which expands the blocks too, the
visible attributes come through as `.text` as well, each with an identity that keeps the attribute's
handle and names the reference in `via` (its `id` reads `8E/9A`); an invisible attribute stays out.

- A reference inside a block has its attributes carried by the placement of that block only, since
  the file already drew them where its own reference is.
- An array repeats them per instance, as `ezdxf`'s `multi_insert()` does. Inside a block that is
  scaled, `ezdxf` leaves the grid unscaled and SwiftDXF scales it, as it does for the block's own
  entities. Under a non-uniform scale the height and rotation of an attribute follow the rule for a
  `TEXT` (see *Extrusion* and the mirrored text above), which differs from `ezdxf`'s.
- An attribute on layer `0` in a block takes the layer of the reference to that block, and a
  `BYBLOCK` colour is the colour of the attribute's own reference.
- A visible constant attribute, which no reference carries, comes through from its block's
  definition, placed as the block's other entities are; an invisible one stays out. A reference
  carries it when one of its attributes has the same tag, compared as written (`company` is not
  `COMPANY`), as `ezdxf` does. A reference to a block the file does not define places nothing,
  attributes included, as before.

`dxfdump --attributes file.dxf` prints the attributes and definitions as JSON, and
`dxfdump --expand-attributes` reads with `expandAttributes`.

### Extrusion

Arcs, circles, polylines, text, hatches, solids and the text point of a dimension are written in
their own coordinate system (OCS), whose z axis is the entity's extrusion direction (groups 210, 220, 230).
For an extrusion of `(0, 0, -1)`, which is what a drawing made on a flipped plane or mirrored in
a CAD program holds, the OCS x axis is the world `-x`. The reader gives you world coordinates:

| Entity | On a `-z` plane |
|---|---|
| `ARC`, `CIRCLE`, `LWPOLYLINE`, 2D `POLYLINE` | centre or vertices mirrored (x and z change sign), arc angles `180 - angle`, swapped and wrapped into `0..<360`, bulges change sign. A 2D `POLYLINE`'s elevation (group 30) is the z of its vertices, as for `LWPOLYLINE` |
| `ELLIPSE` | centre and axis are world coordinates already; the parameter range is reversed, so it still runs counter-clockwise |
| `TEXT`, `ATTRIB`, `ATTDEF` | insertion point mirrored, rotation `180 - rotation` |
| `HATCH` | boundary paths mirrored; a path that travelled an arc counter-clockwise now travels it clockwise |
| `SOLID` | corners mirrored (x and z change sign), in outline order |
| `DIMENSION` | the text point (group 11) and the arc point (group 16), and the rotation (group 50), an angle in the OCS, becomes `180 - rotation`. The definition points are world coordinates already, and the oblique angle (group 52) is left as written, as in `ezdxf` |

`MTEXT`, `POINT`, `SPLINE`, `LEADER`, `TOLERANCE`, `WIPEOUT`, `3DFACE` and a 3D polyline hold world
coordinates and are never converted (an `MTEXT`'s rotation is read as written). An `LWPOLYLINE`'s elevation (group 38) is the z of its vertices. The conversion agrees
with `ezdxf.upright`, `ezdxf`'s own, on a drawing with one of each.

A normal that is not along z cannot be held by a planar entity, so such an entity is read as written
and counted: `dwg.warnings` has `.extrusionNotApplied(type:count:)` for each type, counting the
model space and the blocks. The contour layer then sees the entity where the file wrote it, not where
it is drawn. An `INSERT`'s extrusion is applied when the reference is expanded; a tilted one is
expanded flat, unmirrored, and reported as `unsupportedExtrusion`.

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

### Geometric tolerances, solids, wipeouts and faces

```swift
for case .tolerance(let t) in dwg.entities {
    t.insertion, t.direction, t.styleName     // where the frame is, which way it runs
    t.text                                    // {\Fgdt;i}%%v0.012%%v%%vB%%v%%v, as written
    for frame in t.frames {                   // one per line of the string
        frame.characteristic                  // .symmetry
        frame.tolerance                       // Zone(isDiameter: false, value: 0.012, ...)
        frame.datums                          // [Datum(reference: "B")]
    }
    t.isFullyRead                             // false when anything was kept as written
}
```

A `TOLERANCE` is read into the string of its frame (group 1) and the frames in it. `^J` separates
the lines of the string (a second line is a composite frame), and `%%v` the boxes of a line: the
symbol, the first and second tolerance, and up to three datums. The symbol is a letter of the GDT
font (`{\Fgdt;j}`), read as the font `gdt.shx` defines it: `a` angularity, `b` perpendicularity,
`c` flatness, `d` profile of a surface, `e` circularity, `f` parallelism, `g` cylindricity, `h`
circular runout, `i` symmetry, `j` position, `k` profile of a line, `r` concentricity, `t` total
runout, `u` straightness. A tolerance box states a `value` (a comma is read as the decimal mark), a
diameter (`%%c`, or `{\Fgdt;n}`), a material condition (`{\Fgdt;m}`, `l`, `s`) and a projected zone
(`{\Fgdt;p}`, `isProjected`); a datum box its reference and a material condition. A first box that
is none of those symbols is `.unrecognised(raw)`, and a symbol in another box that is not one of
those stays in the box's `text` and is listed in `Frame.unread`, as is a box after the sixth: they
are kept as written and not guessed at. `isFullyRead` is `false` for them, and for a tolerance box
that holds no number (`0.05/25`). The rest of the text is decoded as
`MTEXT` is, `%%nnn` through the drawing's code page. The size of a frame comes from its dimension
style, which `styleName` names; the size is not looked up.

`SOLID`, `WIPEOUT` and `3DFACE` carry their corners:

- `Solid.corners` is in outline order: the file lists a quadrilateral as corners 1, 2, 4, 3, so the
  third and fourth are swapped, and a triangle (a repeated third corner, or none) has three. A
  `SOLID` is written in its object coordinate system, so one on a `-z` plane is converted, like an
  `ARC`.
- `Face3D.corners` are the four corners as written, in the world, with their z; `invisibleEdges` is
  the file's bit field, and `isEdgeVisible(_:)` and `isTriangle` read it.
- `Wipeout.boundary` is the clip boundary in the world. The file stores a `WIPEOUT` as an image, with
  the clip in pixels from its top left corner, and the reader places it as `ezdxf` does:
  `insertion + u (x + 1/2) + v (height - y - 1/2)`. Two clip vertices are a rectangle (four corners),
  and a polygon does not repeat its first vertex. The clip mode, which can invert the mask, is not
  read.

The contour layer ignores all four, with a warning (`.ignoredEntities`): a filled `SOLID` is a fill
as a solid `HATCH` is, and most are arrowheads, whose outline would only add loops that nothing
encloses; a `WIPEOUT` is a mask, a `3DFACE` a surface patch, and a `TOLERANCE` an annotation.
`bounds` takes in their corners, boundary points and insertion points.

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

### Text

The `string` of a `TEXT` or `MTEXT` entity is the text as it reads, with its codes decoded. The
string as the file writes it, and its stacked parts, are kept beside it:

```swift
for (i, entity) in dwg.entities.enumerated() {
    guard case .text(_, _, _, let string, _, _) = entity,
        let content = dwg.textContent(ofEntityAt: i)
    else { continue }
    string                     // "36 +0,011/-0,005": as it reads, the same as content.plain
    content.raw                // "36{\H2.4;\S+0,011^ -0,005;}": as the file writes it
    content.syntax             // .mtext, or .text for a TEXT entity
    content.stacks             // [StackedText(upper: "+0,011", lower: "-0,005", kind: .tolerance)]
    content.stacks[0].lowerValue   // -0.005: a comma or a point is the decimal mark
}
```

- **Special characters**, in both: `%%c` is `⌀` (the diameter sign, U+2300), `%%d` is `°`, `%%p`
  is `±`, `%%%` is `%`, and `%%nnn`, with three digits, is the character numbered nnn in the
  drawing's code page (`Drawing.codePage`, from `$DWGCODEPAGE`): in Windows-1252 `%%176` is `°`
  and `%%128` the euro sign, and in Shift-JIS `%%177` is the half-width katakana `ｱ`. A drawing with
  no code page takes nnn as a Unicode code point up to 255.
  `%%u`, `%%o` and `%%k`, which switch underline, overline and strike-through, are dropped.
  `\U+XXXX` is the Unicode character, and two that make a surrogate pair, `\U+D83D\U+DE00`, are
  one character. `\M+nXXXX` is the character whose two bytes XXXX are in the multibyte code page
  that `n` names, as `ezdxf` reads it: 1 is Shift-JIS, 2 Big5, 3 Korean Wansung and 5 GB 2312,
  whatever the drawing's own code page. Of the caret notation of DXF strings, `^ ` is a caret,
  `^I` a tab and `^J` a line break.
- **MTEXT formatting codes are removed** with their arguments up to the `;`: `\A` (alignment), `\C`
  and `\c` (colour), `\F` and `\f` (font), `\H` (height), `\Q` (oblique angle), `\T` (tracking),
  `\W` (width) and `\p` (paragraph). So are the switches `\L`, `\l`, `\O`, `\o`, `\K` and `\k`,
  and the `{` and `}` that group codes. When the `;` is missing, a code with one value (all but the
  font and paragraph codes) ends with its value, as `ezdxf` reads it, so `\H2xBig` reads `Big`.
  `\P`, `\N` and `\X` are line breaks, `\~` is a no-break space, and `\\`, `\{` and `\}` are the
  characters themselves. `{\fArial|b1|i0|c0|p34;www.example.com}` reads `www.example.com`.
- **Stacks.** `\S` writes two parts one above the other, divided by `^` for a tolerance (written
  `^ ` in a DXF file), `/` for a fraction or `#` for a diagonal fraction. Each stack is a
  `DXF.StackedText` with its two parts as written. The plain text gives a stack as `upper/lower`
  after a space, so `1\S1/2;` reads `1 1/2`, and `content.parts` holds the text and the stacks in
  order.
- **A backslash in `TEXT` is a character.** `TEXT` has no formatting codes, so a file path such as
  `C:\DRAWINGS\PLAN.DWG` stays whole.
- **A code that is not understood is kept as written**: an unknown backslash code, a `\M+nXXXX`
  whose `n` is not 1, 2, 3 or 5 (Korean Johab, 4, is not decoded) or whose bytes are not a
  character of its page, a `%%nnn` that names a control character, a number above 255, or a byte
  the code page leaves unassigned or uses to start a double-byte character, and a `\U+XXXX` that
  names a control character or is half a surrogate pair. A `}` ends a stack as it ends the group
  around it, so a `\S` whose `;` is missing ends there, or at the end of the text.

`dwg.textContents` is parallel to `entities` like `identities`, and is cleared when `entities`
changes. A block's are in `Block.textContents`, and an expansion carries them through.

### Dimensions

A `DIMENSION` says what it measures, and how the number is to be stated:

```swift
for case .dimension(let d) in dwg.entities {
    d.measurement                         // the stored value (group 42); nil when absent, 0 or -1
    d.computedMeasurement                 // the value the geometry gives: units, or degrees for an angle
    d.rotation, d.obliqueAngle            // groups 50 (51, negated, for ordinate) and 52, in degrees
    d.isXOrdinate                         // bit 64 of group 70: an ordinate dimension of the X type
    dwg.displayedMeasurement(of: d)       // computed value times the style's linear scale (not an angle)
    let style = dwg.styleVariables(of: d)
    style.decimalPlaces                   // DIMDEC: 1 if stated to one place, nil if unstated
    style.suppressesTrailingZeros         // DIMZIN: "8.1" may be 8.100 with its zeros hidden
    style.linearScale, style.unitSuffix   // DIMLFAC and DIMPOST
    style.angleUnit                       // DIMAUNIT: .decimalDegrees, .degreesMinutesSeconds, .gradians, .radians
    style.effectiveAngleDecimalPlaces     // DIMADEC (DIMDEC where DIMADEC is -1)
    dwg.text(of: d).typedAngles           // a typed 45°30'15" (or 50g, 0.7854r) in degrees, per the style's unit
    d.text.showsMeasurement               // does the text show the measured value?
    d.text.stacks, d.text.plain           // a stacked tolerance, and the text as it reads
}
```

- **`measurement` is `nil`, not `-1`.** Many writers (every McMaster-Carr sheet checked) store
  `-1` in group 42 and `<>` as the text. A value of zero or below reads as missing.
- **`computedMeasurement`** is the same number for every consumer: for a linear dimension the
  distance between the two extension-line origins along `rotation` (horizontal when absent), for an
  aligned one the distance between them, for a radius or diameter the distance between its two
  definition points. For these it matches `ezdxf`'s `Dimension.get_measurement()`, which also
  applies no scale. Group 50 absent means horizontal, as the DXF default says, and agreed with the
  direction worked out from the dimension-line point on every one of 339 real dimensions checked.
  The rest are as follows.
  - **Angular and three-point angular dimensions are in degrees**, as `rotation` and the angles of
    an `ARC` are, and are not scaled by `DIMLFAC`: `displayedMeasurement(of:)` leaves them alone. A
    three-point dimension is the angle at its vertex (group 15) between the rays to groups 13 and
    14; a two-line one is the angle between the line from group 13 to 14 and the line from 15 to
    10, where the lines cross. Either is the angle **on the side of the arc location** (group 16,
    or group 10 for a three-point one), which is what AutoCAD displays: three-point angles are
    between 0 and 360 and can be over 180; two crossing lines make two angles and their
    supplements, so a two-line angle is between 0 and 180. `ezdxf`'s `get_measurement()` is the
    angle counter-clockwise from the first line to the second whichever side the arc is on, so it
    differs where the arc is on the other side. Checked against AutoCAD's own anonymous blocks in
    two DWG files: all 8 three-point angular dimensions in them, of which 7 are different (the
    tests hold those) and 2 put the arc on the side `ezdxf`'s number does not (AutoCAD drew 125 and
    130 where `ezdxf` gives 235 and 230); and against `ezdxf`'s numbers where the side is the same
    (`tools/angular_fixtures.py`). A dimension with a point missing, lines that are parallel, a ray
    of no length, or an arc location exactly on the vertex or the crossing has none. The unit and
    decimal places an angle is shown in (`DIMAUNIT`, `DIMADEC`) are style variables, below; the
    computed value stays in degrees whatever they are. `measurement` (group 42) of an angular
    dimension is the file's number, not converted.
  - **An ordinate dimension** is the distance from its origin (group 10) to its feature location
    (group 13) along x when `isXOrdinate` (bit 64 of group 70) and along y when not. The axes are
    those of the coordinate system the dimension was made in: `rotation` is the negative of group
    51, and a block insertion or a `-z` plane turns it as it turns a linear dimension's. The value
    is always positive, as `ezdxf` draws it, with the same value for a feature on either side of
    the origin. It was checked against `ezdxf`'s own rendering only (`tools/angular_fixtures.py`):
    there was no AutoCAD drawing with an ordinate dimension to check it against, so whether
    AutoCAD shows a sign for the far side of the origin is not known.
- **Style variables** come from the entity's own overrides in its extended data (`ACAD` /
  `DSTYLE`), then the `DIMSTYLE` record it names. A variable neither states is `nil`: SolidWorks
  styles often leave `DIMDEC` out, and the reader does not guess it. The header's own current
  values are in `dwg.dimensionDefaults` for a caller that wants them as a fallback; they belong to
  whichever style was current when the file was saved (`dwg.currentDimensionStyleName` names it),
  so they are not applied for you. A negative
  `DIMLFAC` applies to paper space only and is ignored.
- **The unit and places of an angle** are `DIMAUNIT` (group 275) and `DIMADEC` (group 179), read
  from the same three places as the other variables: the `DIMSTYLE` record, the entity's `DSTYLE`
  overrides and the header (`dwg.dimensionDefaults`). `angleUnitCode` and `angleDecimalPlaces` are
  the numbers as written; `angleUnit` names the code (`0` decimal degrees, `1` degrees, minutes and
  seconds, `2` gradians, `3` radians) and is `nil` for an unstated or unknown one;
  `effectiveAngleDecimalPlaces` is `DIMADEC`, or `DIMDEC` where `DIMADEC` is `-1`. AutoCAD leaves a
  variable at its default out of a `DIMSTYLE` record (a drawing checked had neither in either of
  its two records, and `0` and `0` in the header), so `nil` there means the default, decimal
  degrees; the reader still does not fill it in. What `DIMADEC` means for degrees, minutes and
  seconds (how far the angle is written) is left to the application that drew the text. The
  computed angle and `displayedMeasurement(of:)` stay in degrees, whatever the style shows.
  Checked against `ezdxf` (`tools/angle_unit_fixtures.py`: the variables of each record, the
  header, an override, and the text its renderer wrote in each unit read back to the computed
  angle) and against one AutoCAD 2018 drawing with three angular dimensions, whose `90°`, `126°`
  and `36°` agree with `DIMADEC` `0` and `DIMAUNIT` `0`. Of 3,103 DXF files on the machine
  (36 with dimensions, none angular) none sets `DIMAUNIT` to anything but `0`, so the degrees,
  minutes and seconds, gradian and radian readings rest on `ezdxf`'s text, not on a real drawing.
  `ezdxf` truncates degrees, minutes and seconds, so the tests allow a whole unit of the last
  place there.
  - **Reading a typed angle in the style's unit.** `DXF.DimensionText(raw, angleUnit:)`,
    `dimension.text(angleUnit:)` and `dwg.text(of: dimension)` (which finds the unit) read what
    the text shows in that unit as one angle in `typedAngles`, in degrees: `45°30'15"`, `45°30'`
    (degrees, minutes and seconds), `50g` (gradians) or `0.7854r` (radians), the letter not
    followed by another letter. It is the style that makes `50g` an angle, as it could be a mass,
    so with no unit nothing changes: `45°` is the only text read as an angle, and `45°30'15"` is
    still the angle 45 and the numbers 30 and 15. Minutes must be whole and minutes and seconds
    below 60, or the degrees stand alone. A typed number with no unit mark (`45.5`) is a number,
    as it could be a length.
- **The text** is split into parts: `<>` (the measured value), numbers typed into it, plain words,
  `\P` line breaks and stacks. `<> mm`, `<>\PBore Size`, `67 mm\P(max)`, `40 - 60 mm\P(Adjustable)`
  and `Length is representative\PProduct sold by Length` come out as a decorated value, a label, a
  limit, a range and a note. `d.text.typedNumbers` and `d.text.words` give the pieces, and an
  angle (`45°`, `45%%d`) is in `typedAngles`, in degrees, and not in `typedNumbers` where a length
  would be read;
  `isSuppressed` is the single space that hides the text. The codes are decoded as in an `MTEXT`
  (see *Text*), so `%%c<>` gives the words `⌀` and `<>{\H0.7x;\S+0.1^ -0.2;}` the measurement and
  a tolerance stack, whose numbers are not typed numbers. `d.textOverride` is the override as the
  file writes it.
- **How a drawing writes numbers** is not in the text. `10,439` is two numbers to `typedNumbers`
  (10 and 439), as it always was. Jw_cad writes ten thousand four hundred and thirty-nine that way,
  and a drawing that writes decimals with a comma means `0,125` as one eighth, so say which:

  ```swift
  d.text(numbers: .commaSeparatesThousands).typedNumbers   // "10,439" -> [10439]
  d.text(numbers: .commaIsDecimalMark).typedNumbers        // "0,125"  -> [0.125]
  DXF.DimensionText("5,186.6", numbers: .commaSeparatesThousands).typedNumbers   // [5186.6]
  ```

  A comma separates thousands only inside a number written in groups of three (`1,930`,
  `12,345,678`); `40,60`, `1,2345` and `0,125` stay as written. A point is a decimal mark under
  every setting. Full-width digits, point and comma (`１０，４３９`) read as the ordinary ones under
  every setting, and the part keeps the characters it was written with.

### Rebuilding dimensions from loose pieces

A drawing from a Jw_cad export, a vector PDF or a scan holds a dimension as separate pieces: a value
text, a dimension line, extension lines, and marks at the ends. `rebuildingDimensions()` puts them
back together, without any format's flags:

```swift
let result = dwg.rebuildingDimensions()
for d in result.dimensions {
    d.textOverride                    // "1,829": the text as written
    d.measurement                     // 22.863: the length the geometry gives, in drawing units
    dwg.displayedMeasurement(of: d)   // 1829.04: that times the scale (`styleOverrides.linearScale`)
    d.rebuilt?.scale                  // 80
    d.rebuilt?.pieces                 // the identities it was built from, the value text first
}
result.scales                         // per layer group: scale 80, 29 supporting, 0 contradicting
result.warnings                       // each value it could not explain, and what disagrees
let withDimensions = result.applied(to: dwg)   // the dimensions added after the entities
```

It starts from each text that states a number and works out the rest, like SwiftJWW's
`recoveringDimensions()`, which uses Jw_cad's attribute flags and stays as it is:

- **Ends.** A dimension line is a line beside the text, or a chain of collinear pieces (broken
  around the text is fine). Its ends are where an extension line meets it, or a `POINT`, a small
  closed triangle (an arrowhead, whose tip is the end) or a small shape such as a dot or a tick
  lies on it. An extension line gives the exact place; a mark is used where there is none. A
  dimension is a span between two ends that the line covers, near the text, with at most two
  other ends inside it (an arrowhead has a base) or the whole line. A dimension line is read up to
  512 collinear pieces. `Options(tolerance:)` is how
  far apart pieces may be and still meet, 3% of the text height by default; a length may differ
  from its value by twice that, times the scale.
- **Scale.** Every candidate span and reading implies a scale, the value over the length. The scale
  that explains the most texts is refined to the least-squares scale of the ones it explains, and
  made a round scale (80, 1/2) when it is within what the values can tell apart. Each layer group
  has its own, a group being the `0` of a Jw_cad layer `0-E` and otherwise the layer. Groups that
  differ are reported with `.scalesDisagree`, never averaged. A scale counts only when it is
  between 1/20 and 1,000,000 and explains at least three values and more than it leaves, or two
  when they are all the values of the group and the scale is round: a numbered sequence beside
  lines (the ports of a panel, a scale bar, a border) is explained by some scale too, and is
  usually left unexplained: a dimension is between neighbouring ends, with at most two others
  inside it. A
  value votes only when it is ten units of its last place (`5` does not, `50` and `2.5` do): it
  can be explained once the scale is known. Of scales that explain as much, the one whose
  geometry is nearest its texts wins, then a reduction over an enlargement. `Options(scale:)`
  states the scale instead; anything but a positive number is no scale.
- **Values.** A comma or a point is a decimal mark or a thousands separator, whichever the geometry
  bears out: `1,829` is 1.829 or 1829, and `1.234,5` is 1234.5. Where the geometry cannot tell
  (a chain of `1,829` and `1,981` fits 1:1 and 1:1000 alike), say how the drawing writes numbers
  with `Options(numbers:)`, the setting `DimensionText` takes: a Jw_cad export is
  `.commaSeparatesThousands`, and then `10,439` is 10439 and never 10.439. With a setting a comma
  is read only as it says, and a number it does not read as one (`40,60`) is listed as several.
  Full-width digits, a diameter or
  radius symbol before the number and a trailing `mm` are read; a tolerance stack is ignored.
  Angles, other units, texts with several numbers and numbers that are not read (`1.2.3`) are
  listed as not rebuilt, with the reason. Numbers a text assembler ran
  together (`200 629`) are read as the values they are, so a space as a thousands separator
  (`1 600`) is read as two.
- **Diameters and radii** come from the geometry, not the symbol: a line through the centre of a
  circle or arc that ends on it at both ends is a diameter, and one that ends on it at one end
  (from the centre, or along a leader) is a radius. The symbol is a check: `.symbolDisagrees` says
  where it does not bear the geometry out, or a radius symbol is on a straight dimension (a
  diameter symbol there is ordinary), and the geometry decides.
- **Marked, and flagged.** Each dimension has `rebuilt` set. A value text that no dimension
  explains, on a layer where one was rebuilt or (an angle, or a value in another unit) beside a
  dimension line, is a
  `.valueNotExplained` warning with its reason. A drawing with `DIMENSION` entities and no loose
  pieces gains nothing and warns of nothing.
- **Pieces are on the layer of the text** unless `Options(pieceLayers: .any)`, and are read from
  `entities`: read a drawing with `expandBlocks` when its pieces are in blocks, and with
  `skipPaperSpace` to leave a sheet's paper space out, as model and paper space are one plane
  here. The text's direction is a preference, not a rule: Jw_cad writes a vertical text's angle as
  5156.62, and an AutoCAD style may keep a text horizontal beside a vertical line. A text is
  placed from its insertion point (the left of the baseline for a `TEXT`, the top left for an
  `MTEXT`) and its length is estimated from its characters: justification is not read.

On Jw_cad's own DXF export of the 2120 it gives all 29 dimensions at 1:80 with all 29 supporting,
the same values SwiftJWW gives for the JWW. So it does for a DXF of the JWW's loose pieces, and for
the PDF through OCCTSwiftPDF, whose positions are noisy to about 0.1 mm: 29 at 1:80 (the least
squares scale is 80.04). Over 2,855 DXF files on one machine, the 38 that have real
dimensions (22 of them McMaster-Carr sheets) gained none, 35 of them with no warning and 3 with
warnings for numbers beside lines, and the other Jw_cad railway drawings (`dd12`,
`ka2000`, `tmf1`, `to1`) found 1:80. On the 2120, 17 of the 29 values carry a comma: with
`Options(numbers: .commaSeparatesThousands)` the result is the same 29 at 1:80; told a comma is a
decimal mark it finds 17 at a scale of 0.08, and told a comma is not part of a number, 12.

It is an inference. It does not rebuild angular or ordinate dimensions, a text on a dimension
line that is not beside it (a leader), or two scales in one layer group; an arrowhead drawn as a
filled `SOLID` is not used as an end mark. `dxfdump --rebuild [--scale N] [--numbers thousands|decimal|plain] file.dxf`
prints the result as JSON. The 2120 and the drawings with real dimensions are checked by tests that
need the files: `DXF_REBUILD_FILE` (a drawing that gives 29 at 1:80) and `DXF_REBUILD_CORPUS` (a
folder in which every drawing with real dimensions gains none). `tools/rebuild_corpus.py <folder>`
prints what each drawing of a folder gives, with totals, as the figures above were taken.

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

### Header variables

`Drawing` exposes header essentials: `version` (`$ACADVER`), `insUnits` (`$INSUNITS`), and the
declared `extMin` / `extMax` extents (`$EXTMIN` / `$EXTMAX`), plus a computed `bounds` over the
entities actually read. Five more say how to read the drawing's numbers, each `nil` when the file
lacks it (an R12 file has no `$INSUNITS` or `$MEASUREMENT`):

```swift
dwg.measurement                // $MEASUREMENT: 0 imperial, 1 metric; the file's answer when insUnits is 0 or nil
dwg.currentDimensionStyleName  // $DIMSTYLE: the style the dimension defaults below belong to
dwg.currentDimensionStyle      // its record in dimensionStyles (case-insensitive), or nil
dwg.dimensionScale             // $DIMSCALE: the overall dimension scale (sizes, not measured values)
dwg.linearUnitFormat           // $LUNITS: 1 scientific, 2 decimal, 3 engineering, 4 architectural, 5 fractional
dwg.linearUnitPrecision        // $LUPREC
dwg.headerVariables["$MEASUREMENT"]?.value(70)?.integer   // any variable, by name
dwg.headerVariables["$EXTMIN"]?.point                      // 10/20/30 as a point
```

`headerVariables` holds **every** variable of the `HEADER` section by name, each a
`DXF.HeaderVariable` of its group-coded values in file order (`$EXTMIN` is three, groups 10, 20 and
30; `$DIMSTYLE` is one, group 2). A consumer can read a variable the package has no property for,
such as `$LIMMIN` or `$PSLTSCALE`; `value(code)?.integer`, `.real` and `.text` read one, and
`point` reads a point. The properties above were read from it, and the two are not kept in step, so
changing one does not change the other.

- **Text keeps the file's characters.** A string value is read through the drawing's code page
  like the rest of the file (the bytes `43 61 66 E9` of a `$DIMSTYLE` in an `ANSI_1252` file read
  as `Café`), whitespace is kept (the named `currentDimensionStyleName` is trimmed), and `%%` codes
  are not decoded: they are for the text of the drawing, and `$DIMPOST` keeps `<>%%d` as written.
- **Only the `HEADER` section is read.** A variable written twice keeps its first value, and a file
  with no `HEADER` section has none. A value of the wrong type, such as a `$MEASUREMENT` that is
  not an integer or is written in another group, reads as `nil` from the named property and is
  still in `headerVariables`.
- **`$DIMSCALE` is not `$DIMLFAC`.** `dimensionScale` scales sizes such as text height and arrow
  size, and `0` leaves it to the application. The factor that multiplies a measured value is
  `dimensionDefaults.linearScale` (`$DIMLFAC`).

### Behaviours worth knowing

- **Encoding.** Files are decoded as UTF-8 when valid, and a file of R2007 or later (`$ACADVER`
  `AC1021` and after) always is, with a stray byte as U+FFFD. Otherwise the bytes are in the code
  page that `$DWGCODEPAGE` names (`ANSI_932`, `ANSI_936`, `ANSI_949`, `ANSI_950`, `ANSI_874` and
  `ANSI_1250` to `ANSI_1258`; `Drawing.codePage` says which), or in **CP932 / Shift-JIS** when it
  names none or one that is not read (`DOS437`, `ISO8859-1`, `ANSI_1361`): the common code page
  for DXF exported by Japanese CAD tools (e.g. Jw_cad). Each is an ASCII superset, so the
  group-code structure is unaffected. A byte its page cannot decode is shown as U+FFFD, and the
  rest of the file is still read in the page. Without CoreFoundation, only Shift-JIS and
  `ANSI_1250` to `ANSI_1254` are decoded. The codes inside text are decoded too, and `%%nnn`
  through the code page when the header names one; see *Text*.
- **Line endings & padding.** Handles LF / CRLF / CR and R12-style space-padded group codes (`  0`).
- **Ellipse normalisation.** DXF requires `ratio = minor/major ≤ 1`. Files that emit `ratio > 1`
  (a swapped major axis) are normalised to the canonical form (same curve, valid axis), so consumers
  like OCCT's `Geom_Ellipse` (which demands `majorRadius ≥ minorRadius`) get correct geometry. This
  matches `ezdxf`'s normalisation exactly.
- **Binary DXF** is detected and rejected (`Error.binaryUnsupported`): convert to ASCII DXF first.
- **Model space.** The `ENTITIES` section is what `ezdxf`'s `modelspace()` iterates. Paper-space
  entities are counted and can be left out, and `BLOCKS` definitions are read and flattened into the
  entities only on request (see *Block references and paper space*).

### Upgrading from 0.6.0

- **An attribute tag is compared as written** when a reference's attribute stands in for a block's
  constant `ATTDEF`, as `ezdxf` does. A reference attribute `company` no longer hides a constant
  `COMPANY`, so `expandAttributes` gives both. Nothing else changes.

### Upgrading from 0.5

- **`Drawing` has new header properties**: `headerVariables` (every variable of the `HEADER`
  section by name), `measurement`, `currentDimensionStyleName`, `dimensionScale`,
  `linearUnitFormat` and `linearUnitPrecision`, and a computed `currentDimensionStyle`. The stored
  ones are defaulted in `init`, which keeps its parameters in their order with the new ones last,
  so existing calls compile unchanged; see *Header variables*. Only the `HEADER` section is read
  for the header properties now: a group 9 elsewhere in the file was once taken for a variable.
- **`DXF.Entity` has four new cases**, `.tolerance`, `.solid`, `.wipeout` and `.face3D`, so an
  exhaustive `switch` needs them. `TOLERANCE`, `SOLID`, `WIPEOUT` and `3DFACE` no longer appear in
  `dwg.skipped`, and `Counts` gains `tolerance`, `solid`, `wipeout` and `face3D`, which `total`
  and `bounds` include. `DXF.Tolerance`, `Solid`, `Wipeout` and `Face3D` are new types.
- **`Contour.Warning` has a new case**, `.ignoredEntities(type:count:)`, so an exhaustive `switch`
  over it needs it. A `SOLID` and the others were `.skippedEntities` before.
- **A `SOLID` on a `-z` plane is converted into the world**, as an `ARC` is; one on a tilted plane
  is read as written and reported as `.extrusionNotApplied`.
- **`ATTRIB` is no longer in `dwg.skipped`**, and `ATTDEF` no longer in a block's `skippedByLayer`:
  they are read (see *Attributes*). `BlockReference` gains `attributes`, `Block` gains
  `attributeDefinitions` and `ReadOptions` gains `expandAttributes`, all defaulted, so nothing
  changes for a caller that ignores them. The `SEQEND` after an `INSERT`'s attributes is read with
  them. A record that follows an `INSERT`'s attributes keeps the locator it had. The attributes of
  a paper-space `INSERT` are no longer counted in `dwg.paperSpace["ATTRIB"]` either, and are left
  out with it by `skipPaperSpace`.
- **`Dimension` has a new property**, `rebuilt`, `nil` for a dimension the file holds and set by
  `rebuildingDimensions()`; it is defaulted in `init`. `Dimension.text` reads `%%nnn` through its
  `codePage`, a new property read from the drawing.
- **A file is read through its `$DWGCODEPAGE`.** A file that is not UTF-8 used to be read as
  Shift-JIS whatever its header said, so a drawing that names `ANSI_1252` (McMaster-Carr's, for
  one) read `é`, `°` and `Ø` as other characters, or as replacement characters. It now reads them
  in the page it names. A file with no `$DWGCODEPAGE` is still read as Shift-JIS.
  `DXF.CodePage`, `Drawing.codePage` and `Dimension.codePage` are new, and `TextContent.init` and
  `DimensionText.init` take a `codePage`, defaulted to none.
- **A file of R2007 or later is read as UTF-8.** One with bytes that are not valid UTF-8 used to
  be read as Shift-JIS; its `$DWGCODEPAGE` is not used for the bytes of such a file, and a stray
  byte is U+FFFD.
- **`%%nnn`, `\M+nXXXX` and surrogate pairs.** `%%128` in an `ANSI_1252` drawing is the euro sign,
  where it was kept as written; `\M+nXXXX` is decoded, where it was kept as written; and two
  `\U+` escapes that make a surrogate pair are one character, where each was kept.
- **`computedMeasurement` has a value for angular, three-point angular and ordinate dimensions**,
  where it was `nil`: degrees for the angular kinds (not scaled by `DIMLFAC`), a distance for an
  ordinate, along x when the new `Dimension.isXOrdinate` is set. A block expansion no longer scales
  an angular dimension's group 42 by the insertion scale, which was wrong for an angle.
- **`DimensionText.Part` has another new case**, `.angle`, so an exhaustive `switch` over the parts
  needs it. An angle typed into the text (`45°`, `45%%d`, `45\U+00B0`) is in `typedAngles`, in
  degrees, and no longer in `typedNumbers`: that was `[45]` and is `[]`. Full-width digits and the
  full-width comma now read as numbers.
- **How a drawing writes numbers can be stated.** `DimensionText(_:numbers:codePage:)`,
  `Dimension.text(numbers:)` and `DimensionRebuild.Options(numbers:)` take a `NumberConvention`,
  defaulted to `.plain`, which reads `10,439` as two numbers, as before; see *Dimensions*.

### Upgrading from 0.4

- **The `string` of `.text` is the text as it reads.** It used to drop only the backslash of each
  MTEXT code and keep the rest (`36{H2.400000;S+0,011^ -0,005;}`), and to leave `%%c`, `%%d` and
  `%%p` as written. The codes are now decoded or removed (`36 +0,011/-0,005`), and
  `Drawing.textContent(ofEntityAt:)` gives the string as written, its syntax and its stacks.
  `Drawing` and `Block` gain `textContents`, defaulted in `init`.
- **A backslash in `TEXT` stays.** A `\P` in a `TEXT` used to become a line break and every other
  backslash was dropped, which broke file paths. `\U+XXXX` is still decoded, and needs its four hex
  digits; one that names a control character is kept as written. An MTEXT code that is not
  understood keeps its backslash.
- **`DimensionText.Part` has a new case**, `.stack`, so an exhaustive `switch` over the parts needs
  it. `.words` no longer holds formatting codes, `%%c` in it is `⌀`, and `\X` is a `.lineBreak`. A
  sign after a line break now belongs to the number that follows. `Dimension.textOverride` is
  unchanged: the override as the file writes it.

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
- **Entities on a `-z` plane change coordinates.** `ARC`, `CIRCLE`, `LWPOLYLINE`, 2D `POLYLINE`,
  `TEXT`, `HATCH` and a dimension's text point used to come out as the file wrote them, in the
  entity's own coordinate system; they are now mirrored into the world, so a drawing that relied on
  the old values moves. Other drawings are unchanged, apart from the next two items.
- **`LWPOLYLINE` vertices carry the elevation** (group 38) as their z, which was `0`.
- **Arcs carried through a mirroring or rotating reference have both angles in `0..<360`** unless
  they are a full turn, and **text through a mirroring reference gets the mirrored rotation**
  (`180 - rotation` for a flip of x) instead of `rotation + 180`.
- **`Warning` has a new case**, `.extrusionNotApplied(type:count:)`, so an exhaustive `switch` over
  it needs it.
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
| `TOLERANCE`, `SOLID`, `WIPEOUT`, `3DFACE` | ignored, with an `ignoredEntities` warning for each type |
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
  `ignoredHatches`, `ignoredLeaders`, `ignoredEntities`, `fittedCurves`, `openChains`, `degenerateGeometry`,
  `coincidentLoops`, `crossingLoops`, `nestedLoopsDropped`.

Limits:

- Geometry is projected onto the XY plane; `z` is ignored.
- Entities on a tilted plane (an extrusion that is not along z) are read as written, not tipped
  into the drawing plane; see *Extrusion* above. A normal of `(0, 0, -1)` is handled.
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
and splines are measured against the exact curves. `SOLID`, `3DFACE` and `WIPEOUT` are checked on
`Fixtures/solids.dxf` (`tools/solid_fixtures.py`), which has a triangle and quadrilaterals, a
`-z` plane, invisible edges, and a clip on a rotated, scaled grid of pixels, and by `dxfdump` against
`tools/oracle.py` (`tools/oracle_diff.py`) over the 341 drawings on one machine that hold one of
them in any section (a survey of its `.dxf` files, leaving out iCloud folders): the 365 `SOLID` in 35
drawings and 13,106 `3DFACE` in 170 agree on every count and every coordinate. No drawing there held
a `TOLERANCE` or a `WIPEOUT`, so those two rest on the fixture, whose frames are asserted from the
format (`ezdxf` has no parser for the string).

Across an 11-file corpus (~62,000 entities, mixed R12 drawings incl. Jw_cad exports), SwiftDXF
matches `ezdxf` **exactly**: every entity count and every coordinate scalar, to the bit. The
`Tests/SwiftDXFTests/CorpusOracleTests.swift` suite pins those ezdxf-derived counts as a regression
gate (skipped when the corpus is absent; point `DXF_CORPUS` at a folder of `.dxf` files to run).
The single-curve fit has a second gate: point `DXF_SPLINE_FILE` at a drawing with splines to check
every spline in it fits within 0.001 and chains into the contour layer's regions.

Text is checked with `tools/text_oracle.py`, which prints, from `ezdxf`, the shape that
`dxfdump --texts` prints: each `TEXT`, `MTEXT` and dimension override in entity order, as it reads
and with its stacks.

```bash
diff <(swift run dxfdump --texts --skip-paper-space drawing.dxf) \
    <(python3 tools/text_oracle.py drawing.dxf)
```

`--skip-paper-space` leaves out what `ezdxf`'s `modelspace()` leaves out; `--expand` would add the
texts of blocks, which the oracle does not list.

Attributes are checked with `tools/attrib_oracle.py`, which prints, from `ezdxf`, the shape that
`dxfdump --attributes` prints: the model-space references that carry attributes (`Insert.attribs`)
and, for each block, its `ATTDEF`s and the nested references that carry attributes. With
`--compare` it runs `dxfdump` itself and prints each field that differs:

```bash
python3 tools/attrib_oracle.py --compare .build/debug/dxfdump drawing.dxf
```

Over the 170 drawings of a local corpus that hold an `ATTRIB` or an `ATTDEF` (a library of furniture,
car and people symbols: 165 of R12, 5 of R2013), every one of the 7,020 attributes of 309
model-space references, the 3,634 attributes of 158 references inside blocks and the 6,680
definitions has the same tag, value, position, height, rotation, layer, flags and handle in both.
Expansion is compared too, against `ezdxf`'s `virtual_entities()`: on the same files all 441 visible
attributes, those of references inside blocks carried through their blocks' placement, come out at
the same position, height and rotation. The R2000 title block, the R2018 multiline
attribute and the rotated array of `Tests/SwiftDXFTests/Fixtures/attributes*.dxf` are written and
read back by `ezdxf` (`tools/attrib_fixtures.py`). No drawing of the corpus is a title block written by AutoCAD with
R2000 attribute records filled in, or has a multiline attribute: those two forms are tested on
`ezdxf`'s own output.

The oracle writes `%%c` as `⌀`, a stack as `upper/lower` after a space, `\~` as a no-break space and
`\X` as a line break, as SwiftDXF does, so the diff shows only where the two read a string
differently. Over 23,429 strings in 3,109 real drawings, given to both with their non-ASCII
characters written as `\U+XXXX`, the two agree on all but 25, each a Jw_cad superscript mark from
the third case below. Both read a file through its `$DWGCODEPAGE`; with none, `ezdxf` reads
Windows-1252 and SwiftDXF Shift-JIS, so a Japanese file with no header reads differently in the
two. Over the 96 files of a local corpus that are not UTF-8, the strings of 86 are the same in
both, and the other 10 are Japanese files with no `$DWGCODEPAGE`. They read a string
differently in these cases, on purpose:

- `%%nnn` is decoded, through the drawing's code page; `ezdxf` leaves it.
- `^J` in a `TEXT` is a line break; `ezdxf` keeps a `TEXT` on one line and drops it.
- A caret other than `^ `, `^I` and `^J` is text; `ezdxf` reads every caret as a control
  character, so the Jw_cad superscript mark in `m^u3` becomes `m53`.
- `%%u`, `%%o` and `%%k` are dropped in `MTEXT` as in `TEXT`; `ezdxf` keeps them in `MTEXT`.
- In a stack, `%%` codes are decoded, `^I` and `^J` are a tab and a line break, and any other `^`
  without its space still divides (`ezdxf` reads `^-` as a control character). A `\S` with no
  divider is read as text, where `ezdxf` gives a stack with an empty lower part, and a `}` ends a
  stack, where `ezdxf` runs it on to its `;`.
- `\M+4XXXX` (Korean Johab) is kept as written; `ezdxf` decodes it. A `\U+XXXX` of a control
  character, or of half a surrogate pair, is kept as written; `ezdxf` decodes it. `ezdxf` leaves
  a surrogate pair as two code points, and the oracle joins them as SwiftDXF does. A `%%` or a
  backslash at the very end is kept; `ezdxf` drops it.

The header is checked with `tools/oracle.py --header`, which reads the `HEADER` section with
`ezdxf` and prints the shape `dxfdump --header` prints: the variables SwiftDXF names, and every
variable of the file with its first group-coded value. `--against` runs `dxfdump` on each file and
lists where the two differ, numbers compared as numbers:

```bash
swift build && python3 tools/oracle.py --header --against .build/debug/dxfdump drawing.dxf [...]
```

Over 2,943 real drawings (R10 to R2013, from Jw_cad exports to McMaster-Carr sheets and CAD block
libraries) the two agree on every variable of every file, and so on the named properties. In that
set 412 drawings declare `$MEASUREMENT` (383 metric, 29 imperial) and 2,651 declare the other
four; the 292 that lack `$DIMSTYLE`, `$DIMSCALE`, `$LUNITS` and `$LUPREC` are R12 or R10 files or
have no `$ACADVER`. 2,530 have no `$INSUNITS`, and of the 413 that do, 31 say `0` (unitless),
25 of them with an imperial `$MEASUREMENT`. Eleven have no header variable at all.
`$MEASUREMENT` is not a statement of the units: 354 drawings declare inches and a metric
`$MEASUREMENT`. Only one file has a non-ASCII header string (`$CLAYER` in an `ANSI_1252` file),
which both readers read alike; the `$DIMSTYLE` and `$DIMPOST` cases are tested on constructed files
in `HeaderVariablesTests`.

## Install

```swift
.package(url: "https://github.com/SecondMouseAU/SwiftDXF.git", from: "0.1.0"),
// target dependency: .product(name: "SwiftDXF", package: "SwiftDXF")
```

## Scope

A focused 2D reader, not a full DXF/DWG toolkit. Out of scope for now: DWG, binary DXF, entities on
a tilted plane, and writing. (DXF *writing* for the JWW format lives in
[SwiftJWW](https://github.com/SecondMouseAU/SwiftJWW).)

## License

MIT: see [LICENSE](LICENSE).
