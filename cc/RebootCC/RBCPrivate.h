//
//  RBCPrivate.h
//  ControlCenterUIKit 的私有介面。Theos 的 vendor/include 只有 CCUIContentModule 這兩個協定,
//  選單模組的 view controller 自己宣告(方法名稱對照 iOS 16/17 的 class-dump)。
//

#import <UIKit/UIKit.h>
#import <ControlCenterUIKit/CCUIContentModule-Protocol.h>
#import <ControlCenterUIKit/CCUIContentModuleContentViewController-Protocol.h>

@interface CCUIButtonModuleViewController : UIViewController <CCUIContentModuleContentViewController>
@property (nonatomic, strong) UIImage *glyphImage;
@property (nonatomic, strong) UIColor *glyphColor;
@property (nonatomic, getter=isSelected) BOOL selected;
@property (nonatomic, readonly, getter=isExpanded) BOOL expanded;
- (void)buttonTapped:(id)button forEvent:(UIEvent *)event;
- (void)willTransitionToExpandedContentMode:(BOOL)willTransition;
@end

// handler 回傳 YES 時選單收起,NO 時維持展開
typedef BOOL (^CCUIMenuModuleActionHandler)(void);

// 模組和控制中心之間的橋梁;鎖定時用它要求 Face ID / 密碼
@interface CCUIContentModuleContext : NSObject
- (void)requestAuthenticationWithCompletionHandler:(void (^)(BOOL authenticated))completion;
@end

@interface CCUIMenuModuleViewController : CCUIButtonModuleViewController
@property (nonatomic, weak) CCUIContentModuleContext *contentModuleContext;
- (void)addActionWithTitle:(NSString *)title subtitle:(NSString *)subtitle glyph:(UIImage *)glyph handler:(CCUIMenuModuleActionHandler)handler;
- (void)removeAllActions;
- (BOOL)shouldBeginTransitionToExpandedContentModule;
@end
