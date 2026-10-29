//
//  RBCActions.h
//  模組的動作,和它們在選單上的文字、圖示、設定。
//

#import <UIKit/UIKit.h>

// 順序就是選單順序(由輕到重)
typedef NS_ENUM(NSInteger, RBCAction) {
    RBCActionNone = 0,
    RBCActionRespring,
    RBCActionRebuildIconCache,
    RBCActionUserspaceReboot,
    RBCActionSafeMode,
    RBCActionReboot,
};

#define RBCActionFirst RBCActionRespring
#define RBCActionLast RBCActionReboot

// 除錯版(沒有 FINALPACKAGE)寫到 /var/mobile/Library/Logs/ControlDeck.log,正式版什麼都不做
#ifdef DEBUG
void RBCDebugLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
#define RBCLog(fmt, ...) RBCDebugLog(fmt, ##__VA_ARGS__)
#else
#define RBCLog(fmt, ...) do {} while (0)
#endif

// ControlDeckCC.bundle 裡的 Localizable.strings
NSString *RBCLocalized(NSString *key);

NSString *RBCActionTitle(RBCAction action);
UIImage *RBCActionGlyph(RBCAction action);

// 以下都從設定頁的偏好讀,每次呼叫都重新讀,改設定不必 respring。

// 點一下模組要做的事(rebootTapAction,預設 respring)
RBCAction RBCTapAction(void);
// 選單裡要不要顯示(rebootShow<動作>,預設都顯示)
BOOL RBCActionIsShownInMenu(RBCAction action);
// 要不要點兩次:重新開機一律要;Userspace Reboot 和安全模式看 rebootConfirm(預設 YES)
BOOL RBCActionNeedsConfirm(RBCAction action);
// 裝置鎖定中而且 rebootRequireUnlock(預設 YES)開著,要先解鎖才執行
BOOL RBCUnlockRequired(void);

void RBCPerform(RBCAction action);
