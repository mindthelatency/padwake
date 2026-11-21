#ifndef PADWAKE_CORE_H
#define PADWAKE_CORE_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

#define PW_TARGET_VID        0x057E
#define PW_TARGET_PID        0x2069
#define PW_BUTTON_COUNT      21

typedef enum {
    PW_STATUS_DISCONNECTED = 0,
    PW_STATUS_ASLEEP       = 1,
    PW_STATUS_AWAKE        = 2
} pw_status_t;

typedef struct {
    bool     connected;
    uint32_t buttons;      // 21-bit mask (bits 0..20)
    int32_t  lx;           // 0..4095, center ~2048
    int32_t  ly;           // 0..4095, center ~2048
    int32_t  rx;           // 0..4095, center ~2048
    int32_t  ry;           // 0..4095, center ~2048
    uint64_t report_count;
} pw_input_state_t;

typedef void (*pw_status_callback_t)(pw_status_t status, void *context);
typedef void (*pw_input_callback_t)(pw_input_state_t state, void *context);

// Returns human-readable label for button index 0..20 (NULL if out of range).
const char *pw_button_name(int index);

// Sends USB wake handshake + Player LED command to all connected target controllers.
// led_mask: 0x01 (P1), 0x02 (P2), 0x04 (P3), 0x08 (P4).
// Returns number of controllers initialized.
int pw_wake_all(uint8_t led_mask);

// Same as pw_wake_all, optionally printing USB device details and ACK packets to stdout.
int pw_wake_all_verbose(uint8_t led_mask, bool verbose);

// Updates the Player LED mask on all connected target controllers.
int pw_set_led_all(uint8_t led_mask);

// Synchronously probes HID reports for up to timeout_sec (stopping early at max_reports if > 0).
// Returns: -1 if no target HID device is connected, 0 if asleep, or >0 report count sampled.
int pw_probe_reports(double timeout_sec, int max_reports);

// Synchronously probes whether a target controller is disconnected, asleep, or streaming HID.
pw_status_t pw_probe_status(double timeout_sec);

// Background USB hotplug watcher (auto-wakes on connect/reconnect).
bool pw_watcher_start(uint8_t led_mask, pw_status_callback_t cb, void *context);
void pw_watcher_set_led_mask(uint8_t led_mask);
void pw_watcher_stop(void);

// Background live HID Report 0x09 monitor (run while UI tester is visible).
bool pw_hid_monitor_start(pw_input_callback_t cb, void *context);
void pw_hid_monitor_stop(void);

#ifdef __cplusplus
}
#endif

#endif // PADWAKE_CORE_H
