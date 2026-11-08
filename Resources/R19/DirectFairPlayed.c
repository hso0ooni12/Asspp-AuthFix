// Experimental in-process integration of morzelowski/FairPlayed, pinned in CI.
// fpcore.c is compiled here to reuse its read-only remap, safe page reads and
// acceptance heuristic. Its permissive parser/exporter are NOT our entry points.
#include "fpcore.c"
#include "DirectFairPlayed.h"
#include <pthread.h>

#define DIRECT_MAX_CRYPT (64ULL * 1024 * 1024)
#define DIRECT_MAX_FILE (8ULL * 1024 * 1024 * 1024)

typedef struct { char *text; size_t capacity, used; } direct_report_t;
static pthread_mutex_t direct_lock = PTHREAD_MUTEX_INITIALIZER;

static void direct_note(direct_report_t *r, const char *fmt, ...) {
    if (!r->text || r->used + 1 >= r->capacity) return;
    va_list ap; va_start(ap, fmt);
    int n = vsnprintf(r->text + r->used, r->capacity - r->used, fmt, ap);
    va_end(ap);
    if (n > 0) r->used += (size_t)n < r->capacity - r->used
        ? (size_t)n : r->capacity - r->used - 1;
}

static bool direct_range(uint64_t offset, uint64_t length, uint64_t total) {
    return offset <= total && length <= total - offset;
}

// Validate every slice before fpcore sees it. Never silently skip malformed,
// unsupported or excess slices, and never accept an incomplete command table.
static int direct_thin(int fd, uint64_t off, uint64_t size, fp_slice_t *s,
                       direct_report_t *r) {
    struct mach_header_64 mh;
    if (size < sizeof mh || !pread_full(fd, &mh, sizeof mh, (off_t)off) ||
        mh.magic != MH_MAGIC_64 || mh.cputype != CPU_TYPE_ARM64 ||
        (mh.filetype != MH_EXECUTE && mh.filetype != MH_DYLIB && mh.filetype != MH_BUNDLE) ||
        mh.sizeofcmds > 16 * 1024 * 1024 || mh.sizeofcmds == 0 ||
        !direct_range(sizeof mh, mh.sizeofcmds, size) ||
        mh.ncmds == 0 || mh.ncmds > mh.sizeofcmds / sizeof(struct load_command)) {
        direct_note(r, "Unsupported or truncated arm64 Mach-O header.\n"); return -1;
    }
    uint8_t *cmds = malloc(mh.sizeofcmds);
    if (!cmds || !pread_full(fd, cmds, mh.sizeofcmds, (off_t)(off + sizeof mh))) {
        free(cmds); direct_note(r, "Load-command read failed.\n"); return -1;
    }
    memset(s, 0, sizeof *s);
    s->slice_off = off; s->slice_size = size;
    s->cputype = mh.cputype; s->cpusubtype = mh.cpusubtype; s->filetype = mh.filetype;
    uint64_t pos = 0; int rc = 0; bool has_signature = false;
    for (uint32_t i = 0; i < mh.ncmds; i++) {
        if (!direct_range(pos, sizeof(struct load_command), mh.sizeofcmds)) { rc = -1; break; }
        struct load_command lc; memcpy(&lc, cmds + pos, sizeof lc);
        if (lc.cmdsize < sizeof lc || lc.cmdsize % 8 ||
            !direct_range(pos, lc.cmdsize, mh.sizeofcmds)) { rc = -1; break; }
        if (lc.cmd == LC_ENCRYPTION_INFO_64 || lc.cmd == LC_ENCRYPTION_INFO) {
            size_t minimum = lc.cmd == LC_ENCRYPTION_INFO_64
                ? sizeof(struct encryption_info_command_64) : sizeof(struct encryption_info_command);
            if (s->has_enc || lc.cmdsize < minimum) { rc = -1; break; }
            struct encryption_info_command enc; memcpy(&enc, cmds + pos, sizeof enc);
            if (enc.cryptid > 2 || !direct_range(enc.cryptoff, enc.cryptsize, size) ||
                (enc.cryptid && (enc.cryptsize == 0 || enc.cryptsize > DIRECT_MAX_CRYPT ||
                 enc.cryptoff < sizeof mh + mh.sizeofcmds))) { rc = -1; break; }
            s->has_enc = true; s->enc_lc_off = off + sizeof mh + pos;
            s->cryptoff = enc.cryptoff; s->cryptsize = enc.cryptsize; s->cryptid = enc.cryptid;
        } else if (lc.cmd == LC_CODE_SIGNATURE) {
            if (has_signature || lc.cmdsize < sizeof(struct linkedit_data_command)) { rc = -1; break; }
            struct linkedit_data_command sig; memcpy(&sig, cmds + pos, sizeof sig);
            if (!direct_range(sig.dataoff, sig.datasize, size)) { rc = -1; break; }
            has_signature = true; s->cs_off = sig.dataoff; s->cs_size = sig.datasize;
        }
        pos += lc.cmdsize;
    }
    if (pos != mh.sizeofcmds) rc = -1;
    free(cmds);
    if (rc) direct_note(r, "Invalid commands, encryption range, or unsupported size (64 MiB per encrypted slice maximum).\n");
    return rc;
}

static int direct_parse(int fd, fp_slice_t *slices, int *count, direct_report_t *r) {
    *count = 0;
    struct stat st; uint32_t magic = 0;
    if (fstat(fd, &st) || !S_ISREG(st.st_mode) || st.st_size < 4 ||
        (uint64_t)st.st_size > DIRECT_MAX_FILE || !pread_full(fd, &magic, 4, 0)) {
        direct_note(r, "Invalid file or file size.\n"); return -1;
    }
    if (magic == MH_MAGIC_64) {
        if (direct_thin(fd, 0, st.st_size, slices, r)) return -1;
        *count = 1; return 0;
    }
    if (magic != FAT_CIGAM && magic != FAT_CIGAM_64) {
        direct_note(r, "Unsupported Mach-O format.\n"); return -1;
    }
    struct fat_header fh;
    if (!pread_full(fd, &fh, sizeof fh, 0)) return -1;
    uint32_t n = OSSwapBigToHostInt32(fh.nfat_arch);
    bool fat64 = magic == FAT_CIGAM_64;
    uint64_t stride = fat64 ? sizeof(struct fat_arch_64) : sizeof(struct fat_arch);
    uint64_t table_end = sizeof fh + (uint64_t)n * stride;
    if (!n || n > FP_MAX_SLICES || table_end > (uint64_t)st.st_size) {
        direct_note(r, "Invalid or excessive FAT slice table.\n"); return -1;
    }
    for (uint32_t i = 0; i < n; i++) {
        uint64_t off, size; uint32_t cpu;
        if (fat64) {
            struct fat_arch_64 a;
            if (!pread_full(fd, &a, sizeof a, sizeof fh + i * stride)) return -1;
            off = OSSwapBigToHostInt64(a.offset); size = OSSwapBigToHostInt64(a.size);
            cpu = OSSwapBigToHostInt32(a.cputype);
        } else {
            struct fat_arch a;
            if (!pread_full(fd, &a, sizeof a, sizeof fh + i * stride)) return -1;
            off = OSSwapBigToHostInt32(a.offset); size = OSSwapBigToHostInt32(a.size);
            cpu = OSSwapBigToHostInt32(a.cputype);
        }
        if (cpu != CPU_TYPE_ARM64 || off < table_end ||
            !direct_range(off, size, st.st_size)) {
            direct_note(r, "Unsupported CPU or out-of-bounds FAT slice.\n"); return -1;
        }
        for (uint32_t j = 0; j < i; j++) {
            if (off < slices[j].slice_off + slices[j].slice_size &&
                slices[j].slice_off < off + size) {
                direct_note(r, "Overlapping FAT slices.\n"); return -1;
            }
        }
        if (direct_thin(fd, off, size, &slices[i], r)) return -1;
        (*count)++;
    }
    return 0;
}

int AssppFPInspect(const char *path, char *report, size_t capacity) {
    direct_report_t r = {report, capacity, 0}; if (report && capacity) report[0] = 0;
    int fd = open(path, O_RDONLY | O_NOFOLLOW);
    if (fd < 0) { direct_note(&r, "Open failed: errno %d.\n", errno); return -1; }
    fp_slice_t slices[FP_MAX_SLICES]; int n = 0;
    int rc = direct_parse(fd, slices, &n, &r); close(fd);
    if (rc) return -1;
    for (int i = 0; i < n; i++) if (slices[i].has_enc && slices[i].cryptid) return 1;
    return 0;
}

int AssppFPProcess(const char *source, const char *output, char *report, size_t capacity) {
    direct_report_t r = {report, capacity, 0}; if (report && capacity) report[0] = 0;
    pthread_mutex_lock(&direct_lock);
    int in = -1, out = -1, rc = -1; bool created = false, encrypted = false;
    fp_slice_t slices[FP_MAX_SLICES]; int n = 0;
    in = open(source, O_RDONLY | O_NOFOLLOW);
    if (in < 0) { direct_note(&r, "Source open failed: errno %d.\n", errno); goto finish; }
    if (direct_parse(in, slices, &n, &r)) goto finish;
    struct stat st;
    if (fstat(in, &st)) goto finish;
    // A brand-new destination prevents accidental modification of either source.
    out = open(output, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW, 0600);
    if (out < 0) { direct_note(&r, "New output creation failed: errno %d.\n", errno); goto finish; }
    created = true;
    uint8_t *copy = malloc(1024 * 1024);
    if (!copy) { direct_note(&r, "Copy allocation failed.\n"); goto finish; }
    bool copied = true;
    for (off_t at = 0; at < st.st_size;) {
        size_t amount = (uint64_t)(st.st_size - at) < 1024 * 1024 ? (size_t)(st.st_size - at) : 1024 * 1024;
        if (!pread_full(in, copy, amount, at) || !pwrite_full(out, copy, amount, at)) { copied = false; break; }
        at += amount;
    }
    free(copy);
    if (!copied) { direct_note(&r, "Binary copy failed.\n"); goto finish; }
    for (int i = 0; i < n; i++) {
        fp_slice_t *s = &slices[i];
        if (!s->has_enc || !s->cryptid) continue;
        encrypted = true;
        uint8_t *plain = malloc(s->cryptsize);
        if (!plain) { direct_note(&r, "Decrypt allocation failed.\n"); goto finish; }
        bool accepted = false;
        // Both attempts use READ only and cryptid=2; no executable mapping/JIT.
        for (int sigs = 0; sigs < 2 && !accepted; sigs++) {
            fp_attempt_t a; char description[768];
            fp_attempt(source, s, FP_MODE_R_CID2, sigs != 0, plain, &a);
            fp_attempt_describe(&a, description, sizeof description);
            accepted = attempt_looks_decrypted(&a);
            direct_note(&r, "slice %d: %s; accepted=%d\n", i, description, accepted);
        }
        if (!accepted) { free(plain); direct_note(&r, "No output: syscall, page-read or plaintext validation failed.\n"); goto finish; }
        uint32_t zero = 0;
        bool written = pwrite_full(out, plain, s->cryptsize, s->slice_off + s->cryptoff) &&
            pwrite_full(out, &zero, sizeof zero, s->enc_lc_off + offsetof(struct encryption_info_command, cryptid));
        free(plain);
        if (!written) { direct_note(&r, "Plaintext write failed.\n"); goto finish; }
    }
    if (fsync(out) != 0 || fchmod(out, st.st_mode & 0777) != 0) goto finish;
    fp_slice_t verified[FP_MAX_SLICES]; int vn = 0;
    if (direct_parse(out, verified, &vn, &r) || vn != n) goto finish;
    for (int i = 0; i < vn; i++) if (verified[i].has_enc && verified[i].cryptid) goto finish;
    rc = encrypted ? 0 : 1;
finish:
    if (in >= 0) close(in);
    if (out >= 0) close(out);
    if (rc < 0 && created) unlink(output);
    pthread_mutex_unlock(&direct_lock);
    return rc;
}
