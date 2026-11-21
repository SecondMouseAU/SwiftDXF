#!/usr/bin/env python3
"""Generate the attribute fixtures and ezdxf reference values used by AttributeTests.swift.

    python3 tools/attrib_fixtures.py [out_dir]

Builds, with ezdxf, `<out_dir>/attributes.dxf` (R2000: a title block with attribute definitions,
one reference in model space that fills them in, one inside another block, and an invisible and a
constant attribute), `<out_dir>/attributes_mtext.dxf` (R2018: a multiline attribute and attribute
definition, which carry their `MTEXT` as an embedded object) and `<out_dir>/attributes_array.dxf`
(R2000: a rotated 2 by 2 array of a reference with a coloured attribute, and a rotated, scaled
block that holds a rotated reference with an attribute). Then prints, per file, what ezdxf reads
back from it, in the shape `dxfdump --attributes` prints; the values are pasted into
Tests/SwiftDXFTests/AttributeTests.swift and AttributeExpansionTests.swift.

Requires: pip install ezdxf
"""
import json
import os
import sys

import ezdxf
from ezdxf.entities import MText

from attrib_oracle import summarize

INVISIBLE = 1
CONSTANT = 2


def title_block(doc):
    block = doc.blocks.new("TITLE", base_point=(0, 0, 0))
    block.add_lwpolyline([(0, 0), (100, 0), (100, 40), (0, 40)], close=True)
    block.add_attdef(
        "DWG_NO", (5, 30), text="NO-0", height=5,
        dxfattribs={"prompt": "Drawing number", "layer": "TEXT"})
    block.add_attdef(
        "TITLE", (5, 20), text="UNTITLED", height=3.5,
        dxfattribs={"prompt": "Title", "layer": "TEXT"})
    block.add_attdef(
        "SCALE", (60, 5), text="1:1", height=2.5,
        dxfattribs={"prompt": "Scale", "flags": INVISIBLE})
    block.add_attdef(
        "COMPANY", (5, 5), text="ACME", height=2.5,
        dxfattribs={"prompt": "Company", "flags": CONSTANT})
    return block


def build_title(out_dir):
    doc = ezdxf.new("R2000")
    doc.layers.add("TEXT", color=3)
    title_block(doc)
    outer = doc.blocks.new("SHEET")
    outer.add_line((0, 0), (200, 0))
    inner = outer.add_blockref("TITLE", (10, 10))
    inner.add_attrib("DWG_NO", "S-7", (15, 40), {"height": 5, "layer": "TEXT"})

    msp = doc.modelspace()
    ref = msp.add_blockref("TITLE", (100, 50), dxfattribs={"rotation": 90})
    ref.add_attrib("DWG_NO", "D-1234 %%d5", (95, 105), {"height": 5, "layer": "TEXT",
                                                         "rotation": 90})
    ref.add_attrib("TITLE", "Plate %%c20 hole", (97, 120), {"height": 3.5, "layer": "TEXT",
                                                             "rotation": 90})
    ref.add_attrib("SCALE", "1:2", (112, 110), {"height": 2.5, "flags": INVISIBLE,
                                                 "rotation": 90})
    msp.add_blockref("SHEET", (300, 0))
    path = os.path.join(out_dir, "attributes.dxf")
    doc.saveas(path)
    return path


def build_mtext(out_dir):
    doc = ezdxf.new("R2018")
    block = doc.blocks.new("NOTE")
    block.add_circle((0, 0), 1)
    definition = block.add_attdef("NOTE", (2, 0), text="Note", height=2.5,
                                  dxfattribs={"prompt": "Note"})
    default = MText.new(dxfattribs={"insert": (2, 0), "char_height": 2.5})
    default.text = "First line\\PSecond line"
    definition.embed_mtext(default)

    msp = doc.modelspace()
    ref = msp.add_blockref("NOTE", (10, 10))
    attrib = ref.add_attrib("NOTE", "x", (12, 10), {"height": 2.5})
    filled = MText.new(dxfattribs={"insert": (12, 10), "char_height": 2.5})
    filled.text = "Bore \\U+2300 20\\PDepth 15 %%d"
    attrib.embed_mtext(filled)
    path = os.path.join(out_dir, "attributes_mtext.dxf")
    doc.saveas(path)
    return path


def build_array(out_dir):
    doc = ezdxf.new("R2000")
    title_block(doc)
    outer = doc.blocks.new("SHEET")
    outer.add_blockref("TITLE", (10, 0), dxfattribs={"rotation": 90}).add_attrib(
        "DWG_NO", "N-1", (15, 40), {"height": 5})

    msp = doc.modelspace()
    ref = msp.add_blockref(
        "TITLE", (0, 0),
        dxfattribs={"rotation": 90, "column_count": 2, "row_count": 2, "column_spacing": 150,
                    "row_spacing": 60})
    ref.add_attrib("DWG_NO", "A-1", (-5, 5), {"height": 5, "rotation": 90})
    ref.add_attrib("TITLE", "Array", (-20, 5), {"height": 3.5, "rotation": 90, "color": 3})
    msp.add_blockref("SHEET", (500, 0), dxfattribs={"rotation": 30, "xscale": 2, "yscale": 2})
    path = os.path.join(out_dir, "attributes_array.dxf")
    doc.saveas(path)
    return path


def main(argv):
    out_dir = argv[0] if argv else "."
    os.makedirs(out_dir, exist_ok=True)
    out = {}
    for path in (build_title(out_dir), build_mtext(out_dir), build_array(out_dir)):
        out[os.path.basename(path)] = summarize(path)
    print(json.dumps(out, indent=1, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
