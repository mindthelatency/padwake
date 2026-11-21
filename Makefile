CC      := clang
CFLAGS  := -Wall -Wextra -Wformat -Wformat-security \
           -Werror=implicit-function-declaration -Werror=return-type \
           -O2 -std=c11 -fstack-protector-strong -D_FORTIFY_SOURCE=2 -fno-common
LDFLAGS := -framework IOKit -framework CoreFoundation

TARGET  := bin/padwake
SRC     := src/padwake_cli.c src/padwake_core.c
HDR     := src/padwake_core.h
APP     := build/PadWake.app

.PHONY: all clean enable status monitor watch app open-app install-app release preview-site install-wow launch-wow install-daemon uninstall-daemon

all: $(TARGET)

$(TARGET): $(SRC) $(HDR)
	@mkdir -p bin
	$(CC) $(CFLAGS) $(SRC) -o $(TARGET) $(LDFLAGS)

# --- Native macOS Menu-Bar App (PadWake.app) ---

app:
	./scripts/build-app.sh

open-app: app
	open $(APP)

install-app: app
	-pkill -x PadWake 2>/dev/null || true
	rm -rf /Applications/PadWake.app
	ditto $(APP) /Applications/PadWake.app
	@echo "[app] Installed /Applications/PadWake.app"
	open /Applications/PadWake.app

release:
	./scripts/sign-and-notarize.sh

preview-site:
	open docs/index.html

# --- CLI & Daemon ---

enable: $(TARGET)
	./$(TARGET) enable

status: $(TARGET)
	./$(TARGET) status

monitor: $(TARGET)
	./$(TARGET) monitor

watch: $(TARGET)
	./$(TARGET) watch

install-wow:
	./scripts/install-wow.sh

launch-wow: $(TARGET)
	./scripts/launch-wow.sh

install-daemon: $(TARGET)
	./scripts/install-launchagent.sh install

uninstall-daemon:
	./scripts/install-launchagent.sh uninstall

clean:
	rm -rf bin build
