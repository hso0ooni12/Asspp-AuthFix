#!/usr/bin/env python3
"""Retain R17/R18 guarantees and label the direct engine as experimental."""
import importlib.util
import json
import sys
from pathlib import Path

sys.dont_write_bytecode = True
root = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("r17_checks", root / "Resources/R17/verify_release.py")
checks = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checks)
checks.VERSION = "4.7.2"
checks.BUILD = "2026110819"
checks.IPA_NAME = "Asspp-R19-DirectFairPlayed-Experimental-unsigned.ipa"
checks.validate_sources()
checks.validate_archive()
path = root / "artifacts/build-info.json"
report = json.loads(path.read_text())
report.update(
    release="R19 experimental",
    directDecryptionOfNewDownloads=None,
    directDecryptionStatus="in-process engine experiment; real-device result unknown",
    deviceValidation="requires an iPhone test; host tests validate bounds and failure handling only",
    pinnedFairPlayed="bad7df138839b5e0ac8b9f20cc4689140b8436fb",
    directModes="READ / cryptid=2 only",
    directSources=["selected installed app if exact version and full binary hash match", "downloaded data-container copy"],
    failedDirectAttemptExportsIPA=False,
    quickDownloadFromSearch=True,
    performanceChanges="R18 foreground warm-up, in-flight coalescing, concurrent metadata lookup, TLS reuse",
)
path.write_text(json.dumps(report, indent=2) + "\n")
print("R19 direct engine is experimental; no real-device success is claimed")
