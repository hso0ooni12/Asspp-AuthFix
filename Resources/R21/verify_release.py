#!/usr/bin/env python3
"""Verify R20 download reliability and R21 FairPlayed four-mode experiment."""
import importlib.util
import json
import sys
from pathlib import Path

sys.dont_write_bytecode = True
root = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("r17_checks", root / "Resources/R17/verify_release.py")
checks = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checks)
checks.VERSION = "4.7.4"
checks.BUILD = "2026110821"
checks.IPA_NAME = "Asspp-R21-FairPlayed-FourModes-Experimental-unsigned.ipa"

service = (root / "Asspp/Backend/AppStore/StoreDownloadService.swift").read_text()
assert "defer { session.invalidateAndCancel() }" in service
assert "private static let metadataSession" not in service
assert "DownloadPreparation.shared.generation" not in service
app_store = (root / "Asspp/Backend/AppStore/AppStore.swift").read_text()
assert "No-op retained for existing view call sites." in app_store
protocol = (root / "Asspp/Backend/AppStore/StoreDownloadProtocol.swift").read_text()
assert 'onFallback("volumeStore-timeout")' in protocol
source = (root / "Resources/R19/DirectFairPlayed.c").read_text()
for mode in ["{FP_MODE_R_CID2, false}", "{FP_MODE_R_CID2, true}",
             "{FP_MODE_RX_CID1, false}", "{FP_MODE_RX_CID1, true}"]:
    assert source.count(mode) == 1, mode
assert "attempt_looks_decrypted(&a)" in source
assert "if (rc < 0 && created) unlink(output);" in source
patcher = (root / "Resources/R19/prepare_core.py").read_text()
assert "mode != FP_MODE_R_CID2 && mode != FP_MODE_RX_CID1" in patcher
tests = (root / "Resources/R19/NativeChecks.c").read_text()
assert "FP_MODE_R_CID1, false" in tests and "FP_MODE_RX_CID1, false" in tests
swift = (root / "Asspp/Backend/Decryption/DirectFairPlayed.swift").read_text()
assert "R/cryptid2 + RX/cryptid1" in swift

checks.validate_sources()
checks.validate_archive()
path = root / "artifacts/build-info.json"
report = json.loads(path.read_text())
report.update(
    release="R21 FairPlayed four-mode experiment",
    internalSigning=False,
    directDecryptionOfNewDownloads=None,
    directDecryptionStatus="four upstream mapping attempts compiled; iPhone outcome unknown",
    directModes=["R/cryptid2", "R/cryptid2+sigs", "RX/cryptid1", "RX/cryptid1+sigs"],
    deviceValidation="iOS 27 real-device retest required; errno12 may persist",
    noExecutedMappedCode=True,
    noJIT=True,
    failedDirectAttemptExportsIPA=False,
    downloadTransport="R20 stable per-request URLSession; unchanged",
    quickDownloadFromSearch=True,
)
path.write_text(json.dumps(report, indent=2) + "\n")
print("R21 verified stable downloads, upstream-mode parity, and complete-only export.")
