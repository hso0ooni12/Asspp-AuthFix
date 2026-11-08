#!/usr/bin/env python3
"""Reuse the no-signing release checks with R18's exact release metadata."""
import importlib.util
import json
import sys
from pathlib import Path

sys.dont_write_bytecode = True
root = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("r17_checks", root / "Resources/R17/verify_release.py")
checks = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checks)
checks.VERSION = "4.7.1"
checks.BUILD = "2026110818"
checks.IPA_NAME = "Asspp-R18-FastDownloads-unsigned.ipa"
checks.validate_sources()
checks.validate_archive()
path = root / "artifacts/build-info.json"
report = json.loads(path.read_text())
report.update(release="R18", quickDownloadFromSearch=True,
              performanceChanges="foreground warm-up, in-flight coalescing, concurrent metadata lookup, TLS reuse",
              measuredDeviceSpeedup="not benchmarked in CI")
path.write_text(json.dumps(report, indent=2) + "\n")
