# 版本號只寫在這裡:以 CD_VERSION 傳給設定 bundle(「關於」的版本列),
# 兩個 Info.plist 的 __VERSION__ 在 stage 時填入。control 的 Version 由 Theos 用這個值覆蓋。
export PACKAGE_VERSION := 1.0.1

TARGET := iphone:clang:16.5:15.0

THEOS_PACKAGE_SCHEME = rootless

# arm64e slice 由 Xcode toolchain 產生(同 NowLyrics 的說明),SpringBoard 是 arm64e 程序。
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

# ---- 新增模組 ----
# 控制中心模組:class 放 cc/<模組>/,在 cc/CDProvider.m 的 kCDModules 登記一行,檔案加到 ControlDeckCC_FILES。
# SpringBoard 裡的 hook:檔案放 springboard/,加到 ControlDeck_FILES,從 springboard/CDSpringBoard.m 呼叫它的初始化。
# 設定:prefs/<模組>.plist 一頁,在 prefs/ControlDeck.plist 的「模組」群組加一列;偏好鍵以模組名開頭(rebootTapAction)。

# SpringBoard:ConnectStrip(系統連線模組的版面)和舊套件設定的搬移。
TWEAK_NAME += ControlDeck

ControlDeck_FILES += springboard/CDSpringBoard.m springboard/ConnectStrip.x
ControlDeck_CFLAGS += -fobjc-arc -Wall
ControlDeck_FRAMEWORKS += UIKit QuartzCore

# Metal HUD 的載入器(pookjw 的 MetalHudLoader):注入每個用 Metal 的程序,開關打開時載入 libMTLHud。
TWEAK_NAME += ControlDeckMetalHUD

ControlDeckMetalHUD_FILES += metalhud/MHLLoader.m
ControlDeckMetalHUD_CFLAGS += -fobjc-arc -Wall
ControlDeckMetalHUD_FRAMEWORKS += Foundation

include $(THEOS_MAKE_PATH)/tweak.mk

# 控制中心模組:一個 CCSupport 的 module provider(/Library/ControlCenter/CCSupport_Providers,載入到
# SpringBoard,也載入到「設定」列出控制項),提供設定頁打開的每個模組。
BUNDLE_NAME += ControlDeckCC

ControlDeckCC_FILES += cc/CDProvider.m cc/RebootCC/RBCModule.m cc/RebootCC/RBCActions.m cc/MetalHUD/MHLModule.m
ControlDeckCC_CFLAGS += -fobjc-arc -Wall
ControlDeckCC_FRAMEWORKS += UIKit QuartzCore
ControlDeckCC_PRIVATE_FRAMEWORKS += ControlCenterUIKit
ControlDeckCC_INSTALL_PATH = /Library/ControlCenter/CCSupport_Providers
ControlDeckCC_RESOURCE_DIRS = cc/Resources

# 設定頁:prefs/ 裡是 ControlDeck.plist(entry + 首頁)、每個模組一頁的 plist 和各語言的 Localizable.strings;
# ControlDeckPrefs.bundle 的主類別 CDRootListController 繼承 libprefs 的 PLLocalizedListController,
# 首頁和模組頁都由它顯示,加上 SF Symbol 圖示和右上角「套用」(respring)按鈕。
BUNDLE_NAME += ControlDeckPrefs

ControlDeckPrefs_FILES += prefsbundle/CDRootListController.m
ControlDeckPrefs_CFLAGS += -fobjc-arc -Wall -DCD_VERSION=\"$(PACKAGE_VERSION)\"
ControlDeckPrefs_FRAMEWORKS += UIKit
ControlDeckPrefs_PRIVATE_FRAMEWORKS += Preferences
ControlDeckPrefs_INSTALL_PATH = /Library/PreferenceBundles
ControlDeckPrefs_RESOURCE_DIRS = bundle

include $(THEOS_MAKE_PATH)/bundle.mk

# SpringBoard 是 mobile,做不了 userspace reboot、也寫不進 root 擁有的 basebin,所以 RebootCC 交給這個
# setuid root 的小程式(Dopamine 會替 jbroot 裡的 setuid 二進位修正 uid,jbctl 也是這樣拿 root)。
# 擁有者和 setuid 位元由 layout/DEBIAN/postinst 設定。
TOOL_NAME += ControlDeckHelper

ControlDeckHelper_FILES += helper/main.c
ControlDeckHelper_CFLAGS += -Wall
ControlDeckHelper_CODESIGN_FLAGS = -Shelper/entitlements.plist
ControlDeckHelper_INSTALL_PATH = /usr/libexec

include $(THEOS_MAKE_PATH)/tool.mk

# PreferenceLoader 會遞迴掃描 Preferences/ 底下所有 .plist,沒有 entry 的(模組頁)會略過;
# plist 所在的資料夾就是來源 bundle,PLLocalizedListController 從那裡讀各語言的 Localizable.strings。
internal-stage::
	$(ECHO_NOTHING)mkdir -p "$(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/ControlDeck"$(ECHO_END)
	$(ECHO_NOTHING)cp -R prefs/ "$(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/ControlDeck/"$(ECHO_END)
	$(ECHO_NOTHING)sed "s/__VERSION__/$(PACKAGE_VERSION)/g" bundle/Info.plist > "$(THEOS_STAGING_DIR)/Library/PreferenceBundles/ControlDeckPrefs.bundle/Info.plist"$(ECHO_END)
	$(ECHO_NOTHING)sed "s/__VERSION__/$(PACKAGE_VERSION)/g" cc/Resources/Info.plist > "$(THEOS_STAGING_DIR)/Library/ControlCenter/CCSupport_Providers/ControlDeckCC.bundle/Info.plist"$(ECHO_END)
	$(ECHO_NOTHING)chmod 4755 "$(THEOS_STAGING_DIR)/usr/libexec/ControlDeckHelper"$(ECHO_END)
