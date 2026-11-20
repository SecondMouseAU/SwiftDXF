#!/usr/bin/env python3
"""Runs `dxfdump --rebuild` over a folder of DXF files and prints what each one gives.

    python3 tools/rebuild_corpus.py [--dxfdump path] [--numbers thousands|decimal|plain] <folder>

`--numbers` is passed to `dxfdump --rebuild`: how the drawings write a comma in a number (Jw_cad's
`10,439` is `thousands`). Without it a comma is read every way it can be.

Prints one line per drawing that has rebuilt dimensions or warnings: the file, how many real
`DIMENSION` entities it holds, how many it rebuilt, how many warnings, and the scales found as
`group=scale (supporting/contradicting)`; then totals. A drawing with real dimensions should
rebuild none, and a Jw_cad railway drawing should find 1:80. These are the figures the README
quotes; the corpus is not in the repository.

Needs `dxfdump` built (`swift build --product dxfdump`).
"""
import json
import os
import subprocess
import sys


def real_dimensions(path):
    """The count of DIMENSION entities, by the entity digest of `dxfdump`."""
    out = subprocess.run([DXFDUMP, path], capture_output=True, text=True).stdout
    try:
        return json.loads(out.splitlines()[0])["counts"]["DIMENSION"]
    except (IndexError, ValueError, KeyError):
        return None


if __name__ == "__main__":
    args = sys.argv[1:]
    DXFDUMP = ".build/debug/dxfdump"
    if "--dxfdump" in args:
        i = args.index("--dxfdump")
        DXFDUMP = args[i + 1]
        del args[i : i + 2]
    NUMBERS = []
    if "--numbers" in args:
        i = args.index("--numbers")
        NUMBERS = args[i : i + 2]
        del args[i : i + 2]
    if len(args) != 1:
        sys.exit(__doc__)
    files = sorted(
        os.path.join(root, name)
        for root, _, names in os.walk(args[0])
        for name in names
        if name.lower().endswith(".dxf")
    )
    if not files:
        sys.exit(f"no .dxf files under {args[0]}")
    totals = {
        "files": 0, "rebuilt": 0, "with_real_dimensions": 0, "real_that_rebuilt": 0, "failed": 0,
    }
    for path in files:
        out = subprocess.run(
            [DXFDUMP, "--rebuild", *NUMBERS, path], capture_output=True, text=True
        ).stdout
        try:
            result = json.loads(out.splitlines()[0])
            if "error" in result:
                raise ValueError(result["error"])
        except (IndexError, ValueError):
            totals["failed"] += 1
            print(f"{path}\tFAILED (dxfdump --rebuild gave no result)")
            continue
        real = real_dimensions(path)
        if real is None:
            totals["failed"] += 1
            print(f"{path}\tFAILED (dxfdump gave no digest)")
            continue
        totals["files"] += 1
        rebuilt = len(result.get("dimensions", []))
        totals["rebuilt"] += rebuilt
        if real:
            totals["with_real_dimensions"] += 1
            totals["real_that_rebuilt"] += 1 if rebuilt else 0
        warnings = len(result.get("warnings", []))
        if rebuilt or warnings:
            scales = ", ".join(
                f"{s['group']}={s['scale']:g} ({s['supporting']}/{s['contradicting']})"
                for s in result.get("scales", [])
            )
            print(f"{path}\treal={real}\trebuilt={rebuilt}\twarnings={warnings}\t{scales}")
    print(totals)
    sys.exit(1 if totals["failed"] else 0)
