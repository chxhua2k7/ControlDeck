# ControlDeck

把控制中心的東西裝在同一個套件裡（`com.c3x14n.controldeck`），每個模組在設定頁各有開關。

- 需要 Dopamine（rootless）、[CCSupport](https://github.com/opa334/CCSupport)、PreferenceLoader。
- 取代 RebootCC、ConnectStrip（和更早的 ConnectivityStrip）、MetalHudLoader：安裝時 dpkg 會自動移除它們，舊的設定在第一次 respring 時搬過來。
- 安裝後到「設定 → 控制中心」加入 RebootCC、Metal HUD；設定頁在「設定 → ControlDeck」。

## 模組

| 模組 | 做什麼 |
| --- | --- |
| RebootCC | 控制中心模組：點一下重新啟動 SpringBoard（可改），長按選單有重建圖示快取、Userspace Reboot、安全模式、重新開機。Userspace Reboot 和安全模式預設要點兩次，重新開機一律要點兩次；鎖定時先要求解鎖。 |
| Metal HUD | 控制中心模組：點一下開關 Metal HUD（之後打開的 App 生效），長按選要顯示的項目。預設關閉。改自 Jinwoo Kim（pookjw）的 [MetalHudLoader](https://github.com/pookjw/MetalHudLoader)。 |
| ConnectStrip | 改系統的「連線」模組：直向 1×4，放不下的按鈕左右無限循環滑動；橫向 3×2。 |

設定頁關掉的模組不會出現在控制中心，也不會載入；開關後按右上角「套用」。

## 結構

```
cc/                 ControlDeckCC.bundle：CCSupport 的 module provider，所有控制中心模組在這裡
  CDProvider.m      模組表 kCDModules
  RebootCC/         RebootCC 模組
  MetalHUD/         Metal HUD 模組
  Resources/        模組圖示和翻譯
springboard/        ControlDeck.dylib（SpringBoard）：ConnectStrip 和舊設定的搬移
metalhud/           ControlDeckMetalHUD.dylib（所有用 Metal 的程序）：載入 libMTLHud
helper/             ControlDeckHelper（setuid root）：RebootCC 要 root 的動作
prefsbundle/        設定頁的 controller（首頁和每個模組頁）
prefs/              設定頁：ControlDeck.plist（首頁）、每個模組一頁、四種語言的字串
shared/CDShared.h   共用的偏好設定（com.c3x14n.controldeck）
```

### 新增模組

1. **控制中心模組**：class 放 `cc/<模組>/`，在 `cc/CDProvider.m` 的 `kCDModules` 登記一行（ID、class、總開關、名字、圖示），檔案加到 Makefile 的 `ControlDeckCC_FILES`，圖示放 `cc/Resources/<圖示>@2x.png`、`@3x.png`，名字加到 `cc/Resources/*.lproj/Localizable.strings`。
2. **SpringBoard 裡的 hook**：檔案放 `springboard/`，加到 `ControlDeck_FILES`，從 `springboard/CDSpringBoard.m` 呼叫它的初始化（先檢查自己的總開關）。
3. **設定**：`prefs/<模組>.plist` 一頁（第一列是模組的總開關 `<模組>Enabled`），在 `prefs/ControlDeck.plist` 的「模組」群組加一列連結，字串加到 `prefs/*.lproj/Localizable.strings`。偏好鍵以模組名開頭（`rebootTapAction`）。

## 建置

```sh
make package FINALPACKAGE=1 THEOS=$HOME/theos
```

版本號只寫在 Makefile 的 `PACKAGE_VERSION`。

## 授權

GPL-3.0（見 LICENSE）。Metal HUD 的部分來自 pookjw/MetalHudLoader。
