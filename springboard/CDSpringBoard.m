//
//  CDSpringBoard.m
//  ControlDeck.dylib 在 SpringBoard 的進入點:先把舊套件的設定搬過來,再啟動各模組的 hook。
//

#import "../shared/CDShared.h"

// ConnectStrip.x
void CSInitialize(void);

// 換成 ControlDeck 前,RebootCC 和 ConnectStrip 各有自己的偏好 domain。把裡面的鍵加上模組名
// 搬過來(tapAction → rebootTapAction、loop → connectLoop)。舊的檔案留著,不再讀。
static void CDMigrateDomain(CFStringRef oldDomain, NSString *prefix) {
    NSArray *keys = CFBridgingRelease(CFPreferencesCopyKeyList(oldDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
    for (NSString *key in keys) {
        if (![key isKindOfClass:NSString.class] || key.length == 0) continue;
        id value = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, oldDomain));
        if (!value) continue;
        NSString *name = [[key substringToIndex:1].uppercaseString stringByAppendingString:[key substringFromIndex:1]];
        CFPreferencesSetAppValue((__bridge CFStringRef)[prefix stringByAppendingString:name], (__bridge CFPropertyListRef)value, kCDPreferencesDomain);
    }
}

// 只搬一次(Metal HUD 的開關檔由 ControlDeckMetalHUD 自己搬)
static void CDMigrateOldPackages(void) {
    if (CDPreferenceBool(@"migrated", NO)) return;
    CDMigrateDomain(CFSTR("com.c3x14n.rebootcc"), @"reboot");
    CDMigrateDomain(CFSTR("com.c3x14n.connectstrip"), @"connect");
    CFPreferencesSetAppValue(CFSTR("migrated"), kCFBooleanTrue, kCDPreferencesDomain);
    CFPreferencesAppSynchronize(kCDPreferencesDomain);
}

__attribute__((constructor)) static void CDSpringBoardInit(void) {
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
    CDMigrateOldPackages();
    CSInitialize();
}
