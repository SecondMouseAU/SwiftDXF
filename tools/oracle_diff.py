#!/usr/bin/env python3
"""Compare `dxfdump` with `tools/oracle.py` over a list of drawings, type by type.

    python3 tools/oracle_diff.py <dxfdump> <file.dxf> [...]

Runs both on each file and prints a line for each file where an entity count, or the count or the
sum of the coordinate scalars of one entity type, differs. Then it prints how many entities of each
type were compared. The digests are summed in document order by both, so they agree to rounding.
Handles and skipped types are not compared: ezdxf gives handles to a file that has none and reads
`ATTRIB` into its `INSERT`.

Requires: pip install ezdxf
"""
import json
import os
import subprocess
import sys

ORACLE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "oracle.py")


def rows(command, files):
    out = subprocess.run(command + files, capture_output=True, text=True).stdout
    result = []
    for line in out.splitlines():
        try:
            result.append(json.loads(line))
        except ValueError:
            result.append(None)
    return result


def compare(path, mine, ref):
    if mine is None or ref is None or "error" in mine or "error" in ref:
        return ["not read by one of them"]
    problems = []
    for kind in sorted(set(mine["counts"]) | set(ref["counts"])):
        a, b = mine["counts"].get(kind, 0), ref["counts"].get(kind, 0)
        if a != b:
            problems.append(f"count {kind}: {a} against {b}")
    for kind in sorted(set(mine["geomByType"]) | set(ref["geomByType"])):
        a, b = mine["geomByType"].get(kind), ref["geomByType"].get(kind)
        if a is None or b is None:
            problems.append(f"digest {kind}: {a} against {b}")
        elif a["scalars"] != b["scalars"] or abs(a["sum"] - b["sum"]) > 1e-6 * max(1.0, abs(b["sum"])):
            problems.append(f"digest {kind}: {a} against {b}")
    return problems


def main(argv):
    if len(argv) < 2:
        sys.stderr.write("usage: oracle_diff.py <dxfdump> <file.dxf> [...]\n")
        return 2
    dxfdump, files = argv[0], argv[1:]
    compared, differing = {}, 0
    for start in range(0, len(files), 25):
        chunk = files[start:start + 25]
        mine = rows([dxfdump], chunk)
        ref = rows([sys.executable, ORACLE], chunk)
        if len(mine) != len(chunk) or len(ref) != len(chunk):
            sys.stderr.write(f"a run of {len(chunk)} files did not give one row each\n")
            return 1
        for path, a, b in zip(chunk, mine, ref):
            problems = compare(path, a, b)
            if problems:
                differing += 1
                print("DIFF", path, "; ".join(problems[:4]))
            elif a is not None:
                for kind, n in a["counts"].items():
                    if kind != "total":
                        compared[kind] = compared.get(kind, 0) + n
    print(f"{len(files)} files, {differing} differ; entities compared: {json.dumps(compared)}")
    return 1 if differing else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
