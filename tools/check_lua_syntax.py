#!/usr/bin/env python3
"""Syntax-check V-NPCs Lua files with LuaJIT (via lupa).

GMod's patched LuaJIT supports `continue` and C-style `&& || !=` operators,
which stock LuaJIT rejects. We preprocess those tokens into stock-Lua
equivalents (purely for parsing - the code is never executed), then compile.
"""
import re
import sys
from pathlib import Path

import lupa
from lupa import LuaRuntime

lua = LuaRuntime(unpack_returned_tuples=True)

# GMod allows C-style operators; translate to Lua equivalents for the parser.
C_OPS = [
    (re.compile(r"&&"), "and"),
    (re.compile(r"\|\|"), "or"),
    (re.compile(r"!="), "~="),
    (re.compile(r"!(?!=)"), "not "),
]
CONT_RE = re.compile(r"\bcontinue\b")

def preprocess(src: str) -> str:
    src = CONT_RE.sub("do end", src)
    for pat, repl in C_OPS:
        src = pat.sub(repl, src)
    return src

def check(path: Path) -> list:
    errors = []
    src = path.read_text(encoding="utf-8", errors="replace")
    pp = preprocess(src)
    try:
        lua.compile(pp, str(path))
    except Exception as exc:  # lupa raises various exception types
        errors.append(f"{path}: {exc}")
    return errors

def main():
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(".")
    files = sorted(root.rglob("*.lua"))
    total_errors = 0
    checked = 0
    for f in files:
        errs = check(f)
        checked += 1
        for e in errs:
            total_errors += 1
            print(e)
    print(f"Checked {checked} Lua files, {total_errors} errors.")
    return 1 if total_errors else 0

if __name__ == "__main__":
    sys.exit(main())
