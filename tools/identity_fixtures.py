#!/usr/bin/env python3
"""Generate the handle fixture and ezdxf reference values used by IdentityTests.swift.

    python3 tools/identity_fixtures.py [out_dir]

Builds a drawing with ezdxf that has model-space entities (one of them an INSERT, which SwiftDXF
skips), a block with its own entities, a layer, a line type and a dimension style. It writes
`<out_dir>/handles.dxf`, then prints the handles ezdxf reads back as JSON. The printed values are
pasted into Tests/SwiftDXFTests/IdentityTests.swift.

Requires: pip install ezdxf
"""
import json
import os
import sys

import ezdxf

MODELLED = {"LINE", "CIRCLE", "ARC", "ELLIPSE", "POINT", "TEXT", "MTEXT", "LWPOLYLINE",
            "POLYLINE", "DIMENSION", "SPLINE"}


def build(out_dir):
    doc = ezdxf.new("R2018")
    doc.layers.add("OUTLINE", color=3)
    doc.dimstyles.new("MYSTYLE")

    block = doc.blocks.new("PART", base_point=(1, 2, 0))
    block.add_line((0, 0), (5, 0))
    block.add_circle((2, 2), 1)

    msp = doc.modelspace()
    msp.add_line((0, 0), (10, 0), dxfattribs={"layer": "OUTLINE"})
    msp.add_blockref("PART", (20, 0))
    msp.add_circle((5, 5), 2)
    msp.add_lwpolyline([(0, 0), (4, 0), (4, 4)], close=True)
    msp.add_text("note", height=2.5, dxfattribs={"insert": (1, 1)})

    path = os.path.join(out_dir, "handles.dxf")
    doc.saveas(path)

    back = ezdxf.readfile(path)
    modelled = [e for e in back.modelspace() if e.dxftype() in MODELLED]
    part = back.blocks.get("PART")
    return {
        "entities": [[e.dxftype(), e.dxf.handle] for e in modelled],
        "allModelSpace": [[e.dxftype(), e.dxf.handle] for e in back.modelspace()],
        "block": {"name": "PART", "handle": part.block.dxf.handle,
                  "entities": [[e.dxftype(), e.dxf.handle] for e in part]},
        "layer": {"name": "OUTLINE", "handle": back.layers.get("OUTLINE").dxf.handle},
        "dimstyle": {"name": "MYSTYLE", "handle": back.dimstyles.get("MYSTYLE").dxf.handle},
    }


def main(argv):
    out_dir = argv[0] if argv else "."
    os.makedirs(out_dir, exist_ok=True)
    print(json.dumps(build(out_dir), indent=1))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
