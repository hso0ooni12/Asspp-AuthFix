#pragma once
#include <stddef.h>

// 0: valid plaintext, 1: contains encrypted slices, -1: invalid/unsupported.
int AssppFPInspect(const char *path, char *report, size_t capacity);
// 0: decrypted, 1: already plaintext, -1: failed (new output is removed).
int AssppFPProcess(const char *source, const char *output, char *report, size_t capacity);
// Looks up only the explicitly selected app; never enumerates installed apps.
int AssppFPResolveInstalled(const char *bundleID, char *path, size_t capacity);
