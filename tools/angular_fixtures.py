#!/usr/bin/env python3
"""Generate the angular and ordinate DIMENSION fixture and the reference values for AngularDimensionTests.

    python3 tools/angular_fixtures.py [out_dir]

Builds `<out_dir>/angular.dxf` with ezdxf: three-point angular dimensions, two-line angular
dimensions with the arc location in each of the four angles the two lines make, and ordinate
dimensions of both types. Then it prints, as JSON, for each dimension:

- `ezdxf`: what ezdxf's `Dimension.get_measurement()` gives. For an angular dimension that is the
  angle counter-clockwise from the first line (or ray) to the second, in degrees, whichever side
  the arc location is on; for an ordinate dimension it is the vector from the origin to the feature
  location, and `ezdxf` here is its length along the measured axis.
- `rendered`: the text ezdxf's own renderer wrote into the dimension's anonymous block.
- `arcSide`: the angle on the side of the arc location, which is what AutoCAD displays. This is
  not ezdxf's number where the arc location is on the other side. It was checked against AutoCAD's
  own anonymous blocks in two DWG files (8 three-point angular dimensions, 4 of which put the arc
  on the side ezdxf's number does not): AutoCAD wrote 125 and 130 where counter-clockwise from the
  first ray to the second is 235 and 230. Here it is worked out with ezdxf's vector maths, from
  the definition points, as an independent check of the Swift code.

The values are pasted into Tests/SwiftDXFTests/AngularDimensionTests.swift.

Requires: pip install ezdxf
"""
import json
import math
import os
import sys

import ezdxf
from ezdxf.math import Vec2, intersection_line_line_2d


def ccw(a, b):
    """The counter-clockwise turn from angle `a` to angle `b` in degrees, in [0, 360)."""
    return (b - a) % 360.0


def arc_side_3p(vertex, p1, p2, arc):
    """The angle at `vertex` from the ray to `p1` to the ray to `p2` on the side of `arc`."""
    a, b, w = ((p - vertex).angle_deg for p in (p1, p2, arc))
    turn = ccw(a, b)
    return turn if ccw(a, w) <= turn else 360.0 - turn


def arc_side_2l(line1, line2, arc):
    """The angle between the two lines, in the gap between their four rays that holds `arc`."""
    vertex = intersection_line_line_2d(line1, line2)
    d1, d2 = line1[1] - line1[0], line2[1] - line2[0]
    rays = sorted(a % 360.0 for a in (d1.angle_deg, d2.angle_deg, d1.angle_deg + 180, d2.angle_deg + 180))
    w = (arc - vertex).angle_deg % 360.0
    lower, upper = rays[3], rays[0] + 360.0
    for i in range(3):
        if rays[i] <= w < rays[i + 1]:
            lower, upper = rays[i], rays[i + 1]
    return upper - lower


def build(out_dir):
    doc = ezdxf.new("R2018", setup=True)
    msp = doc.modelspace()
    cases = []

    def three_point(name, center, p1, p2, base):
        dim = msp.add_angular_dim_3p(base=base, center=center, p1=p1, p2=p2)
        dim.render()
        v = [Vec2(p) for p in (center, p1, p2, base)]
        cases.append((name, dim.dimension, arc_side_3p(*v)))

    def two_line(name, line1, line2, base):
        dim = msp.add_angular_dim_2l(base=base, line1=line1, line2=line2)
        dim.render()
        l1, l2, b = [Vec2(p) for p in line1], [Vec2(p) for p in line2], Vec2(base)
        cases.append((name, dim.dimension, arc_side_2l(l1, l2, b)))

    # Three-point: the arc on the counter-clockwise side, then on the other, and the two rays in
    # the opposite order, each way. A vertex away from the origin, and an obtuse angle.
    three_point("3p ccw side", (0, 0), (10, 0), (0, 10), (7, 7))
    three_point("3p other side, over 180", (0, 0), (10, 0), (0, 10), (-7, -7))
    three_point("3p rays swapped, arc between", (0, 0), (0, 10), (10, 0), (7, 7))
    three_point("3p rays swapped, arc outside", (0, 0), (0, 10), (10, 0), (-7, -7))
    three_point("3p obtuse, vertex off the origin", (5, 5), (15, 5), (-1, 13), (5, 17))
    three_point("3p obtuse, over 180", (5, 5), (15, 5), (-1, 13), (5, -7))
    three_point("3p straight, arc above", (0, 0), (10, 0), (-10, 0), (0, 8))
    # Two-line, from the segments only: the lines cross at the origin, beyond the first segment.
    line1 = ((4, 0), (10, 0))
    line2 = ((3, 4), (6, 8))
    two_line("2l first angle", line1, line2, (10, 3))
    two_line("2l second angle", line1, line2, (0, 10))
    two_line("2l third angle", line1, line2, (-10, -3))
    two_line("2l fourth angle", line1, line2, (0, -10))
    two_line("2l lines reversed", line1[::-1], line2[::-1], (10, 3))
    two_line("2l crossing off the origin", ((10, 10), (20, 10)), ((12, 11), (14, 15)), (24, 14))

    # Ordinate dimensions: X type and Y type, towards the origin and away from it.
    msp.add_ordinate_x_dim(feature_location=(12.5, 7), offset=(0, 10), origin=(2, 3)).render()
    msp.add_ordinate_y_dim(feature_location=(12.5, 7), offset=(10, 0), origin=(2, 3)).render()
    msp.add_ordinate_x_dim(feature_location=(-4, -1), offset=(0, -10), origin=(2, 3)).render()
    msp.add_ordinate_y_dim(feature_location=(-4, -1), offset=(-10, 0), origin=(2, 3)).render()

    path = os.path.join(out_dir, "angular.dxf")
    doc.saveas(path)

    back = ezdxf.readfile(path)
    out = []
    for e in back.modelspace():
        if e.dxftype() != "DIMENSION":
            continue
        rendered = None
        for entity in back.blocks.get(e.dxf.geometry):
            if entity.dxftype() in ("MTEXT", "TEXT"):
                rendered = entity.dxf.text
        kind = e.dxf.dimtype & 15
        measured = e.get_measurement()
        row = {"handle": e.dxf.handle, "type": e.dxf.dimtype, "rendered": rendered}
        if kind == 6:
            x_type = bool(e.dxf.dimtype & 64)
            row["ezdxf"] = abs(measured.x if x_type else measured.y)
        else:
            row["ezdxf"] = measured
        for name, group in (("p10", "defpoint"), ("p13", "defpoint2"), ("p14", "defpoint3"),
                            ("p15", "defpoint4"), ("p16", "defpoint5")):
            if e.dxf.hasattr(group):
                p = getattr(e.dxf, group)
                row[name] = [p.x, p.y]
        out.append(row)
    for row, (name, _, side) in zip([r for r in out if r["type"] & 15 != 6], cases):
        row["name"] = name
        row["arcSide"] = side
    return out


def main(argv):
    out_dir = argv[0] if argv else "."
    os.makedirs(out_dir, exist_ok=True)
    print(json.dumps(build(out_dir), indent=1))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
