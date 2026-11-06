// This source is copied into github.com/majd/ipatool/v2/cmd/r3bridge
// before compilation so it may use ipatool's internal SAP packages.
//
// R3 experimental bridge only. No Apple credentials are handled here;
// the host iOS app must already have a valid account session.
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
    "strings"
    "time"
    "unsafe"

    "github.com/majd/ipatool/v2/internal/sap/assets"
    "github.com/majd/ipatool/v2/internal/sap/machine"
)

//export R3GenerateKBSync
func R3GenerateKBSync(guid *C.char, accountDSID C.ulonglong) *C.char {
    if guid == nil || accountDSID == 0 {
        return C.CString("")
    }
    hardwareID, err := hex.DecodeString(strings.TrimSpace(C.GoString(guid)))
    if err != nil || len(hardwareID) != 6 {
        return C.CString("")
    }
    ctx, cancel := context.WithTimeout(context.Background(), 150*time.Second)
    defer cancel()
    bundle, err := assets.Load(ctx)
    if err != nil {
        return C.CString("")
    }
    data, err := machine.GenerateKBSync(ctx, bundle, hardwareID, uint64(accountDSID))
    if err != nil || len(data) == 0 {
        return C.CString("")
    }
    return C.CString(base64.StdEncoding.EncodeToString(data))
}

//export R3FreeKBSyncString
func R3FreeKBSyncString(ptr *C.char) {
    C.free(unsafe.Pointer(ptr))
}

func main() {}
