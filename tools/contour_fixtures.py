#!/usr/bin/env python3
"""Generate the DXF fixtures used by ContourTests.swift.

    python3 tools/contour_fixtures.py [out_dir]

Each fixture is written with ezdxf. The expected areas and bounds asserted in the tests are
analytic (stated next to each case below), so no reference reader output needs pasting.

Requires: pip install ezdxf
"""
import math
import os
import sys

import ezdxf
from ezdxf import units


def new(unit=units.MM):
    doc = ezdxf.new("R2000")
    doc.units = unit
    return doc, doc.modelspace()


def rect_lines(msp, x0, y0, x1, y1, layer="0", reverse=False):
    pts = [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]
    edges = [(pts[i], pts[(i + 1) % 4]) for i in range(4)]
    if reverse:
        edges = [(b, a) for a, b in reversed(edges)]
    for a, b in edges:
        msp.add_line(a, b, dxfattribs={"layer": layer})


def rounded_rect(msp, w, h, r, layer="0"):
    b = math.tan(math.pi / 8)
    pts = [
        (r, 0, 0), (w - r, 0, b), (w, r, 0), (w, h - r, b),
        (w - r, h, 0), (r, h, b), (0, h - r, 0), (0, r, b),
    ]
    msp.add_lwpolyline(pts, format="xyb", close=True, dxfattribs={"layer": layer})


def case_square():  # area 100, bounds (0,0)-(10,10)
    doc, msp = new()
    rect_lines(msp, 0, 0, 10, 10)
    return doc


def case_rounded_rect():  # 40 x 20, r 5: area 800 - (4 - pi) * 25
    doc, msp = new()
    rounded_rect(msp, 40, 20, 5)
    return doc


def case_plate_holes():  # 100 x 60 plate, three holes r 5: area 6000 - 75 pi
    doc, msp = new()
    msp.add_lwpolyline([(0, 0), (100, 0), (100, 60), (0, 60)], close=True)
    for c in [(20, 30), (50, 30), (80, 30)]:
        msp.add_circle(c, 5)
    return doc


def case_nested():  # squares 100 / 80 / 60 / 40 centred: shapes 3600 and 2000
    doc, msp = new()
    for size in (100, 80, 60, 40):
        o = (100 - size) / 2
        msp.add_lwpolyline(
            [(o, o), (o + size, o), (o + size, o + size), (o, o + size)], close=True)
    return doc


def case_slot_shuffled():  # slot, centres (0,0) and (20,0), r 10: area 100 pi + 400
    doc, msp = new()
    msp.add_line((20, -10), (0, -10))  # reversed
    msp.add_arc((20, 0), 10, -90, 90)
    msp.add_line((0, 10), (20, 10))
    msp.add_arc((0, 0), 10, 90, 270)
    return doc


def case_gap(width):  # unit square with the last side stopping `width` short
    doc, msp = new()
    msp.add_line((0, 0), (10, 0))
    msp.add_line((10, 0), (10, 10))
    msp.add_line((10, 10), (0, 10))
    msp.add_line((0, 10), (0, width))
    return doc


def case_duplicates():  # one square, one circle r 3, each drawn twice
    doc, msp = new()
    rect_lines(msp, 0, 0, 10, 10)
    rect_lines(msp, 0, 0, 10, 10, reverse=True)
    msp.add_circle((5, 5), 3)
    msp.add_circle((5, 5), 3)
    return doc


def case_ellipse():  # a = 30, b = 15 rotated 30 degrees: area 450 pi
    doc, msp = new()
    a = 30
    t = math.radians(30)
    msp.add_ellipse((100, 50), (a * math.cos(t), a * math.sin(t), 0), ratio=0.5)
    return doc


def case_ellipse_round():  # ratio 1: an exact circle r 12, area 144 pi
    doc, msp = new()
    msp.add_ellipse((0, 0), (12, 0, 0), ratio=1.0)
    return doc


def case_spline():  # clamped cubic closed by one line
    doc, msp = new()
    cps = [(0, 0), (10, 25), (30, 30), (50, 10), (70, 25), (80, 0)]
    msp.add_open_spline(cps, degree=3)
    msp.add_line((80, 0), (0, 0))
    return doc


def case_inch():  # 2 x 2 inch square declared as inches: 50.8 mm side
    doc, msp = new(units.IN)
    rect_lines(msp, 0, 0, 2, 2)
    return doc


def case_unitless():
    doc, msp = new(0)
    rect_lines(msp, 0, 0, 10, 10)
    return doc


def case_layers():
    doc, msp = new()
    doc.layers.add("CUT")
    doc.layers.add("GUIDES")
    doc.layers.add("NOTES")
    rect_lines(msp, 0, 0, 10, 10, layer="CUT")
    msp.add_circle((50, 50), 4, dxfattribs={"layer": "GUIDES"})
    msp.add_text("note", dxfattribs={"layer": "NOTES", "height": 2})
    block = doc.blocks.new("PART")
    block.add_line((0, 0), (1, 1))
    msp.add_blockref("PART", (100, 100), dxfattribs={"layer": "GUIDES"})
    msp.add_hatch(dxfattribs={"layer": "CUT"})
    return doc


CASES = {
    "square": case_square,
    "rounded_rect": case_rounded_rect,
    "plate_holes": case_plate_holes,
    "nested": case_nested,
    "slot_shuffled": case_slot_shuffled,
    "gap_within": lambda: case_gap(0.005),
    "gap_beyond": lambda: case_gap(0.5),
    "duplicates": case_duplicates,
    "ellipse": case_ellipse,
    "ellipse_round": case_ellipse_round,
    "spline": case_spline,
    "inch": case_inch,
    "unitless": case_unitless,
    "layers": case_layers,
}


def main(argv):
    out = argv[0] if argv else "."
    os.makedirs(out, exist_ok=True)
    for name, build in CASES.items():
        build().saveas(os.path.join(out, name + ".dxf"))
        print("wrote", name)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
