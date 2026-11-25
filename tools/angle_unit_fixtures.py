#!/usr/bin/env python3
"""Generate the angle unit fixture and the reference values for AngleUnitTests.

    python3 tools/angle_unit_fixtures.py [out_dir]

Builds `<out_dir>/angle_units.dxf` with ezdxf: dimension styles that show an angle in each
`DIMAUNIT` (0 decimal degrees, 1 degrees/minutes/seconds, 2 gradians, 3 radians) with a
`DIMADEC`, a style whose `DIMADEC` is -1 (use `DIMDEC`), a header
that holds its own `$DIMAUNIT` and `$DIMADEC`, and angular dimensions of 45.5 degrees in those
styles, one with its unit and places overridden in the entity's DSTYLE extended data. Then it
prints, as JSON, what ezdxf reads back and wrote:

- `styles`: each DIMSTYLE record's `dimaunit` and `dimadec` (`null` where the record does not
  state one; ezdxf writes every variable, so there is always one here).
- `header`: `$DIMAUNIT` and `$DIMADEC`.
- `dimensions`: per dimension, the style name, `overrides` (ezdxf's own reading of the DSTYLE
  extended data), `measurement` (`get_measurement()`, in degrees) and `rendered`, the text ezdxf's
  own renderer wrote into the dimension's anonymous block (`45°30'`, `50.56g`, `0.7942r`).

The rendered texts are pasted into Tests/SwiftDXFTests/AngleUnitTests.swift, which reads each
with the style's unit and checks it against the computed measurement.

Requires: pip install ezdxf
"""
import json
import os
import sys

import ezdxf

# The sweep of every dimension: 45 degrees 30 minutes 15 seconds, so each unit has something to
# show that rounding then takes away.
START = 10.0
SWEEP = 45.0 + 30.0 / 60.0 + 15.0 / 3600.0


def build(out_dir):
    doc = ezdxf.new("R2018", setup=True)
    doc.header["$DIMAUNIT"] = 2
    doc.header["$DIMADEC"] = 3
    # name: (dimaunit, dimadec). ezdxf writes every variable of a record, so a record that states
    # neither is built by hand in the tests. The decimal mark is a point.
    styles = {
        "DEG1": (0, 1),
        "DMS0": (1, 0),
        "DMS2": (1, 2),
        "DMS4": (1, 4),
        "DMS6": (1, 6),
        "GRAD2": (2, 2),
        "RAD4": (3, 4),
        "USEDEC": (0, -1),
    }
    for name, (unit, places) in styles.items():
        doc.dimstyles.new(
            name, dxfattribs={"dimaunit": unit, "dimadec": places, "dimdsep": 46})

    msp = doc.modelspace()
    rendered = ["DEG1", "DMS0", "DMS2", "DMS4", "DMS6", "GRAD2", "RAD4"]
    for row, name in enumerate(rendered):
        msp.add_angular_dim_cra(
            center=(0, row * 40), radius=10, start_angle=START, end_angle=START + SWEEP,
            distance=15, dimstyle=name).render()
    # Overridden in the entity: the style says degrees, the dimension says minutes and seconds.
    msp.add_angular_dim_cra(
        center=(0, 400), radius=10, start_angle=START, end_angle=START + SWEEP, distance=15,
        dimstyle="DEG1", override={"dimaunit": 1, "dimadec": 4}).render()
    # A text override that states the angle in the style's unit.
    msp.add_angular_dim_cra(
        center=(0, 440), radius=10, start_angle=START, end_angle=START + SWEEP, distance=15,
        dimstyle="DMS4", text="<> typed 45°30'15\"").render()

    path = os.path.join(out_dir, "angle_units.dxf")
    doc.saveas(path)

    back = ezdxf.readfile(path)
    dims = []
    for e in back.modelspace():
        if e.dxftype() != "DIMENSION":
            continue
        texts = [t.text if t.dxftype() == "MTEXT" else t.dxf.text
                 for t in back.blocks[e.dxf.geometry] if t.dxftype() in ("MTEXT", "TEXT")]
        dims.append({
            "handle": e.dxf.handle, "style": e.dxf.dimstyle,
            "overrides": {k: v for k, v in e.override().dimstyle_attribs.items()},
            "measurement": e.get_measurement(), "text": e.dxf.get("text", None),
            "rendered": texts,
        })
    records = {}
    for s in back.dimstyles:
        records[s.dxf.name] = {
            "dimaunit": s.dxf.get("dimaunit", None), "dimadec": s.dxf.get("dimadec", None)}
    return {
        "styles": records, "dimensions": dims,
        "header": {k: back.header.get(k) for k in ("$DIMAUNIT", "$DIMADEC")},
    }


def main(argv):
    out_dir = argv[0] if argv else "."
    os.makedirs(out_dir, exist_ok=True)
    print(json.dumps(build(out_dir), indent=1, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
