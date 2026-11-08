#!/usr/bin/env python3
"""R20: recover the reliable download path while retaining R19 FairPlayed experiments."""
import importlib.util
import json
import sys
from pathlib import Path

sys.dont_write_bytecode = True
root = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("r17_checks", root / "Resources/R17/verify_release.py")
checks = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checks)
checks.VERSION = "4.7.3"
checks.BUILD = "2026110820"
checks.IPA_NAME = "Asspp-R20-RestoreDownloads-unsigned.ipa"

service = (root / "Asspp/Backend/AppStore/StoreDownloadService.swift").read_text()
assert "defer { session.invalidateAndCancel() }" in service, "Stable per-request session not restored"
assert "private static let metadataSession" not in service, "Persistent metadataSession still active"
assert "DownloadPreparation.shared.generation" not in service, "Eager preparation wait still active"
app_store = (root / "Asspp/Backend/AppStore/AppStore.swift").read_text()
assert "No-op retained for existing view call sites." in app_store, "Background warm-up still active"
protocol = (root / "Asspp/Backend/AppStore/StoreDownloadProtocol.swift").read_text()
assert 'onFallback("volumeStore-timeout")' in protocol, "Timeout recovery unavailable"
checks.validate_sources()
checks.validate_archive()

report_path = root / "artifacts/build-info.json"
report = json.loads(report_path.read_text())
report.update(
    release="R20 download reliability (experimental direct engine)",
    internalSigning=False,
    directDecryptionOfNewDownloads=None,
    directDecryptionStatus="in-process FairPlayed experimental; physical iPhone outcome unknown",
    deviceValidation="required for Apple download and direct FairPlayed paths",
    pinnedFairPlayed="bad7df138839b5e0ac8b9f20cc4689140b8436fb",
    quickDownloadFromSearch=True,
    downloadTransport="restored per-request R17 URLSession",
    expensiveAccountSearchWarmup=False,
    volumeStoreTimeoutRecovery=True,
)
report_path.write_text(json.dumps(report, indent=2) + "\n")
print("R20 transport rollback, fallback safety, and IPA metadata verified")
