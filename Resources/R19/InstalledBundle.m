#import <Foundation/Foundation.h>
#import "DirectFairPlayed.h"
#include <string.h>

// These APIs can be unavailable/denied on a normally signed iPhone. A nil result
// is a diagnostic outcome, not a reason to enumerate apps or guess private paths.
int AssppFPResolveInstalled(const char *bundleID, char *path, size_t capacity) {
    if (!path || capacity == 0) return -1;
    path[0] = 0;
    @autoreleasepool {
        NSString *bid = bundleID ? [NSString stringWithUTF8String:bundleID] : nil;
        if (bid.length == 0 || [bid isEqual:NSBundle.mainBundle.bundleIdentifier]) return -1;
        NSURL *url = nil;
        Class cls = NSClassFromString(@"LSApplicationProxy");
        SEL sel = NSSelectorFromString(@"applicationProxyForIdentifier:");
        if ([cls respondsToSelector:sel]) {
            @try {
                id (*lookup)(id, SEL, id) = (void *)[cls methodForSelector:sel];
                id proxy = lookup(cls, sel, bid);
                id value = [proxy valueForKey:@"bundleURL"];
                if ([value isKindOfClass:NSURL.class]) url = value;
            } @catch (__unused NSException *exception) {}
        }
        if (!url) {
            Class record = NSClassFromString(@"LSApplicationRecord");
            SEL initializer = NSSelectorFromString(@"initWithBundleIdentifier:allowPlaceholder:error:");
            if ([record instancesRespondToSelector:initializer]) {
                @try {
                    typedef id (*Initializer)(__attribute__((ns_consumed)) id, SEL, NSString *, BOOL, NSError *__autoreleasing *)
                        __attribute__((ns_returns_retained));
                    Initializer init = (Initializer)[record instanceMethodForSelector:initializer];
                    NSError *error = nil;
                    id instance = init([record alloc], initializer, bid, NO, &error);
                    id value = [instance valueForKey:@"URL"];
                    if ([value isKindOfClass:NSURL.class]) url = value;
                } @catch (__unused NSException *exception) {}
            }
        }
        if (!url.isFileURL || ![url.pathExtension.lowercaseString isEqual:@"app"]) return 1;
        const char *resolved = url.fileSystemRepresentation;
        if (!resolved || strlen(resolved) + 1 > capacity) return -1;
        memcpy(path, resolved, strlen(resolved) + 1);
        return 0;
    }
}
