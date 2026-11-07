// Asspp R12 — on-device code signing adapter.
// The zsign implementation is fetched from its pinned MIT-licensed upstream at CI time.
// Signing executes locally on the iPhone. No key or IPA is sent to a remote server.
#include "common.h"
#include "bundle.h"
#include "openssl.h"
#include "archive.h"
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>
#include <unistd.h>

static int fail(char *message, int capacity, const char *why, int code) {
    if (message && capacity > 0) snprintf(message, (size_t)capacity, "%s", why);
    return code;
}

extern "C" int AssppSignIPA(const char *inputIPA,
                             const char *p12Path,
                             const char *p12Password,
                             const char *profilePath,
                             const char *outputIPA,
                             const char *workDirectory,
                             char *message,
                             int messageCapacity) {
    if (!inputIPA || !p12Path || !p12Password || !profilePath || !outputIPA || !workDirectory)
        return fail(message, messageCapacity, "Missing IPA, signing identity, or output path.", 1);
    if (!ZFile::IsZipFile(inputIPA))
        return fail(message, messageCapacity, "Input is not a valid IPA archive.", 2);
    if (!ZFile::IsFileExists(p12Path) || !ZFile::IsFileExists(profilePath))
        return fail(message, messageCapacity, "Certificate or provisioning profile is missing.", 3);
    if (!ZFile::IsFolder(workDirectory))
        return fail(message, messageCapacity, "Working directory is unavailable.", 4);

    ZLog::SetLogLever(ZLog::E_WARN);
    ZSignAsset identity;
    if (!identity.Init("", p12Path, profilePath, "", p12Password, false, true, false))
        return fail(message, messageCapacity, "Invalid P12 password, certificate or provisioning profile.", 5);

    const std::string temp = std::string(workDirectory) + "/Signer-" +
        std::to_string((unsigned long long)ZUtil::GetMicroSecond());
    if (!Zip::Extract(inputIPA, temp.c_str()))
        return fail(message, messageCapacity, "Could not unpack the FairPlayed helper.", 6);

    ZBundle bundle;
    std::vector<std::string> empty;
    // Keep the identity of the FairPlayed helper. A wildcard provisioning
    // profile can cover it; an explicitly scoped profile must match it.
    const bool signedOK = bundle.SignFolder(&identity, temp, "", "", "", empty,
                                             empty, true, false, false, false);
    bool archived = false;
    if (signedOK) {
        const size_t payload = bundle.m_strAppFolder.rfind("Payload");
        if (payload != std::string::npos && payload > 0) {
            const std::string root = bundle.m_strAppFolder.substr(0, payload - 1);
            archived = Zip::Archive(root, outputIPA, 0);
        }
    }
    ZFile::RemoveFolder(temp.c_str());
    if (!signedOK) return fail(message, messageCapacity, "Signing failed. Check that the profile permits this bundle ID and device.", 7);
    if (!archived || !ZFile::IsZipFile(outputIPA))
        return fail(message, messageCapacity, "Failed to package the signed IPA.", 8);
    return fail(message, messageCapacity, "Signed IPA is ready to install.", 0);
}
