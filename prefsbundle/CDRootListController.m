//
//  CDRootListController.m
//  設定頁的 controller,首頁和每個模組頁都是它。libprefs 的 PLLocalizedListController 從
//  PreferenceLoader 的 prefs 資料夾載入項目並翻譯:首頁是 ControlDeck.plist,模組頁是首頁連結上
//  pl_alt_plist_name 指的 plist(RebootCC.plist 等)。這個子類加上:
//  - 列的 SF Symbol 圖示(和 NowLyrics / IslandSwipe / RebootCC 同一套)
//  - 首頁模組列右邊的「開啟 / 關閉」(get = cdModuleState:,讀列上 cdEnabledKey 指的開關)
//  - 右上角「套用」按鈕:確認後透過 FrontBoardServices 的 SBSRelaunchAction 重啟 SpringBoard
//

#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <libprefs/prefs.h>
#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>

#ifndef CD_VERSION
#error CD_VERSION comes from PACKAGE_VERSION in the Makefile
#endif

static CFStringRef const kCDPreferencesDomain = CFSTR("com.c3x14n.controldeck");

@interface CDRootListController : PLLocalizedListController
@end

#pragma mark - Icons(列上寫 iconSymbol / iconColor,執行期畫成 SF Symbol 圖示)

static const CGFloat kCDIconSize = 29;
static const CGFloat kCDIconCornerRadius = 6.5;
static const CGFloat kCDIconGlyphPointSize = 15;

static UIColor *CDColorFromHex(id value) {
    if (![value isKindOfClass:[NSString class]]) return nil;
    NSString *digits = [value hasPrefix:@"#"] ? [value substringFromIndex:1] : value;
    unsigned rgb = 0;
    if (digits.length != 6 || ![[NSScanner scannerWithString:digits] scanHexInt:&rgb]) return nil;
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0 green:((rgb >> 8) & 0xFF) / 255.0 blue:(rgb & 0xFF) / 255.0 alpha:1];
}

static UIImage *CDTileIcon(NSString *symbolName, UIColor *color) {
    UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:kCDIconGlyphPointSize weight:UIImageSymbolWeightMedium];
    UIImage *glyph = [[UIImage systemImageNamed:symbolName withConfiguration:configuration]
                      imageWithTintColor:UIColor.whiteColor renderingMode:UIImageRenderingModeAlwaysOriginal];
    CGRect tile = CGRectMake(0, 0, kCDIconSize, kCDIconSize);
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:tile.size];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [color setFill];
        [[UIBezierPath bezierPathWithRoundedRect:tile cornerRadius:kCDIconCornerRadius] fill];
        if (!glyph) return;
        CGSize size = glyph.size;
        [glyph drawInRect:CGRectMake((kCDIconSize - size.width) / 2, (kCDIconSize - size.height) / 2, size.width, size.height)];
    }];
}

static void CDApplyIcon(PSSpecifier *specifier) {
    if ([specifier propertyForKey:PSIconImageKey]) return;
    NSString *symbol = [specifier propertyForKey:@"iconSymbol"];
    UIColor *color = CDColorFromHex([specifier propertyForKey:@"iconColor"]);
    if (![symbol isKindOfClass:[NSString class]] || !color) return;
    [specifier setProperty:CDTileIcon(symbol, color) forKey:PSIconImageKey];
}

@implementation CDRootListController

// 項目和翻譯都在 PreferenceLoader 的資料夾,不在這個 bundle 裡。從
// <根目錄>/Library/PreferenceBundles/ControlDeckPrefs.bundle 往上推:模組頁是從首頁推進來的,
// 它的 specifier 不一定帶著 preferenceLoaderBundle。
- (NSBundle *)bundle {
    NSString *library = [[[NSBundle bundleForClass:[self class]].bundlePath stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
    return [NSBundle bundleWithPath:[library stringByAppendingPathComponent:@"PreferenceLoader/Preferences/ControlDeck"]];
}

- (NSString *)cdLocalized:(NSString *)key {
    return [[self bundle] localizedStringForKey:key value:key table:nil] ?: key;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:[self cdLocalized:@"Apply"]
                                                                              style:UIBarButtonItemStyleDone
                                                                             target:self
                                                                             action:@selector(cdApplyTapped)];
}

// 從模組頁回來時,首頁的「開啟 / 關閉」跟著更新
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    for (PSSpecifier *specifier in [_specifiers copy]) {
        if ([specifier propertyForKey:@"cdEnabledKey"]) [self reloadSpecifier:specifier];
    }
}

- (NSMutableArray *)specifiers {
    NSMutableArray *specifiers = [super specifiers];
    for (PSSpecifier *specifier in specifiers) {
        CDApplyIcon(specifier);
        // libprefs 的 PLCustomListController 會把沒有 bundle 路徑的 PSLinkCell 的 detail 類別
        // 一律改成宿主類別;有明寫 detail 的連結把類別改回去(同 IslandSwipe)。
        NSString *detail = [specifier propertyForKey:@"detail"];
        Class detailClass = [detail isKindOfClass:NSString.class] ? NSClassFromString(detail) : Nil;
        if (detailClass && specifier.detailControllerClass != detailClass) {
            [specifier setValue:detailClass forKey:@"detailControllerClass"];
        }
    }
    return specifiers;
}

#pragma mark 首頁

// 模組列(plist 的 get = cdModuleState:)右邊的狀態
- (NSString *)cdModuleState:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"cdEnabledKey"];
    CFPreferencesAppSynchronize(kCDPreferencesDomain);
    Boolean valid = false;
    Boolean enabled = CFPreferencesGetAppBooleanValue((__bridge CFStringRef)key, kCDPreferencesDomain, &valid);
    return [self cdLocalized:(!valid || enabled) ? @"On" : @"Off"];
}

#pragma mark 「關於」

// 版本列(plist 的 get = cdVersion:)。
- (NSString *)cdVersion:(PSSpecifier *)specifier {
    return @CD_VERSION;
}

#pragma mark 套用

- (void)cdApplyTapped {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[self cdLocalized:@"Apply"]
                                                                   message:[self cdLocalized:@"Restart SpringBoard to apply?"]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:[self cdLocalized:@"Cancel"] style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:[self cdLocalized:@"Respring"] style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [self cdRespring];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)cdRespring {
    dlopen("/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices", RTLD_NOW);
    dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_NOW);
    Class actionClass = objc_getClass("SBSRelaunchAction");
    Class serviceClass = objc_getClass("FBSSystemService");
    if (!actionClass || !serviceClass) return;
    // SBSRelaunchActionOptionsRestartRenderServer = 1 << 0
    id action = ((id (*)(id, SEL, id, NSUInteger, id))objc_msgSend)(actionClass, @selector(actionWithReason:options:targetURL:), @"ControlDeck", 1, nil);
    id service = ((id (*)(id, SEL))objc_msgSend)(serviceClass, @selector(sharedService));
    ((void (*)(id, SEL, id, id))objc_msgSend)(service, @selector(sendActions:withResult:), [NSSet setWithObject:action], nil);
}

@end
