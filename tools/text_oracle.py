#!/usr/bin/env python3
"""Reference decoding of TEXT, MTEXT and dimension text, using ezdxf (MIT-licensed).

    python3 tools/text_oracle.py file1.dxf [file2.dxf ...]

Prints, per file, one JSON line in the shape `dxfdump --texts` prints: for each model-space TEXT
and MTEXT entity, and each DIMENSION with a text override, in entity order, the text as it reads
(`plain`) and its stacks (`[upper, lower, kind]`). The output of the two can be diffed line for
line:

    diff <(swift run dxfdump --texts f.dxf) <(python3 tools/text_oracle.py f.dxf)

What is a code, what is text and what is stacked comes from ezdxf: `plain_text` for TEXT, the
`MTextParser` tokens for MTEXT and dimension text. Four things are written SwiftDXF's way, as its
README says, so that the diff shows only real disagreements: `%%c` reads as the diameter sign
U+2300 (ezdxf gives U+00D8), a stack reads as `upper/lower` after a space (ezdxf joins the parts
with the divider and no space), `\\~` is a no-break space (ezdxf gives a space), and `\\X` is a line
break (ezdxf drops it). The README lists where the two still read a string differently.

ezdxf decodes a file's characters through its `$DWGCODEPAGE`, and SwiftDXF as UTF-8 or else CP932,
so a file whose text is in neither reads differently in the two before any code is decoded.

Requires: pip install ezdxf
"""
import json
import os
import re
import sys

from ezdxf import recover
from ezdxf.tools.text import MTextParser, TokenType, plain_text

KINDS = {"^": "tolerance", "/": "fraction", "#": "diagonalFraction"}
DIAMETER = re.compile("%%[cC]")


def mtext(raw):
    """The plain text and stacks of an MTEXT string, from ezdxf's tokens."""
    out = ""
    stacks = []
    for token in MTextParser(DIAMETER.sub("⌀", raw)):
        t = token.type
        if t == TokenType.WORD:
            out += token.data
        elif t == TokenType.SPACE:
            out += " "
        elif t == TokenType.NBSP:
            out += " "
        elif t == TokenType.TABULATOR:
            out += "\t"
        elif t in (TokenType.NEW_PARAGRAPH, TokenType.NEW_COLUMN, TokenType.WRAP_AT_DIMLINE):
            out += "\n"
        elif t == TokenType.STACK:
            upper, lower, divider = token.data
            stacks.append([upper, lower, KINDS.get(divider, divider)])
            if out and not out[-1].isspace():
                out += " "
            out += upper + "/" + lower
    return out, stacks


def summarize(path):
    try:
        doc, _ = recover.readfile(path)
    except Exception as exc:  # noqa: BLE001
        return {"file": os.path.basename(path), "error": str(exc)}
    texts = []
    for e in doc.modelspace():
        kind = e.dxftype()
        if kind == "TEXT":
            texts.append({
                "type": "TEXT", "plain": plain_text(DIAMETER.sub("⌀", e.dxf.text)),
                "stacks": []})
        elif kind == "MTEXT":
            plain, stacks = mtext(e.text)
            texts.append({"type": "MTEXT", "plain": plain, "stacks": stacks})
        elif kind == "DIMENSION" and e.dxf.get("text", ""):
            plain, stacks = mtext(e.dxf.text)
            texts.append({"type": "DIMENSION", "plain": plain, "stacks": stacks})
    return {"file": os.path.basename(path), "texts": texts}


if __name__ == "__main__":
    for p in sys.argv[1:]:
        line = json.dumps(summarize(p), sort_keys=True, ensure_ascii=False, separators=(",", ":"))
        # A lone surrogate (from an escape such as \U+D800) is printed as its escape.
        sys.stdout.buffer.write((line + "\n").encode("utf-8", "backslashreplace"))
