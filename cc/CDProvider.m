//
//  CDProvider.m
//  ControlDeck 的控制中心模組:一個 CCSupport 的 module provider(Info.plist 的 NSPrincipalClass,
//  /Library/ControlCenter/CCSupport_Providers),載入到 SpringBoard,也載入到「設定」列出控制項。
//  只提供設定頁打開的模組;關掉的不在「設定 → 控制中心」的清單裡,也不會建立。
//  新模組:class 放 cc/<模組>/,在 kCDModules 加一行,Resources 放 <icon>@2x/@3x.png 和名稱的翻譯。
//

#import "CDProvider.h"
#import "../shared/CDShared.h"

NSString *CDLocalized(NSString *key) {
    static NSBundle *bundle;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        bundle = [NSBundle bundleForClass:NSClassFromString(@"CDProvider")];
    });
    return [bundle localizedStringForKey:key value:key table:nil] ?: key;
}

typedef struct {
    __unsafe_unretained NSString *identifier;
    __unsafe_unretained NSString *className;   // CCUIContentModule
    __unsafe_unretained NSString *enabledKey;  // 設定頁上的總開關(預設開)
    __unsafe_unretained NSString *name;        // 清單上的名字(Localizable.strings 的 key)
    __unsafe_unretained NSString *icon;        // 清單上的圖示(Resources 裡的 PNG)
} CDModule;

// 順序就是「設定 → 控制中心」清單裡的順序
static const CDModule kCDModules[] = {
    { @"com.c3x14n.controldeck.rebootcc", @"RBCModule", kCDRebootCCEnabledKey, @"RebootCC", @"RebootCC" },
    { @"com.c3x14n.controldeck.metalhud", @"MHLModule", kCDMetalHUDEnabledKey, @"Metal HUD", @"MetalHUD" },
};
static const NSUInteger kCDModuleCount = sizeof(kCDModules) / sizeof(kCDModules[0]);

static const CDModule *CDModuleWithIdentifier(NSString *identifier) {
    for (NSUInteger index = 0; index < kCDModuleCount; index++) {
        if ([kCDModules[index].identifier isEqualToString:identifier]) return &kCDModules[index];
    }
    return NULL;
}

@interface CDProvider : NSObject
@end

@implementation CDProvider {
    // 打開的模組在 kCDModules 的位置。建立時讀一次:CCSupport 先問數量再逐一問 ID,中途不能變;
    // 開關改了要 respring(設定頁的「套用」)
    NSArray<NSNumber *> *_enabled;
}

- (instancetype)init {
    if ((self = [super init])) {
        NSMutableArray<NSNumber *> *enabled = [NSMutableArray array];
        for (NSUInteger index = 0; index < kCDModuleCount; index++) {
            if (CDPreferenceBool(kCDModules[index].enabledKey, YES)) [enabled addObject:@(index)];
        }
        _enabled = enabled;
    }
    return self;
}

- (NSUInteger)numberOfProvidedModules {
    return _enabled.count;
}

- (NSString *)identifierForModuleAtIndex:(NSUInteger)index {
    return index < _enabled.count ? kCDModules[_enabled[index].unsignedIntegerValue].identifier : nil;
}

- (id)moduleInstanceForModuleIdentifier:(NSString *)identifier {
    const CDModule *module = CDModuleWithIdentifier(identifier);
    return module ? [NSClassFromString(module->className) new] : nil;
}

- (NSString *)displayNameForModuleIdentifier:(NSString *)identifier {
    const CDModule *module = CDModuleWithIdentifier(identifier);
    return module ? CDLocalized(module->name) : identifier;
}

- (UIImage *)settingsIconForModuleIdentifier:(NSString *)identifier {
    const CDModule *module = CDModuleWithIdentifier(identifier);
    if (!module) return nil;
    return [UIImage imageNamed:module->icon inBundle:[NSBundle bundleForClass:self.class] compatibleWithTraitCollection:nil];
}

@end
