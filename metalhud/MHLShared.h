//
//  MHLShared.h
//  Metal HUD (from pookjw's MetalHudLoader): shared by the loader injected into
//  every Metal process (ControlDeckMetalHUD) and the Control Center toggle
//  (cc/MetalHUD/MHLModule.m).
//

#ifndef MetalHudLoader_shared_h
#define MetalHudLoader_shared_h

#import <Foundation/Foundation.h>

// Darwin notification state is used to share the toggle across sandboxed
// processes; the plist persists it across reboots (restored by SpringBoard).
#define kMHLEnabledStateName "com.c3x14n.controldeck.metalhud"
// Written directly (not via cfprefsd) from SpringBoard, next to the system's
// own ModuleConfiguration.plist which SpringBoard is always allowed to write.
#define kMHLPrefsPath "/var/mobile/Library/ControlCenter/ControlDeck-MetalHUD.plist"
// MetalHudLoader's own file, moved to kMHLPrefsPath once by SpringBoard.
#define kMHLOldPrefsPath "/var/mobile/Library/ControlCenter/MetalHudLoader.plist"
#define kMHLEnabledKey "Enabled"
#define kMHLElementsKey "Elements"

// State layout: bits 0-7 hold the enabled field, bits 8+ hold a bitmask of
// MHLElementNames indices (0 = show the HUD's default elements). Sandboxed
// apps can't read the plist, so the whole configuration travels in the
// 64-bit notify state.
enum {
    MHLStateUnset = 0,
    MHLStateDisabled = 1,
    MHLStateEnabled = 2,
};
#define MHLEnabledFieldMask 0xFFULL
#define MHLElementsShift 8

// Metric names accepted by MTL_HUD_ELEMENTS; the bit index must stay stable
// because it is what gets persisted in the notify state.
static const char *const MHLElementNames[] = {
    "device", "rosetta", "layersize", "layerscale", "memory", "fps",
    "frameinterval", "gputime", "thermal", "frameintervalgraph",
    "presentdelay", "frameintervalhistogram", "metalcpu", "gputimeline",
    "shaders", "framenumber", "disk", "fpsgraph",
    "toplabeledcommandbuffers", "toplabeledencoders",
};
enum { MHLElementCount = sizeof(MHLElementNames) / sizeof(MHLElementNames[0]) };

// "Elements" may be a comma-separated string or an array of strings;
// unknown names are ignored.
static inline uint64_t MHLElementsMaskFromPrefs(NSDictionary *prefs) {
    id value = prefs[@kMHLElementsKey];
    NSArray *names = nil;
    if ([value isKindOfClass:NSString.class]) {
        names = [(NSString *)value componentsSeparatedByString:@","];
    } else if ([value isKindOfClass:NSArray.class]) {
        names = value;
    }

    uint64_t mask = 0;
    for (id name in names) {
        if (![name isKindOfClass:NSString.class]) {
            continue;
        }
        NSString *trimmed = [(NSString *)name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].lowercaseString;
        for (uint64_t i = 0; i < MHLElementCount; i++) {
            if ([trimmed isEqualToString:@(MHLElementNames[i])]) {
                mask |= 1ULL << i;
                break;
            }
        }
    }
    return mask;
}

static inline uint64_t MHLStateMake(BOOL enabled, uint64_t elementsMask) {
    return (enabled ? MHLStateEnabled : MHLStateDisabled) | (elementsMask << MHLElementsShift);
}

#endif
