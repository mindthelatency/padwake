// padwake_cli.c
// Native macOS IOKit USB initializer, hotplug daemon, and HID monitor
// for USB HID Gamepad (VID 0x057E, PID 0x2069).
//
// Zero external dependencies — links only against IOKit and CoreFoundation.

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <signal.h>
#include <unistd.h>

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/IOMessage.h>
#include <IOKit/usb/IOUSBLib.h>
#include <IOKit/hid/IOHIDManager.h>

#define TARGET_USB_VID       0x057E
#define TARGET_USB_PID       0x2069
#define VENDOR_INTERFACE_NUM 1

// USB initialization handshake sent over Interface 1 Bulk OUT (EP 0x02)
static const UInt8 CMD_USB_INIT[] = {
    0x03, 0x91, 0x00, 0x0d, 0x00, 0x08,
    0x00, 0x00, 0x01, 0x00, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff
};

// Player LED command sent over Interface 1 Bulk OUT (byte 8 = LED bitmask 0x01..0x0F)
static const UInt8 CMD_SET_LED_BASE[] = {
    0x09, 0x91, 0x00, 0x07, 0x00, 0x08,
    0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
};

static const char *BUTTON_NAMES[21] = {
    "B", "A", "Y", "X", "R", "ZR", "+", "R3",
    "Down", "Right", "Left", "Up", "L", "ZL", "-", "L3",
    "Home", "Capture", "GR", "GL", "C"
};

static volatile sig_atomic_t g_stop = 0;
static CFRunLoopRef g_mainRunLoop = NULL;
static uint8_t g_ledMask = 0x01;

static void handle_signal(int sig) {
    (void)sig;
    g_stop = 1;
    if (g_mainRunLoop) {
        CFRunLoopStop(g_mainRunLoop);
    }
}

static bool get_int_prop(io_service_t svc, CFStringRef key, int *out) {
    CFTypeRef ref = IORegistryEntryCreateCFProperty(svc, key, kCFAllocatorDefault, 0);
    if (!ref) return false;
    bool ok = false;
    if (CFGetTypeID(ref) == CFNumberGetTypeID()) {
        ok = CFNumberGetValue((CFNumberRef)ref, kCFNumberIntType, out);
    }
    CFRelease(ref);
    return ok;
}

static bool get_string_prop(io_service_t svc, CFStringRef key, char *buf, size_t bufSize) {
    CFTypeRef ref = IORegistryEntryCreateCFProperty(svc, key, kCFAllocatorDefault, 0);
    if (!ref) return false;
    bool ok = false;
    if (CFGetTypeID(ref) == CFStringGetTypeID()) {
        ok = CFStringGetCString((CFStringRef)ref, buf, (CFIndex)bufSize, kCFStringEncodingUTF8);
    }
    CFRelease(ref);
    return ok;
}

static bool is_target_vendor_interface(io_service_t svc) {
    int vid = 0, pid = 0, ifaceNum = -1;
    if (!get_int_prop(svc, CFSTR("idVendor"), &vid)) return false;
    if (!get_int_prop(svc, CFSTR("idProduct"), &pid)) return false;
    if (!get_int_prop(svc, CFSTR("bInterfaceNumber"), &ifaceNum)) return false;
    return (vid == TARGET_USB_VID && pid == TARGET_USB_PID && ifaceNum == VENDOR_INTERFACE_NUM);
}

static bool send_bulk_command(IOUSBInterfaceInterface300 **intf,
                              UInt8 outPipe, UInt8 inPipe,
                              const UInt8 *cmd, UInt32 cmdLen,
                              const char *label, bool verbose) {
    UInt8 mutableBuf[64];
    if (cmdLen > sizeof(mutableBuf)) return false;
    memcpy(mutableBuf, cmd, cmdLen);

    kern_return_t kr = (*intf)->WritePipeTO(intf, outPipe, mutableBuf, cmdLen, 1000, 1000);
    if (kr != KERN_SUCCESS) {
        fprintf(stderr, "[padwake] WritePipeTO(%s) failed: 0x%08x\n", label, kr);
        return false;
    }

    if (inPipe != 0) {
        UInt8 resp[64] = {0};
        UInt32 respLen = sizeof(resp);
        kr = (*intf)->ReadPipeTO(intf, inPipe, resp, &respLen, 500, 500);
        if (verbose) {
            if (kr == KERN_SUCCESS) {
                printf("  [%s] ACK (%u bytes):", label, (unsigned)respLen);
                for (UInt32 i = 0; i < respLen; i++) printf(" %02x", resp[i]);
                printf("\n");
            } else {
                printf("  [%s] Write OK (no ACK within 500ms: 0x%08x)\n", label, kr);
            }
        }
    }
    return true;
}

static bool initialize_interface(io_service_t svc, uint8_t ledMask, bool verbose) {
    IOCFPlugInInterface **plugIn = NULL;
    SInt32 score = 0;
    kern_return_t kr = IOCreatePlugInInterfaceForService(
        svc, kIOUSBInterfaceUserClientTypeID, kIOCFPlugInInterfaceID, &plugIn, &score);
    if (kr != KERN_SUCCESS || !plugIn) {
        fprintf(stderr, "[padwake] IOCreatePlugInInterfaceForService failed: 0x%08x\n", kr);
        return false;
    }

    IOUSBInterfaceInterface300 **intf = NULL;
    HRESULT res = (*plugIn)->QueryInterface(
        plugIn, CFUUIDGetUUIDBytes(kIOUSBInterfaceInterfaceID300), (LPVOID *)&intf);
    (*plugIn)->Release(plugIn);
    if (res != S_OK || !intf) {
        fprintf(stderr, "[padwake] QueryInterface(IOUSBInterfaceInterface300) failed: 0x%08x\n", (int)res);
        return false;
    }

    kr = (*intf)->USBInterfaceOpen(intf);
    if (kr != KERN_SUCCESS) {
        fprintf(stderr, "[padwake] USBInterfaceOpen failed: 0x%08x\n", kr);
        (*intf)->Release(intf);
        return false;
    }

    UInt8 numEndpoints = 0;
    (*intf)->GetNumEndpoints(intf, &numEndpoints);

    UInt8 bulkOutPipe = 0, bulkInPipe = 0;
    for (UInt8 pipe = 1; pipe <= numEndpoints; pipe++) {
        UInt8 dir = 0, num = 0, xferType = 0, interval = 0;
        UInt16 maxPkt = 0;
        if ((*intf)->GetPipeProperties(intf, pipe, &dir, &num, &xferType, &maxPkt, &interval) == KERN_SUCCESS) {
            if (xferType == kUSBBulk && dir == kUSBOut) bulkOutPipe = pipe;
            if (xferType == kUSBBulk && dir == kUSBIn) bulkInPipe = pipe;
        }
    }

    if (bulkOutPipe == 0) {
        fprintf(stderr, "[padwake] Bulk OUT pipe not found on Interface 1\n");
        (*intf)->USBInterfaceClose(intf);
        (*intf)->Release(intf);
        return false;
    }

    bool ok = send_bulk_command(intf, bulkOutPipe, bulkInPipe,
                                CMD_USB_INIT, sizeof(CMD_USB_INIT), "USB_INIT", verbose);
    if (ok) {
        UInt8 ledCmd[sizeof(CMD_SET_LED_BASE)];
        memcpy(ledCmd, CMD_SET_LED_BASE, sizeof(ledCmd));
        ledCmd[8] = ledMask;
        send_bulk_command(intf, bulkOutPipe, bulkInPipe,
                          ledCmd, sizeof(ledCmd), "SET_LED", verbose);
    }

    (*intf)->USBInterfaceClose(intf);
    (*intf)->Release(intf);
    return ok;
}

static int enable_all_connected(uint8_t ledMask, bool verbose) {
    CFMutableDictionaryRef matching = IOServiceMatching(kIOUSBInterfaceClassName);
    if (!matching) return 0;

    io_iterator_t iter = 0;
    kern_return_t kr = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter);
    if (kr != KERN_SUCCESS) return 0;

    int enabled = 0;
    io_service_t svc;
    while ((svc = IOIteratorNext(iter))) {
        if (is_target_vendor_interface(svc)) {
            int loc = 0;
            char prod[128] = "USB Gamepad";
            get_int_prop(svc, CFSTR("locationID"), &loc);
            get_string_prop(svc, CFSTR("USB Product Name"), prod, sizeof(prod));
            printf("[padwake] Waking %s (VID=0x%04x PID=0x%04x loc=0x%08x)...\n",
                   prod, TARGET_USB_VID, TARGET_USB_PID, loc);
            if (initialize_interface(svc, ledMask, verbose)) {
                enabled++;
                printf("[padwake] Controller awake and Player LED set (mask=0x%02x).\n", ledMask);
            }
            fflush(stdout);
        }
        IOObjectRelease(svc);
    }
    IOObjectRelease(iter);
    return enabled;
}

// --- HID Status & Live Monitor ---

typedef struct {
    int count;
    int maxCount;
    bool monitorMode;
    uint32_t lastButtons;
    int lastLX, lastLY, lastRX, lastRY;
    bool hasPrev;
} HidProbeState;

static void decode_report_09(const uint8_t *r, CFIndex len, HidProbeState *st) {
    if (len < 12 || r[0] != 0x09) return;

    uint32_t buttons = ((uint32_t)r[3]) |
                       ((uint32_t)r[4] << 8) |
                       (((uint32_t)r[5] & 0x1F) << 16);

    int lx = (int)r[6] | (((int)r[7] & 0x0F) << 8);
    int ly = (((int)r[7] & 0xF0) >> 4) | ((int)r[8] << 4);
    int rx = (int)r[9] | (((int)r[10] & 0x0F) << 8);
    int ry = (((int)r[10] & 0xF0) >> 4) | ((int)r[11] << 4);

    if (!st->monitorMode) return;

    bool changed = !st->hasPrev ||
                   buttons != st->lastButtons ||
                   abs(lx - st->lastLX) > 40 ||
                   abs(ly - st->lastLY) > 40 ||
                   abs(rx - st->lastRX) > 40 ||
                   abs(ry - st->lastRY) > 40;

    if (!changed) return;

    st->hasPrev = true;
    st->lastButtons = buttons;
    st->lastLX = lx; st->lastLY = ly;
    st->lastRX = rx; st->lastRY = ry;

    double nlx = (lx - 2048.0) / 2048.0;
    double nly = (ly - 2048.0) / 2048.0;
    double nrx = (rx - 2048.0) / 2048.0;
    double nry = (ry - 2048.0) / 2048.0;

    printf("L=(%4d,%4d [%+.2f,%+.2f]) R=(%4d,%4d [%+.2f,%+.2f]) Buttons:",
           lx, ly, nlx, nly, rx, ry, nrx, nry);
    bool any = false;
    for (int i = 0; i < 21; i++) {
        if (buttons & (1u << i)) {
            printf(" %s(b%d)", BUTTON_NAMES[i], i);
            any = true;
        }
    }
    if (!any) printf(" (none)");
    printf("\n");
    fflush(stdout);
}

static void hid_report_cb(void *context, IOReturn result, void *sender,
                          IOHIDReportType type, uint32_t reportID,
                          uint8_t *report, CFIndex reportLength) {
    (void)result; (void)sender; (void)type; (void)reportID;
    HidProbeState *st = (HidProbeState *)context;
    st->count++;
    decode_report_09(report, reportLength, st);
    if (st->maxCount > 0 && st->count >= st->maxCount) {
        CFRunLoopStop(CFRunLoopGetCurrent());
    }
}

static int run_hid_check(bool monitorMode, double timeoutSec, int maxReports) {
    IOHIDManagerRef mgr = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    CFMutableDictionaryRef match = CFDictionaryCreateMutable(
        kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);

    int vid = TARGET_USB_VID, pid = TARGET_USB_PID;
    CFNumberRef vidNum = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &vid);
    CFNumberRef pidNum = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &pid);
    CFDictionarySetValue(match, CFSTR(kIOHIDVendorIDKey), vidNum);
    CFDictionarySetValue(match, CFSTR(kIOHIDProductIDKey), pidNum);
    CFRelease(vidNum);
    CFRelease(pidNum);

    IOHIDManagerSetDeviceMatching(mgr, match);
    CFRelease(match);

    IOReturn ret = IOHIDManagerOpen(mgr, kIOHIDOptionsTypeNone);
    if (ret != kIOReturnSuccess) {
        fprintf(stderr, "[padwake] IOHIDManagerOpen failed: 0x%08x\n", ret);
        CFRelease(mgr);
        return -1;
    }

    CFSetRef devices = IOHIDManagerCopyDevices(mgr);
    if (!devices || CFSetGetCount(devices) == 0) {
        printf("[padwake] No USB Gamepad HID device detected.\n");
        if (devices) CFRelease(devices);
        IOHIDManagerClose(mgr, kIOHIDOptionsTypeNone);
        CFRelease(mgr);
        return -1;
    }

    CFIndex count = CFSetGetCount(devices);
    IOHIDDeviceRef *devList = calloc((size_t)count, sizeof(IOHIDDeviceRef));
    CFSetGetValues(devices, (const void **)devList);
    IOHIDDeviceRef dev = devList[0];

    static uint8_t buf[128];
    HidProbeState state;
    memset(&state, 0, sizeof(state));
    state.maxCount = maxReports;
    state.monitorMode = monitorMode;

    IOHIDDeviceRegisterInputReportCallback(dev, buf, sizeof(buf), hid_report_cb, &state);
    IOHIDDeviceScheduleWithRunLoop(dev, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);

    if (monitorMode) {
        printf("[padwake] Monitoring live USB Gamepad HID inputs (Ctrl+C to quit)...\n");
        fflush(stdout);
        g_mainRunLoop = CFRunLoopGetCurrent();
        while (!g_stop) {
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.25, false);
        }
    } else {
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, timeoutSec, false);
    }

    IOHIDDeviceUnscheduleFromRunLoop(dev, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    free(devList);
    CFRelease(devices);
    IOHIDManagerClose(mgr, kIOHIDOptionsTypeNone);
    CFRelease(mgr);
    return state.count;
}

// --- Hotplug Daemon (watch) ---

static void usb_interface_matched(void *refCon, io_iterator_t iter) {
    (void)refCon;
    io_service_t svc;
    while ((svc = IOIteratorNext(iter))) {
        if (is_target_vendor_interface(svc)) {
            // Brief settle delay when freshly plugged in
            usleep(200000);
            int loc = 0;
            get_int_prop(svc, CFSTR("locationID"), &loc);
            printf("[padwake] Hotplug detected (loc=0x%08x), sending USB wake handshake...\n", loc);
            fflush(stdout);

            bool ok = false;
            for (int attempt = 1; attempt <= 3 && !ok; attempt++) {
                ok = initialize_interface(svc, g_ledMask, false);
                if (!ok && attempt < 3) {
                    usleep(250000);
                }
            }
            if (ok) {
                printf("[padwake] Controller ready for macOS HID / SDL2.\n");
            } else {
                fprintf(stderr, "[padwake] Failed to initialize controller after 3 attempts.\n");
            }
            fflush(stdout);
        }
        IOObjectRelease(svc);
    }
}

static int run_watch_daemon(uint8_t ledMask) {
    g_ledMask = ledMask;
    g_mainRunLoop = CFRunLoopGetCurrent();

    IONotificationPortRef notifyPort = IONotificationPortCreate(kIOMainPortDefault);
    if (!notifyPort) {
        fprintf(stderr, "[padwake] IONotificationPortCreate failed\n");
        return 1;
    }

    CFRunLoopSourceRef runLoopSource = IONotificationPortGetRunLoopSource(notifyPort);
    CFRunLoopAddSource(g_mainRunLoop, runLoopSource, kCFRunLoopDefaultMode);

    CFMutableDictionaryRef matching = IOServiceMatching(kIOUSBInterfaceClassName);
    io_iterator_t iter = 0;
    kern_return_t kr = IOServiceAddMatchingNotification(
        notifyPort, kIOMatchedNotification, matching,
        usb_interface_matched, NULL, &iter);
    if (kr != KERN_SUCCESS) {
        fprintf(stderr, "[padwake] IOServiceAddMatchingNotification failed: 0x%08x\n", kr);
        IONotificationPortDestroy(notifyPort);
        return 1;
    }

    printf("[padwake] Watching for USB Gamepad (057e:2069)...\n");
    fflush(stdout);

    // Drain initial iterator to wake any already-connected controller(s)
    usb_interface_matched(NULL, iter);

    while (!g_stop) {
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 1.0, false);
    }

    printf("[padwake] Shutting down watcher.\n");
    IOObjectRelease(iter);
    IONotificationPortDestroy(notifyPort);
    return 0;
}

static uint8_t parse_led_arg(int argc, char **argv) {
    for (int i = 2; i < argc - 1; i++) {
        if (strcmp(argv[i], "--led") == 0) {
            int p = atoi(argv[i + 1]);
            if (p >= 1 && p <= 4) return (uint8_t)(1u << (p - 1));
        }
    }
    return 0x01; // Player 1 LED
}

static void print_usage(const char *prog) {
    fprintf(stderr,
        "Usage: %s <command> [options]\n\n"
        "Commands:\n"
        "  status              Check USB/HID presence and whether HID reports are streaming\n"
        "  enable [--led 1-4]  Send USB init handshake & wake connected USB Gamepad\n"
        "  watch  [--led 1-4]  Stay running and auto-wake controller whenever plugged in\n"
        "  monitor             Live-decode all 21 buttons and both analog sticks from HID\n",
        prog);
}

int main(int argc, char **argv) {
    signal(SIGINT, handle_signal);
    signal(SIGTERM, handle_signal);

    if (argc < 2) {
        print_usage(argv[0]);
        return 1;
    }

    const char *cmd = argv[1];
    uint8_t ledMask = parse_led_arg(argc, argv);

    if (strcmp(cmd, "enable") == 0) {
        int n = enable_all_connected(ledMask, true);
        if (n == 0) {
            fprintf(stderr, "[padwake] No USB Gamepad found on USB.\n");
            return 1;
        }
        usleep(100000);
        int reports = run_hid_check(false, 1.0, 5);
        if (reports > 0) {
            printf("[padwake] Verified: receiving live HID Report 0x09 stream (%d reports sampled).\n", reports);
            return 0;
        } else {
            fprintf(stderr, "[padwake] Warning: init succeeded, but no HID reports observed within 1s.\n");
            return 2;
        }
    } else if (strcmp(cmd, "status") == 0) {
        int reports = run_hid_check(false, 0.75, 5);
        if (reports > 0) {
            printf("[padwake] Status: CONNECTED & AWAKE (received %d HID reports).\n", reports);
            return 0;
        } else if (reports == 0) {
            printf("[padwake] Status: CONNECTED BUT ASLEEP (0 HID reports). Run '%s enable'.\n", argv[0]);
            return 1;
        } else {
            printf("[padwake] Status: NOT CONNECTED.\n");
            return 1;
        }
    } else if (strcmp(cmd, "monitor") == 0) {
        // Auto-wake if asleep before monitoring
        int probe = run_hid_check(false, 0.3, 1);
        if (probe == 0) {
            printf("[padwake] Controller is asleep; waking automatically...\n");
            enable_all_connected(ledMask, false);
            usleep(100000);
        }
        return run_hid_check(true, 0.0, 0) >= 0 ? 0 : 1;
    } else if (strcmp(cmd, "watch") == 0) {
        return run_watch_daemon(ledMask);
    } else {
        print_usage(argv[0]);
        return 1;
    }
}
