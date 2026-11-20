// padwake_core.c
// Native macOS IOKit USB wake, hotplug watcher, and HID Report 0x09 decoder
// for USB HID Gamepad (VID 0x057E, PID 0x2069).
// Zero external dependencies — links only against IOKit and CoreFoundation.

#include "padwake_core.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <pthread.h>

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/IOMessage.h>
#include <IOKit/usb/IOUSBLib.h>
#include <IOKit/hid/IOHIDManager.h>

#define PW_VENDOR_IFACE_NUM 1

static const UInt8 CMD_USB_INIT[] = {
    0x03, 0x91, 0x00, 0x0d, 0x00, 0x08,
    0x00, 0x00, 0x01, 0x00, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff
};

static const UInt8 CMD_SET_LED_BASE[] = {
    0x09, 0x91, 0x00, 0x07, 0x00, 0x08,
    0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
};

static const char *kButtonNames[PW_BUTTON_COUNT] = {
    "B", "A", "Y", "X", "R", "ZR", "+", "R3",
    "Down", "Right", "Left", "Up", "L", "ZL", "-", "L3",
    "Home", "Capture", "GR", "GL", "C"
};

const char *pw_button_name(int index) {
    if (index < 0 || index >= PW_BUTTON_COUNT) return NULL;
    return kButtonNames[index];
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

static bool is_target_vendor_interface(io_service_t svc) {
    int vid = 0, pid = 0, ifaceNum = -1;
    if (!get_int_prop(svc, CFSTR("idVendor"), &vid)) return false;
    if (!get_int_prop(svc, CFSTR("idProduct"), &pid)) return false;
    if (!get_int_prop(svc, CFSTR("bInterfaceNumber"), &ifaceNum)) return false;
    return (vid == PW_TARGET_VID && pid == PW_TARGET_PID && ifaceNum == PW_VENDOR_IFACE_NUM);
}

static bool send_bulk_cmd(IOUSBInterfaceInterface300 **intf,
                          UInt8 outPipe, UInt8 inPipe,
                          const UInt8 *cmd, UInt32 cmdLen) {
    UInt8 buf[64];
    if (cmdLen > sizeof(buf)) return false;
    memcpy(buf, cmd, cmdLen);

    kern_return_t kr = (*intf)->WritePipeTO(intf, outPipe, buf, cmdLen, 1000, 1000);
    if (kr != KERN_SUCCESS) return false;

    if (inPipe != 0) {
        UInt8 resp[64] = {0};
        UInt32 respLen = sizeof(resp);
        (*intf)->ReadPipeTO(intf, inPipe, resp, &respLen, 400, 400);
    }
    return true;
}

static bool open_and_send(io_service_t svc, bool sendInit, uint8_t ledMask) {
    IOCFPlugInInterface **plugIn = NULL;
    SInt32 score = 0;
    kern_return_t kr = IOCreatePlugInInterfaceForService(
        svc, kIOUSBInterfaceUserClientTypeID, kIOCFPlugInInterfaceID, &plugIn, &score);
    if (kr != KERN_SUCCESS || !plugIn) return false;

    IOUSBInterfaceInterface300 **intf = NULL;
    HRESULT res = (*plugIn)->QueryInterface(
        plugIn, CFUUIDGetUUIDBytes(kIOUSBInterfaceInterfaceID300), (LPVOID *)&intf);
    (*plugIn)->Release(plugIn);
    if (res != S_OK || !intf) return false;

    kr = (*intf)->USBInterfaceOpen(intf);
    if (kr != KERN_SUCCESS) {
        (*intf)->Release(intf);
        return false;
    }

    UInt8 numEndpoints = 0;
    (*intf)->GetNumEndpoints(intf, &numEndpoints);
    UInt8 bulkOut = 0, bulkIn = 0;
    for (UInt8 p = 1; p <= numEndpoints; p++) {
        UInt8 dir = 0, num = 0, xfer = 0, interval = 0;
        UInt16 maxPkt = 0;
        if ((*intf)->GetPipeProperties(intf, p, &dir, &num, &xfer, &maxPkt, &interval) == KERN_SUCCESS) {
            if (xfer == kUSBBulk && dir == kUSBOut) bulkOut = p;
            if (xfer == kUSBBulk && dir == kUSBIn) bulkIn = p;
        }
    }

    bool ok = false;
    if (bulkOut != 0) {
        ok = true;
        if (sendInit) {
            ok = send_bulk_cmd(intf, bulkOut, bulkIn, CMD_USB_INIT, sizeof(CMD_USB_INIT));
        }
        if (ok && ledMask != 0) {
            UInt8 ledCmd[sizeof(CMD_SET_LED_BASE)];
            memcpy(ledCmd, CMD_SET_LED_BASE, sizeof(ledCmd));
            ledCmd[8] = ledMask;
            send_bulk_cmd(intf, bulkOut, bulkIn, ledCmd, sizeof(ledCmd));
        }
    }

    (*intf)->USBInterfaceClose(intf);
    (*intf)->Release(intf);
    return ok;
}

static int visit_interfaces(bool sendInit, uint8_t ledMask) {
    CFMutableDictionaryRef matching = IOServiceMatching(kIOUSBInterfaceClassName);
    if (!matching) return 0;

    io_iterator_t iter = 0;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter) != KERN_SUCCESS) {
        return 0;
    }

    int count = 0;
    io_service_t svc;
    while ((svc = IOIteratorNext(iter))) {
        if (is_target_vendor_interface(svc)) {
            if (open_and_send(svc, sendInit, ledMask)) {
                count++;
            }
        }
        IOObjectRelease(svc);
    }
    IOObjectRelease(iter);
    return count;
}

int pw_wake_all(uint8_t led_mask) {
    return visit_interfaces(true, led_mask ? led_mask : 0x01);
}

int pw_set_led_all(uint8_t led_mask) {
    return visit_interfaces(false, led_mask ? led_mask : 0x01);
}

// --- Synchronous Status Probe ---

typedef struct {
    int count;
} ProbeCtx;

static void probe_report_cb(void *context, IOReturn result, void *sender,
                            IOHIDReportType type, uint32_t reportID,
                            uint8_t *report, CFIndex reportLength) {
    (void)result; (void)sender; (void)type; (void)reportID; (void)report; (void)reportLength;
    ProbeCtx *ctx = (ProbeCtx *)context;
    ctx->count++;
    if (ctx->count >= 2) {
        CFRunLoopStop(CFRunLoopGetCurrent());
    }
}

static CFDictionaryRef create_hid_matching(void) {
    CFMutableDictionaryRef match = CFDictionaryCreateMutable(
        kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    int vid = PW_TARGET_VID, pid = PW_TARGET_PID;
    CFNumberRef vidNum = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &vid);
    CFNumberRef pidNum = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &pid);
    CFDictionarySetValue(match, CFSTR(kIOHIDVendorIDKey), vidNum);
    CFDictionarySetValue(match, CFSTR(kIOHIDProductIDKey), pidNum);
    CFRelease(vidNum);
    CFRelease(pidNum);
    return match;
}

pw_status_t pw_probe_status(double timeout_sec) {
    IOHIDManagerRef mgr = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    if (!mgr) return PW_STATUS_DISCONNECTED;

    CFDictionaryRef match = create_hid_matching();
    IOHIDManagerSetDeviceMatching(mgr, match);
    CFRelease(match);

    if (IOHIDManagerOpen(mgr, kIOHIDOptionsTypeNone) != kIOReturnSuccess) {
        CFRelease(mgr);
        return PW_STATUS_DISCONNECTED;
    }

    CFSetRef devices = IOHIDManagerCopyDevices(mgr);
    if (!devices || CFSetGetCount(devices) == 0) {
        if (devices) CFRelease(devices);
        IOHIDManagerClose(mgr, kIOHIDOptionsTypeNone);
        CFRelease(mgr);
        return PW_STATUS_DISCONNECTED;
    }

    CFIndex n = CFSetGetCount(devices);
    IOHIDDeviceRef *list = calloc((size_t)n, sizeof(IOHIDDeviceRef));
    CFSetGetValues(devices, (const void **)list);
    IOHIDDeviceRef dev = list[0];

    uint8_t buf[128];
    ProbeCtx ctx = {0};
    IOHIDDeviceRegisterInputReportCallback(dev, buf, sizeof(buf), probe_report_cb, &ctx);
    IOHIDDeviceScheduleWithRunLoop(dev, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);

    CFRunLoopRunInMode(kCFRunLoopDefaultMode, timeout_sec > 0 ? timeout_sec : 0.4, false);

    IOHIDDeviceUnscheduleFromRunLoop(dev, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    free(list);
    CFRelease(devices);
    IOHIDManagerClose(mgr, kIOHIDOptionsTypeNone);
    CFRelease(mgr);

    return ctx.count > 0 ? PW_STATUS_AWAKE : PW_STATUS_ASLEEP;
}

// --- Background USB Hotplug Watcher ---

typedef struct {
    pthread_mutex_t      lock;
    pthread_t            thread;
    bool                 running;
    CFRunLoopRef         runLoop;
    uint8_t              ledMask;
    pw_status_callback_t callback;
    void                *context;
} WatcherState;

static WatcherState g_watcher = {
    .lock = PTHREAD_MUTEX_INITIALIZER,
    .running = false,
    .runLoop = NULL,
    .ledMask = 0x01,
    .callback = NULL,
    .context = NULL
};

static void notify_watcher_status(pw_status_t st) {
    pthread_mutex_lock(&g_watcher.lock);
    pw_status_callback_t cb = g_watcher.callback;
    void *ctx = g_watcher.context;
    pthread_mutex_unlock(&g_watcher.lock);
    if (cb) cb(st, ctx);
}

static void watcher_matched_cb(void *refCon, io_iterator_t iter) {
    (void)refCon;
    io_service_t svc;
    while ((svc = IOIteratorNext(iter))) {
        if (is_target_vendor_interface(svc)) {
            usleep(200000);
            pthread_mutex_lock(&g_watcher.lock);
            uint8_t mask = g_watcher.ledMask;
            pthread_mutex_unlock(&g_watcher.lock);

            bool ok = false;
            for (int attempt = 0; attempt < 3 && !ok; attempt++) {
                ok = open_and_send(svc, true, mask);
                if (!ok && attempt < 2) usleep(250000);
            }
            if (ok) {
                usleep(80000);
                pw_status_t st = pw_probe_status(0.4);
                notify_watcher_status(st);
            } else {
                notify_watcher_status(PW_STATUS_ASLEEP);
            }
        }
        IOObjectRelease(svc);
    }
}

static void watcher_terminated_cb(void *refCon, io_iterator_t iter) {
    (void)refCon;
    bool sawTarget = false;
    io_service_t svc;
    while ((svc = IOIteratorNext(iter))) {
        if (is_target_vendor_interface(svc)) {
            sawTarget = true;
        }
        IOObjectRelease(svc);
    }
    if (sawTarget) {
        usleep(100000);
        notify_watcher_status(pw_probe_status(0.25));
    }
}

static void *watcher_thread_main(void *arg) {
    (void)arg;
    CFRunLoopRef rl = CFRunLoopGetCurrent();

    pthread_mutex_lock(&g_watcher.lock);
    g_watcher.runLoop = rl;
    CFRetain(rl);
    pthread_mutex_unlock(&g_watcher.lock);

    IONotificationPortRef port = IONotificationPortCreate(kIOMainPortDefault);
    if (port) {
        CFRunLoopAddSource(rl, IONotificationPortGetRunLoopSource(port), kCFRunLoopDefaultMode);

        io_iterator_t matchIter = 0;
        io_iterator_t termIter = 0;

        CFMutableDictionaryRef m1 = IOServiceMatching(kIOUSBInterfaceClassName);
        if (IOServiceAddMatchingNotification(port, kIOMatchedNotification, m1,
                                             watcher_matched_cb, NULL, &matchIter) == KERN_SUCCESS) {
            watcher_matched_cb(NULL, matchIter);
        }

        CFMutableDictionaryRef m2 = IOServiceMatching(kIOUSBInterfaceClassName);
        if (IOServiceAddMatchingNotification(port, kIOTerminatedNotification, m2,
                                             watcher_terminated_cb, NULL, &termIter) == KERN_SUCCESS) {
            // Drain initial terminated iterator
            io_service_t s;
            while ((s = IOIteratorNext(termIter))) IOObjectRelease(s);
        }

        notify_watcher_status(pw_probe_status(0.35));

        while (true) {
            pthread_mutex_lock(&g_watcher.lock);
            bool keepGoing = g_watcher.running;
            pthread_mutex_unlock(&g_watcher.lock);
            if (!keepGoing) break;
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.5, false);
        }

        if (matchIter) IOObjectRelease(matchIter);
        if (termIter) IOObjectRelease(termIter);
        IONotificationPortDestroy(port);
    }

    pthread_mutex_lock(&g_watcher.lock);
    if (g_watcher.runLoop) {
        CFRelease(g_watcher.runLoop);
        g_watcher.runLoop = NULL;
    }
    pthread_mutex_unlock(&g_watcher.lock);
    return NULL;
}

bool pw_watcher_start(uint8_t led_mask, pw_status_callback_t cb, void *context) {
    pthread_mutex_lock(&g_watcher.lock);
    if (g_watcher.running) {
        pthread_mutex_unlock(&g_watcher.lock);
        return true;
    }
    g_watcher.ledMask = led_mask ? led_mask : 0x01;
    g_watcher.callback = cb;
    g_watcher.context = context;
    g_watcher.running = true;
    int rc = pthread_create(&g_watcher.thread, NULL, watcher_thread_main, NULL);
    if (rc != 0) {
        g_watcher.running = false;
        pthread_mutex_unlock(&g_watcher.lock);
        return false;
    }
    pthread_mutex_unlock(&g_watcher.lock);
    return true;
}

void pw_watcher_set_led_mask(uint8_t led_mask) {
    pthread_mutex_lock(&g_watcher.lock);
    g_watcher.ledMask = led_mask ? led_mask : 0x01;
    pthread_mutex_unlock(&g_watcher.lock);
}

void pw_watcher_stop(void) {
    pthread_mutex_lock(&g_watcher.lock);
    if (!g_watcher.running) {
        pthread_mutex_unlock(&g_watcher.lock);
        return;
    }
    g_watcher.running = false;
    CFRunLoopRef rl = g_watcher.runLoop;
    if (rl) CFRunLoopStop(rl);
    pthread_t th = g_watcher.thread;
    pthread_mutex_unlock(&g_watcher.lock);

    pthread_join(th, NULL);
}

// --- Background Live HID Report 0x09 Monitor ---

typedef struct {
    pthread_mutex_t     lock;
    pthread_t           thread;
    bool                running;
    CFRunLoopRef        runLoop;
    pw_input_callback_t callback;
    void               *context;
    pw_input_state_t    lastState;
    uint8_t             reportBuf[128];
} MonitorState;

static MonitorState g_monitor = {
    .lock = PTHREAD_MUTEX_INITIALIZER,
    .running = false,
    .runLoop = NULL,
    .callback = NULL,
    .context = NULL
};

static void monitor_report_cb(void *context, IOReturn result, void *sender,
                              IOHIDReportType type, uint32_t reportID,
                              uint8_t *r, CFIndex len) {
    (void)context; (void)result; (void)sender; (void)type; (void)reportID;
    if (len < 12 || r[0] != 0x09) return;

    pw_input_state_t st;
    st.connected = true;
    st.buttons = ((uint32_t)r[3]) |
                 ((uint32_t)r[4] << 8) |
                 (((uint32_t)r[5] & 0x1F) << 16);
    st.lx = (int32_t)r[6] | (((int32_t)r[7] & 0x0F) << 8);
    st.ly = (((int32_t)r[7] & 0xF0) >> 4) | ((int32_t)r[8] << 4);
    st.rx = (int32_t)r[9] | (((int32_t)r[10] & 0x0F) << 8);
    st.ry = (((int32_t)r[10] & 0xF0) >> 4) | ((int32_t)r[11] << 4);

    pthread_mutex_lock(&g_monitor.lock);
    g_monitor.lastState.report_count++;
    st.report_count = g_monitor.lastState.report_count;
    bool changed = (st.report_count == 1) ||
                   (st.buttons != g_monitor.lastState.buttons) ||
                   (abs(st.lx - g_monitor.lastState.lx) > 20) ||
                   (abs(st.ly - g_monitor.lastState.ly) > 20) ||
                   (abs(st.rx - g_monitor.lastState.rx) > 20) ||
                   (abs(st.ry - g_monitor.lastState.ry) > 20);
    pw_input_callback_t cb = g_monitor.callback;
    void *cbCtx = g_monitor.context;
    if (changed) {
        g_monitor.lastState = st;
    }
    pthread_mutex_unlock(&g_monitor.lock);

    if (changed && cb) {
        cb(st, cbCtx);
    }
}

static void monitor_dev_matched_cb(void *context, IOReturn result, void *sender, IOHIDDeviceRef dev) {
    (void)context; (void)result; (void)sender;
    IOHIDDeviceRegisterInputReportCallback(
        dev, g_monitor.reportBuf, sizeof(g_monitor.reportBuf), monitor_report_cb, NULL);
}

static void monitor_dev_removed_cb(void *context, IOReturn result, void *sender, IOHIDDeviceRef dev) {
    (void)context; (void)result; (void)sender; (void)dev;
    pw_input_state_t empty = {0};
    empty.connected = false;
    empty.lx = 2048; empty.ly = 2048;
    empty.rx = 2048; empty.ry = 2048;

    pthread_mutex_lock(&g_monitor.lock);
    g_monitor.lastState = empty;
    pw_input_callback_t cb = g_monitor.callback;
    void *cbCtx = g_monitor.context;
    pthread_mutex_unlock(&g_monitor.lock);

    if (cb) cb(empty, cbCtx);
}

static void *monitor_thread_main(void *arg) {
    (void)arg;
    CFRunLoopRef rl = CFRunLoopGetCurrent();

    pthread_mutex_lock(&g_monitor.lock);
    g_monitor.runLoop = rl;
    CFRetain(rl);
    memset(&g_monitor.lastState, 0, sizeof(g_monitor.lastState));
    g_monitor.lastState.lx = 2048; g_monitor.lastState.ly = 2048;
    g_monitor.lastState.rx = 2048; g_monitor.lastState.ry = 2048;
    pthread_mutex_unlock(&g_monitor.lock);

    IOHIDManagerRef mgr = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    if (mgr) {
        CFDictionaryRef match = create_hid_matching();
        IOHIDManagerSetDeviceMatching(mgr, match);
        CFRelease(match);

        IOHIDManagerRegisterDeviceMatchingCallback(mgr, monitor_dev_matched_cb, NULL);
        IOHIDManagerRegisterDeviceRemovalCallback(mgr, monitor_dev_removed_cb, NULL);
        IOHIDManagerScheduleWithRunLoop(mgr, rl, kCFRunLoopDefaultMode);
        IOHIDManagerOpen(mgr, kIOHIDOptionsTypeNone);

        while (true) {
            pthread_mutex_lock(&g_monitor.lock);
            bool keepGoing = g_monitor.running;
            pthread_mutex_unlock(&g_monitor.lock);
            if (!keepGoing) break;
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.2, false);
        }

        IOHIDManagerUnscheduleFromRunLoop(mgr, rl, kCFRunLoopDefaultMode);
        IOHIDManagerClose(mgr, kIOHIDOptionsTypeNone);
        CFRelease(mgr);
    }

    pthread_mutex_lock(&g_monitor.lock);
    if (g_monitor.runLoop) {
        CFRelease(g_monitor.runLoop);
        g_monitor.runLoop = NULL;
    }
    pthread_mutex_unlock(&g_monitor.lock);
    return NULL;
}

bool pw_hid_monitor_start(pw_input_callback_t cb, void *context) {
    pthread_mutex_lock(&g_monitor.lock);
    if (g_monitor.running) {
        pthread_mutex_unlock(&g_monitor.lock);
        return true;
    }
    g_monitor.callback = cb;
    g_monitor.context = context;
    g_monitor.running = true;
    int rc = pthread_create(&g_monitor.thread, NULL, monitor_thread_main, NULL);
    if (rc != 0) {
        g_monitor.running = false;
        pthread_mutex_unlock(&g_monitor.lock);
        return false;
    }
    pthread_mutex_unlock(&g_monitor.lock);
    return true;
}

void pw_hid_monitor_stop(void) {
    pthread_mutex_lock(&g_monitor.lock);
    if (!g_monitor.running) {
        pthread_mutex_unlock(&g_monitor.lock);
        return;
    }
    g_monitor.running = false;
    CFRunLoopRef rl = g_monitor.runLoop;
    if (rl) CFRunLoopStop(rl);
    pthread_t th = g_monitor.thread;
    pthread_mutex_unlock(&g_monitor.lock);

    pthread_join(th, NULL);
}
