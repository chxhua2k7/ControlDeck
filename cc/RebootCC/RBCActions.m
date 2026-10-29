//
//  RBCActions.m
//  動作的實作。模組跑在 SpringBoard(mobile):
//  - respring:spawn sbreload(uikittools),失敗才退回 FrontBoardServices 的 SBSRelaunchAction
//  - 重建圖示快取 / userspace reboot / 安全模式 / 重新開機:spawn setuid root 的 ControlDeckHelper
//    (見 helper/main.c)
//

#import "RBCActions.h"
#import "../../shared/CDShared.h"
#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <spawn.h>
#import <sys/wait.h>

#ifndef THEOS_PACKAGE_INSTALL_PREFIX
#define THEOS_PACKAGE_INSTALL_PREFIX ""
#endif


extern char **environ;

static const char *const kRBCSbreloadPath = THEOS_PACKAGE_INSTALL_PREFIX "/usr/bin/sbreload";
static const char *const kRBCHelperPath = THEOS_PACKAGE_INSTALL_PREFIX "/usr/libexec/ControlDeckHelper";

#pragma mark - 除錯記錄

#ifdef DEBUG
// SpringBoard 的 unified log 用 mobile 讀不到,除錯版寫到檔案
void RBCDebugLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], message];
    NSString *path = @"/var/mobile/Library/Logs/ControlDeck.log";
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!handle) {
        [line writeToFile:path atomically:NO encoding:NSUTF8StringEncoding error:nil];
        return;
    }
    [handle seekToEndOfFile];
    [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    [handle closeFile];
}
#endif

#pragma mark - 文字和圖示

NSString *RBCLocalized(NSString *key) {
    static NSBundle *bundle;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        bundle = [NSBundle bundleForClass:NSClassFromString(@"RBCModule")];
    });
    return [bundle localizedStringForKey:key value:key table:nil] ?: key;
}

// 代表動作的字串:tapAction 的值、show<Key> 的後綴、helper 的參數
static NSString *RBCActionKey(RBCAction action) {
    switch (action) {
        case RBCActionRespring: return @"respring";
        case RBCActionRebuildIconCache: return @"uicache";
        case RBCActionUserspaceReboot: return @"userspace";
        case RBCActionSafeMode: return @"safemode";
        case RBCActionReboot: return @"reboot";
        case RBCActionNone: break;
    }
    return nil;
}

NSString *RBCActionTitle(RBCAction action) {
    switch (action) {
        case RBCActionRespring: return RBCLocalized(@"Respring");
        case RBCActionRebuildIconCache: return RBCLocalized(@"Rebuild Icon Cache");
        case RBCActionUserspaceReboot: return RBCLocalized(@"Userspace Reboot");
        case RBCActionSafeMode: return RBCLocalized(@"Safe Mode");
        case RBCActionReboot: return RBCLocalized(@"Reboot");
        case RBCActionNone: break;
    }
    return @"";
}

UIImage *RBCActionGlyph(RBCAction action) {
    NSString *symbol = nil;
    switch (action) {
        case RBCActionRespring: symbol = @"arrow.clockwise"; break;
        case RBCActionRebuildIconCache: symbol = @"square.grid.2x2"; break;
        case RBCActionUserspaceReboot: symbol = @"arrow.triangle.2.circlepath"; break;
        case RBCActionSafeMode: symbol = @"checkmark.shield"; break;
        case RBCActionReboot: symbol = @"power"; break;
        case RBCActionNone: return nil;
    }
    return [UIImage systemImageNamed:symbol];
}

#pragma mark - 設定

// 每次都重新讀,設定頁改了不必 respring。鍵在 ControlDeck 的 domain,以 reboot 開頭。

RBCAction RBCTapAction(void) {
    id value = CDPreferenceValue(@"rebootTapAction");
    if ([value isKindOfClass:[NSString class]]) {
        for (RBCAction action = RBCActionFirst; action <= RBCActionLast; action++) {
            if ([value isEqualToString:RBCActionKey(action)]) return action;
        }
    }
    return RBCActionRespring;
}

BOOL RBCActionIsShownInMenu(RBCAction action) {
    NSString *key = RBCActionKey(action);
    if (!key) return NO;
    // rebootShow + 首字大寫,例如 rebootShowUserspace
    NSString *name = [[key substringToIndex:1].uppercaseString stringByAppendingString:[key substringFromIndex:1]];
    return CDPreferenceBool([@"rebootShow" stringByAppendingString:name], YES);
}

BOOL RBCActionNeedsConfirm(RBCAction action) {
    if (action == RBCActionReboot) return YES; // 重開後會失去越獄,一律要點兩次
    if (action != RBCActionUserspaceReboot && action != RBCActionSafeMode) return NO;
    return CDPreferenceBool(@"rebootConfirm", YES);
}

// SpringBoard 的鎖定狀態;查不到時當成鎖定,寧可多要求一次解鎖
static BOOL RBCDeviceIsLocked(void) {
    Class managerClass = objc_getClass("SBLockScreenManager");
    if (![managerClass respondsToSelector:@selector(sharedInstance)]) return YES;
    id manager = ((id (*)(id, SEL))objc_msgSend)(managerClass, @selector(sharedInstance));
    if (![manager respondsToSelector:@selector(isUILocked)]) {
        RBCLog(@"SBLockScreenManager %@ has no isUILocked", manager);
        return YES;
    }
    BOOL locked = ((BOOL (*)(id, SEL))objc_msgSend)(manager, @selector(isUILocked));
    RBCLog(@"isUILocked = %d", locked);
    return locked;
}

BOOL RBCUnlockRequired(void) {
    return CDPreferenceBool(@"rebootRequireUnlock", YES) && RBCDeviceIsLocked();
}

#pragma mark - 執行

// 子程序另開 session,SpringBoard 被重啟時不會連帶收到訊號;在背景回收避免殭屍程序。
static BOOL RBCSpawn(const char *path, const char *argument) {
    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETSID);
    char *argv[] = { (char *)path, (char *)argument, NULL };
    pid_t pid = 0;
    int result = posix_spawn(&pid, path, NULL, &attr, argv, environ);
    posix_spawnattr_destroy(&attr);
    if (result != 0) {
        RBCLog(@"posix_spawn %s failed: %d", path, result);
        return NO;
    }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        int status = 0;
        waitpid(pid, &status, 0);
        RBCLog(@"%s %s exited with status %d", path, argument ?: "", status);
    });
    return YES;
}

// 和設定頁「套用」相同的 respring(BootLogStop 的 blsRespring)
static void RBCRelaunchSpringBoard(void) {
    dlopen("/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices", RTLD_NOW);
    dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_NOW);
    Class actionClass = objc_getClass("SBSRelaunchAction");
    Class serviceClass = objc_getClass("FBSSystemService");
    if (!actionClass || !serviceClass) return;
    // SBSRelaunchActionOptionsRestartRenderServer = 1 << 0
    id action = ((id (*)(id, SEL, id, NSUInteger, id))objc_msgSend)(actionClass, @selector(actionWithReason:options:targetURL:), @"RebootCC", 1, nil);
    id service = ((id (*)(id, SEL))objc_msgSend)(serviceClass, @selector(sharedService));
    ((void (*)(id, SEL, id, id))objc_msgSend)(service, @selector(sendActions:withResult:), [NSSet setWithObject:action], nil);
}

void RBCPerform(RBCAction action) {
    switch (action) {
        case RBCActionRespring:
            if (!RBCSpawn(kRBCSbreloadPath, NULL)) RBCRelaunchSpringBoard();
            break;
        case RBCActionRebuildIconCache:
        case RBCActionUserspaceReboot:
        case RBCActionSafeMode:
        case RBCActionReboot:
            RBCSpawn(kRBCHelperPath, RBCActionKey(action).UTF8String);
            break;
        case RBCActionNone:
            break;
    }
}
