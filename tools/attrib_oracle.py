#!/usr/bin/env python3
"""Reference reading of ATTRIB and ATTDEF, using ezdxf (MIT-licensed).

    python3 tools/attrib_oracle.py file1.dxf [file2.dxf ...]
    python3 tools/attrib_oracle.py --compare .build/debug/dxfdump file1.dxf [...]

Prints, per file, one JSON line in the shape `dxfdump --attributes` prints: the block references
of model space that carry attributes (`Insert.attribs`), and for each block that has any, its
attribute definitions (`ATTDEF`) and the nested references that carry attributes. Only what has
attributes is listed.

With `--compare`, `dxfdump --attributes --skip-paper-space` is run on the same files (ezdxf's
`modelspace()` leaves out the paper-space entities) and the two are compared field
by field (numbers to 1e-9, the references in file order, the blocks by name); each difference is
printed, and the exit status is 1 when there is one.

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

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from ezdxf import recover  # noqa: E402
from ezdxf.math import Vec3  # noqa: E402
from ezdxf.tools.text import plain_text  # noqa: E402

from oracle import SWIFT_WHITESPACES  # noqa: E402
from text_oracle import diameter, joined, mtext  # noqa: E402


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


def summarize(path):
    try:
        doc, _ = recover.readfile(path)
    except Exception as exc:  # noqa: BLE001
        return {"file": os.path.basename(path), "error": str(exc)}
    blocks = []
    for block in doc.blocks:
        if block.name.lower().startswith(("*model_space", "*paper_space")):
            continue  # the layouts' blocks hold their entities here; the file's are in ENTITIES
        nested = references(block)
        definitions = [fields(e) for e in block if e.dxftype() == "ATTDEF"]
        if nested or definitions:
            blocks.append({"name": block.name, "references": nested, "definitions": definitions})
    return {
        "file": os.path.basename(path),
        "references": references(doc.modelspace()),
        "blocks": sorted(blocks, key=lambda b: b["name"]),
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
    compare_list(
        "blocks", sorted(ours["blocks"], key=lambda b: b["name"]), theirs["blocks"], block)
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
        command = [compare, "--attributes", "--skip-paper-space", path]
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
