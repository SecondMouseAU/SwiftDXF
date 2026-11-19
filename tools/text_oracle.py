#!/usr/bin/env python3
"""Reference decoding of TEXT, MTEXT and dimension text, using ezdxf (MIT-licensed).

    python3 tools/text_oracle.py file1.dxf [file2.dxf ...]

Prints, per file, one JSON line in the shape `dxfdump --texts` prints: for each model-space TEXT
and MTEXT entity, and each DIMENSION with a text override, in entity order, the text as it reads
(`plain`) and its stacks (`[upper, lower, kind]`). The output of the two can be diffed line for
line:

    diff <(swift run dxfdump --texts --skip-paper-space f.dxf) <(python3 tools/text_oracle.py f.dxf)

`--skip-paper-space` because `modelspace()`, read here, leaves out the paper-space entities of the
ENTITIES section.

What is a code, what is text and what is stacked comes from ezdxf: `plain_text` for TEXT, the
`MTextParser` tokens for MTEXT and dimension text. Four things are written SwiftDXF's way, as its
README says, so that the diff shows only real disagreements: `%%c` reads as the diameter sign
U+2300 (ezdxf gives U+00D8), a stack reads as `upper/lower` after a space (ezdxf joins the parts
with the divider and no space), `\\~` is a no-break space (ezdxf gives a space), and `\\X` is a line
break (ezdxf drops it). The README lists where the two still read a string differently.

Both read a file's characters through its `$DWGCODEPAGE` when it is not UTF-8. With none, ezdxf
reads Windows-1252 and SwiftDXF Shift-JIS, so a Japanese file with no `$DWGCODEPAGE` reads
differently in the two before any code is decoded. ezdxf leaves a surrogate pair written as two
`\\U+` escapes as two code points; the oracle joins them, as SwiftDXF does. ezdxf does not decode
`%%nnn`, which SwiftDXF reads through the drawing's code page.

A string ezdxf fails to parse gets an entry with an `error` in place of `plain` and `stacks`, so
the run goes on and the diff shows it.

Requires: pip install ezdxf
"""
import json
import os
import re
import sys

from ezdxf import recover
from ezdxf.tools.text import MTextParser, TokenType, plain_text

KINDS = {"^": "tolerance", "/": "fraction", "#": "diagonalFraction"}
# A `%%` code with its character, read left to right as ezdxf reads them, so `%%%c` is `%%%`
# then `c`, not `%` then `%%c`.
SPECIAL = re.compile("%%(.)")


def diameter(text):
    """`text` with each `%%c` written as the diameter sign U+2300."""
    return SPECIAL.sub(lambda m: "\u2300" if m.group(1) in "cC" else m.group(0), text)


def mtext(raw):
    """The plain text and stacks of an MTEXT string, from ezdxf's tokens."""
    out = ""
    stacks = []
    for token in MTextParser(diameter(raw)):
        t = token.type
        if t == TokenType.WORD:
            out += token.data
        elif t == TokenType.SPACE:
            out += " "
        elif t == TokenType.NBSP:
            out += "\u00a0"
        elif t == TokenType.TABULATOR:
            out += "\t"
        elif t in (TokenType.NEW_PARAGRAPH, TokenType.NEW_COLUMN, TokenType.WRAP_AT_DIMLINE):
            out += "\n"
        elif t == TokenType.STACK:
            # ezdxf always builds this as (upper, lower, divider); see MTextParser.parse_stacking.
            upper, lower, divider = token.data
            stacks.append([upper, lower, KINDS.get(divider, divider)])
            if out and not out[-1].isspace():
                out += " "
            out += upper + "/" + lower
    return out, stacks


def joined(text):
    """`text` with each surrogate pair made one character."""
    return text.encode("utf-16", "surrogatepass").decode("utf-16", "surrogatepass")


def joined_stacks(stacks):
    return [[joined(upper), joined(lower), kind] for upper, lower, kind in stacks]


def summarize(path):
    try:
        doc, _ = recover.readfile(path)
    except Exception as exc:  # noqa: BLE001
        return {"file": os.path.basename(path), "error": str(exc)}
    texts = []
    for e in doc.modelspace():
        kind = e.dxftype()
        if kind not in ("TEXT", "MTEXT", "DIMENSION"):
            continue
        if kind == "DIMENSION" and not e.dxf.get("text", ""):
            continue
        try:
            if kind == "TEXT":
                plain, stacks = plain_text(diameter(e.dxf.text)), []
            else:
                plain, stacks = mtext(e.text if kind == "MTEXT" else e.dxf.text)
            texts.append(
                {"type": kind, "plain": joined(plain), "stacks": joined_stacks(stacks)})
        except Exception as exc:  # noqa: BLE001
            # ezdxf failed on this string (1.4.5 raises TypeError on `\S1/2\`). The entry
            # says so, and shows up in the diff, instead of ending the run.
            texts.append({"type": kind, "error": f"{type(exc).__name__}: {exc}"})
    return {"file": os.path.basename(path), "texts": texts}


if __name__ == "__main__":
    for p in sys.argv[1:]:
        line = json.dumps(summarize(p), sort_keys=True, ensure_ascii=False, separators=(",", ":"))
        # A lone surrogate (from an escape such as \U+D800) is printed as its escape.
        sys.stdout.buffer.write((line + "\n").encode("utf-8", "backslashreplace"))
