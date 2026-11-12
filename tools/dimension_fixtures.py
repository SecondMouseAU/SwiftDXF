#!/usr/bin/env python3
"""Generate the DIMENSION fixture and ezdxf reference values used by DimensionTests.swift.

    python3 tools/dimension_fixtures.py [out_dir]

Builds `<out_dir>/dimensions.dxf` with ezdxf: linear dimensions (horizontal, vertical, rotated and
oblique), aligned, radius, diameter and angular dimensions, dimension styles that set the
decimal places, zero suppression, linear scale and unit suffix, per-entity DSTYLE overrides, and
dimensions whose stored measurement is positive, zero and negative. Then it prints, as JSON, what
ezdxf reads back: its own measurement (`Dimension.get_measurement()`, geometry with no scale
applied), the rotation, the style name and the overrides. The values are pasted into
Tests/SwiftDXFTests/DimensionTests.swift.

Requires: pip install ezdxf
"""
import json
import os
import sys

import ezdxf


def build(out_dir):
    doc = ezdxf.new("R2018", setup=True)
    doc.dimstyles.new("PLAIN", dxfattribs={"dimdec": 2, "dimzin": 8})
    doc.dimstyles.new("SCALED", dxfattribs={"dimdec": 3, "dimlfac": 2.0, "dimpost": "<> mm"})
    doc.dimstyles.new("NOPREC")  # states none of the four variables

    msp = doc.modelspace()
    # Linear: horizontal, vertical, rotated.
    msp.add_linear_dim(base=(0, 5), p1=(0, 0), p2=(40, 0), dimstyle="PLAIN").render()
    msp.add_linear_dim(base=(-5, 0), p1=(0, 0), p2=(0, 25), angle=90, dimstyle="PLAIN").render()
    msp.add_linear_dim(
        base=(60, 5), p1=(50, 0), p2=(70, 20), angle=30, dimstyle="SCALED").render()
    # Aligned.
    msp.add_aligned_dim(p1=(0, 40), p2=(30, 60), distance=4, dimstyle="PLAIN").render()
    # Radius and diameter.
    msp.add_radius_dim(center=(100, 20), radius=7.5, angle=45, dimstyle="PLAIN").render()
    msp.add_diameter_dim(center=(130, 20), radius=6, angle=135, dimstyle="PLAIN").render()
    # Angular: no computed value.
    msp.add_angular_dim_2l(
        base=(0, 100), line1=((0, 80), (20, 80)), line2=((0, 80), (10, 95)),
        dimstyle="PLAIN").render()
    # Per-entity overrides in DSTYLE extended data.
    msp.add_linear_dim(
        base=(0, 120), p1=(0, 110), p2=(12.5, 110), dimstyle="PLAIN",
        override={"dimdec": 1, "dimzin": 4, "dimlfac": 25.4, "dimpost": "<> in"}).render()
    # A style that states nothing.
    msp.add_linear_dim(base=(0, 140), p1=(0, 130), p2=(8, 130), dimstyle="NOPREC").render()
    # Text overrides.
    msp.add_linear_dim(
        base=(0, 160), p1=(0, 150), p2=(15, 150), dimstyle="PLAIN", text="<> mm").render()
    msp.add_linear_dim(
        base=(0, 180), p1=(0, 170), p2=(67, 170), dimstyle="PLAIN", text="67 mm\\P(max)").render()

    dims = [e for e in msp if e.dxftype() == "DIMENSION"]
    # Stored measurement: positive, zero and negative (McMaster sheets store -1).
    for dim, value in zip(dims[:3], (12.5, 0.0, -1.0)):
        dim.dxf.actual_measurement = value
    # An oblique angle and a rotation that is absent (group 50 omitted).
    dims[0].dxf.oblique_angle = 20.0
    dims[8].dxf.discard("angle")

    path = os.path.join(out_dir, "dimensions.dxf")
    doc.saveas(path)

    back = ezdxf.readfile(path)
    out = []
    for e in back.modelspace():
        if e.dxftype() != "DIMENSION":
            continue
        out.append({
            "handle": e.dxf.handle, "type": e.dxf.dimtype & 15,
            "measurement": e.get_measurement() if (e.dxf.dimtype & 15) != 2 else None,
            "stored": e.dxf.get("actual_measurement", None),
            "rotation": e.dxf.angle if e.dxf.hasattr("angle") else None,
            "oblique": e.dxf.oblique_angle if e.dxf.hasattr("oblique_angle") else None,
            "style": e.dxf.dimstyle, "text": e.dxf.get("text", None),
            "overrides": {k: v for k, v in e.override().dimstyle_attribs.items()},
        })
    styles = {}
    for s in back.dimstyles:
        styles[s.dxf.name] = {
            "handle": s.dxf.handle, "dimdec": s.dxf.get("dimdec", None),
            "dimzin": s.dxf.get("dimzin", None), "dimlfac": s.dxf.get("dimlfac", None),
            "dimpost": s.dxf.get("dimpost", None)}
    return {"dimensions": out, "styles": styles,
            "header": {k: back.header.get(k) for k in ("$DIMDEC", "$DIMZIN", "$DIMLFAC", "$DIMPOST")}}


def main(argv):
    out_dir = argv[0] if argv else "."
    os.makedirs(out_dir, exist_ok=True)
    print(json.dumps(build(out_dir), indent=1))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
