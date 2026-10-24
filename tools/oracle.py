#!/usr/bin/env python3
"""Reference oracle for SwiftDXF, using ezdxf (MIT-licensed).

Emits, per file, a compact JSON summary whose `counts` shape matches `dxfdump`'s, so the two can be
diffed entity-for-entity. Model-space entities only, to mirror SwiftDXF (which reads the ENTITIES
section). TEXT/MTEXT and LWPOLYLINE/POLYLINE are folded together the same way SwiftDXF folds them.

    python3 tools/oracle.py file1.dxf [file2.dxf ...]

Requires: pip install ezdxf
"""
import json
import os
import sys
import unicodedata
from collections import Counter

import ezdxf
from ezdxf import recover


# Mirrors Foundation's CharacterSet.whitespaces (tab plus every Unicode Zs space separator), which
# is what Reader.swift trims the layer name with. str.strip() with no argument trims more (newlines,
# control characters), so pass this explicitly.
SWIFT_WHITESPACES = "\t" + "".join(
    c for c in map(chr, range(0x3100)) if unicodedata.category(c) == "Zs")


def summarize(path):
    try:
        doc, _ = recover.readfile(path)   # tolerant loader for messy real-world DXF
    except Exception as exc:  # noqa: BLE001
        return {"file": os.path.basename(path), "error": str(exc)}

    msp = doc.modelspace()
    raw = Counter(e.dxftype() for e in msp)

    # Geometry digest: sum + count of every defining scalar (rounded), mirroring dxfdump exactly.
    acc = {"sum": 0.0, "n": 0}
    by_type = {}

    def add(bucket, *vs):
        slot = by_type.setdefault(bucket, [0.0, 0])
        for v in vs:
            f = float(v)
            acc["sum"] += f
            acc["n"] += 1
            slot[0] += f
            slot[1] += 1

    for e in msp:
        t = e.dxftype()
        if t == "LINE":
            s, en = e.dxf.start, e.dxf.end
            add("LINE", s.x, s.y, en.x, en.y)
        elif t == "CIRCLE":
            c = e.dxf.center
            add("CIRCLE", c.x, c.y, e.dxf.radius)
        elif t == "ARC":
            c = e.dxf.center
            add("ARC", c.x, c.y, e.dxf.radius, e.dxf.start_angle, e.dxf.end_angle)
        elif t == "ELLIPSE":
            c, m = e.dxf.center, e.dxf.major_axis
            add("ELLIPSE", c.x, c.y, m.x, m.y, e.dxf.ratio, e.dxf.start_param, e.dxf.end_param)
        elif t == "POINT":
            p = e.dxf.location
            add("POINT", p.x, p.y)
        elif t == "TEXT":
            p = e.dxf.insert
            add("TEXT", p.x, p.y, e.dxf.height)
        elif t == "MTEXT":
            p = e.dxf.insert
            add("TEXT", p.x, p.y, e.dxf.char_height)
        elif t == "LWPOLYLINE":
            for x, y in e.get_points("xy"):
                add("POLYLINE", x, y)
        elif t == "POLYLINE":
            for v in e.vertices:
                loc = v.dxf.location
                add("POLYLINE", loc.x, loc.y)
        elif t == "DIMENSION":
            tm, dp = e.dxf.text_midpoint, e.dxf.defpoint
            vs = [tm.x, tm.y, dp.x, dp.y]
            if e.dxf.hasattr("actual_measurement"):
                vs.append(e.dxf.actual_measurement)
            for name in ("defpoint2", "defpoint3", "defpoint4", "defpoint5"):
                if e.dxf.hasattr(name):
                    p = getattr(e.dxf, name)
                    vs.extend([p.x, p.y])
            add("DIMENSION", *vs)
        elif t == "SPLINE":
            for p in e.control_points:
                add("SPLINE", p[0], p[1])
            for p in e.fit_points:
                add("SPLINE", p[0], p[1])
    counts = {
        "LINE": raw.get("LINE", 0),
        "CIRCLE": raw.get("CIRCLE", 0),
        "ARC": raw.get("ARC", 0),
        "ELLIPSE": raw.get("ELLIPSE", 0),
        "POINT": raw.get("POINT", 0),
        "TEXT": raw.get("TEXT", 0) + raw.get("MTEXT", 0),
        "POLYLINE": raw.get("LWPOLYLINE", 0) + raw.get("POLYLINE", 0),
        "DIMENSION": raw.get("DIMENSION", 0),
        "SPLINE": raw.get("SPLINE", 0),
    }
    counts["total"] = sum(counts.values())
    modelled = {"LINE", "CIRCLE", "ARC", "ELLIPSE", "POINT", "TEXT", "MTEXT", "LWPOLYLINE",
                "POLYLINE", "DIMENSION", "SPLINE"}
    skipped = {k: v for k, v in sorted(raw.items()) if k not in modelled}
    skipped_by_layer = {}
    for e in msp:
        t = e.dxftype()
        if t in modelled:
            continue
        layers = skipped_by_layer.setdefault(t, {})
        layer = (e.dxf.layer if e.dxf.hasattr("layer") else "0").strip(SWIFT_WHITESPACES)
        layers[layer] = layers.get(layer, 0) + 1
    skipped_by_layer = {t: dict(sorted(v.items())) for t, v in sorted(skipped_by_layer.items())}
    return {
        "skipped": skipped,
        "skippedByLayer": skipped_by_layer,
        "file": os.path.basename(path),
        "version": doc.dxfversion,
        "counts": counts,
        "geom": {"sum": acc["sum"], "scalars": acc["n"]},
        "geomByType": {k: {"sum": v[0], "scalars": v[1]} for k, v in sorted(by_type.items())},
        "raw": dict(sorted(raw.items())),
    }


def main(argv):
    if not argv:
        sys.stderr.write("usage: oracle.py <file.dxf> [...]\n")
        return 2
    for path in argv:
        print(json.dumps(summarize(path), sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
