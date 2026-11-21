import Cocoa
import SwiftUI
import ServiceManagement

// MARK: - World of Warcraft Setup Model

enum WoWClassPreset: String, CaseIterable, Identifiable {
    case auto
    case warrior
    case paladin
    case hunter
    case rogue
    case priest
    case deathknight
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
        case .auto:        return "Auto-detect in-game"
        case .warrior:     return "Warrior"
        case .paladin:     return "Paladin"
        case .hunter:      return "Hunter"
        case .rogue:       return "Rogue"
        case .priest:      return "Priest"
        case .deathknight: return "Death Knight (Classic)"
        case .shaman:      return "Shaman"
        case .mage:        return "Mage"
        case .warlock:     return "Warlock"
        case .druid:       return "Druid"
        }
    }

    var paddleSummary: String {
        switch self {
        case .auto:
            return "Auto-detects class & spec · run /padwake apply in-game"
        case .warrior:
            return "0° turn · GR Pummel/Bash · GL Charge/Intercept · Victory Rush"
        case .paladin:
            return "0° turn · SoftFriend · GR HoJ · GL Cleanse · Smart Heal"
        case .hunter:
            return "115° kite · GR Feign Death · GL Pet Toggle · Combat Trap"
        case .rogue:
            return "0° turn · Stealth ZR bar · GR Kick · GL Stealth/Vanish"
        case .priest:
            return "115° cast · SoftFriend=3 · GR Scream · GL Shield · Smart Heal"
        case .deathknight:
            return "0° turn · GR Mind Freeze · GL Death Grip · AMS / Death Strike"
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

struct DetectedWoWTarget: Identifiable, Equatable {
    var id: String { path }
    let flavorName: String
    let label: String
    let path: String
    let isForever: Bool
    let isClassic: Bool
    let isConfigured: Bool
    let hasDialogueUI: Bool
    let dialogueUISwitchMode: Bool
}

struct WoWSetupState {
    var targets: [DetectedWoWTarget] = []
    var selectedPath: String? = nil
    var lastResult: String? = nil
    var lastResultIsError: Bool = false

    var primaryTarget: DetectedWoWTarget? {
        if let selectedPath, let match = targets.first(where: { $0.path == selectedPath }) {
            return match
        }
        return targets.first(where: \.isForever)
            ?? targets.first(where: \.isClassic)
            ?? targets.first
    }

    var configuredCount: Int {
        targets.filter(\.isConfigured).count
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
    @Published var showWoWOptions: Bool = false {
        didSet {
            if showWoWOptions {
                refreshWoWStatus()
            }
        }
    }
    @Published var wowState = WoWSetupState()
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
        refreshWoWStatus()
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

    // MARK: - World of Warcraft Detection & Installation

    nonisolated private static let defaultWoWPath = "/Applications/World of Warcraft"
    private static let savedWoWPathsKey = "profilePaths.wow-wtf"

    private func savedWoWPaths() -> [String] {
        UserDefaults.standard.stringArray(forKey: Self.savedWoWPathsKey) ?? []
    }

    private func rememberWoWPath(_ path: String) {
        var paths = savedWoWPaths()
        if !paths.contains(path) {
            paths.append(path)
            UserDefaults.standard.set(paths, forKey: Self.savedWoWPathsKey)
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

    nonisolated private static func flavorRoot(for wtfFolder: URL) -> URL {
        wtfFolder.lastPathComponent == "WTF" ? wtfFolder.deletingLastPathComponent() : wtfFolder
    }

    nonisolated private static let knownFlavorNames: [String: String] = [
        "_forever_":         "WoW: Forever",
        "_classic_era_":     "WoW Classic Era",
        "_anniversary_":     "WoW Classic Anniversary",
        "_classic_":         "WoW Classic",
        "_classic_ptr_":     "WoW Classic PTR",
        "_classic_era_ptr_": "WoW Classic Era PTR",
        "_classic_beta_":    "WoW Classic Beta",
        "_retail_":          "WoW Retail",
        "_ptr_":             "WoW PTR",
        "_xptr_":            "WoW PTR",
    ]

    nonisolated private static let flavorPriority: [String] = [
        "_forever_",
        "_classic_era_",
        "_anniversary_",
        "_classic_",
        "_classic_ptr_",
        "_classic_era_ptr_",
        "_classic_beta_",
        "_retail_",
    ]

    nonisolated private static func flavorKey(for folder: URL) -> String {
        let root = flavorRoot(for: folder)
        return root.lastPathComponent
    }

    nonisolated private static func friendlyFlavorName(for folder: URL) -> String {
        let key = flavorKey(for: folder)
        return knownFlavorNames[key] ?? displayLabel(for: folder)
    }

    nonisolated private static func inspectWoWTarget(folder: URL) -> DetectedWoWTarget {
        let fm = FileManager.default
        let root = flavorRoot(for: folder)
        let dbURL = folder.appendingPathComponent("gamecontrollerdb.txt")
        let jsonURL = folder.appendingPathComponent("GamePadConfig_PadWake.json")
        let addonURL = root
            .appendingPathComponent("Interface")
            .appendingPathComponent("AddOns")
            .appendingPathComponent("PadWakeProfiles")
            .appendingPathComponent("PadWakeProfiles.lua")

        let hasDB = (try? readTextPreservingEncoding(at: dbURL))
            .map { containsMapping(guid: primaryGUID, in: $0) } ?? false
        let isConfigured = hasDB
            && fm.fileExists(atPath: jsonURL.path)
            && fm.fileExists(atPath: addonURL.path)

        let dialogueAddonDir = root
            .appendingPathComponent("Interface")
            .appendingPathComponent("AddOns")
            .appendingPathComponent("DialogueUI")
        let hasDialogueUI = fm.fileExists(atPath: dialogueAddonDir.path)

        var dialogueSwitch = false
        if hasDialogueUI {
            let accountDir = folder.appendingPathComponent("Account")
            if let accounts = try? fm.contentsOfDirectory(
                at: accountDir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
            ) {
                for acct in accounts {
                    let sv = acct
                        .appendingPathComponent("SavedVariables")
                        .appendingPathComponent("DialogueUI.lua")
                    if let txt = try? readTextPreservingEncoding(at: sv),
                       txt.contains("[\"InputDevice\"] = 4") {
                        dialogueSwitch = true
                        break
                    }
                }
            }
        }

        let key = flavorKey(for: folder)
        let label = displayLabel(for: folder)
        return DetectedWoWTarget(
            flavorName: friendlyFlavorName(for: folder),
            label: label,
            path: folder.standardizedFileURL.path,
            isForever: key == "_forever_",
            isClassic: key.contains("classic") || key == "_anniversary_",
            isConfigured: isConfigured,
            hasDialogueUI: hasDialogueUI,
            dialogueUISwitchMode: dialogueSwitch
        )
    }

    nonisolated private static func displayLabel(for folder: URL) -> String {
        let name = folder.lastPathComponent
        let parent = folder.deletingLastPathComponent().lastPathComponent
        if name == "WTF" && !parent.isEmpty {
            return "\(parent)/WTF"
        }
        return name
    }

    func refreshWoWStatus() {
        let savedSnapshot = savedWoWPaths()

        ioQueue.async { [weak self] in
            let fm = FileManager.default
            var seen = Set<String>()
            var targets: [DetectedWoWTarget] = []

            func appendTarget(_ path: String, allowMissingWTF: Bool = false) {
                let url = URL(fileURLWithPath: path).standardizedFileURL
                let normalized = url.path
                guard !seen.contains(normalized) else { return }
                var isDir: ObjCBool = false
                let exists = fm.fileExists(atPath: normalized, isDirectory: &isDir) && isDir.boolValue
                if !exists {
                    guard allowMissingWTF else { return }
                    let parentPath = url.deletingLastPathComponent().path
                    var parentIsDir: ObjCBool = false
                    guard fm.fileExists(atPath: parentPath, isDirectory: &parentIsDir), parentIsDir.boolValue else {
                        return
                    }
                }
                seen.insert(normalized)
                targets.append(Self.inspectWoWTarget(folder: url))
            }

            // Auto-detect all WoW flavors (Forever, Classic Era, Anniversary, Classic, Retail)
            let candidateBases = [
                URL(fileURLWithPath: Self.defaultWoWPath),
                URL(fileURLWithPath: "/Applications/World of Warcraft Classic"),
            ]
            for wowBase in candidateBases {
                if let entries = try? fm.contentsOfDirectory(
                    at: wowBase, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
                ) {
                    let sorted = entries.sorted { a, b in
                        let ai = Self.flavorPriority.firstIndex(of: a.lastPathComponent) ?? Int.max
                        let bi = Self.flavorPriority.firstIndex(of: b.lastPathComponent) ?? Int.max
                        if ai != bi { return ai < bi }
                        return a.lastPathComponent < b.lastPathComponent
                    }
                    for entry in sorted {
                        let key = entry.lastPathComponent
                        let wtfPath = entry.appendingPathComponent("WTF").path
                        let isKnownFlavor = Self.knownFlavorNames[key] != nil
                        appendTarget(wtfPath, allowMissingWTF: isKnownFlavor)
                    }
                }
            }

            for saved in savedSnapshot {
                appendTarget(saved, allowMissingWTF: false)
            }

            Task { @MainActor in
                guard let self else { return }
                self.wowState.targets = targets
                if let sel = self.wowState.selectedPath, !targets.contains(where: { $0.path == sel }) {
                    self.wowState.selectedPath = nil
                }
            }
        }
    }

    func chooseWoWFolderAndInstall() {
        let panel = NSOpenPanel()
        panel.title = "Select World of Warcraft Folder"
        panel.message = "Choose a WoW flavor folder (_forever_, _classic_era_, _classic_, _anniversary_, or _retail_) or its WTF folder."
        panel.prompt = "Install"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        let fm = FileManager.default
        if let last = savedWoWPaths().last, fm.fileExists(atPath: last) {
            panel.directoryURL = URL(fileURLWithPath: last)
        } else if fm.fileExists(atPath: Self.defaultWoWPath) {
            panel.directoryURL = URL(fileURLWithPath: Self.defaultWoWPath)
        } else {
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
        }

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, var folder = panel.url else { return }

        if folder.lastPathComponent != "WTF" {
            let nestedWTF = folder.appendingPathComponent("WTF")
            if Self.knownFlavorNames[folder.lastPathComponent] != nil
                || fm.fileExists(atPath: nestedWTF.path) {
                folder = nestedWTF
            }
        }

        wowState.selectedPath = folder.standardizedFileURL.path
        installWoW(into: folder)
    }

    func installWoW(into folder: URL) {
        let fm = FileManager.default

        do {
            let root = Self.flavorRoot(for: folder)
            var rootIsDir: ObjCBool = false
            guard fm.fileExists(atPath: root.path, isDirectory: &rootIsDir), rootIsDir.boolValue else {
                wowState.lastResult = "Selected WoW folder is not accessible."
                wowState.lastResultIsError = true
                return
            }
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)

            guard let dbRes = Bundle.main.url(
                forResource: "gamecontrollerdb_padwake", withExtension: "txt", subdirectory: "games/sdl2"
            ) else {
                wowState.lastResult = "Bundled SDL2 mapping template missing."
                wowState.lastResultIsError = true
                return
            }

            var actions: [String] = []

            // 1. Upsert Switch 2 SDL2 mapping lines idempotently into gamecontrollerdb.txt
            let dbDst = folder.appendingPathComponent("gamecontrollerdb.txt")
            let templateLines = try String(contentsOf: dbRes, encoding: .utf8)
                .components(separatedBy: .newlines)
                .filter { !$0.isEmpty && !$0.hasPrefix("#") }

            let dbExisted = fm.fileExists(atPath: dbDst.path)
            let existing = dbExisted
                ? try Self.readTextPreservingEncoding(at: dbDst)
                : "# SDL2 Game Controller Mappings File\n"

            var lines = existing.components(separatedBy: "\n")
            var added = 0
            var updated = 0
            for tpl in templateLines {
                let guid = tpl.split(separator: ",").first.map(String.init) ?? tpl
                let prefix = "\(guid),"
                if let idx = lines.firstIndex(where: {
                    let trimmed = $0.drop(while: { $0 == " " || $0 == "\t" })
                    return !trimmed.hasPrefix("#") && trimmed.hasPrefix(prefix)
                }) {
                    if lines[idx].trimmingCharacters(in: .whitespacesAndNewlines) != tpl {
                        lines[idx] = tpl
                        updated += 1
                    }
                } else {
                    if let last = lines.last, !last.isEmpty {
                        lines.append("")
                    }
                    lines.append(tpl)
                    added += 1
                }
            }
            if added > 0 || updated > 0 || !dbExisted {
                var out = lines.joined(separator: "\n")
                if !out.hasSuffix("\n") { out += "\n" }
                try out.write(to: dbDst, atomically: true, encoding: .utf8)
            }
            if added > 0 || updated > 0 {
                let parts = [added > 0 ? "+\(added)" : nil, updated > 0 ? "~\(updated)" : nil].compactMap { $0 }
                actions.append("gamecontrollerdb.txt (\(parts.joined(separator: ", ")))")
            } else {
                actions.append("gamecontrollerdb.txt")
            }

            // 2. GamePadConfig_PadWake.json + Config.wtf
            guard let jsonRes = Bundle.main.url(
                forResource: "GamePadConfig_PadWake", withExtension: "json", subdirectory: "games/wow"
            ) else {
                wowState.lastResult = "Bundled GamePadConfig JSON missing."
                wowState.lastResultIsError = true
                return
            }
            let jsonDst = folder.appendingPathComponent("GamePadConfig_PadWake.json")
            let jsonData = try Data(contentsOf: jsonRes)
            try jsonData.write(to: jsonDst, options: [.atomic])
            let legacyJsonDst = folder.appendingPathComponent("GamePadConfig_Switch2.json")
            if fm.fileExists(atPath: legacyJsonDst.path) {
                try? fm.removeItem(at: legacyJsonDst)
            }
            actions.append("GamePadConfig")

            let cfgDst = folder.appendingPathComponent("Config.wtf")
            if fm.fileExists(atPath: cfgDst.path) {
                var cfg = try Self.readTextPreservingEncoding(at: cfgDst)
                if !cfg.contains("SET GamePadEnable ") {
                    if !cfg.hasSuffix("\n") { cfg += "\n" }
                    cfg += "SET GamePadEnable \"1\"\n"
                    try cfg.write(to: cfgDst, atomically: true, encoding: .utf8)
                }
            }

            // 3. Install/update lightweight PadWakeProfiles companion addon
            if let addonSrc = Bundle.main.resourceURL?.appendingPathComponent("games/wow/AddOns/PadWakeProfiles"),
               fm.fileExists(atPath: addonSrc.path) {
                let root = Self.flavorRoot(for: folder)
                let addonDst = root
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

                let presetLua = """
                -- Updated automatically by PadWake.app
                local _, ns = ...
                ns.selectedPreset = "\(selectedWoWClass.luaToken)"
                """ + "\n"
                let presetDst = addonDst.appendingPathComponent("SelectedPreset.lua")
                try presetLua.write(to: presetDst, atomically: true, encoding: .utf8)
                actions.append("PadWakeProfiles (\(selectedWoWClass.displayName))")
            }

            rememberWoWPath(folder.standardizedFileURL.path)
            let label = Self.displayLabel(for: folder)
            wowState.lastResult = "\(label): " + actions.joined(separator: " · ")
            wowState.lastResultIsError = false
            refreshWoWStatus()
            infoMessage = "Ready in \(label). Run /padwake apply in-game."
        } catch {
            wowState.lastResult = "Setup failed: \(error.localizedDescription)"
            wowState.lastResultIsError = true
            infoMessage = wowState.lastResult
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
    var clicked: Bool = false

    private var normX: CGFloat {
        max(-1, min(1, CGFloat(rawX - 2048) / 2048.0))
    }
    private var normY: CGFloat {
        // Flip Y for screen display (4095 = Up -> -1 in SwiftUI Y)
        max(-1, min(1, -CGFloat(rawY - 2048) / 2048.0))
    }

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .fill(clicked ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.06))
                    .overlay(
                        Circle().stroke(
                            clicked ? Color.accentColor : Color.primary.opacity(0.18),
                            lineWidth: clicked ? 1.5 : 1
                        )
                    )
                Path { p in
                    p.move(to: CGPoint(x: 22, y: 4))
                    p.addLine(to: CGPoint(x: 22, y: 40))
                    p.move(to: CGPoint(x: 4, y: 22))
                    p.addLine(to: CGPoint(x: 40, y: 22))
                }
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.75)

                Circle()
                    .fill(Color.accentColor)
                    .frame(width: clicked ? 11 : 9, height: clicked ? 11 : 9)
                    .offset(x: normX * 14, y: normY * 14)
            }
            .frame(width: 44, height: 44)

            Text(label)
                .font(.system(size: 9, weight: clicked ? .bold : .medium, design: .rounded))
                .foregroundStyle(clicked ? Color.accentColor : .secondary)
        }
    }
}

struct TesterPillView: View {
    let label: String
    let active: Bool
    var minWidth: CGFloat = 22
    var height: CGFloat = 18

    var body: some View {
        Text(label)
            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
            .foregroundStyle(active ? Color.white : Color.primary.opacity(0.8))
            .frame(minWidth: minWidth, minHeight: height)
            .padding(.horizontal, 4)
            .background(active ? Color.accentColor : Color.primary.opacity(0.07))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(active ? Color.accentColor : Color.primary.opacity(0.14), lineWidth: 0.75)
            )
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

struct TesterFaceButtonView: View {
    let label: String
    let active: Bool

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(active ? Color.white : Color.primary.opacity(0.85))
            .frame(width: 20, height: 20)
            .background(active ? Color.accentColor : Color.primary.opacity(0.08))
            .overlay(
                Circle().stroke(active ? Color.accentColor : Color.primary.opacity(0.18), lineWidth: 0.9)
            )
            .clipShape(Circle())
    }
}

struct TesterDPadKeyView: View {
    let symbol: String
    let active: Bool

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 8.5, weight: .bold))
            .foregroundStyle(active ? Color.white : Color.primary.opacity(0.75))
            .frame(width: 17, height: 17)
            .background(active ? Color.accentColor : Color.primary.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .stroke(active ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: 0.75)
            )
            .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
    }
}

struct Switch2VisualTesterView: View {
    let input: pw_input_state_t
    let pressedButtons: [String]

    private func isPressed(_ bit: Int) -> Bool {
        (input.buttons & (1 << bit)) != 0
    }

    var body: some View {
        VStack(spacing: 8) {
            // Top Row: Triggers, Shoulders & Center System Buttons
            HStack(spacing: 4) {
                HStack(spacing: 3) {
                    TesterPillView(label: "ZL", active: isPressed(13), minWidth: 22)
                    TesterPillView(label: "L", active: isPressed(12), minWidth: 18)
                }
                Spacer(minLength: 2)
                HStack(spacing: 3) {
                    TesterPillView(label: "−", active: isPressed(14), minWidth: 16)
                    TesterPillView(label: "Cap", active: isPressed(17), minWidth: 24)
                    Image(systemName: "house.fill")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(isPressed(16) ? Color.white : Color.primary.opacity(0.8))
                        .frame(width: 20, height: 18)
                        .background(isPressed(16) ? Color.accentColor : Color.primary.opacity(0.07))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .stroke(isPressed(16) ? Color.accentColor : Color.primary.opacity(0.14), lineWidth: 0.75)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    TesterPillView(label: "C", active: isPressed(20), minWidth: 18)
                    TesterPillView(label: "+", active: isPressed(6), minWidth: 16)
                }
                Spacer(minLength: 2)
                HStack(spacing: 3) {
                    TesterPillView(label: "R", active: isPressed(4), minWidth: 18)
                    TesterPillView(label: "ZR", active: isPressed(5), minWidth: 22)
                }
            }

            // Middle Row: D-Pad · L3/R3 Analog Sticks · Switch 2 Face Diamond (X Top, Y Left, A Right, B Bottom)
            HStack(alignment: .center, spacing: 8) {
                // D-Pad Cross
                VStack(spacing: 2) {
                    TesterDPadKeyView(symbol: "chevron.up", active: isPressed(11))
                    HStack(spacing: 2) {
                        TesterDPadKeyView(symbol: "chevron.left", active: isPressed(10))
                        Color.clear.frame(width: 15, height: 15)
                        TesterDPadKeyView(symbol: "chevron.right", active: isPressed(9))
                    }
                    TesterDPadKeyView(symbol: "chevron.down", active: isPressed(8))
                }
                .frame(width: 55)

                Spacer(minLength: 2)

                // Dual Sticks with L3 / R3 Click Highlight
                HStack(spacing: 10) {
                    StickDotView(label: "L3", rawX: input.lx, rawY: input.ly, clicked: isPressed(15))
                    StickDotView(label: "R3", rawX: input.rx, rawY: input.ry, clicked: isPressed(7))
                }

                Spacer(minLength: 2)

                // Switch 2 Diamond: X Top (b3), Y Left (b2), A Right (b1), B Bottom (b0)
                VStack(spacing: 1) {
                    TesterFaceButtonView(label: "X", active: isPressed(3))
                    HStack(spacing: 16) {
                        TesterFaceButtonView(label: "Y", active: isPressed(2))
                        TesterFaceButtonView(label: "A", active: isPressed(1))
                    }
                    TesterFaceButtonView(label: "B", active: isPressed(0))
                }
                .frame(width: 60)
            }

            // Bottom Row: Rear Grip Paddles (GL = b19, GR = b18)
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Text("GL")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                    Text("Rear Left")
                        .font(.system(size: 9))
                        .opacity(0.8)
                }
                .foregroundStyle(isPressed(19) ? Color.white : Color.primary.opacity(0.8))
                .frame(maxWidth: .infinity, minHeight: 21)
                .background(isPressed(19) ? Color.accentColor : Color.primary.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(isPressed(19) ? Color.accentColor : Color.primary.opacity(0.14), lineWidth: 0.8)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                HStack(spacing: 4) {
                    Text("GR")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                    Text("Rear Right")
                        .font(.system(size: 9))
                        .opacity(0.8)
                }
                .foregroundStyle(isPressed(18) ? Color.white : Color.primary.opacity(0.8))
                .frame(maxWidth: .infinity, minHeight: 21)
                .background(isPressed(18) ? Color.accentColor : Color.primary.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(isPressed(18) ? Color.accentColor : Color.primary.opacity(0.14), lineWidth: 0.8)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }

            // Live Button Summary
            if pressedButtons.isEmpty {
                Text("Press any button, rear paddle, or move sticks…")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                Text(pressedButtons.joined(separator: "  •  "))
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.accentColor)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.035))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.75)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.top, 4)
    }
}

struct ReadinessRowView<Trailing: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(iconColor)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.medium))
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 4)
            trailing()
        }
    }
}

struct WoWReadinessCardView: View {
    @ObservedObject var model: PadWakeModel

    private var primary: DetectedWoWTarget? {
        model.wowState.primaryTarget
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text(primary?.flavorName ?? "WoW Readiness")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if model.wowState.targets.count > 1 {
                    Menu {
                        ForEach(model.wowState.targets) { target in
                            Button {
                                model.wowState.selectedPath = target.path
                            } label: {
                                if target.path == primary?.path {
                                    Label(target.flavorName, systemImage: "checkmark")
                                } else {
                                    Text(target.flavorName)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                Spacer()
                if model.status == PW_STATUS_AWAKE && model.disableMFiVeto && (primary?.isConfigured ?? false) {
                    Label("Ready", systemImage: "checkmark.seal.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }

            // 1. Switch 2 Controller state
            ReadinessRowView(
                icon: model.status == PW_STATUS_AWAKE ? "checkmark.circle.fill" : (model.status == PW_STATUS_ASLEEP ? "exclamationmark.circle.fill" : "circle.dashed"),
                iconColor: model.status == PW_STATUS_AWAKE ? .green : (model.status == PW_STATUS_ASLEEP ? .orange : .secondary),
                title: "Switch 2 Controller",
                subtitle: model.status == PW_STATUS_AWAKE ? "Awake & streaming HID (057E:2069)" : (model.status == PW_STATUS_ASLEEP ? "Connected but asleep" : "Connect over USB-C")
            ) {
                if model.status != PW_STATUS_AWAKE {
                    Button("Wake") { model.wakeNow() }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                }
            }

            // 2. macOS SDL2 MFi Veto fix
            ReadinessRowView(
                icon: model.disableMFiVeto ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                iconColor: model.disableMFiVeto ? .green : .orange,
                title: "macOS SDL2 Veto Fix",
                subtitle: model.disableMFiVeto ? "SDL_JOYSTICK_MFI=0 active" : "Disabled — WoW may see 0 pads"
            ) {
                Toggle("", isOn: $model.disableMFiVeto)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }

            // 3. WoW files + PadWakeProfiles addon (Forever / Classic / Retail)
            ReadinessRowView(
                icon: (primary?.isConfigured ?? false) ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
                iconColor: (primary?.isConfigured ?? false) ? .green : .orange,
                title: "\(primary?.flavorName ?? "WoW") Setup",
                subtitle: primary.map { $0.isConfigured ? "\($0.label) + PadWakeProfiles" : "\($0.label) — needs install" } ?? "Folder not detected yet"
            ) {
                if let target = primary {
                    Button(target.isConfigured ? "Update" : "Setup") {
                        model.installWoW(into: URL(fileURLWithPath: target.path))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                } else {
                    Button("Locate…") {
                        model.chooseWoWFolderAndInstall()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }

            // 4. DialogueUI Switch Mode (only shown when DialogueUI addon is installed)
            if let target = primary, target.hasDialogueUI {
                ReadinessRowView(
                    icon: target.dialogueUISwitchMode ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
                    iconColor: target.dialogueUISwitchMode ? .green : .orange,
                    title: "DialogueUI Addon",
                    subtitle: target.dialogueUISwitchMode ? "Switch mode (A=Accept, B=Exit)" : "Set Control → Input Device → Switch"
                ) {
                    EmptyView()
                }
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.045))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.75)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                Switch2VisualTesterView(
                    input: model.inputState,
                    pressedButtons: pressedButtons
                )
            }
            .font(.subheadline)

            Divider()

            // WoW Readiness Checklist & Class Options
            VStack(alignment: .leading, spacing: 8) {
                WoWReadinessCardView(model: model)

                DisclosureGroup(isExpanded: $model.showWoWOptions) {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 6) {
                            Text("Class Preset")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Picker("", selection: $model.selectedWoWClass) {
                                ForEach(WoWClassPreset.allCases) { preset in
                                    Text(preset.displayName).tag(preset)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .controlSize(.mini)
                        }
                        Text(model.selectedWoWClass.paddleSummary)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if !model.wowState.targets.isEmpty {
                            Divider()
                            ForEach(model.wowState.targets) { target in
                                HStack(spacing: 6) {
                                    Image(systemName: target.isConfigured ? "checkmark.circle.fill" : "folder")
                                        .font(.caption2)
                                        .foregroundStyle(target.isConfigured ? Color.green : Color.secondary)
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(target.flavorName)
                                            .font(.caption2.weight(.medium))
                                            .lineLimit(1)
                                        Text(target.label)
                                            .font(.system(size: 9.5, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                    Spacer()
                                    Button(target.isConfigured ? "Update" : "Install") {
                                        model.wowState.selectedPath = target.path
                                        model.installWoW(into: URL(fileURLWithPath: target.path))
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)
                                }
                            }
                        }

                        Text("Auto-detects Forever, Classic Era, Classic, Anniversary & Retail.")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack {
                            Button {
                                model.chooseWoWFolderAndInstall()
                            } label: {
                                Label("Other WoW Folder…", systemImage: "folder.badge.plus")
                                    .font(.caption2)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            Spacer()
                        }

                        if let result = model.wowState.lastResult {
                            Text(result)
                                .font(.caption2)
                                .foregroundStyle(model.wowState.lastResultIsError ? Color.red : Color.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.top, 6)
                } label: {
                    HStack {
                        Text("Class Preset & Folders")
                        Spacer()
                        Text(model.selectedWoWClass.displayName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
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
        .frame(width: 328)
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
                    model.refreshWoWStatus()
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
