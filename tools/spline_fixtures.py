#!/usr/bin/env python3
"""Generate the SPLINE fixtures and ezdxf reference samples used by SplineTests.swift.

    python3 tools/spline_fixtures.py [out_dir]

Builds each spline with ezdxf, writes it to `<out_dir>/<name>.dxf`, then prints, per case, the
control data ezdxf reads back and ezdxf's curve evaluated at 9 evenly spaced parameters across the
valid domain. The printed values are pasted into Tests/SwiftDXFTests/SplineTests.swift.

Requires: pip install ezdxf
"""
import json
import os
import sys

import ezdxf
from ezdxf.math import BSpline

CASES = {
    # cubic, clamped, non-rational
    "cubic_clamped": dict(
        degree=3, flags=8,
        cps=[(0, 0, 0), (1, 3, 0), (3, 4, 0), (5, 1, 0), (7, 3, 0), (9, 0, 0)],
        knots=[0, 0, 0, 0, 1, 2, 3, 3, 3, 3], weights=[]),
    # quadratic rational circular arc (quarter circle) with weights
    "rational_arc": dict(
        degree=2, flags=12,
        cps=[(1, 0, 0), (1, 1, 0), (0, 1, 0)],
        knots=[0, 0, 0, 1, 1, 1], weights=[1.0, 0.7071067811865476, 1.0]),
    # cubic with non-uniform weights, 3D
    "rational_cubic_3d": dict(
        degree=3, flags=4,
        cps=[(0, 0, 0), (2, 5, 1), (5, 5, 2), (8, 0, 3), (10, 4, 1)],
        knots=[0, 0, 0, 0, 0.4, 1, 1, 1, 1], weights=[1, 2.5, 0.5, 3, 1]),
    # closed periodic cubic: control points wrap by `degree`, uniform unclamped knots
    "periodic_cubic": dict(
        degree=3, flags=3,
        cps=[(0, 0, 0), (4, 0, 0), (4, 4, 0), (0, 4, 0), (0, 0, 0), (4, 0, 0), (4, 4, 0)],
        knots=[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10], weights=[]),
    # degree 1 (polyline)
    "linear": dict(
        degree=1, flags=8, cps=[(0, 0, 0), (2, 1, 0), (4, 0, 0)],
        knots=[0, 0, 1, 2, 2], weights=[]),
}


def build(name, c, out_dir):
    doc = ezdxf.new("R2000")
    msp = doc.modelspace()
    sp = msp.add_spline(dxfattribs={"layer": "CURVES", "color": 5})
    sp.dxf.degree = c["degree"]
    sp.dxf.flags = c["flags"]
    sp.control_points = c["cps"]
    sp.knots = c["knots"]
    if c["weights"]:
        sp.weights = c["weights"]
    path = os.path.join(out_dir, name + ".dxf")
    doc.saveas(path)
    back = ezdxf.readfile(path).modelspace()[0]
    bs = BSpline(
        [tuple(p) for p in back.control_points], order=back.dxf.degree + 1,
        knots=list(back.knots), weights=list(back.weights) or None)
    p, n = back.dxf.degree, len(back.control_points)
    lo, hi = bs.knots()[p], bs.knots()[n]
    ts = [lo + (hi - lo) * i / 8 for i in range(9)]
    # Evaluate just inside the upper end: ezdxf's clamped evaluation at the exact end is fine,
    # but unclamped (periodic) knots need t < hi.
    ts[-1] = hi - 1e-12 if c["flags"] & 2 else hi
    pts = [tuple(bs.point(t)) for t in ts]
    return {"name": name, "degree": back.dxf.degree, "flags": back.dxf.flags,
            "layer": back.dxf.layer, "color": back.dxf.color,
            "control": [tuple(p) for p in back.control_points],
            "knots": list(back.knots), "weights": list(back.weights),
            "ts": ts, "points": pts}


def main(argv):
    out_dir = argv[0] if argv else "."
    os.makedirs(out_dir, exist_ok=True)
    for name, c in CASES.items():
        print(json.dumps(build(name, c, out_dir)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
