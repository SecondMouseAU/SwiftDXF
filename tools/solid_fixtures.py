#!/usr/bin/env python3
"""Generate the SOLID / 3DFACE / WIPEOUT / TOLERANCE fixture and ezdxf reference values.

    python3 tools/solid_fixtures.py [out_dir]

Builds `<out_dir>/solids.dxf` with ezdxf: SOLIDs (a triangle, quadrilaterals whose file order is
1, 2, 4, 3, one with z, one on a -z plane and one on a tilted plane), 3DFACEs (a quadrilateral with
two invisible edges and z, a triangle), WIPEOUTs (a polygon, a rectangle, and one with a rotated
and scaled pixel grid of 200 x 100 pixels), and TOLERANCEs. Then it prints, as JSON, what ezdxf
reads back from that file. The values are pasted into Tests/SwiftDXFTests/SolidTests.swift and
Tests/SwiftDXFTests/ToleranceTests.swift.

SOLID uses `Solid.vertices()` (outline order, in the object coordinate system) after
`ezdxf.upright`, 3DFACE the four stored corners, WIPEOUT `boundary_path_wcs()` without its closing
vertex, and TOLERANCE the stored insertion point, direction and string. ezdxf has no parser for the
string, so the frames are asserted against the format in the tests.

It also writes two more fixtures and prints what ezdxf reads from them under `clip` and
`elevation`:

* `wipeout_clip.dxf` (R2018): WIPEOUTs with the clip mode (group 290) inverted or not, the clipping
  state (280) off, a rectangular and a polygonal clip (71), and one with no clip vertices. ezdxf
  keeps 280, 71 and 290 as `clipping`, `clipping_boundary_type` and `clip_mode`, and does not act
  on them: `boundary_path_wcs()` is the same either way.
* `solid_r12.dxf` (AC1009, written by hand: ezdxf never writes group 38) and
  `solid_r2000_elevation.dxf` (AC1015): SOLIDs of the R11 kind, whose z is the record's elevation
  (group 38) and not a group 30. ezdxf gives the elevation to each corner whose z is 0, in a file
  of R12 or earlier only (`elevation_to_z_axis` in `ezdxf/entities/dxfgfx.py`, called from
  `Solid.load_dxf_attribs` under `processor.r12`), and ignores it in a later one.

Requires: pip install ezdxf
"""
import json
import math
import os
import sys

import ezdxf
from ezdxf.upright import upright_all

SQUARE_ROOT_HALF = math.sqrt(0.5)


def build(out_dir):
    doc = ezdxf.new("R2018")
    msp = doc.modelspace()

    # SOLIDs take their corners in file order: 1, 2, then 4 and 3 of the outline.
    msp.add_solid([(0, 0), (4, 0), (2, 3), (2, 3)], dxfattribs={"layer": "FILL", "color": 1})
    msp.add_solid([(0, 0), (5, 0), (1, 4), (6, 4)], dxfattribs={"layer": "FILL"})
    msp.add_solid([(10, 0, 2.5), (14, 0, 2.5), (10, 2, 2.5), (14, 2, 2.5)])
    msp.add_solid(
        [(1, 1, 2.5), (3, 1, 2.5), (1, 2, 2.5), (3, 2, 2.5)], dxfattribs={"extrusion": (0, 0, -1)})
    msp.add_solid([(0, 0), (2, 0), (0, 2), (2, 2)], dxfattribs={"extrusion": (0, 1, 0)})

    msp.add_3dface(
        [(0, 0, 0), (1, 0, 1), (1, 1, 2), (0, 1, 1)], dxfattribs={"invisible_edges": 5})
    msp.add_3dface([(5, 5, 1), (6, 5, 1), (5.5, 6, 3), (5.5, 6, 3)])

    # A polygon, then a rectangle (two opposite corners), as ezdxf writes a masking area.
    msp.add_wipeout([(10, 10), (20, 10), (20, 15), (15, 20), (10, 15)])
    msp.add_wipeout([(0, 0), (8, 6)])
    # A pixel grid that is rotated, scaled and not square: 200 x 100 pixels of 0.1 units, turned by
    # 30 degrees, with a polygon clip in pixels measured from the top left.
    angle = math.radians(30)
    wipeout = msp.add_wipeout([(0, 0), (1, 1)])
    wipeout.dxf.insert = (10, 20, 1)
    wipeout.dxf.u_pixel = (0.1 * math.cos(angle), 0.1 * math.sin(angle), 0)
    wipeout.dxf.v_pixel = (-0.1 * math.sin(angle), 0.1 * math.cos(angle), 0)
    wipeout.dxf.image_size = (200, 100)
    wipeout.set_boundary_path([(-0.5, -0.5), (100, 10), (150, 80), (20, 90)])

    for text in (
        r"{\Fgdt;i}%%v0.012%%v%%vB%%v%%v",
        r"{\Fgdt;j}%%v{\Fgdt;n}0.001%%v%%v%%v%%v",
        r"{\Fgdt;j}%%v%%c0.1{\Fgdt;m}%%v%%vA%%vB{\Fgdt;m}%%vC",
        r"{\Fgdt;j}%%v%%c0.5%%v%%vA%%vB%%v^J%%v%%c0.2%%v%%vA",
    ):
        msp.new_entity(
            "TOLERANCE",
            {
                "insert": (388.5, 557.92, 0),
                "x_axis_vector": (1, 0, 0),
                "dimstyle": "ISO-25",
                "content": text,
                "layer": "Quote",
            },
        )

    path = os.path.join(out_dir, "solids.dxf")
    doc.saveas(path)

    back = ezdxf.readfile(path)
    mspb = back.modelspace()
    upright_all(mspb)
    solids, faces, wipeouts, tolerances = [], [], [], []
    for e in mspb:
        t = e.dxftype()
        if t == "SOLID":
            solids.append({
                "handle": e.dxf.handle, "layer": e.dxf.layer,
                "vertices": [list(v) for v in e.vertices()]})
        elif t == "3DFACE":
            faces.append({
                "handle": e.dxf.handle,
                "corners": [list(e.dxf.vtx0), list(e.dxf.vtx1), list(e.dxf.vtx2),
                            list(e.dxf.vtx3)],
                "invisible": e.dxf.get("invisible_edges", 0),
                "visibility": e.get_edges_visibility()})
        elif t == "WIPEOUT":
            wipeouts.append({
                "handle": e.dxf.handle,
                "boundary": [list(v) for v in e.boundary_path_wcs()[:-1]]})
        elif t == "TOLERANCE":
            tolerances.append({
                "handle": e.dxf.handle, "layer": e.dxf.layer, "insert": list(e.dxf.insert),
                "direction": list(e.dxf.x_axis_vector), "style": e.dxf.dimstyle,
                "content": e.dxf.content})
    return {"solids": solids, "faces": faces, "wipeouts": wipeouts, "tolerances": tolerances}


def build_clip(out_dir):
    doc = ezdxf.new("R2018")
    msp = doc.modelspace()
    polygon = [(0, 0), (10, 0), (10, 6), (5, 9), (0, 6)]

    def masked(vertices, *, mode, clipping=1, layer="0"):
        w = msp.add_wipeout(vertices, dxfattribs={"layer": layer})
        w.dxf.clip_mode = mode
        w.dxf.clipping = clipping
        return w

    masked(polygon, mode=0, layer="MASK")
    masked([(x + 20, y) for x, y in polygon], mode=1, layer="MASK")
    masked([(40, 0), (48, 6)], mode=1)
    masked([(60, 0), (68, 6)], mode=0)
    masked([(x + 80, y) for x, y in polygon], mode=0, clipping=0)
    # No clip vertices at all: ezdxf resets the clip to the whole image and switches clipping off.
    bare = msp.add_wipeout([(0, 0), (1, 1)])
    bare.dxf.insert = (100, 0, 0)
    bare.dxf.u_pixel = (4, 0, 0)
    bare.dxf.v_pixel = (0, 3, 0)
    bare.dxf.image_size = (1, 1)
    bare._boundary_path = []
    path = os.path.join(out_dir, "wipeout_clip.dxf")
    doc.saveas(path)
    back = ezdxf.readfile(path)
    clip = []
    for e in back.modelspace():
        clip.append({
            "layer": e.dxf.layer,
            "boundary": [list(v) for v in e.boundary_path_wcs()[:-1]],
            "clipping": e.dxf.get("clipping"),
            "type": e.dxf.get("clipping_boundary_type"),
            "mode": e.dxf.get("clip_mode"),
        })
    return clip


def solid_record(
    corners, *, handle, elevation=None, extrusion=None, subclass=False, layer="0"
):
    """A SOLID record as R11 wrote it: corners 10..13 with or without group 3x, then 38."""
    tags = ["0", "SOLID"]
    if subclass:
        tags += ["5", f"{handle:X}", "100", "AcDbEntity"]
    tags += ["8", layer]
    if subclass:
        tags += ["100", "AcDbTrace"]
    for index, corner in enumerate(corners):
        tags += [str(10 + index), repr(float(corner[0])), str(20 + index), repr(float(corner[1]))]
        if len(corner) > 2:
            tags += [str(30 + index), repr(float(corner[2]))]
    if elevation is not None:
        tags += ["38", repr(float(elevation))]
    if extrusion is not None:
        tags += ["210", repr(float(extrusion[0])), "220", repr(float(extrusion[1])),
                 "230", repr(float(extrusion[2]))]
    return tags


def legacy_file(version, records):
    tags = ["0", "SECTION", "2", "HEADER", "9", "$ACADVER", "1", version, "0", "ENDSEC",
            "0", "SECTION", "2", "ENTITIES"]
    for record in records:
        tags += record
    tags += ["0", "ENDSEC", "0", "EOF"]
    return "\n".join(tags) + "\n"


ELEVATION_RECORDS = [
    # A flat quadrilateral with only an elevation: every corner is at z 3.5.
    dict(corners=[(0, 0), (4, 0), (0, 2), (4, 2)], elevation=3.5),
    # Corners with their own z keep it: the elevation is only for a corner whose z is 0.
    dict(corners=[(0, 0, 5), (4, 0, 5), (0, 2, 5), (4, 2, 5)], elevation=2),
    # A triangle (no fourth corner) with an elevation.
    dict(corners=[(10, 0), (14, 0), (12, 3)], elevation=1.5),
    # No elevation, and elevation 0: z stays 0.
    dict(corners=[(20, 0), (24, 0), (20, 2), (24, 2)]),
    dict(corners=[(20, 0), (24, 0), (20, 2), (24, 2)], elevation=0),
    # An elevation on a -z plane: the OCS z is the elevation, upright flips it.
    dict(corners=[(1, 1), (3, 1), (1, 2), (3, 2)], elevation=2.5, extrusion=(0, 0, -1)),
    # One corner with an explicit z of its own and one without.
    dict(corners=[(30, 0, 4), (34, 0), (30, 2), (34, 2, 4)], elevation=7),
]


def build_elevation(out_dir):
    result = {}
    for name, version, subclass in (
        ("solid_r12.dxf", "AC1009", False),
        ("solid_r2000_elevation.dxf", "AC1015", True),
    ):
        records = [
            solid_record(handle=0x100 + i, subclass=subclass, **spec)
            for i, spec in enumerate(ELEVATION_RECORDS)
        ]
        path = os.path.join(out_dir, name)
        with open(path, "w") as handle:
            handle.write(legacy_file(version, records))
        back = ezdxf.readfile(path)
        mspb = back.modelspace()
        upright_all(mspb)
        solids = []
        for e in mspb:
            corners = e.vertices() if e.dxf.hasattr("vtx3") else [
                e.dxf.vtx0, e.dxf.vtx1, e.dxf.vtx2]
            solids.append([list(v) for v in corners])
        result[name] = solids
    return result


def main(argv):
    out_dir = argv[0] if argv else "."
    os.makedirs(out_dir, exist_ok=True)
    result = build(out_dir)
    result["clip"] = build_clip(out_dir)
    result["elevation"] = build_elevation(out_dir)
    print(json.dumps(result, indent=1))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
