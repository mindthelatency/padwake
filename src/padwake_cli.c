// padwake_cli.c
// Standalone CLI wrapper around padwake_core.c for USB HID Gamepad (VID 0x057E, PID 0x2069).
// Zero external dependencies — links only against IOKit and CoreFoundation.

#include "padwake_core.h"

#include <errno.h>
#include <limits.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static volatile sig_atomic_t g_stop = 0;

static void handle_signal(int sig) {
    (void)sig;
    g_stop = 1;
}

static void install_signal_handlers(void) {
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = handle_signal;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = 0;
    sigaction(SIGINT, &sa, NULL);
    sigaction(SIGTERM, &sa, NULL);
}

typedef struct {
    bool     hasPrev;
    uint32_t lastButtons;
    int32_t  lastLX, lastLY, lastRX, lastRY;
} CliMonitorCtx;

static void cli_input_cb(pw_input_state_t st, void *context) {
    CliMonitorCtx *ctx = (CliMonitorCtx *)context;
    if (!ctx) return;

    if (!st.connected) {
        ctx->hasPrev = false;
        printf("[padwake] Controller disconnected.\n");
        fflush(stdout);
        return;
    }

    bool changed = !ctx->hasPrev ||
                   st.buttons != ctx->lastButtons ||
                   abs(st.lx - ctx->lastLX) > 40 ||
                   abs(st.ly - ctx->lastLY) > 40 ||
                   abs(st.rx - ctx->lastRX) > 40 ||
                   abs(st.ry - ctx->lastRY) > 40;
    if (!changed) return;

    ctx->hasPrev = true;
    ctx->lastButtons = st.buttons;
    ctx->lastLX = st.lx;
    ctx->lastLY = st.ly;
    ctx->lastRX = st.rx;
    ctx->lastRY = st.ry;

    double nlx = (st.lx - 2048.0) / 2048.0;
    double nly = (st.ly - 2048.0) / 2048.0;
    double nrx = (st.rx - 2048.0) / 2048.0;
    double nry = (st.ry - 2048.0) / 2048.0;

    printf("L=(%4d,%4d [%+.2f,%+.2f]) R=(%4d,%4d [%+.2f,%+.2f]) Buttons:",
           st.lx, st.ly, nlx, nly, st.rx, st.ry, nrx, nry);
    bool any = false;
    for (int i = 0; i < PW_BUTTON_COUNT; i++) {
        if (st.buttons & (1u << i)) {
            const char *name = pw_button_name(i);
            printf(" %s(b%d)", name ? name : "?", i);
            any = true;
        }
    }
    if (!any) printf(" (none)");
    printf("\n");
    fflush(stdout);
}

static void cli_status_cb(pw_status_t st, void *context) {
    (void)context;
    switch (st) {
        case PW_STATUS_AWAKE:
            printf("[padwake] Controller ready for macOS HID / SDL2.\n");
            break;
        case PW_STATUS_ASLEEP:
            fprintf(stderr, "[padwake] Controller connected but asleep (HID reports not yet streaming).\n");
            break;
        case PW_STATUS_DISCONNECTED:
            printf("[padwake] Controller disconnected.\n");
            break;
    }
    fflush(stdout);
}

static bool parse_led_arg(int argc, char **argv, uint8_t *outMask) {
    *outMask = 0x01; // Player 1 LED default
    for (int i = 2; i < argc; i++) {
        if (strcmp(argv[i], "--led") == 0) {
            if (i + 1 >= argc) {
                fprintf(stderr, "[padwake] Error: --led requires a player number (1-4).\n");
                return false;
            }
            const char *val = argv[i + 1];
            char *end = NULL;
            errno = 0;
            long p = strtol(val, &end, 10);
            if (errno != 0 || end == val || *end != '\0' || p < 1 || p > 4) {
                fprintf(stderr, "[padwake] Error: invalid --led value '%s' (expected 1-4).\n", val);
                return false;
            }
            *outMask = (uint8_t)(1u << (p - 1));
            i++;
        }
    }
    return true;
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
    install_signal_handlers();

    if (argc < 2) {
        print_usage(argv[0]);
        return 1;
    }

    const char *cmd = argv[1];
    uint8_t ledMask = 0x01;
    if (!parse_led_arg(argc, argv, &ledMask)) {
        return 1;
    }

    if (strcmp(cmd, "enable") == 0) {
        int n = pw_wake_all_verbose(ledMask, true);
        if (n == 0) {
            fprintf(stderr, "[padwake] No USB Gamepad found on USB.\n");
            return 1;
        }
        usleep(100000);
        int reports = pw_probe_reports(1.0, 5);
        if (reports > 0) {
            printf("[padwake] Verified: receiving live HID Report 0x09 stream (%d reports sampled).\n", reports);
            return 0;
        }
        fprintf(stderr, "[padwake] Warning: init succeeded, but no HID reports observed within 1s.\n");
        return 2;
    } else if (strcmp(cmd, "status") == 0) {
        int reports = pw_probe_reports(0.75, 5);
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
        int probe = pw_probe_reports(0.3, 1);
        if (probe < 0) {
            printf("[padwake] No USB Gamepad HID device detected.\n");
            return 1;
        }
        if (probe == 0) {
            printf("[padwake] Controller is asleep; waking automatically...\n");
            fflush(stdout);
            pw_wake_all(ledMask);
            usleep(100000);
        }

        CliMonitorCtx ctx;
        memset(&ctx, 0, sizeof(ctx));
        printf("[padwake] Monitoring live USB Gamepad HID inputs (Ctrl+C to quit)...\n");
        fflush(stdout);
        if (!pw_hid_monitor_start(cli_input_cb, &ctx)) {
            fprintf(stderr, "[padwake] Failed to start HID monitor.\n");
            return 1;
        }
        while (!g_stop) {
            usleep(100000);
        }
        pw_hid_monitor_stop();
        return 0;
    } else if (strcmp(cmd, "watch") == 0) {
        printf("[padwake] Watching for USB Gamepad (%04x:%04x)...\n", PW_TARGET_VID, PW_TARGET_PID);
        fflush(stdout);
        if (!pw_watcher_start(ledMask, cli_status_cb, NULL)) {
            fprintf(stderr, "[padwake] Failed to start USB hotplug watcher.\n");
            return 1;
        }
        while (!g_stop) {
            usleep(100000);
        }
        printf("[padwake] Shutting down watcher.\n");
        pw_watcher_stop();
        return 0;
    } else {
        print_usage(argv[0]);
        return 1;
    }
}
