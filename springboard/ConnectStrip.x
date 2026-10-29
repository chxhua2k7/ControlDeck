#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import "../shared/CDShared.h"

// ConnectStrip：控制中心「連線」模組
// 直向：1 列 x 4 欄（寬 4、高 1），按鈕超出時可左右無限循環滑動
// 橫向：3 列 x 2 欄（寬 2、高 3），跟系統「家庭」模組橫向同大小

typedef struct {
	NSUInteger width;
	NSUInteger height;
} CCUILayoutSize;

static NSString *const kCSConnectivityModuleID = @"com.apple.control-center.ConnectivityModule";
static NSString *const kCSReloadNotification = @"com.c3x14n.controldeck/connectstrip";
static const CCUILayoutSize kCSPortraitSize = {4, 1};
static const CCUILayoutSize kCSLandscapeSize = {2, 3};

@interface CCUIModuleSettings : NSObject
- (instancetype)initWithPortraitLayoutSize:(CCUILayoutSize)portrait landscapeLayoutSize:(CCUILayoutSize)landscape;
- (CCUILayoutSize)layoutSizeForInterfaceOrientation:(UIInterfaceOrientation)orientation;
@end

@interface CCUILabeledRoundButtonViewController : UIViewController
@property (nonatomic, assign) BOOL labelsVisible;
@property (nonatomic, strong) UIControl *button;
@end

@interface CCUIConnectivityModuleViewController : UIViewController
@property (nonatomic, strong) UIViewController *airplaneButton;
@property (nonatomic, strong) UIViewController *cellularDataButton;
@property (nonatomic, strong) UIViewController *wifiButton;
@property (nonatomic, strong) UIViewController *bluetoothButton;
@property (nonatomic, strong) UIViewController *airDropButton;
@property (nonatomic, strong) UIViewController *hotspotButton;
@property (nonatomic, readonly, getter=isExpanded) BOOL expanded;
- (BOOL)_isPortrait;
@end

// ---- 設定 ----
// 模組大小控制中心只讀一次，所以直向、橫向的開關只在啟動時讀（改了要按「套用」）；循環滑動可以即時切換

static BOOL gCSPortrait = YES;
static BOOL gCSLandscape = YES;
static BOOL gCSLoop = YES;

static void CSReloadPrefs(void) {
	gCSLoop = CDPreferenceBool(@"connectLoop", YES);
}

static void CSPrefsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
	CSReloadPrefs();
}

%hook CCUIModuleSettingsManager

- (CCUIModuleSettings *)moduleSettingsForModuleIdentifier:(NSString *)identifier prototypeSize:(CCUILayoutSize)prototypeSize {
	if (![identifier isEqualToString:kCSConnectivityModuleID]) return %orig;
	CCUIModuleSettings *settings = %orig;
	BOOL canReadOriginal = !settings || [settings respondsToSelector:@selector(layoutSizeForInterfaceOrientation:)];
	if (!canReadOriginal && !(gCSPortrait && gCSLandscape)) return settings;

	// 關掉的方向沿用系統原本的大小
	CCUILayoutSize portrait = gCSPortrait ? kCSPortraitSize : (settings ? [settings layoutSizeForInterfaceOrientation:UIInterfaceOrientationPortrait] : prototypeSize);
	CCUILayoutSize landscape = gCSLandscape ? kCSLandscapeSize : (settings ? [settings layoutSizeForInterfaceOrientation:UIInterfaceOrientationLandscapeRight] : prototypeSize);
	return [[%c(CCUIModuleSettings) alloc] initWithPortraitLayoutSize:portrait landscapeLayoutSize:landscape];
}

%end

%group Connectivity

static UIScrollView *CSScrollView(CCUIConnectivityModuleViewController *self) {
	Ivar ivar = class_getInstanceVariable(object_getClass(self), "_buttonContainerScrollView");
	return ivar ? object_getIvar(self, ivar) : nil;
}

static NSArray<UIViewController *> *CSButtons(CCUIConnectivityModuleViewController *self) {
	UIViewController *candidates[] = {
		self.airplaneButton,
		self.cellularDataButton,
		self.wifiButton,
		self.bluetoothButton,
		self.airDropButton,
		self.hotspotButton,
	};
	NSMutableArray *buttons = [NSMutableArray array];
	for (size_t i = 0; i < sizeof(candidates) / sizeof(candidates[0]); i++) {
		if (candidates[i]) [buttons addObject:candidates[i]];
	}
	return buttons;
}

// ---- 無限循環捲動 ----
// 按鈕只有一組，所以把 contentSize 拉成很多個週期，捲動時把每顆按鈕擺到目前看得到的那一圈，
// 離中間太遠就把 contentOffset 平移整數個週期拉回來（畫面上看不出差別）

static const CGFloat kCSLoopPeriods = 200;         // contentSize 總共幾個週期
static const CGFloat kCSLoopRecenterPeriods = 50;  // 偏離中間超過幾個週期就拉回

static CGFloat CSLoopMiddleOffset(CGFloat period) {
	return period * floor(kCSLoopPeriods / 2);
}

// 系統的捲動區是純 UIScrollView，換成這個子類別就能在 layoutSubviews（捲動時會呼叫）重新擺放按鈕，
// 並讓它當自己的 delegate 來處理停下時的對齊
@interface CSLoopScrollView : UIScrollView <UIScrollViewDelegate>
@property (nonatomic, copy) NSArray<UIView *> *cs_loopViews;
@property (nonatomic, copy) NSArray<NSNumber *> *cs_centerFixes;
@property (nonatomic, assign) CGFloat cs_columnWidth;
@property (nonatomic, assign) NSUInteger cs_columns;
- (void)cs_reposition;
@end

// object_setClass 換上去的物件不會跑 init，屬性改存在 associated object
static char kCSLoopViewsKey;
static char kCSCenterFixesKey;
static char kCSColumnWidthKey;
static char kCSColumnsKey;

@implementation CSLoopScrollView

- (NSArray<UIView *> *)cs_loopViews { return objc_getAssociatedObject(self, &kCSLoopViewsKey); }
- (void)setCs_loopViews:(NSArray<UIView *> *)views { objc_setAssociatedObject(self, &kCSLoopViewsKey, views, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (NSArray<NSNumber *> *)cs_centerFixes { return objc_getAssociatedObject(self, &kCSCenterFixesKey); }
- (void)setCs_centerFixes:(NSArray<NSNumber *> *)fixes { objc_setAssociatedObject(self, &kCSCenterFixesKey, fixes, OBJC_ASSOCIATION_COPY_NONATOMIC); }
- (CGFloat)cs_columnWidth { return [objc_getAssociatedObject(self, &kCSColumnWidthKey) doubleValue]; }
- (void)setCs_columnWidth:(CGFloat)width { objc_setAssociatedObject(self, &kCSColumnWidthKey, @(width), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (NSUInteger)cs_columns { return [objc_getAssociatedObject(self, &kCSColumnsKey) unsignedIntegerValue]; }
- (void)setCs_columns:(NSUInteger)columns { objc_setAssociatedObject(self, &kCSColumnsKey, @(columns), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }

- (void)layoutSubviews {
	[super layoutSubviews];
	[self cs_reposition];
}

- (void)cs_reposition {
	NSArray<UIView *> *views = self.cs_loopViews;
	if (views.count == 0) return;
	CGFloat columnWidth = self.cs_columnWidth;
	NSUInteger columns = self.cs_columns;
	NSArray<NSNumber *> *centerFixes = self.cs_centerFixes;
	CGFloat period = columnWidth * columns;
	if (period <= 0) return;

	CGPoint offset = self.contentOffset;
	CGFloat middle = CSLoopMiddleOffset(period);
	BOOL fix = offset.y != 0;  // 只能左右滑，不允許垂直位移
	offset.y = 0;
	if (fabs(offset.x - middle) > period * kCSLoopRecenterPeriods) {
		offset.x -= round((offset.x - middle) / period) * period;
		fix = YES;
	}
	// 換圈和拉回中間都是畫面上看不出來的瞬移：控制中心收合的動畫裡也會跑到這裡，
	// 不能讓它變成橫跨好幾圈的動畫
	[UIView performWithoutAnimation:^{
		if (fix) self.contentOffset = offset;

		// 每顆按鈕的中心放在 [offset - 半欄, offset - 半欄 + 一個週期) 之間
		CGFloat left = offset.x - columnWidth * 0.5;
		for (NSUInteger index = 0; index < views.count; index++) {
			UIView *view = views[index];
			CGFloat base = columnWidth * (index % columns + 0.5);
			CGFloat lap = ceil((left - base) / period);
			CGFloat centerFix = index < centerFixes.count ? centerFixes[index].doubleValue : 0;
			view.center = CGPointMake(base + lap * period + centerFix, view.center.y);
		}
	}];
}

// 放手時把停止位置調整到欄寬的整數倍，讓最左邊剛好是一顆完整的按鈕
- (void)scrollViewWillEndDragging:(UIScrollView *)scrollView withVelocity:(CGPoint)velocity targetContentOffset:(inout CGPoint *)targetContentOffset {
	if (!self.cs_loopViews) return;
	CGFloat columnWidth = self.cs_columnWidth;
	if (columnWidth <= 0) return;
	targetContentOffset->x = round(targetContentOffset->x / columnWidth) * columnWidth;
}

@end

static BOOL CSLoopInstall(UIScrollView *scrollView) {
	Class cls = object_getClass(scrollView);
	if (cls == [CSLoopScrollView class]) return YES;
	// 只接手純 UIScrollView，換掉其他子類別會弄丟它們自己的行為
	if (cls != [UIScrollView class]) {
		NSLog(@"[ControlDeck] ConnectStrip: scroll view is %@, infinite scrolling disabled", NSStringFromClass(cls));
		return NO;
	}
	object_setClass(scrollView, [CSLoopScrollView class]);
	// 原本沒有 delegate 才接手，避免蓋掉系統的
	if (!scrollView.delegate) scrollView.delegate = (CSLoopScrollView *)scrollView;
	return YES;
}

// 捲動位置歸零，按鈕跟著平移，畫面上不動：展開的動畫才會從看得到的位置開始，
// 不會從循環座標（離原點好幾萬點）飛回來
static void CSScrollToOrigin(UIScrollView *scrollView, NSArray<UIView *> *views) {
	[scrollView setContentOffset:scrollView.contentOffset animated:NO];  // 停掉還在減速的捲動
	CGFloat shift = scrollView.contentOffset.x;
	if (shift == 0 && scrollView.contentOffset.y == 0) return;
	[UIView performWithoutAnimation:^{
		for (UIView *view in views) {
			if (view.superview == scrollView) view.center = CGPointMake(view.center.x - shift, view.center.y);
		}
		scrollView.contentOffset = CGPointZero;
	}];
}

static void CSLoopStop(UIScrollView *scrollView) {
	if (![scrollView isKindOfClass:[CSLoopScrollView class]]) return;
	CSLoopScrollView *loopView = (CSLoopScrollView *)scrollView;
	NSArray<UIView *> *views = loopView.cs_loopViews;
	if (!views) return;
	loopView.cs_loopViews = nil;
	CSScrollToOrigin(loopView, views);
}

// 循環模式下第 column 欄的按鈕在目前這一圈的中心 x（和 cs_reposition 同一個算法）
static CGFloat CSLoopCenterX(NSUInteger column, CGFloat offsetX, CGFloat columnWidth, CGFloat period) {
	CGFloat base = columnWidth * (column + 0.5);
	CGFloat left = offsetX - columnWidth * 0.5;
	return base + ceil((left - base) / period) * period;
}

// 往上找模組背景的圓角，讓捲動區用一樣的圓角裁切，按鈕滑到邊緣才不會露出背景外
static CGFloat CSBackgroundCornerRadius(UIView *view) {
	for (UIView *ancestor = view; ancestor; ancestor = ancestor.superview) {
		if (ancestor.layer.cornerRadius > 0) return ancestor.layer.cornerRadius;
		if ([ancestor isKindOfClass:[UIWindow class]]) break;
	}
	return MIN(view.bounds.size.width, view.bounds.size.height) * 0.28;
}

static void CSLayoutCompact(CCUIConnectivityModuleViewController *self, BOOL portrait) {
	UIScrollView *scrollView = CSScrollView(self);
	UIView *container = scrollView ?: self.view;
	CGRect bounds = self.view.bounds;
	if (CGRectIsEmpty(bounds)) return;

	NSArray<UIViewController *> *buttons = CSButtons(self);
	if (buttons.count == 0) return;

	CCUILayoutSize size = portrait ? kCSPortraitSize : kCSLandscapeSize;
	NSUInteger rows = MAX(size.height, 1);
	NSUInteger columns = (buttons.count + rows - 1) / rows;
	NSUInteger visibleColumns = MAX(size.width, 1);

	// 放得下就平均分布在整個寬度，放不下就用固定欄寬並開啟左右滑動
	CGFloat columnWidth = bounds.size.width / (columns <= visibleColumns ? columns : visibleColumns);
	// 實際用到的列數平均分配高度，不留空白列
	NSUInteger usedRows = (buttons.count + columns - 1) / columns;
	CGFloat rowHeight = bounds.size.height / usedRows;
	CGFloat side = floor(MIN(columnWidth, rowHeight) * 0.86);

	// 放不下時改成無限循環捲動
	BOOL loop = gCSLoop && scrollView && columns > visibleColumns && CSLoopInstall(scrollView);
	CGFloat period = columnWidth * columns;
	// 第一次進入循環模式（或欄寬改變）時從中間開始，第一顆按鈕靠左。換到循環座標是瞬移，
	// 在控制中心收合的動畫裡做會變成橫跨好幾萬點的動畫，所以先照一般捲動排，動畫結束再換
	BOOL restart = loop && (!((CSLoopScrollView *)scrollView).cs_loopViews || ((CSLoopScrollView *)scrollView).cs_columnWidth != columnWidth);
	NSTimeInterval animation = [UIView inheritedAnimationDuration];
	if (restart && animation > 0) {
		loop = restart = NO;
		__weak UIView *weakView = self.view;
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((animation + 0.05) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
			[weakView setNeedsLayout];
		});
	}

	if (scrollView) {
		UIView *superview = scrollView.superview;
		scrollView.frame = (superview && superview != self.view) ? [self.view convertRect:bounds toView:superview] : bounds;
		// 不要讓系統依安全區域自動加內距，不然按鈕會整排往下偏
		scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
		scrollView.contentInset = UIEdgeInsetsZero;
		scrollView.layer.cornerCurve = kCACornerCurveContinuous;
		scrollView.layer.cornerRadius = CSBackgroundCornerRadius(self.view);
		if (loop) {
			scrollView.contentSize = CGSizeMake(period * kCSLoopPeriods, bounds.size.height);
			if (restart) {
				// 收合後先照一般捲動排、這時又滑過的話，接著從同一欄開始，畫面不跳
				CGFloat keep = round(fmod(MAX(scrollView.contentOffset.x, 0), period) / columnWidth) * columnWidth;
				[UIView performWithoutAnimation:^{
					scrollView.contentOffset = CGPointMake(CSLoopMiddleOffset(period) + keep, 0);
				}];
			}
		} else {
			CSLoopStop(scrollView);
			scrollView.contentSize = CGSizeMake(columnWidth * columns, bounds.size.height);
			if (scrollView.contentOffset.y != 0) scrollView.contentOffset = CGPointMake(scrollView.contentOffset.x, 0);
		}
		scrollView.scrollEnabled = columns > visibleColumns;
		scrollView.alwaysBounceHorizontal = NO;
		scrollView.alwaysBounceVertical = NO;
		scrollView.showsHorizontalScrollIndicator = NO;
		scrollView.showsVerticalScrollIndicator = NO;
		scrollView.clipsToBounds = YES;
		scrollView.decelerationRate = UIScrollViewDecelerationRateFast;
	}

	NSMutableArray<NSNumber *> *centerFixes = [NSMutableArray array];
	for (NSUInteger index = 0; index < buttons.count; index++) {
		UIView *view = buttons[index].view;
		if (view.superview != container) [container addSubview:view];
		view.hidden = NO;
		view.alpha = 1.0;

		NSUInteger row = index / columns;
		NSUInteger column = index % columns;
		// 循環時放在目前看得到的那一圈。中心只設一次：在動畫裡先設到第 0 圈再瞬移回來，會留下橫跨好幾圈的動畫
		CGFloat x = loop ? CSLoopCenterX(column, scrollView.contentOffset.x, columnWidth, period) : columnWidth * (column + 0.5);
		CGPoint center = CGPointMake(x, rowHeight * (row + 0.5));
		view.bounds = CGRectMake(0, 0, side, side);

		// 按鈕 view 裡圓形本體是靠上排的（下面預留給標籤），量出圓形實際位置再把它移回格子正中間
		CCUILabeledRoundButtonViewController *button = (CCUILabeledRoundButtonViewController *)buttons[index];
		if ([button respondsToSelector:@selector(setLabelsVisible:)] && button.labelsVisible) button.labelsVisible = NO;
		UIView *round = [button respondsToSelector:@selector(button)] ? button.button : nil;
		CGFloat fixX = 0;
		if (round && round != view && [round isDescendantOfView:view]) {
			[view layoutIfNeeded];
			CGRect roundFrame = [round convertRect:round.bounds toView:view];
			fixX = CGRectGetMidX(view.bounds) - CGRectGetMidX(roundFrame);
			center.x += fixX;
			center.y += CGRectGetMidY(view.bounds) - CGRectGetMidY(roundFrame);
		}
		if (restart) {
			[UIView performWithoutAnimation:^{ view.center = center; }];
		} else {
			view.center = center;
		}
		[centerFixes addObject:@(fixX)];
	}

	if (loop) {
		CSLoopScrollView *loopView = (CSLoopScrollView *)scrollView;
		NSMutableArray<UIView *> *views = [NSMutableArray array];
		for (UIViewController *button in buttons) [views addObject:button.view];

		loopView.cs_loopViews = views;
		loopView.cs_columnWidth = columnWidth;
		loopView.cs_columns = columns;
		loopView.cs_centerFixes = centerFixes;
		[loopView cs_reposition];
	}
}

%hook CCUIConnectivityModuleViewController

- (void)viewWillLayoutSubviews {
	%orig;
	if (self.expanded) return;
	BOOL portrait = [self _isPortrait];
	if (portrait ? gCSPortrait : gCSLandscape) {
		CSLayoutCompact(self, portrait);
	} else {
		CSLoopStop(CSScrollView(self));
	}
}

- (void)willTransitionToExpandedContentMode:(BOOL)expanded {
	if (expanded) {
		UIScrollView *scrollView = CSScrollView(self);
		CSLoopStop(scrollView);
		// 不循環但捲動過時也一樣，按鈕跟著回到原點
		NSMutableArray<UIView *> *views = [NSMutableArray array];
		for (UIViewController *button in CSButtons(self)) [views addObject:button.view];
		CSScrollToOrigin(scrollView, views);
		scrollView.contentSize = CGSizeZero;
	}
	%orig;
}

%end

%end

// SpringBoard 啟動時由 CDSpringBoard.m 呼叫
void CSInitialize(void) {
	// 設定頁關掉 ConnectStrip，或兩個方向都關掉，就跟沒裝一樣
	if (!CDPreferenceBool(kCDConnectStripEnabledKey, YES)) return;
	gCSPortrait = CDPreferenceBool(@"connectPortrait", YES);
	gCSLandscape = CDPreferenceBool(@"connectLandscape", YES);
	if (!gCSPortrait && !gCSLandscape) return;

	CSReloadPrefs();
	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, CSPrefsChanged, (__bridge CFStringRef)kCSReloadNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
	NSLog(@"[ControlDeck] ConnectStrip loaded: portrait=%d landscape=%d loop=%d", gCSPortrait, gCSLandscape, gCSLoop);

	%init;
	// ConnectivityModule.bundle 平常是控制中心第一次需要時才載入，這裡先自己載入好掛 hook
	dlopen("/System/Library/ControlCenter/Bundles/ConnectivityModule.bundle/ConnectivityModule", RTLD_NOW);
	if (objc_getClass("CCUIConnectivityModuleViewController")) {
		%init(Connectivity);
	}
}
