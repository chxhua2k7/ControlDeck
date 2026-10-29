//
//  MHLModule.m
//  Metal HUD's Control Center module (pookjw's MetalHudLoader toggle), one of
//  ControlDeck's provided modules: tap to turn the HUD on or off for apps
//  launched afterwards, long-press to pick the metrics it shows.
//

#import <UIKit/UIKit.h>
#import <notify.h>
#import "../../metalhud/MHLShared.h"
#import "../CDProvider.h"

@interface CCUIMenuModuleItem : NSObject
@property (nonatomic, getter=isSelected) BOOL selected;
- (instancetype)initWithTitle:(NSString *)title identifier:(NSString *)identifier handler:(BOOL (^)(void))handler;
@end

@interface CCUIMenuModuleViewController : UIViewController
@property (copy, nonatomic) NSString *title;
@property (nonatomic) BOOL useTrailingCheckmarkLayout;
@property (nonatomic, getter=isSelected) BOOL selected;
@property (retain, nonatomic) UIImage *glyphImage;
@property (retain, nonatomic) UIImage *selectedGlyphImage;
@property (retain, nonatomic) UIColor *selectedGlyphColor;
@property (nonatomic, weak) id contentModuleContext;
- (void)setMenuItems:(NSArray *)menuItems;
@end

@interface CCUIToggleModule : NSObject
@property (nonatomic, getter=isSelected) BOOL selected;
- (UIImage *)iconGlyph;
- (UIColor *)selectedColor;
- (id)contentViewControllerForContext:(id)context;
@end

@interface MHLModule : CCUIToggleModule
- (uint64_t)elementsMask;
- (void)updateElementsMask:(uint64_t)mask;
@end

@interface MHLMenuViewController : CCUIMenuModuleViewController
@property (nonatomic, weak) MHLModule *module;
@end

@implementation MHLMenuViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Metal HUD";
    self.glyphImage = self.module.iconGlyph;
    self.selectedGlyphImage = self.module.iconGlyph;
    self.selectedGlyphColor = self.module.selectedColor;
    self.selected = self.module.isSelected;
    // Private bits that gate the long-press menu; if they change in some
    // iOS version, degrade to a plain toggle instead of crashing.
    @try {
        self.useTrailingCheckmarkLayout = YES;
        [self setValue:@YES forKey:@"allowsMenuInteraction"];
    } @catch (NSException *exception) {}
    [self reloadMenuItems];
}

- (void)reloadMenuItems {
    uint64_t mask = self.module.elementsMask;
    NSMutableArray *items = [NSMutableArray new];
    __weak MHLMenuViewController *weakSelf = self;

    @try {
        CCUIMenuModuleItem *defaultItem = [[CCUIMenuModuleItem alloc] initWithTitle:CDLocalized(@"Default (all)")
                                                                         identifier:@"default"
                                                                            handler:^BOOL {
            [weakSelf.module updateElementsMask:0];
            [weakSelf reloadMenuItems];
            return NO;
        }];
        defaultItem.selected = mask == 0;
        [items addObject:defaultItem];

        for (uint64_t i = 0; i < MHLElementCount; i++) {
            uint64_t bit = 1ULL << i;
            CCUIMenuModuleItem *item = [[CCUIMenuModuleItem alloc] initWithTitle:@(MHLElementNames[i])
                                                                      identifier:@(MHLElementNames[i])
                                                                         handler:^BOOL {
                [weakSelf.module updateElementsMask:weakSelf.module.elementsMask ^ bit];
                [weakSelf reloadMenuItems];
                return NO;
            }];
            item.selected = (mask & bit) != 0;
            [items addObject:item];
        }

        [self setMenuItems:items];
    } @catch (NSException *exception) {}
}

- (void)buttonTapped:(id)button forEvent:(id)event {
    BOOL selected = !self.module.isSelected;
    self.module.selected = selected;
    self.selected = selected;
    if (selected) {
        [self spinGlyph];
    }
}

static void collectImageViews(UIView *view, NSMutableArray<UIImageView *> *out) {
    if ([view isKindOfClass:UIImageView.class]) {
        [out addObject:(UIImageView *)view];
    }
    for (UIView *subview in view.subviews) {
        collectImageViews(subview, out);
    }
}

- (void)spinGlyph {
    if (!self.viewIfLoaded) {
        return;
    }

    NSMutableArray<UIImageView *> *glyphViews = [NSMutableArray new];
    collectImageViews(self.viewIfLoaded, glyphViews);

    CABasicAnimation *spin = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    spin.fromValue = @0;
    spin.toValue = @(2 * M_PI);
    spin.duration = 0.6;
    spin.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];

    for (UIImageView *glyphView in glyphViews) {
        [glyphView.layer addAnimation:spin forKey:@"mhl.spin"];
    }
}

@end

@implementation MHLModule

// The token is intentionally never cancelled: notifyd drops a name's state
// once its last registration goes away.
static int stateToken(void) {
    static int token = NOTIFY_TOKEN_INVALID;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        if (notify_register_check(kMHLEnabledStateName, &token) != NOTIFY_STATUS_OK) {
            token = NOTIFY_TOKEN_INVALID;
        }
    });
    return token;
}

static NSMutableDictionary *readPrefs(void) {
    return [[NSDictionary dictionaryWithContentsOfFile:@kMHLPrefsPath] mutableCopy] ?: [NSMutableDictionary new];
}

- (UIImage *)iconGlyph {
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:24
                                                                                          weight:UIImageSymbolWeightRegular
                                                                                           scale:UIImageSymbolScaleLarge];
    return [UIImage systemImageNamed:@"gauge" withConfiguration:config];
}

- (UIColor *)selectedColor {
    return UIColor.systemGreenColor;
}

- (BOOL)isSelected {
    uint64_t state = MHLStateUnset;
    int token = stateToken();
    if (token != NOTIFY_TOKEN_INVALID) {
        notify_get_state(token, &state);
    }
    return (state & MHLEnabledFieldMask) == MHLStateEnabled;
}

- (void)setSelected:(BOOL)selected {
    NSMutableDictionary *prefs = readPrefs();
    prefs[@kMHLEnabledKey] = @(selected);
    [prefs writeToFile:@kMHLPrefsPath atomically:YES];

    int token = stateToken();
    if (token != NOTIFY_TOKEN_INVALID) {
        notify_set_state(token, MHLStateMake(selected, MHLElementsMaskFromPrefs(prefs)));
    }

    [super setSelected:selected];
}

- (uint64_t)elementsMask {
    return MHLElementsMaskFromPrefs(readPrefs());
}

- (void)updateElementsMask:(uint64_t)mask {
    NSMutableDictionary *prefs = readPrefs();
    if (mask != 0) {
        NSMutableArray<NSString *> *names = [NSMutableArray new];
        for (uint64_t i = 0; i < MHLElementCount; i++) {
            if (mask & (1ULL << i)) {
                [names addObject:@(MHLElementNames[i])];
            }
        }
        prefs[@kMHLElementsKey] = [names componentsJoinedByString:@","];
    } else {
        [prefs removeObjectForKey:@kMHLElementsKey];
    }
    [prefs writeToFile:@kMHLPrefsPath atomically:YES];

    int token = stateToken();
    if (token != NOTIFY_TOKEN_INVALID) {
        notify_set_state(token, MHLStateMake(self.isSelected, mask));
    }
}

- (id)contentViewControllerForContext:(id)context {
    MHLMenuViewController *viewController = [MHLMenuViewController new];
    viewController.module = self;
    @try {
        viewController.contentModuleContext = context;
    } @catch (NSException *exception) {}
    return viewController;
}

@end
