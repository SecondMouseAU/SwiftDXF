#!/usr/bin/env python3
"""Reference oracle for SwiftDXF, using ezdxf (MIT-licensed).

Emits, per file, a compact JSON summary whose `counts` shape matches `dxfdump`'s, so the two can be
diffed entity-for-entity. Model-space entities only, to mirror SwiftDXF (which reads the ENTITIES
section). TEXT/MTEXT and LWPOLYLINE/POLYLINE are folded together the same way SwiftDXF folds them.

    python3 tools/oracle.py file1.dxf [file2.dxf ...]

`--header` prints instead the header variables of each file, in the shape `dxfdump --header` prints:
the ones SwiftDXF names (`header`) and every variable with its first group-coded value
(`variables`), both as ezdxf's `doc.header` has them. `--against DXFDUMP` runs that `dxfdump` on
each file and lists where the two differ, numbers compared as numbers:

    python3 tools/oracle.py --header --against .build/debug/dxfdump file1.dxf [file2.dxf ...]

Requires: pip install ezdxf
"""
import json
import math
import os
import subprocess
import sys
import unicodedata
from collections import Counter

import ezdxf
from ezdxf import recover
from ezdxf.math import Vec2, Vec3
from ezdxf.sections.header import HeaderSection
from ezdxf.upright import upright_all

from angular_fixtures import arc_side_2l, arc_side_3p


# Mirrors Foundation's CharacterSet.whitespaces (tab plus every Unicode Zs space separator), which
# is what Reader.swift trims the layer name with. str.strip() with no argument trims more (newlines,
# control characters), so pass this explicitly.
SWIFT_WHITESPACES = "\t" + "".join(
    c for c in map(chr, range(0x3100)) if unicodedata.category(c) == "Zs")


def flipped(e):
    """Whether the entity is written in an object coordinate system whose normal is -z."""
    if not e.dxf.hasattr("extrusion"):
        return False
    n = Vec3(e.dxf.extrusion)
    return abs(n.x) < 1e-9 and abs(n.y) < 1e-9 and n.z < 0


def summarize(path):
    try:
        doc, _ = recover.readfile(path)   # tolerant loader for messy real-world DXF
    except Exception as exc:  # noqa: BLE001
        return {"file": os.path.basename(path), "error": str(exc)}

    msp = doc.modelspace()
    raw = Counter(e.dxftype() for e in msp)

    # SwiftDXF reads an entity written in a -z object coordinate system as its world geometry.
    # ezdxf's own conversion does ARC, CIRCLE, LWPOLYLINE, POLYLINE, ELLIPSE and HATCH. TEXT keeps
    # its OCS values, and so do the OCS points of a DIMENSION, so mirror those here.
    flipped_text = {e.dxf.handle for e in msp if e.dxftype() == "TEXT" and flipped(e)}
    flipped_dim = {e.dxf.handle for e in msp if e.dxftype() == "DIMENSION" and flipped(e)}
    flipped_ellipse = {e.dxf.handle for e in msp if e.dxftype() == "ELLIPSE" and flipped(e)}
    flipped_arc = {e.dxf.handle for e in msp if e.dxftype() == "ARC" and flipped(e)}
    upright_all(msp)

    # Geometry digest: sum + count of every defining scalar (rounded), mirroring dxfdump exactly.
    acc = {"sum": 0.0, "n": 0}
    by_type = {}
    tolerances = []

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
            start, end = e.dxf.start_angle, e.dxf.end_angle
            if e.dxf.handle in flipped_arc:
                # upright gives 180 - angle; SwiftDXF starts the range in 0..<360 and, unless the
                # arc is a full turn, ends it there too.
                shift = math.floor(start / 360) * 360
                start, end = start - shift, end - shift
                if abs(end - start) < 360 - 1e-9:
                    end -= math.floor(end / 360) * 360
            add("ARC", c.x, c.y, e.dxf.radius, start, end)
        elif t == "ELLIPSE":
            c, m = e.dxf.center, e.dxf.major_axis
            start, end = e.dxf.start_param, e.dxf.end_param
            if e.dxf.handle in flipped_ellipse:
                # Reversed by upright; SwiftDXF also starts the range in 0..<2 pi.
                shift = math.floor(start / (2 * math.pi)) * 2 * math.pi
                start, end = start - shift, end - shift
            add("ELLIPSE", c.x, c.y, m.x, m.y, e.dxf.ratio, start, end)
        elif t == "POINT":
            p = e.dxf.location
            add("POINT", p.x, p.y)
        elif t == "TEXT":
            p = e.dxf.insert
            add("TEXT", -p.x if e.dxf.handle in flipped_text else p.x, p.y, e.dxf.height)
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
            mirror = -1 if e.dxf.handle in flipped_dim else 1
            vs = [mirror * tm.x, tm.y, dp.x, dp.y]
            # Zero or negative means "none" (some writers store -1), as in SwiftDXF.
            if e.dxf.hasattr("actual_measurement") and e.dxf.actual_measurement > 0:
                vs.append(e.dxf.actual_measurement)
            for name in ("defpoint2", "defpoint3", "defpoint4", "defpoint5"):
                if e.dxf.hasattr(name):
                    p = getattr(e.dxf, name)
                    # defpoint5 is the one OCS point.
                    vs.extend([mirror * p.x if name == "defpoint5" else p.x, p.y])
            if (e.dxf.dimtype & 15) == 6:
                # An ordinate dimension has no rotation of its own: SwiftDXF reads the negative of
                # group 51, the angle of its coordinate system, as one.
                if e.dxf.hasattr("horizontal_direction"):
                    angle = -e.dxf.horizontal_direction
                    if e.dxf.handle in flipped_dim:
                        r = math.radians(angle)
                        angle = math.degrees(math.atan2(math.sin(r), -math.cos(r)))
                    vs.append(angle)
            elif e.dxf.hasattr("angle") and (e.dxf.dimtype & 15) in (0, 1):
                angle = e.dxf.angle
                if e.dxf.handle in flipped_dim:
                    # An OCS angle: SwiftDXF reports the world direction of the measuring axis.
                    r = math.radians(angle)
                    angle = math.degrees(math.atan2(math.sin(r), -math.cos(r)))
                vs.append(angle)
            elif e.dxf.hasattr("angle"):
                vs.append(e.dxf.angle)
            if e.dxf.hasattr("oblique_angle"):
                vs.append(e.dxf.oblique_angle)
            add("DIMENSION", *vs)
        elif t == "SPLINE":
            for p in e.control_points:
                add("SPLINE", p[0], p[1])
            for p in e.fit_points:
                add("SPLINE", p[0], p[1])
        elif t == "LEADER":
            for v in e.vertices:
                add("LEADER", v[0], v[1])
        elif t == "TOLERANCE":
            p, d = e.dxf.insert, e.dxf.x_axis_vector
            add("TOLERANCE", p.x, p.y, d.x, d.y)
            tolerances.append(e.dxf.content)
        elif t == "SOLID":
            # Corners in outline order (the file's third and fourth swapped; a triangle has three),
            # after upright_all has flipped a -z plane into the world.
            # A record with no fourth corner is a triangle, as SwiftDXF reads it (ezdxf's own
            # default for the missing corner is the origin).
            corners = e.vertices() if e.dxf.hasattr("vtx3") else [
                e.dxf.vtx0, e.dxf.vtx1, e.dxf.vtx2]
            for p in corners:
                add("SOLID", p.x, p.y, p.z)
        elif t == "WIPEOUT":
            # The clip boundary in the world, closed; SwiftDXF does not repeat the first vertex.
            # Known difference: SwiftDXF caps the tolerance for "the last vertex repeats the first"
            # at 1e-6, ezdxf has none, so a closing vertex 1e-6 to 1e-5 off at coordinates beyond a
            # thousand pixels is a vertex there and a repeat here.
            for p in e.boundary_path_wcs()[:-1]:
                add("WIPEOUT", p.x, p.y, p.z)
            # Then the clip type (71), the clipping state (280) and the clip mode (290), as ezdxf
            # keeps them without acting on them; an unset one reads as SwiftDXF reads it.
            add("WIPEOUT",
                e.dxf.get("clipping_boundary_type", 2 if len(e.boundary_path) > 2 else 1),
                1 if e.dxf.get("clipping", 0) else 0,
                1 if e.dxf.get("clip_mode", 0) else 0)
        elif t == "3DFACE":
            # The four corners as the file lists them, then the invisible-edge flags.
            for p in (e.dxf.vtx0, e.dxf.vtx1, e.dxf.vtx2, e.dxf.get("vtx3", e.dxf.vtx2)):
                add("3DFACE", p.x, p.y, p.z)
            add("3DFACE", e.dxf.get("invisible_edges", 0))
        elif t == "HATCH":
            for boundary in e.paths:
                if type(boundary).__name__ == "PolylinePath":
                    for v in boundary.vertices:
                        add("HATCH", v[0], v[1], v[2])
                    continue
                for edge in boundary.edges:
                    kind = type(edge).__name__
                    if kind == "LineEdge":
                        add("HATCH", edge.start[0], edge.start[1], edge.end[0], edge.end[1])
                    elif kind == "ArcEdge":
                        add("HATCH", edge.center[0], edge.center[1], edge.radius,
                            edge.start_angle, edge.end_angle)
                    elif kind == "EllipseEdge":
                        add("HATCH", edge.center[0], edge.center[1], edge.major_axis[0],
                            edge.major_axis[1], edge.ratio)
                    elif kind == "SplineEdge":
                        for p in edge.control_points:
                            add("HATCH", p[0], p[1])
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
        "HATCH": raw.get("HATCH", 0),
        "LEADER": raw.get("LEADER", 0),
        "TOLERANCE": raw.get("TOLERANCE", 0),
        "SOLID": raw.get("SOLID", 0),
        "WIPEOUT": raw.get("WIPEOUT", 0),
        "3DFACE": raw.get("3DFACE", 0),
    }
    counts["total"] = sum(counts.values())
    modelled = {"LINE", "CIRCLE", "ARC", "ELLIPSE", "POINT", "TEXT", "MTEXT", "LWPOLYLINE",
                "POLYLINE", "DIMENSION", "SPLINE", "HATCH", "LEADER", "TOLERANCE", "SOLID", "WIPEOUT",
                "3DFACE"}
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
    handles = [e.dxf.handle for e in msp if e.dxftype() in modelled]
    dimensions = []
    for e in msp:
        if e.dxftype() != "DIMENSION":
            continue
        try:
            # ezdxf's own measurement: geometry with no style scale, as SwiftDXF's computedMeasurement.
            # It differs for a rotated linear dimension on a -z plane, where it passes the world
            # definition points through the OCS (see tools/ocs_fixtures.py).
            kind = e.dxf.dimtype & 15
            if kind in (0, 1, 3, 4):
                m = e.get_measurement()
            elif kind == 6:
                # The distance from the origin to the feature location along the x axis of the
                # coordinate system it was made in (group 51 is the negative of its angle), or
                # across it, as ezdxf's renderer measures it.
                v = Vec2(e.get_measurement())
                x_axis = Vec2.from_deg_angle(-e.dxf.get("horizontal_direction", 0.0))
                m = abs((x_axis if e.dxf.dimtype & 64 else x_axis.orthogonal()).dot(v))
            elif kind in (2, 5):
                # ezdxf measures the angle counter-clockwise from the first line to the second;
                # AutoCAD shows the one on the side of the arc location (tools/angular_fixtures.py).
                p = {n: Vec2(e.dxf.get(g)) for n, g in (
                    ("p10", "defpoint"), ("p13", "defpoint2"), ("p14", "defpoint3"),
                    ("p15", "defpoint4"), ("p16", "defpoint5")) if e.dxf.hasattr(g)}
                if kind == 5:
                    m = arc_side_3p(p["p15"], p["p13"], p["p14"], p["p10"])
                else:
                    # Group 16 is an OCS point: mirror it as for any dimension on a -z plane.
                    arc = Vec2(-p["p16"].x, p["p16"].y) if e.dxf.handle in flipped_dim else p["p16"]
                    m = arc_side_2l((p["p13"], p["p14"]), (p["p15"], p["p10"]), arc)
            else:
                m = None
            dimensions.append(float(m) if m is not None else None)
        except Exception:  # noqa: BLE001
            dimensions.append(None)
    return {
        "dimensions": dimensions,
        "handles": handles,
        "tolerances": tolerances,
        "skipped": skipped,
        "skippedByLayer": skipped_by_layer,
        "file": os.path.basename(path),
        "version": doc.dxfversion,
        "counts": counts,
        "geom": {"sum": acc["sum"], "scalars": acc["n"]},
        "geomByType": {k: {"sum": v[0], "scalars": v[1]} for k, v in sorted(by_type.items())},
        "raw": dict(sorted(raw.items())),
    }


# The code pages SwiftDXF reads from $DWGCODEPAGE (CodePage.swift): ANSI_ and one of these numbers.
CODE_PAGES = {874, 932, 936, 949, 950, 1250, 1251, 1252, 1253, 1254, 1255, 1256, 1257, 1258}


def code_page_name(text):
    """The code page `text` names as SwiftDXF reads it, such as ANSI_932, or None."""
    upper = text.strip(SWIFT_WHITESPACES).upper()
    number = upper[len("ANSI_"):]
    if not (upper.startswith("ANSI_") and number.isascii() and number.isdecimal()):
        return None
    return upper if str(int(number)) == number and int(number) in CODE_PAGES else None


def header_summary(path):
    """The header variables of `path` in the shape `dxfdump --header` prints."""
    # The header as the file has it: ezdxf's Drawing adds and updates variables once it has loaded
    # (the creation time, the extents), so read the HEADER section itself, as recover.readfile does.
    variables = {}
    try:
        with open(path, "rb") as fp:
            sections = recover.Recover.run(fp).section_dict
        header = sections.get("HEADER")
        for name, var in (HeaderSection.load(header[0]).hdrvars.items() if header else []):
            # A 2D point has no z, which SwiftDXF reads as 0.
            value = list(var.value) + [0.0] * (3 - len(var.value)) if var.ispoint else var.value
            variables[name] = [var.code, value]
    except Exception as exc:  # noqa: BLE001
        return {"file": os.path.basename(path), "error": str(exc)}

    def value(name, code):
        entry = variables.get(name)
        return entry[1] if entry and entry[0] == code else None

    def integer(name):
        v = value(name, 70)
        return v if isinstance(v, int) else None

    def real(name, code):
        v = value(name, code)
        return float(v) if isinstance(v, (int, float)) else None

    def text(name, code, trim=True):
        v = value(name, code)
        if not isinstance(v, str):
            return None
        v = v.strip(SWIFT_WHITESPACES) if trim else v
        return v or None

    def point(name):
        entry = variables.get(name)
        if not entry or entry[0] != 10:
            return None
        return [float(c) for c in entry[1]]

    version = variables.get("$ACADVER")
    return {
        "file": os.path.basename(path),
        "header": {
            "version": version[1].strip(SWIFT_WHITESPACES) if version else "",
            "codePage": code_page_name(value("$DWGCODEPAGE", 3) or ""),
            "insUnits": integer("$INSUNITS"),
            "extMin": point("$EXTMIN"),
            "extMax": point("$EXTMAX"),
            "measurement": integer("$MEASUREMENT"),
            "currentDimensionStyleName": text("$DIMSTYLE", 2),
            "dimensionScale": real("$DIMSCALE", 40),
            "linearUnitFormat": integer("$LUNITS"),
            "linearUnitPrecision": integer("$LUPREC"),
            "dimDec": integer("$DIMDEC"),
            "dimZin": integer("$DIMZIN"),
            "dimLfac": real("$DIMLFAC", 40),
            "dimPost": text("$DIMPOST", 1, trim=False),
        },
        "variables": variables,
    }


def differences(ours, theirs):
    """Where two `--header` summaries of one file differ, as short strings."""
    if "error" in ours or "error" in theirs:
        if ours.get("error") and theirs.get("error"):
            return []
        return ["error: dxfdump %s, ezdxf %s" % (ours.get("error"), theirs.get("error"))]
    out = []
    for key in sorted(set(ours["header"]) | set(theirs["header"])):
        a, b = ours["header"].get(key), theirs["header"].get(key)
        if a != b:
            out.append("header %s: dxfdump %r, ezdxf %r" % (key, a, b))
    for name in sorted(set(ours["variables"]) | set(theirs["variables"])):
        a, b = ours["variables"].get(name), theirs["variables"].get(name)
        if a is None or b is None:
            out.append("variable %s: only in %s" % (name, "ezdxf" if a is None else "dxfdump"))
        elif a != b:
            out.append("variable %s: dxfdump %r, ezdxf %r" % (name, a, b))
    return out


def compare_header(dxfdump, paths):
    """Lists where `dxfdump --header` and ezdxf differ over `paths`; returns the exit status."""
    differing = 0
    for path in paths:
        run = subprocess.run([dxfdump, "--header", path], capture_output=True, text=True)
        try:
            ours = json.loads(run.stdout)
        except ValueError:
            ours = {"file": os.path.basename(path), "error": "dxfdump failed: " + run.stderr[:200]}
        diff = differences(ours, header_summary(path))
        if diff:
            differing += 1
            print(path)
            for line in diff:
                print("   ", line)
    print("%d of %d files differ" % (differing, len(paths)))
    return 1 if differing else 0


def main(argv):
    argv = list(argv)
    header = "--header" in argv
    if header:
        argv.remove("--header")
    against = None
    if "--against" in argv:
        i = argv.index("--against")
        if not header or i + 1 >= len(argv):
            sys.stderr.write("usage: oracle.py --header --against <dxfdump> <file.dxf> [...]\n")
            return 2
        against = argv[i + 1]
        del argv[i:i + 2]
    if not argv:
        sys.stderr.write("usage: oracle.py [--header [--against <dxfdump>]] <file.dxf> [...]\n")
        return 2
    if against:
        return compare_header(against, argv)
    for path in argv:
        print(json.dumps(header_summary(path) if header else summarize(path), sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
