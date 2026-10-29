//
//  CDShared.h
//  各部分共用的偏好設定。全部存在 com.c3x14n.controldeck(設定頁寫,cfprefsd 管),
//  鍵以模組名開頭(rebootTapAction、connectLoop)。每個模組的總開關是 <模組>Enabled,
//  控制中心和 SpringBoard 只在啟動時讀,改了要 respring(設定頁的「套用」)。
//

#import <Foundation/Foundation.h>

#define kCDPreferencesDomain CFSTR("com.c3x14n.controldeck")

// 模組的總開關,預設都開(巨集:cc/CDProvider.m 的模組表要用常數初始化)
#define kCDRebootCCEnabledKey @"rebootEnabled"
#define kCDMetalHUDEnabledKey @"metalhudEnabled"
#define kCDConnectStripEnabledKey @"connectEnabled"

// 每次都重新讀
static inline BOOL CDPreferenceBool(NSString *key, BOOL fallback) {
    CFPreferencesAppSynchronize(kCDPreferencesDomain);
    Boolean valid = false;
    Boolean value = CFPreferencesGetAppBooleanValue((__bridge CFStringRef)key, kCDPreferencesDomain, &valid);
    return valid ? value : fallback;
}

static inline id CDPreferenceValue(NSString *key) {
    CFPreferencesAppSynchronize(kCDPreferencesDomain);
    return CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, kCDPreferencesDomain));
}
