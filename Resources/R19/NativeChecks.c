#include "DirectFairPlayed.h"
#include "fpcore.h"
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <mach-o/loader.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static unsigned char bytes[32768];
static char source[1024], output[1024], note[65536];

static void fixture(uint32_t cryptid) {
    memset(bytes, 0, sizeof bytes);
    struct mach_header_64 mh = {.magic = MH_MAGIC_64, .cputype = CPU_TYPE_ARM64,
        .cpusubtype = CPU_SUBTYPE_ARM64_ALL, .filetype = MH_EXECUTE,
        .ncmds = 1, .sizeofcmds = sizeof(struct encryption_info_command_64)};
    struct encryption_info_command_64 enc = {.cmd = LC_ENCRYPTION_INFO_64,
        .cmdsize = sizeof enc, .cryptoff = 16384, .cryptsize = 16384, .cryptid = cryptid};
    memcpy(bytes, &mh, sizeof mh); memcpy(bytes + sizeof mh, &enc, sizeof enc);
    // Non-random pattern intentionally fails the encrypted->code entropy check.
    for (size_t i = 16384; i < sizeof bytes; i++) bytes[i] = (unsigned char)(i * 13);
}

static void save(size_t size) {
    int fd = open(source, O_WRONLY | O_CREAT | O_TRUNC, 0600); assert(fd >= 0);
    assert(write(fd, bytes, size) == (ssize_t)size); assert(close(fd) == 0);
}

static void reject(size_t size) {
    save(size);
    assert(AssppFPInspect(source, note, sizeof note) == -1);
    unlink(output);
    assert(AssppFPProcess(source, output, note, sizeof note) == -1);
    assert(access(output, F_OK) != 0);
}

int main(void) {
    char dir[] = "/tmp/asspp-direct-checks-XXXXXX"; assert(mkdtemp(dir));
    snprintf(source, sizeof source, "%s/source", dir);
    snprintf(output, sizeof output, "%s/output", dir);
    fixture(0); save(sizeof bytes);
    assert(AssppFPInspect(source, note, sizeof note) == 0);
    assert(AssppFPProcess(source, output, note, sizeof note) == 1);
    unsigned char copied[sizeof bytes];
    int fd = open(output, O_RDONLY); assert(fd >= 0);
    assert(read(fd, copied, sizeof copied) == sizeof copied); close(fd);
    assert(memcmp(bytes, copied, sizeof bytes) == 0);
    // Existing destinations and source==destination must be left untouched.
    assert(AssppFPProcess(source, source, note, sizeof note) == -1);
    assert(AssppFPInspect(source, note, sizeof note) == 0);
    assert(AssppFPProcess(source, output, note, sizeof note) == -1);
    assert(access(output, F_OK) == 0); unlink(output);
    puts("PASS plaintext copy, final inspection and source/destination protection");

    fixture(1); save(sizeof bytes);
    assert(AssppFPInspect(source, note, sizeof note) == 1);
    // Synthetic bytes have no valid FairPlay license. Failure must never leave
    // a plaintext-labelled or partial output, even if a remap syscall returns 0.
    assert(AssppFPProcess(source, output, note, sizeof note) == -1);
    assert(access(output, F_OK) != 0);
    assert(AssppFPInspect(source, note, sizeof note) == 1);
    puts("PASS missing-license failure removes output and preserves ciphertext source");

    fixture(0); reject(4); // truncated thin header
    fixture(0); ((struct mach_header_64 *)bytes)->sizeofcmds = 0xffffffff; reject(sizeof bytes);
    fixture(0); ((struct mach_header_64 *)bytes)->ncmds = 2; reject(sizeof bytes);
    fixture(0); ((struct mach_header_64 *)bytes)->cputype = CPU_TYPE_X86_64; reject(sizeof bytes);
    fixture(1); ((struct encryption_info_command_64 *)(bytes + sizeof(struct mach_header_64)))->cmdsize = 8; reject(sizeof bytes);
    fixture(1); ((struct encryption_info_command_64 *)(bytes + sizeof(struct mach_header_64)))->cryptsize = 0xffffffff; reject(sizeof bytes);
    fixture(1); ((struct encryption_info_command_64 *)(bytes + sizeof(struct mach_header_64)))->cryptoff = 0; reject(sizeof bytes);
    fixture(0); bytes[0] = 0xca; bytes[1] = 0xfe; bytes[2] = 0xba; bytes[3] = 0xbe;
    memset(bytes + 4, 0xff, 4); reject(sizeof bytes);
    puts("PASS malformed command tables, architectures, ranges and FAT tables fail closed");

    // A deterministic mutation corpus exercises boundary validation under ASan
    // and UBSan. Only inspection is used, never remapping arbitrary test input.
    uint32_t state = 0x19f00d;
    for (int i = 0; i < 1200; i++) {
        fixture(i % 2);
        for (int j = 0; j < 8; j++) {
            state = state * 1664525U + 1013904223U;
            bytes[state % 96] ^= (unsigned char)(state >> 24);
        }
        save(i % 3 == 0 ? 60 : sizeof bytes);
        int rc = AssppFPInspect(source, note, sizeof note);
        assert(rc >= -1 && rc <= 1);
    }
    puts("PASS 1200 malformed-input mutations under sanitizers");

    fp_attempt_t attempt; fp_slice_t slice = {0};
    assert(fp_attempt(source, &slice, FP_MODE_R_CID1, false, NULL, &attempt) == -1);
    assert(attempt.mmap_errno == ENOTSUP);
    unlink(source); assert(symlink("/nonexistent", source) == 0);
    assert(AssppFPInspect(source, note, sizeof note) == -1);
    unlink(source); rmdir(dir);
    puts("PASS unsupported mapping mode and symlink inputs are rejected");
    puts("Host checks do not establish that real App Store decryption works on an iPhone.");
    return 0;
}
