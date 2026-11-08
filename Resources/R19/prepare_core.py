#!/usr/bin/env python3
"""Allow only the pinned upstream FairPlayed mapping modes tested in R21."""
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
anchor = "    double t0 = now_ms();\n    const uint64_t pg = (uint64_t)getpagesize();"
assert text.count(anchor) == 1, "Pinned FairPlayed source changed"
text = text.replace(anchor, """    // R21: test upstream's RX mapping as an additional, explicit fallback.\n    // The mapping is never executed: pages are read via vm_read_overwrite.
    if (mode != FP_MODE_R_CID2 && mode != FP_MODE_RX_CID1) { res->mmap_errno = ENOTSUP; return -1; }
    double t0 = now_ms();
    const uint64_t pg = (uint64_t)getpagesize();""")
assert "bool one_page_stub" in text, "R9 verified tiny-framework fix is missing"
path.write_text(text)
