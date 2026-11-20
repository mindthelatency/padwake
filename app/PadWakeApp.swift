import Cocoa
import SwiftUI
import ServiceManagement

// MARK: - Observable Controller State

@MainActor
final class PadWakeModel: ObservableObject {
    @Published var status: pw_status_t = PW_STATUS_DISCONNECTED
    @Published var playerLED: Int {
        didSet {
            UserDefaults.standard.set(playerLED, forKey: "playerLED")
            let mask = UInt8(1 << max(0, min(3, playerLED - 1)))
            pw_watcher_set_led_mask(mask)
            DispatchQueue.global(qos: .userInitiated).async {
                _ = pw_set_led_all(mask)
            }
        }
    }
    @Published var disableMFiVeto: Bool {
        didSet {
            UserDefaults.standard.set(disableMFiVeto, forKey: "disableMFiVeto")
            applyMFiEnvSetting(enabled: disableMFiVeto)
        }
    }
    @Published var launchAtLogin: Bool = false
    @Published var showTester: Bool = false {
        didSet {
            if showTester {
                startHIDMonitor()
            } else {
                stopHIDMonitor()
            }
        }
    }
    @Published var inputState = pw_input_state_t(
        connected: false, buttons: 0, lx: 2048, ly: 2048, rx: 2048, ry: 2048, report_count: 0
    )
    @Published var infoMessage: String?

    var onStatusChange: ((pw_status_t) -> Void)?

    private var watcherStarted = false
    private var monitorActive = false

    init() {
        let savedLED = UserDefaults.standard.integer(forKey: "playerLED")
        self.playerLED = (1...4).contains(savedLED) ? savedLED : 1

        if UserDefaults.standard.object(forKey: "disableMFiVeto") == nil {
            UserDefaults.standard.set(true, forKey: "disableMFiVeto")
        }
        self.disableMFiVeto = UserDefaults.standard.bool(forKey: "disableMFiVeto")
        self.launchAtLogin = (SMAppService.mainApp.status == .enabled)
    }

    func start() {
        if disableMFiVeto {
            applyMFiEnvSetting(enabled: true)
        }
        guard !watcherStarted else { return }
        watcherStarted = true

        let mask = UInt8(1 << max(0, min(3, playerLED - 1)))
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        _ = pw_watcher_start(mask, { newStatus, rawCtx in
            guard let rawCtx else { return }
            let model = Unmanaged<PadWakeModel>.fromOpaque(rawCtx).takeUnretainedValue()
            Task { @MainActor in
                model.status = newStatus
                model.onStatusChange?(newStatus)
            }
        }, ctx)
    }

    func stop() {
        stopHIDMonitor()
        if watcherStarted {
            pw_watcher_stop()
            watcherStarted = false
        }
    }

    func wakeNow() {
        let mask = UInt8(1 << max(0, min(3, playerLED - 1)))
        infoMessage = "Sending USB wake handshake…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let woken = pw_wake_all(mask)
            usleep(100_000)
            let st = pw_probe_status(0.5)
            Task { @MainActor in
                guard let self else { return }
                self.status = st
                self.onStatusChange?(st)
                if woken > 0 && st == PW_STATUS_AWAKE {
                    self.infoMessage = "Controller awake & streaming HID."
                } else if woken == 0 {
                    self.infoMessage = "No USB controller (057E:2069) found."
                } else {
                    self.infoMessage = "Wake sent; waiting for HID reports."
                }
            }
        }
    }

    func refreshStatus() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let st = pw_probe_status(0.35)
            Task { @MainActor in
                guard let self else { return }
                self.status = st
                self.onStatusChange?(st)
            }
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
            infoMessage = launchAtLogin ? "Enabled Launch at Login." : "Disabled Launch at Login."
        } catch {
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
            infoMessage = "Login item note: move PadWake.app to /Applications first."
        }
    }

    func startHIDMonitor() {
        guard !monitorActive else { return }
        monitorActive = true
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        _ = pw_hid_monitor_start({ newState, rawCtx in
            guard let rawCtx else { return }
            let model = Unmanaged<PadWakeModel>.fromOpaque(rawCtx).takeUnretainedValue()
            Task { @MainActor in
                model.inputState = newState
                if newState.connected && model.status != PW_STATUS_AWAKE {
                    model.status = PW_STATUS_AWAKE
                    model.onStatusChange?(PW_STATUS_AWAKE)
                }
            }
        }, ctx)
    }

    func stopHIDMonitor() {
        guard monitorActive else { return }
        monitorActive = false
        pw_hid_monitor_stop()
    }

    func installGameConfig() {
        let panel = NSOpenPanel()
        panel.title = "Select Game WTF Folder"
        panel.message = "Choose your game's WTF folder to install SDL2 & GamePad mappings."
        panel.prompt = "Install Mappings"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        if let savedPath = UserDefaults.standard.string(forKey: "lastConfigFolder"),
           FileManager.default.fileExists(atPath: savedPath) {
            panel.directoryURL = URL(fileURLWithPath: savedPath)
        } else {
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
        }

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        UserDefaults.standard.set(folder.path, forKey: "lastConfigFolder")

        do {
            let fm = FileManager.default
            guard let dbRes = Bundle.main.url(forResource: "gamecontrollerdb_padwake", withExtension: "txt"),
                  let jsonRes = Bundle.main.url(forResource: "GamePadConfig_PadWake", withExtension: "json") else {
                infoMessage = "Bundled mapping templates not found."
                return
            }

            // 1. Append SDL2 mapping lines idempotently into gamecontrollerdb.txt
            let dbDst = folder.appendingPathComponent("gamecontrollerdb.txt")
            let templateLines = try String(contentsOf: dbRes, encoding: .utf8)
                .components(separatedBy: .newlines)
                .filter { !$0.isEmpty && !$0.hasPrefix("#") }

            var existing = (try? String(contentsOf: dbDst, encoding: .utf8)) ?? "# SDL2 Game Controller Mappings File\n"
            var added = 0
            for line in templateLines {
                let guid = line.split(separator: ",").first.map(String.init) ?? line
                if !existing.contains("\(guid),") {
                    if !existing.hasSuffix("\n") { existing += "\n" }
                    existing += "\n\(line)\n"
                    added += 1
                }
            }
            try existing.write(to: dbDst, atomically: true, encoding: .utf8)

            // 2. Copy GamePadConfig_PadWake.json
            let jsonDst = folder.appendingPathComponent("GamePadConfig_PadWake.json")
            if fm.fileExists(atPath: jsonDst.path) {
                try fm.removeItem(at: jsonDst)
            }
            try fm.copyItem(at: jsonRes, to: jsonDst)

            // 3. Ensure SET GamePadEnable "1" in Config.wtf if present
            let cfgDst = folder.appendingPathComponent("Config.wtf")
            if fm.fileExists(atPath: cfgDst.path) {
                var cfg = try String(contentsOf: cfgDst, encoding: .utf8)
                if !cfg.contains("SET GamePadEnable ") {
                    if !cfg.hasSuffix("\n") { cfg += "\n" }
                    cfg += "SET GamePadEnable \"1\"\n"
                    try cfg.write(to: cfgDst, atomically: true, encoding: .utf8)
                }
            }

            infoMessage = added > 0
                ? "Installed mappings (\(added) SDL2 entries + JSON)."
                : "Updated GamePadConfig_PadWake.json (SDL2 already set)."
        } catch {
            infoMessage = "Install failed: \(error.localizedDescription)"
        }
    }

    private func applyMFiEnvSetting(enabled: Bool) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = enabled
            ? ["setenv", "SDL_JOYSTICK_MFI", "0"]
            : ["unsetenv", "SDL_JOYSTICK_MFI"]
        try? task.run()
    }
}

// MARK: - SwiftUI Popover View

struct StickDotView: View {
    let label: String
    let rawX: Int32
    let rawY: Int32

    private var normX: CGFloat {
        max(-1, min(1, CGFloat(rawX - 2048) / 2048.0))
    }
    private var normY: CGFloat {
        // Flip Y for screen display (4095 = Up -> -1 in SwiftUI Y)
        max(-1, min(1, -CGFloat(rawY - 2048) / 2048.0))
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(0.06))
                    .overlay(Circle().stroke(Color.primary.opacity(0.18), lineWidth: 1))
                Path { p in
                    p.move(to: CGPoint(x: 24, y: 4))
                    p.addLine(to: CGPoint(x: 24, y: 44))
                    p.move(to: CGPoint(x: 4, y: 24))
                    p.addLine(to: CGPoint(x: 44, y: 24))
                }
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.75)

                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 10, height: 10)
                    .offset(x: normX * 16, y: normY * 16)
            }
            .frame(width: 48, height: 48)

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct PopoverView: View {
    @ObservedObject var model: PadWakeModel

    private var statusColor: Color {
        switch model.status {
        case PW_STATUS_AWAKE:  return .green
        case PW_STATUS_ASLEEP: return .orange
        default:               return .secondary
        }
    }

    private var statusText: String {
        switch model.status {
        case PW_STATUS_AWAKE:  return "Awake & Streaming"
        case PW_STATUS_ASLEEP: return "Connected (Asleep)"
        default:               return "Not Connected"
        }
    }

    private var pressedButtons: [String] {
        var names: [String] = []
        for i in 0..<Int(PW_BUTTON_COUNT) {
            if (model.inputState.buttons & (1 << i)) != 0,
               let cStr = pw_button_name(Int32(i)) {
                names.append(String(cString: cStr))
            }
        }
        return names
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 10) {
                if let icon = NSApp.applicationIconImage {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("PadWake")
                        .font(.headline)
                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)
                        Text(statusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text("057E:2069")
                    .font(.system(.caption2, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }

            Divider()

            // Quick Actions
            HStack(spacing: 8) {
                Button {
                    model.wakeNow()
                } label: {
                    Label("Wake Controller", systemImage: "bolt.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }

            HStack {
                Text("Player LED")
                    .font(.subheadline)
                Spacer()
                Picker("", selection: $model.playerLED) {
                    Text("P1").tag(1)
                    Text("P2").tag(2)
                    Text("P3").tag(3)
                    Text("P4").tag(4)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
            }

            // Live Input Tester
            DisclosureGroup("Live Input Tester", isExpanded: $model.showTester) {
                VStack(spacing: 8) {
                    HStack(spacing: 24) {
                        StickDotView(label: "Left Stick", rawX: model.inputState.lx, rawY: model.inputState.ly)
                        StickDotView(label: "Right Stick", rawX: model.inputState.rx, rawY: model.inputState.ry)
                    }
                    .padding(.top, 6)

                    if pressedButtons.isEmpty {
                        Text("Press any button or move sticks…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(pressedButtons.joined(separator: "  •  "))
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .font(.subheadline)

            Divider()

            // macOS SDL2 Compatibility & Config
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $model.disableMFiVeto) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Fix macOS SDL2 MFi Veto")
                            .font(.subheadline)
                        Text("Sets SDL_JOYSTICK_MFI=0 for game launchers")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)

                Button {
                    model.installGameConfig()
                } label: {
                    Label("Install Gamepad Mappings…", systemImage: "folder.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Divider()

            // Launch at Login & Quit
            HStack {
                Toggle("Launch at Login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
                .toggleStyle(.checkbox)
                .font(.subheadline)

                Spacer()

                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            if let msg = model.infoMessage {
                Text(msg)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(14)
        .frame(width: 292)
    }
}

// MARK: - AppKit Menu Bar Host

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let model = PadWakeModel()
    private var globalClickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateStatusIcon(PW_STATUS_DISCONNECTED)

        if let btn = statusItem.button {
            btn.action = #selector(togglePopover(_:))
            btn.target = self
        }

        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: PopoverView(model: model))

        model.onStatusChange = { [weak self] st in
            self?.updateStatusIcon(st)
        }
        model.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
    }

    private func updateStatusIcon(_ status: pw_status_t) {
        guard let btn = statusItem?.button else { return }
        let symbolName = (status == PW_STATUS_AWAKE) ? "gamecontroller.fill" : "gamecontroller"
        if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: "PadWake") {
            img.isTemplate = true
            btn.image = img
        }
        btn.alphaValue = (status == PW_STATUS_DISCONNECTED) ? 0.5 : 1.0
        btn.toolTip = {
            switch status {
            case PW_STATUS_AWAKE:  return "PadWake — Controller Awake"
            case PW_STATUS_ASLEEP: return "PadWake — Controller Connected (Asleep)"
            default:               return "PadWake — Waiting for USB Gamepad"
            }
        }()
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let btn = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            model.refreshStatus()
            popover.show(relativeTo: btn.bounds, of: btn, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        model.showTester = false
    }
}

@main
struct PadWakeMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
