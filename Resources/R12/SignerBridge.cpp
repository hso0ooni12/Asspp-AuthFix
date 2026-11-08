// Asspp R12 — on-device code signing adapter.
// The zsign implementation is fetched from its pinned MIT-licensed upstream at CI time.
// Signing executes locally on the iPhone. No key or IPA is sent to a remote server.
#include "common.h"
#include "bundle.h"
#include "openssl.h"
#include "archive.h"
#include <cstdio>
#include <cstring>
#include <memory>
#include <string>
#include <vector>
#include <unistd.h>
#include <openssl/pkcs12.h>
#include <openssl/provider.h>
#include <openssl/rand.h>

static int fail(char *message, int capacity, const char *why, int code) {
    if (message && capacity > 0) snprintf(message, (size_t)capacity, "%s", why);
    return code;
}

// OpenSSL distinguishes an absent PKCS#12 password from an empty Unicode
// password. zsign passes an empty C string, while some passwordless files are
// encoded with a null password. Convert only that second case to a short-lived
// compatibility copy so the rest of zsign's signing pipeline stays unchanged.
static bool repackPasswordlessP12(const char *source, const std::string& destination,
                                  std::string& temporaryPassword) {
    OSSL_PROVIDER_load(NULL, "legacy");
    FILE *in = fopen(source, "rb");
    if (!in) return false;
    PKCS12 *original = d2i_PKCS12_fp(in, NULL);
    fclose(in);
    if (!original) return false;

    EVP_PKEY *key = NULL;
    X509 *certificate = NULL;
    STACK_OF(X509) *chain = NULL;
    // The empty string already failed in Init; a null password is genuinely
    // different and is the only alternate interpretation we attempt here.
    const bool parsed = PKCS12_parse(original, NULL, &key, &certificate, &chain) == 1;
    PKCS12_free(original);
    if (!parsed || !key || !certificate) {
        if (key) EVP_PKEY_free(key);
        if (certificate) X509_free(certificate);
        if (chain) sk_X509_pop_free(chain, X509_free);
        return false;
    }

    unsigned char entropy[18];
    bool wrote = false;
    if (RAND_bytes(entropy, sizeof(entropy)) == 1) {
        const char digits[] = "0123456789abcdef";
        temporaryPassword.clear();
        for (unsigned char byte : entropy) {
            temporaryPassword += digits[byte >> 4];
            temporaryPassword += digits[byte & 0xf];
        }
        PKCS12 *normalized = PKCS12_create(temporaryPassword.c_str(), "Asspp temporary identity",
                                           key, certificate, chain, 0, 0, 0, 0, 0);
        if (normalized) {
            FILE *out = fopen(destination.c_str(), "wb");
            if (out) {
                wrote = i2d_PKCS12_fp(out, normalized) == 1;
                fclose(out);
            }
            PKCS12_free(normalized);
        }
    }
    EVP_PKEY_free(key);
    X509_free(certificate);
    if (chain) sk_X509_pop_free(chain, X509_free);
    if (!wrote) unlink(destination.c_str());
    return wrote;
}

static std::string diagnoseIdentity(const char *p12Path, const char *password,
                                    const char *profilePath) {
    std::string cms;
    std::string profile;
    if (!ZFile::ReadFile(profilePath, cms) ||
        !ZSignAsset::GetCMSContent(cms, profile))
        return "Provisioning profile CMS cannot be decoded by the signing engine.";

    jvalue plist;
    if (!plist.read_plist(profile) ||
        std::string(plist["TeamIdentifier"][0].as_cstr()).empty())
        return "Provisioning profile has no readable TeamIdentifier.";

    OSSL_PROVIDER_load(NULL, "legacy");
    FILE *in = fopen(p12Path, "rb");
    if (!in) return "Cannot read the P12 certificate file.";
    PKCS12 *p12 = d2i_PKCS12_fp(in, NULL);
    fclose(in);
    if (!p12) return "Certificate is not a readable PKCS#12 (P12) file.";

    EVP_PKEY *key = NULL;
    X509 *cert = NULL;
    STACK_OF(X509) *chain = NULL;
    bool parsed = PKCS12_parse(p12, password, &key, &cert, &chain) == 1;
    if (!parsed && (!password || !password[0]))
        parsed = PKCS12_parse(p12, NULL, &key, &cert, &chain) == 1;
    if (!parsed && (!password || !password[0]))
        parsed = PKCS12_parse(p12, "1", &key, &cert, &chain) == 1;
    PKCS12_free(p12);

    std::string reason;
    if (!parsed || !key || !cert) {
        reason = (!password || !password[0])
            ? "P12 private key did not open with empty password or LCSign's documented default (1). Enter its actual password in Settings."
            : "P12 private key did not open with the saved password. Review the password in Settings.";
    } else {
        bool paired = false;
        for (size_t i = 0; i < plist["DeveloperCertificates"].size(); ++i) {
            const std::string der = plist["DeveloperCertificates"][i].as_data();
            const unsigned char *raw = reinterpret_cast<const unsigned char *>(der.data());
            X509 *allowed = d2i_X509(NULL, &raw, static_cast<long>(der.size()));
            if (allowed) {
                paired = X509_cmp(allowed, cert) == 0;
                X509_free(allowed);
            }
            if (paired) break;
        }
        reason = paired
            ? "P12 and profile are readable, but the signing engine could not initialize them."
            : "P12 certificate does not match the profile's DeveloperCertificates.";
    }
    if (key) EVP_PKEY_free(key);
    if (cert) X509_free(cert);
    if (chain) sk_X509_pop_free(chain, X509_free);
    return reason;
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
    std::unique_ptr<ZSignAsset> identity(new ZSignAsset());
    bool loaded = identity->Init("", p12Path, profilePath, "", p12Password, false, true, false);
    if (!loaded && p12Password[0] == '\0') {
        // LCSign's official installation flow tries the common default "1"
        // when the password field is empty. This stays completely on-device.
        identity.reset(new ZSignAsset());
        loaded = identity->Init("", p12Path, profilePath, "", "1", false, true, false);
    }
    if (!loaded && p12Password[0] == '\0') {
        const std::string compatiblePath = std::string(workDirectory) + "/AssppCompatible.p12";
        std::string compatiblePassword;
        if (repackPasswordlessP12(p12Path, compatiblePath, compatiblePassword)) {
            identity.reset(new ZSignAsset());
            loaded = identity->Init("", compatiblePath, profilePath, "",
                                    compatiblePassword, false, true, false);
        }
        unlink(compatiblePath.c_str());
    }
    if (!loaded) {
        const std::string reason = diagnoseIdentity(p12Path, p12Password, profilePath);
        return fail(message, messageCapacity, reason.c_str(), 5);
    }

    // Exact Ad Hoc profiles authorize one bundle identifier only. Let zsign
    // update the helper's plist while signing, and use that same identifier
    // in the OTA manifest. Wildcard profiles retain the helper's normal ID.
    const std::string prefix = identity->m_strTeamId + ".";
    const std::string& entitlement = identity->m_strApplicationId;
    if (entitlement.compare(0, prefix.size(), prefix) != 0)
        return fail(message, messageCapacity, "Provisioning profile has an unexpected application-identifier.", 9);
    const std::string authorizedID = entitlement.substr(prefix.size());
    if (authorizedID.empty() || (authorizedID.find('*') != std::string::npos && authorizedID != "*"))
        return fail(message, messageCapacity, "Provisioning profile App ID is unsupported.", 10);
    const std::string bundleOverride = authorizedID == "*" ? "" : authorizedID;

    const std::string temp = std::string(workDirectory) + "/Signer-" +
        std::to_string((unsigned long long)ZUtil::GetMicroSecond());
    if (!Zip::Extract(inputIPA, temp.c_str()))
        return fail(message, messageCapacity, "Could not unpack the FairPlayed helper.", 6);

    ZBundle bundle;
    std::vector<std::string> empty;
    const bool signedOK = bundle.SignFolder(identity.get(), temp, bundleOverride, "", "", empty,
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
