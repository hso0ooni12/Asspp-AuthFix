// Experimental native bridge to ipatool's pinned KBSync implementation.
// Only fixed stage codes cross this boundary on failure. Never return raw
// errors, Apple credentials, device IDs or signed download URLs.
package main

/*
#include <stdint.h>
#include <stdlib.h>
*/
import "C"

import (
    "context"
    "encoding/base64"
    "encoding/hex"
    "errors"
    "strconv"
    "strings"
    "sync"
    "time"
    "unsafe"

    "github.com/majd/ipatool/v2/internal/sap/assets"
    "github.com/majd/ipatool/v2/internal/sap/machine"
)

// Cache successful account-bound blobs in memory for this process only.
// Never persist them in the app's Documents folder or CI artifacts.
var kbsyncCache = struct {
    sync.Mutex
    blobs map[string]string
}{blobs: make(map[string]string)}

// The interpreter has a substantial working set. Serialize cold generations
// across accounts and recheck the memory cache after waiting for the engine.
var generationMutex sync.Mutex

//export R3GenerateKBSync
func R3GenerateKBSync(guid *C.char, accountDSID C.ulonglong) *C.char {
    if guid == nil || accountDSID == 0 {
        return C.CString("!R3:input")
    }
    hexGUID := strings.TrimSpace(C.GoString(guid))
    hardwareID, err := hex.DecodeString(hexGUID)
    if err != nil || len(hardwareID) != 6 {
        return C.CString("!R3:input")
    }
    cacheKey := strings.ToUpper(hexGUID) + ":" + strconv.FormatUint(uint64(accountDSID), 10)
    kbsyncCache.Lock()
    cached := kbsyncCache.blobs[cacheKey]
    kbsyncCache.Unlock()
    if cached != "" {
        return C.CString(cached)
    }

    generationMutex.Lock()
    defer generationMutex.Unlock()
    kbsyncCache.Lock()
    cached = kbsyncCache.blobs[cacheKey]
    kbsyncCache.Unlock()
    if cached != "" {
        return C.CString(cached)
    }

    ctx, cancel := context.WithTimeout(context.Background(), 150*time.Second)
    defer cancel()

    bundle, err := assets.Load(ctx)
    if err != nil {
        if errors.Is(err, context.DeadlineExceeded) || ctx.Err() != nil {
            return C.CString("!R3:assets-timeout")
        }
        return C.CString("!R3:assets")
    }

    data, err := machine.GenerateKBSync(ctx, bundle, hardwareID, uint64(accountDSID))
    if err != nil {
        failure := strings.ToLower(err.Error())
        switch {
        case errors.Is(err, context.DeadlineExceeded) || ctx.Err() != nil:
            return C.CString("!R3:guest-timeout")
        case strings.Contains(failure, "timed out"):
            return C.CString("!R3:guest-timeout")
        case strings.Contains(failure, "unicorn is not linked"):
            return C.CString("!R3:unicorn-unlinked")
        case strings.Contains(failure, "load apple storeagent asset"):
            return C.CString("!R3:storeagent-asset")
        case strings.Contains(failure, "start storeagent runtime"):
            if strings.Contains(failure, "unicorn") {
                return C.CString("!R3:unicorn-runtime")
            }
            return C.CString("!R3:storeagent-runtime")
        case strings.Contains(failure, "initialize storeagent global context"):
            return C.CString("!R3:storeagent-init")
        case strings.Contains(failure, "generate storeagent kbsync"):
            return C.CString("!R3:storeagent-execute")
        case strings.Contains(failure, "storeagent"):
            return C.CString("!R3:storeagent")
        default:
            return C.CString("!R3:guest")
        }
    }
    if len(data) == 0 {
        return C.CString("!R3:empty")
    }
    blob := base64.StdEncoding.EncodeToString(data)
    kbsyncCache.Lock()
    kbsyncCache.blobs[cacheKey] = blob
    kbsyncCache.Unlock()
    return C.CString(blob)
}

//export R3FreeKBSyncString
func R3FreeKBSyncString(ptr *C.char) {
    C.free(unsafe.Pointer(ptr))
}

func main() {}
