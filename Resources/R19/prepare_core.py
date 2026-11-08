#!/usr/bin/env python3
"""Apply a fail-fast READ/cryptid2-only guard to the pinned, R9-patched core."""
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
anchor = "    double t0 = now_ms();\n    const uint64_t pg = (uint64_t)getpagesize();"
assert text.count(anchor) == 1, "Pinned FairPlayed source changed"
text = text.replace(anchor, """    // Asspp's experimental integration never requests executable mappings.
    if (mode != FP_MODE_R_CID2) { res->mmap_errno = ENOTSUP; return -1; }
    double t0 = now_ms();
    const uint64_t pg = (uint64_t)getpagesize();""")
assert "bool one_page_stub" in text, "R9 verified tiny-framework fix is missing"
path.write_text(text)
