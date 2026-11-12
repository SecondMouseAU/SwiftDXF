#!/usr/bin/env python3
"""Generate the HATCH / LEADER / line type / layer fixture and ezdxf reference values.

    python3 tools/hatch_fixtures.py [out_dir]

Builds `<out_dir>/hatch.dxf` with ezdxf: layers that are off, frozen and locked, entities on
dashed layers and with explicit line types, hatches with polyline and edge boundary paths
(line, arc, clockwise arc, ellipse, spline edges), and leaders. Then it prints, as JSON, what
ezdxf reads back from that file. The values are pasted into Tests/SwiftDXFTests/HatchTests.swift.

Requires: pip install ezdxf
"""
import json
import math
import os
import sys

import ezdxf
from ezdxf import const
from ezdxf import path as ezpath


def vec(v):
    return [v[0], v[1]]


def edge_json(e):
    kind = type(e).__name__
    if kind == "LineEdge":
        return {"type": "line", "start": vec(e.start), "end": vec(e.end)}
    if kind == "ArcEdge":
        return {"type": "arc", "center": vec(e.center), "radius": e.radius,
                "start": e.start_angle, "end": e.end_angle, "ccw": bool(e.ccw)}
    if kind == "EllipseEdge":
        return {"type": "ellipse", "center": vec(e.center), "major": vec(e.major_axis),
                "ratio": e.ratio, "start": e.start_angle, "end": e.end_angle,
                "ccw": bool(e.ccw), "startParam": e.start_param, "endParam": e.end_param}
    if kind == "SplineEdge":
        return {"type": "spline", "degree": e.degree, "rational": bool(e.rational),
                "periodic": bool(e.periodic), "knots": list(e.knot_values),
                "control": [vec(p) for p in e.control_points],
                "weights": list(e.weights), "fit": [vec(p) for p in e.fit_points]}
    raise ValueError(kind)


def path_json(p):
    out = {"flags": p.path_type_flags}
    if type(p).__name__ == "PolylinePath":
        out["kind"] = "polyline"
        out["closed"] = bool(p.is_closed)
        out["vertices"] = [[v[0], v[1], v[2]] for v in p.vertices]
    else:
        out["kind"] = "edges"
        out["edges"] = [edge_json(e) for e in p.edges]
    return out


def build(out_dir):
    doc = ezdxf.new("R2018", setup=True)
    # ezdxf's setup has no HIDDEN type; define it (dash 0.25, gap 0.125).
    doc.linetypes.add("HIDDEN", pattern=[0.375, 0.25, -0.125], description="Hidden __ __ __")
    doc.layers.add("VISIBLE", color=7, linetype="Continuous")
    doc.layers.add("HID", color=1, linetype="HIDDEN")
    doc.layers.add("CENTRE", color=2, linetype="CENTER")
    doc.layers.add("OFFLAYER", color=3).off()
    doc.layers.add("FROZEN", color=4).freeze()
    doc.layers.add("LOCKED", color=5).lock()
    doc.layers.add("NOTES", color=6)

    msp = doc.modelspace()
    # Line types: by layer (absent), explicit, BYBLOCK, spelled BYLAYER.
    msp.add_line((0, 0), (10, 0), dxfattribs={"layer": "HID"})
    msp.add_line((0, 1), (10, 1), dxfattribs={"layer": "VISIBLE", "linetype": "PHANTOM"})
    msp.add_line((0, 2), (10, 2), dxfattribs={"layer": "HID", "linetype": "ByBlock"})
    msp.add_line((0, 3), (10, 3), dxfattribs={"layer": "HID", "linetype": "ByLayer"})
    msp.add_line((0, 4), (10, 4))

    # Solid hatch: a rectangle with a rounded corner (bulge) and a square hole.
    h1 = msp.add_hatch(color=2, dxfattribs={"layer": "VISIBLE"})
    h1.paths.add_polyline_path(
        [(0, 10, 0), (10, 10, 0), (10, 20, 0.5), (0, 20, 0)], is_closed=True,
        flags=const.BOUNDARY_PATH_EXTERNAL | const.BOUNDARY_PATH_POLYLINE)
    h1.paths.add_polyline_path(
        [(3, 13), (6, 13), (6, 16), (3, 16)], is_closed=True, flags=const.BOUNDARY_PATH_DEFAULT)

    # Pattern hatch whose single edge path is a closed loop of line, arc, ellipse and spline.
    h2 = msp.add_hatch(dxfattribs={"layer": "VISIBLE"})
    h2.set_pattern_fill("ANSI31", scale=0.5, angle=45)
    edges = h2.paths.add_edge_path(flags=const.BOUNDARY_PATH_EXTERNAL)
    edges.add_line((20, 10), (30, 10))
    edges.add_arc((30, 12), 2, 270, 90, ccw=True)
    edges.add_ellipse((25, 14), (3, 0), 0.5, 0, 180, ccw=True)
    edges.add_spline(
        control_points=[(22, 14), (21, 12), (20, 12)], knot_values=[0, 0, 0, 1, 1, 1], degree=2)
    edges.add_line((20, 12), (20, 10))

    # Edge path with a clockwise arc.
    h3 = msp.add_hatch(dxfattribs={"layer": "VISIBLE"})
    h3.set_pattern_fill("LINE", scale=1)
    cw = h3.paths.add_edge_path(flags=const.BOUNDARY_PATH_EXTERNAL)
    cw.add_line((40, 10), (50, 10))
    cw.add_arc((45, 10), 5, 0, 180, ccw=False)

    # Partial ellipse edges, counter-clockwise and clockwise: the angle to parameter conversion.
    h4 = msp.add_hatch(dxfattribs={"layer": "VISIBLE"})
    h4.set_pattern_fill("LINE", scale=1)
    ccw_e = h4.paths.add_edge_path(flags=const.BOUNDARY_PATH_EXTERNAL)
    ccw_e.add_ellipse((100, 10), (4, 2), 0.4, 30, 250, ccw=True)
    h5 = msp.add_hatch(dxfattribs={"layer": "VISIBLE"})
    h5.set_pattern_fill("LINE", scale=1)
    cw_e = h5.paths.add_edge_path(flags=const.BOUNDARY_PATH_EXTERNAL)
    cw_e.add_ellipse((120, 10), (4, 2), 0.4, 30, 250, ccw=False)

    note = msp.add_mtext("NOTE", dxfattribs={"insert": (60, 15), "layer": "NOTES"})
    ld1 = msp.add_leader([(60, 15), (65, 20), (70, 20)], dxfattribs={"layer": "NOTES"})
    ld1.dxf.annotation_handle = note.dxf.handle
    ld2 = msp.add_leader([(80, 10), (85, 15)], dxfattribs={"layer": "NOTES"})
    ld2.dxf.has_arrowhead = 0

    path = os.path.join(out_dir, "hatch.dxf")
    doc.saveas(path)

    back = ezdxf.readfile(path)
    mspb = back.modelspace()
    hatches, leaders = [], []
    for e in mspb:
        if e.dxftype() == "HATCH":
            paths = [path_json(p) for p in e.paths]
            # Area of each boundary as ezdxf flattens it (an open path is closed by its chord).
            for pj, boundary in zip(paths, ezpath.from_hatch(e)):
                pts = [(v.x, v.y) for v in boundary.flattening(0.0002)]
                pj["area"] = abs(sum(
                    pts[i][0] * pts[(i + 1) % len(pts)][1] - pts[(i + 1) % len(pts)][0] * pts[i][1]
                    for i in range(len(pts)))) / 2
            hatches.append({
                "handle": e.dxf.handle, "pattern": e.dxf.pattern_name,
                "solid": bool(e.dxf.solid_fill), "layer": e.dxf.layer, "paths": paths})
        elif e.dxftype() == "LEADER":
            leaders.append({
                "handle": e.dxf.handle, "vertices": [list(v) for v in e.vertices],
                "arrow": bool(e.dxf.has_arrowhead), "pathType": e.dxf.path_type,
                "annotationType": e.dxf.annotation_type,
                "annotation": e.dxf.get("annotation_handle", None)})
    lines = [[e.dxf.layer, e.dxf.get("linetype", None)] for e in mspb if e.dxftype() == "LINE"]
    return {
        "layers": {l.dxf.name: {"color": l.color, "linetype": l.dxf.linetype,
                                "off": l.is_off(), "frozen": l.is_frozen(),
                                "locked": l.is_locked()} for l in back.layers},
        "lineTypes": {t.dxf.name: [round(x, 9) for x in t.pattern_tags.compile()]
                      for t in back.linetypes},
        "lines": lines,
        "hatches": hatches,
        "leaders": leaders,
    }


def main(argv):
    out_dir = argv[0] if argv else "."
    os.makedirs(out_dir, exist_ok=True)
    print(json.dumps(build(out_dir), indent=1))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
