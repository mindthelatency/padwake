import Cocoa
import SwiftUI
import ServiceManagement

// MARK: - Game Profiles Model

enum GameProfileKind: String {
    case wowWTF
    case genericSDL2
}

enum WoWClassPreset: String, CaseIterable, Identifiable {
    case auto
    case warrior
    case paladin
    case hunter
    case rogue
    case priest
    case shaman
    case mage
    case warlock
    case druid

    var id: String { rawValue }

    var luaToken: String {
        rawValue.uppercased()
    }

    var displayName: String {
        switch self {
        case .auto:    return "Auto-detect in-game"
        case .warrior: return "Warrior"
        case .paladin: return "Paladin"
        case .hunter:  return "Hunter"
        case .rogue:   return "Rogue"
        case .priest:  return "Priest"
        case .shaman:  return "Shaman"
        case .mage:    return "Mage"
        case .warlock: return "Warlock"
        case .druid:   return "Druid"
        }
    }

    var paddleSummary: String {
        switch self {
        case .auto:
            return "Auto-detects your logged-in class · run /padwake apply in-game"
        case .warrior:
            return "0° turn · GR Pummel/Bash · GL Charge/Intercept · Victory Rush"
        case .paladin:
            return "0° turn · SoftFriend · GR HoJ · GL Cleanse · Smart Heal"
        case .hunter:
            return "115° kite · GR Feign Death · GL Pet Toggle · Combat Trap"
        case .rogue:
            return "0° turn · Stealth mirror · GR Kick · GL Stealth/Vanish"
        case .priest:
            return "115° cast · SoftFriend=3 · ZL+D-Pad Party · GR Scream · GL Shield"
        case .shaman:
            return "0° turn · SoftFriend · GR Earth Shock · GL Indoor Ghost Wolf"
        case .mage:
            return "115° kite · GR Stopcast Counterspell · GL Blink · Ice Block"
        case .warlock:
            return "115° cast · GR Stopcast Fear · GL Pet Toggle · Pet Special"
        case .druid:
            return "0° turn · SoftFriend · GR Form CC · GL Travel/Cat · Bear/HoT"
        }
    }
}

struct DetectedTarget: Identifiable, Equatable {
    var id: String { path }
    let label: String
    let path: String
    let isInstalled: Bool
}

struct GameProfile: Identifiable {
    let id: String
    let name: String
    let subtitle: String
    let filesSummary: String
    let kind: GameProfileKind
    let resourceDir: String
    let panelTitle: String
    let panelMessage: String
    let defaultSearchPath: String

    static let all: [GameProfile] = [
        GameProfile(
            id: "wow-wtf",
            name: "World of Warcraft",
            subtitle: "Forever (Classic+), Classic & Retail",
            filesSummary: "gamecontrollerdb.txt · GamePadConfig · PadWakeProfiles addon",
            kind: .wowWTF,
            resourceDir: "games/wow",
            panelTitle: "Select World of Warcraft WTF Folder",
            panelMessage: "Choose a WTF folder (e.g. _forever_/WTF, _classic_/WTF, or _retail_/WTF) to install PadWake's SDL2, GamePad, and class profiles.",
            defaultSearchPath: "/Applications/World of Warcraft"
        ),
        GameProfile(
            id: "generic-sdl2",
            name: "Generic SDL2 Game",
            subtitle: "Any game reading gamecontrollerdb.txt",
            filesSummary: "gamecontrollerdb.txt (057E:2069 mapping)",
            kind: .genericSDL2,
            resourceDir: "games/sdl2",
            panelTitle: "Select Game Folder",
            panelMessage: "Choose the folder where your game loads gamecontrollerdb.txt.",
            defaultSearchPath: "/Applications"
        )
    ]
}

struct ProfileStatusState {
    var targets: [DetectedTarget] = []
    var lastResult: String? = nil
    var lastResultIsError: Bool = false

    var installedCount: Int {
        targets.filter(\.isInstalled).count
    }
}

// MARK: - Observable Controller State

@MainActor
final class PadWakeModel: ObservableObject {
    static let shared = PadWakeModel()
    nonisolated private static let primaryGUID = "030000007e0500006920000001020000"

    @Published var status: pw_status_t = PW_STATUS_DISCONNECTED
    @Published var playerLED: Int {
        didSet {
            UserDefaults.standard.set(playerLED, forKey: "playerLED")
            let mask = UInt8(1 << max(0, min(3, playerLED - 1)))
            pw_watcher_set_led_mask(mask)
            usbQueue.async {
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
    @Published var showProfiles: Bool = false {
        didSet {
            if showProfiles {
                refreshProfileStatuses()
            }
        }
    }
    @Published var profileStates: [String: ProfileStatusState] = [:]
    @Published var selectedWoWClass: WoWClassPreset {
        didSet {
            UserDefaults.standard.set(selectedWoWClass.rawValue, forKey: "wowClassPreset")
        }
    }
    @Published var inputState = pw_input_state_t(
        connected: false, buttons: 0, lx: 2048, ly: 2048, rx: 2048, ry: 2048, report_count: 0
    )
    @Published var infoMessage: String?

    private let usbQueue = DispatchQueue(label: "com.padwake.usb", qos: .userInitiated)
    private let ioQueue = DispatchQueue(label: "com.padwake.io", qos: .utility)
    private var watcherStarted = false
    private var monitorActive = false

    var totalInstalledProfilesCount: Int {
        profileStates.values.reduce(0) { $0 + $1.installedCount }
    }

    private init() {
        let savedLED = UserDefaults.standard.integer(forKey: "playerLED")
        self.playerLED = (1...4).contains(savedLED) ? savedLED : 1

        if UserDefaults.standard.object(forKey: "disableMFiVeto") == nil {
            UserDefaults.standard.set(true, forKey: "disableMFiVeto")
        }
        self.disableMFiVeto = UserDefaults.standard.bool(forKey: "disableMFiVeto")
        let savedClass = UserDefaults.standard.string(forKey: "wowClassPreset") ?? ""
        self.selectedWoWClass = WoWClassPreset(rawValue: savedClass) ?? .auto
        self.launchAtLogin = (SMAppService.mainApp.status == .enabled)
        refreshProfileStatuses()
    }

    func start() {
        if disableMFiVeto {
            applyMFiEnvSetting(enabled: true)
        }
        guard !watcherStarted else { return }

        let mask = UInt8(1 << max(0, min(3, playerLED - 1)))
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        let started = pw_watcher_start(mask, { newStatus, rawCtx in
            guard let rawCtx else { return }
            let model = Unmanaged<PadWakeModel>.fromOpaque(rawCtx).takeUnretainedValue()
            Task { @MainActor in
                model.status = newStatus
            }
        }, ctx)
        if started {
            watcherStarted = true
        } else {
            infoMessage = "Failed to start USB hotplug watcher."
        }
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
        usbQueue.async { [weak self] in
            let woken = pw_wake_all(mask)
            usleep(100_000)
            let st = pw_probe_status(0.5)
            Task { @MainActor in
                guard let self else { return }
                self.status = st
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
        usbQueue.async { [weak self] in
            let st = pw_probe_status(0.35)
            Task { @MainActor in
                guard let self else { return }
                self.status = st
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
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        let started = pw_hid_monitor_start({ newState, rawCtx in
            guard let rawCtx else { return }
            let model = Unmanaged<PadWakeModel>.fromOpaque(rawCtx).takeUnretainedValue()
            Task { @MainActor in
                model.inputState = newState
                if newState.connected && model.status != PW_STATUS_AWAKE {
                    model.status = PW_STATUS_AWAKE
                }
            }
        }, ctx)
        if started {
            monitorActive = true
        } else {
            infoMessage = "Failed to start live HID monitor."
        }
    }

    func stopHIDMonitor() {
        guard monitorActive else { return }
        monitorActive = false
        pw_hid_monitor_stop()
    }

    // MARK: - Game Profiles Detection & Installation

    private func savedPathsKey(for profileID: String) -> String {
        "profilePaths.\(profileID)"
    }

    private func savedPaths(for profileID: String) -> [String] {
        UserDefaults.standard.stringArray(forKey: savedPathsKey(for: profileID)) ?? []
    }

    private func rememberPath(_ path: String, for profileID: String) {
        var paths = savedPaths(for: profileID)
        if !paths.contains(path) {
            paths.append(path)
            UserDefaults.standard.set(paths, forKey: savedPathsKey(for: profileID))
        }
    }

    nonisolated private static func readTextPreservingEncoding(at url: URL) throws -> String {
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            return try String(contentsOf: url, encoding: .isoLatin1)
        }
    }

    nonisolated private static func containsMapping(guid: String, in text: String) -> Bool {
        let prefix = "\(guid),"
        for line in text.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline) {
            let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
            if trimmed.hasPrefix("#") { continue }
            if trimmed.hasPrefix(prefix) { return true }
        }
        return false
    }

    nonisolated private static func checkInstalled(profile: GameProfile, folder: URL) -> Bool {
        let fm = FileManager.default
        let dbURL = folder.appendingPathComponent("gamecontrollerdb.txt")
        guard let dbText = try? readTextPreservingEncoding(at: dbURL),
              containsMapping(guid: primaryGUID, in: dbText) else {
            return false
        }
        switch profile.kind {
        case .wowWTF:
            let jsonURL = folder.appendingPathComponent("GamePadConfig_PadWake.json")
            return fm.fileExists(atPath: jsonURL.path)
        case .genericSDL2:
            return true
        }
    }

    nonisolated private static func displayLabel(for folder: URL, kind: GameProfileKind) -> String {
        switch kind {
        case .wowWTF:
            let name = folder.lastPathComponent
            let parent = folder.deletingLastPathComponent().lastPathComponent
            if name == "WTF" && !parent.isEmpty {
                return "\(parent)/WTF"
            }
            return name
        case .genericSDL2:
            return folder.lastPathComponent
        }
    }

    func refreshProfileStatuses() {
        let savedSnapshot: [String: [String]] = Dictionary(
            uniqueKeysWithValues: GameProfile.all.map { ($0.id, savedPaths(for: $0.id)) }
        )

        ioQueue.async { [weak self] in
            let fm = FileManager.default
            var scanned: [String: [DetectedTarget]] = [:]

            for profile in GameProfile.all {
                var seen = Set<String>()
                var targets: [DetectedTarget] = []

                func appendIfDir(_ path: String) {
                    let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
                    guard !seen.contains(normalized) else { return }
                    var isDir: ObjCBool = false
                    guard fm.fileExists(atPath: normalized, isDirectory: &isDir), isDir.boolValue else { return }
                    seen.insert(normalized)
                    let url = URL(fileURLWithPath: normalized)
                    targets.append(DetectedTarget(
                        label: Self.displayLabel(for: url, kind: profile.kind),
                        path: normalized,
                        isInstalled: Self.checkInstalled(profile: profile, folder: url)
                    ))
                }

                // Auto-detect standard WoW flavors under /Applications/World of Warcraft/*/WTF
                if profile.kind == .wowWTF {
                    let wowBase = URL(fileURLWithPath: profile.defaultSearchPath)
                    if let entries = try? fm.contentsOfDirectory(
                        at: wowBase, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
                    ) {
                        let sorted = entries.sorted { $0.lastPathComponent < $1.lastPathComponent }
                        for entry in sorted {
                            let wtf = entry.appendingPathComponent("WTF")
                            appendIfDir(wtf.path)
                        }
                    }
                }

                // Include any user-selected custom paths saved previously
                for saved in savedSnapshot[profile.id] ?? [] {
                    appendIfDir(saved)
                }

                scanned[profile.id] = targets
            }

            Task { @MainActor in
                guard let self else { return }
                for (profileID, targets) in scanned {
                    var existing = self.profileStates[profileID] ?? ProfileStatusState()
                    existing.targets = targets
                    self.profileStates[profileID] = existing
                }
            }
        }
    }

    func chooseFolderAndInstall(profile: GameProfile) {
        let panel = NSOpenPanel()
        panel.title = profile.panelTitle
        panel.message = profile.panelMessage
        panel.prompt = "Install Profile"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        let fm = FileManager.default
        if let last = savedPaths(for: profile.id).last, fm.fileExists(atPath: last) {
            panel.directoryURL = URL(fileURLWithPath: last)
        } else if fm.fileExists(atPath: profile.defaultSearchPath) {
            panel.directoryURL = URL(fileURLWithPath: profile.defaultSearchPath)
        } else {
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
        }

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, var folder = panel.url else { return }

        // If user picked a WoW flavor folder (e.g. _forever_) instead of _forever_/WTF, step into WTF/
        if profile.kind == .wowWTF && folder.lastPathComponent != "WTF" {
            let nestedWTF = folder.appendingPathComponent("WTF")
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: nestedWTF.path, isDirectory: &isDir), isDir.boolValue {
                folder = nestedWTF
            }
        }

        install(profile: profile, into: folder)
    }

    func install(profile: GameProfile, into folder: URL) {
        let fm = FileManager.default
        var state = profileStates[profile.id] ?? ProfileStatusState()

        do {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: folder.path, isDirectory: &isDir), isDir.boolValue else {
                state.lastResult = "Selected target is not an accessible directory."
                state.lastResultIsError = true
                profileStates[profile.id] = state
                return
            }

            let dbRes = Bundle.main.url(
                forResource: "gamecontrollerdb_padwake", withExtension: "txt", subdirectory: profile.resourceDir
            ) ?? Bundle.main.url(
                forResource: "gamecontrollerdb_padwake", withExtension: "txt", subdirectory: "games/sdl2"
            )
            guard let dbRes else {
                state.lastResult = "Bundled SDL2 mapping template missing."
                state.lastResultIsError = true
                profileStates[profile.id] = state
                return
            }

            var actions: [String] = []

            // 1. Append SDL2 mapping lines idempotently into gamecontrollerdb.txt without clobbering existing data
            let dbDst = folder.appendingPathComponent("gamecontrollerdb.txt")
            let templateLines = try String(contentsOf: dbRes, encoding: .utf8)
                .components(separatedBy: .newlines)
                .filter { !$0.isEmpty && !$0.hasPrefix("#") }

            var existing: String
            if fm.fileExists(atPath: dbDst.path) {
                existing = try Self.readTextPreservingEncoding(at: dbDst)
            } else {
                existing = "# SDL2 Game Controller Mappings File\n"
            }

            var added = 0
            for line in templateLines {
                let guid = line.split(separator: ",").first.map(String.init) ?? line
                if !Self.containsMapping(guid: guid, in: existing) {
                    if !existing.hasSuffix("\n") { existing += "\n" }
                    existing += "\n\(line)\n"
                    added += 1
                }
            }
            if added > 0 || !fm.fileExists(atPath: dbDst.path) {
                try existing.write(to: dbDst, atomically: true, encoding: .utf8)
            }
            actions.append(added > 0 ? "gamecontrollerdb.txt (+\(added))" : "gamecontrollerdb.txt (up to date)")

            // 2. WoW-specific config files
            if profile.kind == .wowWTF {
                guard let jsonRes = Bundle.main.url(
                    forResource: "GamePadConfig_PadWake", withExtension: "json", subdirectory: profile.resourceDir
                ) else {
                    state.lastResult = "Bundled GamePadConfig JSON missing."
                    state.lastResultIsError = true
                    profileStates[profile.id] = state
                    return
                }
                let jsonDst = folder.appendingPathComponent("GamePadConfig_PadWake.json")
                let jsonData = try Data(contentsOf: jsonRes)
                try jsonData.write(to: jsonDst, options: [.atomic])
                actions.append("GamePadConfig_PadWake.json")

                let cfgDst = folder.appendingPathComponent("Config.wtf")
                if fm.fileExists(atPath: cfgDst.path) {
                    var cfg = try Self.readTextPreservingEncoding(at: cfgDst)
                    if !cfg.contains("SET GamePadEnable ") {
                        if !cfg.hasSuffix("\n") { cfg += "\n" }
                        cfg += "SET GamePadEnable \"1\"\n"
                        try cfg.write(to: cfgDst, atomically: true, encoding: .utf8)
                        actions.append("Config.wtf (GamePadEnable=1)")
                    }
                }

                // 3. Install/update lightweight PadWakeProfiles companion addon (sibling Interface/AddOns)
                if let addonSrc = Bundle.main.resourceURL?.appendingPathComponent("games/wow/AddOns/PadWakeProfiles"),
                   fm.fileExists(atPath: addonSrc.path) {
                    let flavorRoot = folder.lastPathComponent == "WTF"
                        ? folder.deletingLastPathComponent()
                        : folder
                    let addonDst = flavorRoot
                        .appendingPathComponent("Interface")
                        .appendingPathComponent("AddOns")
                        .appendingPathComponent("PadWakeProfiles")
                    try fm.createDirectory(at: addonDst, withIntermediateDirectories: true)

                    for fileName in ["PadWakeProfiles.toc", "PadWakeProfiles.lua"] {
                        let srcFile = addonSrc.appendingPathComponent(fileName)
                        let dstFile = addonDst.appendingPathComponent(fileName)
                        let fileData = try Data(contentsOf: srcFile)
                        try fileData.write(to: dstFile, options: [.atomic])
                    }

                    // Strictly whitelisted Lua token from WoWClassPreset enum
                    let presetLua = """
                    -- Updated automatically by PadWake.app
                    local _, ns = ...
                    ns.selectedPreset = "\(selectedWoWClass.luaToken)"
                    """ + "\n"
                    let presetDst = addonDst.appendingPathComponent("SelectedPreset.lua")
                    try presetLua.write(to: presetDst, atomically: true, encoding: .utf8)
                    actions.append("PadWakeProfiles (\(selectedWoWClass.displayName))")
                }
            }

            rememberPath(folder.standardizedFileURL.path, for: profile.id)
            let label = Self.displayLabel(for: folder, kind: profile.kind)
            state.lastResult = "\(label): " + actions.joined(separator: ", ")
            state.lastResultIsError = false
            profileStates[profile.id] = state
            refreshProfileStatuses()
            if profile.kind == .wowWTF {
                infoMessage = "Installed into \(label). Run /padwake apply in-game."
            } else {
                infoMessage = "Installed \(profile.name) profile into \(label)."
            }
        } catch {
            state.lastResult = "Install failed: \(error.localizedDescription)"
            state.lastResultIsError = true
            profileStates[profile.id] = state
            infoMessage = state.lastResult
        }
    }

    private func applyMFiEnvSetting(enabled: Bool) {
        let args = enabled
            ? ["setenv", "SDL_JOYSTICK_MFI", "0"]
            : ["unsetenv", "SDL_JOYSTICK_MFI"]
        ioQueue.async { [weak self] in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            task.arguments = args
            task.standardInput = FileHandle.nullDevice
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            do {
                try task.run()
                task.waitUntilExit()
                if task.terminationStatus != 0 {
                    let status = task.terminationStatus
                    Task { @MainActor in
                        self?.infoMessage = "launchctl exited with status \(status) updating SDL_JOYSTICK_MFI."
                    }
                }
            } catch {
                let msg = error.localizedDescription
                Task { @MainActor in
                    self?.infoMessage = "Failed to update SDL_JOYSTICK_MFI: \(msg)"
                }
            }
        }
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

struct GameProfileRowView: View {
    let profile: GameProfile
    let state: ProfileStatusState
    let wowClassSelection: Binding<WoWClassPreset>?
    let onInstallTarget: (DetectedTarget) -> Void
    let onChooseFolder: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(profile.name)
                        .font(.caption.weight(.semibold))
                    Text(profile.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if state.installedCount > 0 {
                    Label("Installed", systemImage: "checkmark.circle.fill")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.green)
                        .labelStyle(.titleAndIcon)
                } else {
                    Text("Not installed")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Text(profile.filesSummary)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let classBinding = wowClassSelection {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("Class Preset")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Picker("", selection: classBinding) {
                            ForEach(WoWClassPreset.allCases) { preset in
                                Text(preset.displayName).tag(preset)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .controlSize(.mini)
                    }
                    Text(classBinding.wrappedValue.paddleSummary)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
            }

            if !state.targets.isEmpty {
                VStack(spacing: 4) {
                    ForEach(state.targets) { target in
                        HStack(spacing: 6) {
                            Image(systemName: target.isInstalled ? "checkmark.circle.fill" : "folder")
                                .font(.caption2)
                                .foregroundStyle(target.isInstalled ? Color.green : Color.secondary)
                            Text(target.label)
                                .font(.caption2.monospaced())
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button(target.isInstalled ? "Update" : "Install") {
                                onInstallTarget(target)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }
                    }
                }
                .padding(.top, 2)
            }

            HStack {
                Button {
                    onChooseFolder()
                } label: {
                    Label(state.targets.isEmpty ? "Choose Folder…" : "Other Folder…", systemImage: "folder.badge.plus")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                Spacer()
            }

            if let result = state.lastResult {
                Text(result)
                    .font(.caption2)
                    .foregroundStyle(state.lastResultIsError ? Color.red : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.045))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.75)
        )
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
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

            // macOS SDL2 Compatibility & Game Profiles
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

                DisclosureGroup(isExpanded: $model.showProfiles) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(GameProfile.all) { profile in
                            let st = model.profileStates[profile.id] ?? ProfileStatusState()
                            GameProfileRowView(
                                profile: profile,
                                state: st,
                                wowClassSelection: profile.kind == .wowWTF ? $model.selectedWoWClass : nil,
                                onInstallTarget: { target in
                                    model.install(profile: profile, into: URL(fileURLWithPath: target.path))
                                },
                                onChooseFolder: {
                                    model.chooseFolderAndInstall(profile: profile)
                                }
                            )
                        }
                    }
                    .padding(.top, 6)
                } label: {
                    HStack {
                        Text("Game Profiles")
                        Spacer()
                        if model.totalInstalledProfilesCount > 0 {
                            Text("\(model.totalInstalledProfilesCount) installed")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        } else {
                            Text("WoW · SDL2")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .font(.subheadline)
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
        .frame(width: 316)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - App Lifecycle & Native MenuBarExtra Host

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var rightClickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        PadWakeModel.shared.start()
        installStatusBarRightClickMenu()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = rightClickMonitor {
            NSEvent.removeMonitor(monitor)
            rightClickMonitor = nil
        }
        PadWakeModel.shared.stop()
    }

    private func installStatusBarRightClickMenu() {
        rightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
            let isContextClick = (event.type == .rightMouseDown) ||
                (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
            guard isContextClick, let win = event.window else {
                return event
            }
            let isStatusBarWindow = (win.level == .statusBar) ||
                String(describing: type(of: win)).contains("StatusBar")
            guard isStatusBarWindow else {
                return event
            }

            DispatchQueue.main.async {
                self?.showContextMenu(in: win)
            }
            return nil
        }
    }

    private func showContextMenu(in statusWindow: NSWindow) {
        guard let view = statusWindow.contentView else { return }

        let menu = NSMenu(title: "PadWake")

        let statusText: String = {
            switch PadWakeModel.shared.status {
            case PW_STATUS_AWAKE:  return "PadWake — Awake & Streaming"
            case PW_STATUS_ASLEEP: return "PadWake — Connected (Asleep)"
            default:               return "PadWake — Not Connected"
            }
        }()
        let statusItem = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        menu.addItem(.separator())

        let wakeItem = NSMenuItem(title: "Wake Controller", action: #selector(menuWakeController), keyEquivalent: "")
        wakeItem.target = self
        menu.addItem(wakeItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit PadWake", action: #selector(menuQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        let y: CGFloat = view.isFlipped ? (view.bounds.maxY + 4) : -4
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: y), in: view)
    }

    @objc private func menuWakeController() {
        PadWakeModel.shared.wakeNow()
    }

    @objc private func menuQuit() {
        NSApp.terminate(nil)
    }
}

@main
struct PadWakeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var model = PadWakeModel.shared

    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: model)
                .onAppear {
                    model.refreshStatus()
                    model.refreshProfileStatuses()
                }
                .onDisappear {
                    model.showTester = false
                }
        } label: {
            Image(systemName: model.status == PW_STATUS_AWAKE ? "gamecontroller.fill" : "gamecontroller")
                .accessibilityLabel("PadWake")
        }
        .menuBarExtraStyle(.window)
    }
}
