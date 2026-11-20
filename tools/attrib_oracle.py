#!/usr/bin/env python3
"""Reference reading of ATTRIB and ATTDEF, using ezdxf (MIT-licensed).

    python3 tools/attrib_oracle.py file1.dxf [file2.dxf ...]
    python3 tools/attrib_oracle.py --compare .build/debug/dxfdump file1.dxf [...]

Prints, per file, one JSON line in the shape `dxfdump --attributes` prints: the block references
of model space that carry attributes (`Insert.attribs`), and for each block that has any, its
attribute definitions (`ATTDEF`) and the nested references that carry attributes. Only what has
attributes is listed. `expanded` lists the visible attributes of every reference, nested ones
included, as the texts `dxfdump --expand-attributes` makes of them: ezdxf's `virtual_entities()`
carries a nested reference's attributes through the blocks it sits in, as an expansion does.

With `--compare`, `dxfdump --attributes --expand-attributes --skip-paper-space` is run on the same
files (ezdxf's `modelspace()` leaves out the paper-space entities) and the two are compared field
by field (numbers to 1e-9, the references in file order, the blocks by name, the expanded texts as
sets); each difference is printed, and the exit status is 1 when there is one. A file whose
attributes have no handle is left out of the expanded comparison, which matches by handle.

What is the value of an attribute: `plain_text` of the `TEXT` string, or, for an R2018 multiline
attribute, the `MTextParser` tokens of its embedded `MTEXT` (both from `text_oracle.py`, so `%%c`
is the diameter sign and a stack reads `upper/lower`). ezdxf does not decode `%%nnn`, which
SwiftDXF reads through the drawing's code page. A position and rotation written on a `-z` plane
are turned into the world, as SwiftDXF does.

Requires: pip install ezdxf
"""
import json
import math
import os
import subprocess
import sys
from collections import Counter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from ezdxf import recover  # noqa: E402
from ezdxf.math import Vec3  # noqa: E402
from ezdxf.tools.text import plain_text  # noqa: E402

from oracle import SWIFT_WHITESPACES  # noqa: E402
from text_oracle import diameter, joined, mtext  # noqa: E402

INVISIBLE = 1
LAYOUT_BLOCKS = ("*model_space", "*paper_space")


def fields(a):
    """The fields `dxfdump --attributes` prints for an ATTRIB or ATTDEF."""
    x, y = a.dxf.insert.x, a.dxf.insert.y
    rotation = a.dxf.get("rotation", 0.0)
    extrusion = Vec3(a.dxf.get("extrusion", (0, 0, 1)))
    if abs(extrusion.x) < 1e-9 and abs(extrusion.y) < 1e-9 and extrusion.z < 0:
        # An OCS with a -z normal: x runs the other way, and so does an angle from it.
        x = -x
        r = math.radians(rotation)
        rotation = math.degrees(math.atan2(math.sin(r), -math.cos(r)))
    if a.has_embedded_mtext_entity:
        text = mtext(a.virtual_mtext_entity().text)[0]
    else:
        text = plain_text(diameter(a.dxf.get("text", "")))
    out = {
        "tag": a.dxf.get("tag", "").strip(SWIFT_WHITESPACES),
        "text": joined(text),
        "x": x,
        "y": y,
        "height": a.dxf.get("height", 0.0),
        "rotation": rotation,
        "layer": a.dxf.get("layer", "0").strip(SWIFT_WHITESPACES),
        "flags": a.dxf.get("flags", 0),
        "multiline": a.has_embedded_mtext_entity,
        "handle": a.dxf.handle,
    }
    if a.dxftype() == "ATTDEF":
        out["prompt"] = a.dxf.get("prompt", "")
    return out


def references(layout):
    return [
        {"name": e.dxf.name, "handle": e.dxf.handle, "attributes": [fields(a) for a in e.attribs]}
        for e in layout
        if e.dxftype() == "INSERT" and e.attribs
    ]


def expanded(doc):
    """The visible attributes of the model-space references, as texts in the world."""
    out = []

    def add(insert):
        for a in insert.attribs:
            if not a.dxf.get("flags", 0) & INVISIBLE:
                f = fields(a)
                out.append({k: f[k] for k in ("text", "x", "y", "height", "rotation")})

    def walk(insert, depth=0):
        if depth > 32:
            return
        for one in insert.multi_insert() if insert.mcount > 1 else [insert]:
            for e in one.virtual_entities():
                if e.dxftype() == "INSERT":
                    add(e)
                    walk(e, depth + 1)

    for insert in doc.modelspace().query("INSERT"):
        if insert.dxf.name not in doc.blocks:
            continue  # a reference to a block the file lacks places nothing
        add(insert)
        walk(insert)
    return out


def placed(t):
    """An expanded text as a key two readers can agree on: rounded, the angle in 0..<360."""
    return (t["text"], round(t["x"], 5), round(t["y"], 5), round(t["height"], 5),
            round(t["rotation"] % 360, 4) % 360)


def summarize(path):
    try:
        doc, _ = recover.readfile(path)
    except Exception as exc:  # noqa: BLE001
        return {"file": os.path.basename(path), "error": str(exc)}
    blocks = []
    for block in doc.blocks:
        if block.name.lower().startswith(LAYOUT_BLOCKS):
            continue  # the layouts' blocks hold their entities here; the file's are in ENTITIES
        nested = references(block)
        definitions = [fields(e) for e in block if e.dxftype() == "ATTDEF"]
        if nested or definitions:
            blocks.append({"name": block.name, "references": nested, "definitions": definitions})
    return {
        "file": os.path.basename(path),
        "references": references(doc.modelspace()),
        "blocks": sorted(blocks, key=lambda b: b["name"]),
        "expanded": sorted(expanded(doc), key=placed),
    }


def differences(path, ours, theirs):
    """Each way `ours` (dxfdump) and `theirs` (ezdxf) disagree, as a string."""
    found = []

    def same(label, a, b):
        if isinstance(a, float) or isinstance(b, float):
            if a is None or b is None or abs(a - b) > 1e-9 * max(1.0, abs(a), abs(b)):
                found.append(f"{path}: {label}: dxfdump {a!r} ezdxf {b!r}")
        elif a != b:
            found.append(f"{path}: {label}: dxfdump {a!r} ezdxf {b!r}")

    def compare_list(label, a, b, each):
        if len(a) != len(b):
            found.append(f"{path}: {label}: dxfdump {len(a)} ezdxf {len(b)}")
            return
        for i, (x, y) in enumerate(zip(a, b)):
            each(f"{label}[{i}]", x, y)

    def attribute(label, a, b):
        for key in sorted(set(a) | set(b)):
            same(f"{label}.{key}", a.get(key), b.get(key))

    def reference(label, a, b):
        same(f"{label}.name", a["name"], b["name"])
        same(f"{label}.handle", a["handle"], b["handle"])
        compare_list(f"{label}.attributes", a["attributes"], b["attributes"], attribute)

    def block(label, a, b):
        same(f"{label}.name", a["name"], b["name"])
        compare_list(f"{label}.references", a["references"], b["references"], reference)
        compare_list(f"{label}.definitions", a["definitions"], b["definitions"], attribute)

    if "error" in ours or "error" in theirs:
        same("error", ours.get("error"), theirs.get("error"))
        return found
    compare_list("references", ours["references"], theirs["references"], reference)
    # The layouts' blocks hold nothing here, whatever dxfdump lists of them.
    kept = [b for b in ours["blocks"] if not b["name"].lower().startswith(LAYOUT_BLOCKS)]
    compare_list("blocks", sorted(kept, key=lambda b: b["name"]), theirs["blocks"], block)

    attributes = [a for r in ours["references"] for a in r["attributes"]]
    attributes += [a for b in ours["blocks"] for r in b["references"] for a in r["attributes"]]
    if "expanded" in ours and all(a["handle"] is not None for a in attributes):
        want, got = Counter(map(placed, theirs["expanded"])), Counter(map(placed, ours["expanded"]))
        for key in sorted((want - got).keys())[:5]:
            found.append(f"{path}: expanded: only in ezdxf {key!r}")
        for key in sorted((got - want).keys())[:5]:
            found.append(f"{path}: expanded: only in dxfdump {key!r}")
    return found


def main(argv):
    compare = None
    if argv[:1] == ["--compare"] and len(argv) > 2:
        compare, argv = argv[1], argv[2:]
    if not argv:
        sys.stderr.write("usage: attrib_oracle.py [--compare dxfdump] <file.dxf> [...]\n")
        return 2
    if compare is None:
        for path in argv:
            print(json.dumps(summarize(path), sort_keys=True, ensure_ascii=False))
        return 0
    status = 0
    for path in argv:
        command = [compare, "--attributes", "--expand-attributes", "--skip-paper-space", path]
        run = subprocess.run(command, capture_output=True, check=False)
        if run.returncode != 0 or not run.stdout.strip():
            print(f"{path}: dxfdump failed ({run.returncode})")
            status = 1
            continue
        ours = json.loads(run.stdout.decode("utf-8", "replace"))
        for line in differences(path, ours, summarize(path)):
            print(line)
            status = 1
    return status


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
