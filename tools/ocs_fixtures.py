#!/usr/bin/env python3
"""Generate the object-coordinate-system fixture and ezdxf reference values.

    python3 tools/ocs_fixtures.py [out_dir]

Builds `<out_dir>/ocs.dxf` with ezdxf: one of each entity that is written in its own coordinate
system (ARC, CIRCLE, LWPOLYLINE, POLYLINE, ELLIPSE, TEXT, HATCH, DIMENSION) with an extrusion of
(0, 0, -1), the same kinds with the default extrusion, one with a tilted extrusion, and a block that
holds a flipped arc. It then prints, as JSON, the world-coordinate values ezdxf gives for them.
ARC, CIRCLE, LWPOLYLINE, POLYLINE, ELLIPSE and HATCH come from `ezdxf.upright`, which is ezdxf's own
conversion of a flipped entity; TEXT and DIMENSION from `ocs.to_wcs`. The values are pasted into
Tests/SwiftDXFTests/ExtrusionTests.swift.

Requires: pip install ezdxf
"""
import json
import math
import os
import sys

import ezdxf
from ezdxf.math import UCS, Vec3
from ezdxf.upright import upright_all

DOWN = {"extrusion": (0, 0, -1)}


def build(out_dir):
    doc = ezdxf.new("R2018")
    msp = doc.modelspace()

    msp.add_arc((3, 4, 1), 5, 20, 110, dxfattribs=DOWN)
    msp.add_circle((2, 3, 1), 1.5, dxfattribs=DOWN)
    msp.add_lwpolyline(
        [(0, 0, 0.5), (4, 0, 0), (4, 3, -0.25)], format="xyb",
        dxfattribs={"extrusion": (0, 0, -1), "elevation": 2})
    msp.add_polyline2d(
        [(1, 1, 0.5), (5, 1, 0), (5, 4, 0)], format="xyb",
        dxfattribs={"extrusion": (0, 0, -1), "elevation": (0, 0, 3)})
    msp.add_ellipse((1, 2), (4, 0), 0.5, 0.3, 2.0, dxfattribs=DOWN)
    msp.add_text("note", height=2.5, rotation=30, dxfattribs={"insert": (5, 1), **DOWN})

    hatch = msp.add_hatch(color=1, dxfattribs=DOWN)
    hatch.paths.add_polyline_path([(0, 0), (4, 0), (4, 3), (0, 3)], is_closed=True)
    edges = hatch.paths.add_edge_path()
    edges.add_line((10, 0), (14, 0))
    edges.add_arc((12, 0), 2, 0, 180, ccw=True)

    dim = msp.add_linear_dim(base=(3, 2), p1=(0, 0), p2=(4, 0))
    dim.dimension.dxf.extrusion = (0, 0, -1)
    dim.dimension.dxf.text_midpoint = (-2, 3, 0.5)

    # The same kinds with the default extrusion, to show nothing moves; one tilted entity.
    msp.add_arc((3, 4, 1), 5, 20, 110)
    msp.add_lwpolyline([(0, 0), (4, 0), (4, 3)], dxfattribs={"elevation": 5})
    msp.add_arc((1, 1), 2, 0, 90, dxfattribs={"extrusion": (1, 0, 0)})

    # An arc whose range wraps through 0, an ellipse edge and a spline edge, a rotated linear
    # dimension and an angular one with a point in the OCS (group 16).
    msp.add_arc((0, 0), 3, 300, 50, dxfattribs=DOWN)
    hatch2 = msp.add_hatch(color=2, dxfattribs=DOWN)
    edges2 = hatch2.paths.add_edge_path()
    edges2.add_ellipse((6, 1), (3, 0), 0.5, 0, 180, ccw=True)
    edges2.add_spline(
        control_points=[(0, 0), (1, 2), (3, 2), (4, 0)], degree=3,
        knot_values=[0, 0, 0, 0, 1, 1, 1, 1])
    # Rendered in a flipped UCS: the definition points are written in the world, the angle in the
    # OCS, and the extrusion is -z.
    dim2 = msp.add_linear_dim(base=(3, 2), p1=(0, 0), p2=(4, 3), angle=30)
    dim2.render(ucs=UCS(ux=(-1, 0, 0), uz=(0, 0, -1)))
    dim3 = msp.add_angular_dim_3p(base=(5, 5), center=(0, 0), p1=(4, 0), p2=(0, 4))
    dim3.dimension.dxf.extrusion = (0, 0, -1)
    dim3.dimension.dxf.defpoint5 = (-3, 2, 1)
    dim3.dimension.dxf.text_midpoint = (-1, 2, 0)

    block = doc.blocks.new("FLIPPED")
    block.add_arc((1, 0), 1, 0, 90, dxfattribs=DOWN)
    msp.add_blockref("FLIPPED", (20, 10))

    path = os.path.join(out_dir, "ocs.dxf")
    doc.saveas(path)
    return path


def world_text(e):
    ocs = e.ocs()
    origin = ocs.to_wcs(Vec3(0, 0, 0))
    r = math.radians(e.dxf.rotation)
    d = ocs.to_wcs(Vec3(math.cos(r), math.sin(r), 0)) - origin
    return {"insert": list(ocs.to_wcs(e.dxf.insert)),
            "rotation": math.degrees(math.atan2(d.y, d.x)), "height": e.dxf.height}


def ellipse_points(e, n=20):
    s, t = e.dxf.start_param, e.dxf.end_param
    if t <= s:
        t += 2 * math.pi
    c, m = e.dxf.center, e.dxf.major_axis
    minor = Vec3(e.dxf.extrusion).cross(m).normalize(m.magnitude * e.dxf.ratio)
    pts = []
    for k in range(n + 1):
        u = s + (t - s) * k / n
        p = c + m * math.cos(u) + minor * math.sin(u)
        pts.append([p.x, p.y, p.z])
    return pts


def reference(path):
    # The distance of the rotated dimension's points (0, 0) and (4, 3) along 30 degrees, in the
    # flipped UCS it was drawn in. ezdxf's own get_measurement() gives a different number for a
    # file with a -z extrusion, because it passes the world definition points through the OCS.
    measure = abs(4 * math.cos(math.radians(30)) + 3 * math.sin(math.radians(30)))

    back = ezdxf.readfile(path)
    msp = back.modelspace()
    out = {"text": [], "dimension": [], "polyline2d": [], "rotatedDimensionMeasurement": measure}
    # TEXT, DIMENSION and the 2D polyline's points are read before ezdxf turns the others upright.
    for e in msp:
        if e.dxftype() == "TEXT":
            out["text"].append(world_text(e))
        elif e.dxftype() == "POLYLINE":
            out["polyline2d"].append([list(p) for p in e.points_in_wcs()])
        elif e.dxftype() == "DIMENSION":
            ocs = e.ocs()
            row = {"textMidpoint": list(ocs.to_wcs(e.dxf.text_midpoint)),
                   "angle": e.dxf.angle if e.dxf.hasattr("angle") else None,
                   "defpoint2": list(e.dxf.defpoint2) if e.dxf.hasattr("defpoint2") else None,
                   "defpoint3": list(e.dxf.defpoint3) if e.dxf.hasattr("defpoint3") else None,
                   "extrusion": list(e.dxf.extrusion)}
            if e.dxf.hasattr("defpoint5"):
                row["defpoint5"] = list(ocs.to_wcs(e.dxf.defpoint5))
            out["dimension"].append(row)
    for block in back.blocks:
        if block.name == "FLIPPED":
            upright_all(block)
    upright_all(msp)
    rows = []
    for e in msp:
        t = e.dxftype()
        if t == "ARC":
            rows.append({"type": t, "center": list(e.dxf.center), "radius": e.dxf.radius,
                         "start": e.dxf.start_angle, "end": e.dxf.end_angle,
                         "extrusion": list(e.dxf.extrusion)})
        elif t == "CIRCLE":
            rows.append({"type": t, "center": list(e.dxf.center), "radius": e.dxf.radius})
        elif t == "LWPOLYLINE":
            rows.append({"type": t, "elevation": e.dxf.elevation,
                         "points": [list(p) for p in e.get_points("xyb")]})
        elif t == "POLYLINE":
            rows.append({"type": t, "vertices": [
                [v.dxf.location.x, v.dxf.location.y, v.dxf.location.z, v.dxf.bulge]
                for v in e.vertices]})
        elif t == "ELLIPSE":
            rows.append({"type": t, "points": ellipse_points(e)})
        elif t == "HATCH":
            paths = []
            for p in e.paths:
                if type(p).__name__ == "PolylinePath":
                    paths.append({"kind": "polyline", "vertices": [list(v) for v in p.vertices]})
                else:
                    edges = []
                    for ed in p.edges:
                        kind = type(ed).__name__
                        if kind == "LineEdge":
                            edges.append({"type": "line", "start": list(ed.start),
                                          "end": list(ed.end)})
                        elif kind == "ArcEdge":
                            edges.append({"type": "arc", "center": list(ed.center),
                                          "radius": ed.radius, "start": ed.start_angle,
                                          "end": ed.end_angle, "ccw": bool(ed.ccw)})
                        elif kind == "EllipseEdge":
                            edges.append({"type": "ellipse", "center": list(ed.center),
                                          "major": list(ed.major_axis), "ratio": ed.ratio,
                                          "startParam": ed.start_param,
                                          "endParam": ed.end_param, "ccw": bool(ed.ccw)})
                        elif kind == "SplineEdge":
                            edges.append({"type": "spline",
                                          "control": [list(c) for c in ed.control_points]})
                    paths.append({"kind": "edges", "edges": edges})
            rows.append({"type": t, "paths": paths})
    out["modelSpace"] = rows
    flipped = back.blocks.get("FLIPPED")
    out["block"] = [{"type": e.dxftype(), "center": list(e.dxf.center), "radius": e.dxf.radius,
                     "start": e.dxf.start_angle, "end": e.dxf.end_angle} for e in flipped]
    return out


def main(argv):
    out_dir = argv[0] if argv else "."
    os.makedirs(out_dir, exist_ok=True)
    print(json.dumps(reference(build(out_dir)), indent=1))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
