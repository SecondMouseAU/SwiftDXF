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


def main(argv):
    out_dir = argv[0] if argv else "."
    os.makedirs(out_dir, exist_ok=True)
    print(json.dumps(build(out_dir), indent=1))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
