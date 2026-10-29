//
//  ControlDeckHelper
//  控制中心模組(在 SpringBoard,身分是 mobile)要做 root 才能做的事時 spawn 這個程式。
//  目前是 RebootCC 的動作:
//    ControlDeckHelper uicache     重建圖示快取(uikittools 的 uicache -a)
//    ControlDeckHelper userspace   userspace reboot
//    ControlDeckHelper safemode    建立 basebin/.safe_mode 後 userspace reboot
//    ControlDeckHelper reboot      完整重新開機(重開後要重新越獄)
//  安全模式照 Dopamine 的做法:systemhook 看到 .safe_mode 就不注入任何 tweak,
//  到 Dopamine 的設定打開「Tweak Injection」會刪掉這個檔案並提示再 userspace reboot。
//  setuid root 由 layout/DEBIAN/postinst 設定;Dopamine 在程序 checkin 時替 jbroot 裡的
//  setuid 二進位修正 svuid,所以 setuid(0) 會成功(jbctl 也是這樣拿 root)。
//

#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#ifndef THEOS_PACKAGE_INSTALL_PREFIX
#define THEOS_PACKAGE_INSTALL_PREFIX ""
#endif

// 和 Dopamine 的 jbctl、Procursus 的 launchctl 相同
#define RB2_USERREBOOT (0x2000000000000000llu)
#define RB2_FULLREBOOT (0x8000000000000000llu)
int reboot3(uint64_t flags, ...);

static const char *const kSafeModePath = THEOS_PACKAGE_INSTALL_PREFIX "/basebin/.safe_mode";
static const char *const kJbctlPath = THEOS_PACKAGE_INSTALL_PREFIX "/basebin/jbctl";
static const char *const kLaunchctlPath = THEOS_PACKAGE_INSTALL_PREFIX "/usr/bin/launchctl";
static const char *const kUicachePath = THEOS_PACKAGE_INSTALL_PREFIX "/usr/bin/uicache";
static const uid_t kMobileUID = 501;

static int userspaceReboot(void) {
    sync();
    int result = reboot3(RB2_USERREBOOT);
    // 走到這裡表示 launchd 拒絕了;改交給 Dopamine 自己的 jbctl(同樣是 reboot3,但它的 entitlements 一定對)
    fprintf(stderr, "reboot3 failed (%d), falling back to jbctl\n", result);
    execl(kJbctlPath, "jbctl", "reboot_userspace", (char *)NULL);
    perror(kJbctlPath);
    return 4;
}

static int fullReboot(void) {
    sync();
    int result = reboot3(RB2_FULLREBOOT);
    fprintf(stderr, "reboot3 failed (%d), falling back to launchctl\n", result);
    execl(kLaunchctlPath, "launchctl", "reboot", (char *)NULL);
    perror(kLaunchctlPath);
    return 4;
}

int main(int argc, char *argv[]) {
    if (argc != 2) {
        fprintf(stderr, "usage: %s uicache|userspace|safemode|reboot\n", argv[0]);
        return 2;
    }
    const char *command = argv[1];
    int known = !strcmp(command, "uicache") || !strcmp(command, "userspace")
             || !strcmp(command, "safemode") || !strcmp(command, "reboot");
    if (!known) {
        fprintf(stderr, "unknown command: %s\n", command);
        return 2;
    }

    // 只替 SpringBoard(mobile)和 root 做事
    uid_t caller = getuid();
    if (caller != 0 && caller != kMobileUID) {
        fprintf(stderr, "not allowed for uid %d\n", caller);
        return 1;
    }
    if (setgid(0) != 0 || setuid(0) != 0) {
        perror("setuid");
        return 1;
    }

    if (!strcmp(command, "uicache")) {
        execl(kUicachePath, "uicache", "-a", (char *)NULL);
        perror(kUicachePath);
        return 4;
    }
    if (!strcmp(command, "reboot")) return fullReboot();

    if (!strcmp(command, "safemode")) {
        int fd = open(kSafeModePath, O_WRONLY | O_CREAT, 0644);
        if (fd < 0) {
            perror(kSafeModePath);
            return 3;
        }
        close(fd);
    }
    return userspaceReboot();
}
