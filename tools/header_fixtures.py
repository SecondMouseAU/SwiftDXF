#!/usr/bin/env python3
"""Generate the header fixtures and ezdxf reference values used by HeaderVariablesTests.swift.

    python3 tools/header_fixtures.py [out_dir]

Writes two drawings with ezdxf to `<out_dir>`, then prints, as JSON, the header variables ezdxf
reads back from each file:

- `header_r12.dxf`, a drawing saved as R12, which has no `$MEASUREMENT` and no `$INSUNITS`.
- `header_imperial.dxf`, an R2018 drawing that sets all five variables `Drawing` exposes to values
  that are not ezdxf's defaults: imperial, architectural units, a 1:48 dimension scale.

The printed values are pasted into Tests/SwiftDXFTests/HeaderVariablesTests.swift.

Requires: pip install ezdxf
"""
import json
import os
import sys

import ezdxf

NAMES = ("$ACADVER", "$MEASUREMENT", "$INSUNITS", "$DIMSTYLE", "$DIMSCALE", "$LUNITS", "$LUPREC",
         "$DIMDEC", "$DIMPOST", "$EXTMIN", "$EXTMAX")


def build(out_dir):
    r12 = ezdxf.new("R12")
    r12.modelspace().add_line((0, 0), (10, 5))
    r12.saveas(os.path.join(out_dir, "header_r12.dxf"))

    imperial = ezdxf.new("R2018")
    imperial.dimstyles.new("ARCH-48")
    imperial.header["$MEASUREMENT"] = 0
    imperial.header["$INSUNITS"] = 1
    imperial.header["$DIMSTYLE"] = "ARCH-48"
    imperial.header["$DIMSCALE"] = 48.0
    imperial.header["$LUNITS"] = 4
    imperial.header["$LUPREC"] = 3
    imperial.header["$DIMPOST"] = "<> in"
    imperial.modelspace().add_line((0, 0), (120, 60))
    imperial.saveas(os.path.join(out_dir, "header_imperial.dxf"))


def read_back(out_dir):
    out = {}
    for name in ("header_r12.dxf", "header_imperial.dxf"):
        header = ezdxf.readfile(os.path.join(out_dir, name)).header
        out[name] = {k: (list(header[k]) if k in ("$EXTMIN", "$EXTMAX") else header[k])
                     for k in NAMES if k in header}
    return out


def main(argv):
    out_dir = argv[0] if argv else "Tests/SwiftDXFTests/Fixtures"
    build(out_dir)
    print(json.dumps(read_back(out_dir), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
