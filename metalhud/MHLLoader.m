//
//  MHLLoader.m
//  ControlDeckMetalHUD.dylib (pookjw's MetalHudLoader): injected into every
//  process that loads Metal; with the Control Center toggle on, it loads
//  libMTLHud before the app draws.
//

#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <notify.h>
#import "MHLShared.h"
#import "../shared/CDShared.h"

// SpringBoard launches before any app, so it restores the persisted
// preference into notifyd where sandboxed processes can read it. With Metal
// HUD turned off in ControlDeck's settings, the HUD stays off whatever the
// toggle said (its module isn't in Control Center then).
static void restoreState(int token) {
    NSFileManager *fileManager = NSFileManager.defaultManager;
    if (![fileManager fileExistsAtPath:@kMHLPrefsPath] && [fileManager fileExistsAtPath:@kMHLOldPrefsPath]) {
        [fileManager moveItemAtPath:@kMHLOldPrefsPath toPath:@kMHLPrefsPath error:nil];
    }
    if (!CDPreferenceBool(kCDMetalHUDEnabledKey, YES)) {
        notify_set_state(token, MHLStateDisabled);
        return;
    }
    // Off until the toggle is turned on: installing ControlDeck for its other
    // modules shouldn't put the HUD over every app.
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:@kMHLPrefsPath];
    NSNumber *enabled = prefs[@kMHLEnabledKey];
    notify_set_state(token, MHLStateMake(enabled.boolValue, MHLElementsMaskFromPrefs(prefs)));
}

static uint64_t currentState(void) {
    uint64_t state = MHLStateUnset;
    // The token is intentionally never cancelled: notifyd drops a name's
    // state once its last registration goes away, so every process keeps
    // one registration alive (SpringBoard anchors it across the session).
    static int token;
    if (notify_register_check(kMHLEnabledStateName, &token) == NOTIFY_STATUS_OK) {
        if ([NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) {
            restoreState(token);
        }
        notify_get_state(token, &state);
    }
    return state;
}

__attribute__((constructor)) static void init() {
    uint64_t state = currentState();
    if ((state & MHLEnabledFieldMask) != MHLStateEnabled) {
        return;
    }

    uint64_t elementsMask = state >> MHLElementsShift;
    if (elementsMask != 0) {
        NSMutableArray<NSString *> *names = [NSMutableArray new];
        for (uint64_t i = 0; i < MHLElementCount; i++) {
            if (elementsMask & (1ULL << i)) {
                [names addObject:@(MHLElementNames[i])];
            }
        }
        setenv("MTL_HUD_ELEMENTS", [names componentsJoinedByString:@","].UTF8String, 1);
    }

    setenv("MTL_HUD_ENABLED", "1", 1);

    const char *path;
    if (kCFCoreFoundationVersionNumber >= 2042.1020) {
        path = "/Symbols/usr/lib/libMTLHud.dylib";
    } else {
        path = "/usr/lib/libMTLHud.dylib";
    }

    dlopen(path, RTLD_NOW);
}
