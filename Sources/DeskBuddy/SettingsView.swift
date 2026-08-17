import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension Notification.Name {
    /// Posted whenever a setting changes so AppDelegate can re-apply
    /// wandering, hotkey registration, menus, and language.
    static let settingsChanged = Notification.Name("DeskBuddy.settingsChanged")
}

enum SettingsKeys {
    static let language = "DeskBuddy.language"
    static let showCalendar = "DeskBuddy.showCalendar"
    static let eventAlerts = "DeskBuddy.eventAlerts"
    static let eventAlertLead = "DeskBuddy.eventAlertLead"
    static let character = "DeskBuddy.character"
    static let throwEnabled = "DeskBuddy.throwEnabled"
    static let wander = "DeskBuddy.wander"
    static let hotkeyKeyCode = "DeskBuddy.hotkeyKeyCode"
    static let hotkeyModifiers = "DeskBuddy.hotkeyModifiers"
    static let hotkeyDisplay = "DeskBuddy.hotkeyDisplay"
}

struct SettingsView: View {
    @ObservedObject var calendar: CalendarService

    @AppStorage(SettingsKeys.language) private var languageRaw = AppLanguage.system.rawValue
    @AppStorage(SettingsKeys.character) private var characterRaw = CharacterKind.slime.rawValue
    @AppStorage(SettingsKeys.showCalendar) private var showCalendar = true
    @AppStorage(SettingsKeys.eventAlerts) private var eventAlerts = true
    @AppStorage(SettingsKeys.eventAlertLead) private var eventAlertLead = 10
    @AppStorage(SettingsKeys.throwEnabled) private var throwEnabled = true
    @AppStorage(SettingsKeys.wander) private var wanderEnabled = false
    @AppStorage(SettingsKeys.hotkeyKeyCode) private var hotkeyKeyCode = -1
    @AppStorage(SettingsKeys.hotkeyModifiers) private var hotkeyModifiers = 0
    @AppStorage(SettingsKeys.hotkeyDisplay) private var hotkeyDisplay = ""

    @State private var recording = false
    @State private var keyMonitor: Any?
    @State private var customs: [String] = []
    @State private var renameTarget: String?
    @State private var renameText = ""
    @State private var showRename = false

    var body: some View {
        Form {
            Section {
                Picker(L.s("settings.language"), selection: $languageRaw) {
                    Text(L.s("settings.follow_system")).tag(AppLanguage.system.rawValue)
                    Text("한국어").tag(AppLanguage.korean.rawValue)
                    Text("English").tag(AppLanguage.english.rawValue)
                }
                .pickerStyle(.menu)
            } header: {
                Text(L.s("settings.general"))
            }

            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(CharacterKind.allCases) { kind in
                            characterOption(.builtin(kind), label: kind.label)
                        }
                        ForEach(customs, id: \.self) { name in
                            characterOption(.custom(name), label: CustomCharacters.displayName(name), deletable: true)
                                .contextMenu {
                                    Button(L.s("settings.rename")) { beginRename(name) }
                                    Button(L.s("settings.delete"), role: .destructive) { removeCustom(name) }
                                }
                        }
                        addCharacterButton
                    }
                    .padding(.vertical, 2)
                }

                Toggle(L.s("settings.throwable"), isOn: $throwEnabled)
                Toggle(L.s("settings.wander"), isOn: $wanderEnabled)
            } header: {
                Text(L.s("settings.character"))
            } footer: {
                Text(L.s("settings.character_footer"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                calendarIntegrationRow
                if calendar.access == .authorized {
                    Toggle(L.s("settings.show_events"), isOn: $showCalendar)
                    Toggle(L.s("settings.event_alerts"), isOn: $eventAlerts)
                    if eventAlerts {
                        Picker(L.s("settings.alert_timing"), selection: $eventAlertLead) {
                            Text(L.s("settings.before_5min")).tag(5)
                            Text(L.s("settings.before_10min")).tag(10)
                            Text(L.s("settings.before_15min")).tag(15)
                            Text(L.s("settings.before_30min")).tag(30)
                        }
                        .pickerStyle(.menu)
                    }
                }
            } header: {
                Text(L.s("settings.integrations"))
            } footer: {
                Text(L.s("settings.integrations_footer"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Text(L.s("settings.hotkey_action"))
                    Spacer()
                    Button {
                        recording ? stopRecording() : startRecording()
                    } label: {
                        Text(recording
                             ? L.s("settings.press_keys")
                             : (hotkeyDisplay.isEmpty ? L.s("settings.record_shortcut") : hotkeyDisplay))
                            .frame(minWidth: 130)
                    }
                    if !hotkeyDisplay.isEmpty && !recording {
                        Button(action: clearHotkey) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(L.s("settings.remove_shortcut"))
                    }
                }
            } header: {
                Text(L.s("settings.global_shortcut"))
            } footer: {
                Text(L.s("settings.hotkey_footer"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 380, height: 500)
        .onChange(of: languageRaw) { notifyChange() }
        .onChange(of: throwEnabled) { notifyChange() }
        .onChange(of: wanderEnabled) { notifyChange() }
        .onAppear { customs = CustomCharacters.list() }
        .onDisappear(perform: stopRecording)
        .alert(L.s("settings.character_name"), isPresented: $showRename) {
            TextField(L.s("settings.name"), text: $renameText)
            Button(L.s("settings.save")) {
                if let target = renameTarget {
                    CustomCharacters.setDisplayName(renameText, for: target)
                }
                renameTarget = nil
            }
            Button(L.s("settings.cancel"), role: .cancel) { renameTarget = nil }
        }
    }

    private func beginRename(_ name: String) {
        renameTarget = name
        renameText = CustomCharacters.displayName(name)
        showRename = true
    }

    // MARK: - Calendar integration

    @ViewBuilder
    private var calendarIntegrationRow: some View {
        switch calendar.access {
        case .notDetermined:
            HStack {
                Text(L.s("settings.calendar"))
                Spacer()
                Button(L.s("settings.connect")) { calendar.requestAccess() }
            }
        case .denied:
            HStack {
                Text(L.s("settings.calendar"))
                Spacer()
                Text(L.s("settings.access_denied"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(L.s("settings.open_system_settings")) { calendar.openPrivacySettings() }
            }
        case .authorized:
            HStack {
                Text(L.s("settings.calendar"))
                Spacer()
                Label(L.s("settings.connected"), systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
    }

    // MARK: - Character selection

    private func characterOption(_ choice: CharacterChoice, label: String, deletable: Bool = false) -> some View {
        let selected = characterRaw == choice.raw
        return Button {
            characterRaw = choice.raw
        } label: {
            VStack(spacing: 2) {
                CharacterBody(choice: choice)
                    .frame(width: 76, height: 84)
                    .scaleEffect(0.65)
                    .frame(width: 56, height: 60)
                Text(label)
                    .font(.system(size: 10, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 60)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(selected ? Color.accentColor.opacity(0.15) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(selected ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.1), lineWidth: 1)
            )
            .overlay(alignment: .topTrailing) {
                if deletable, case .custom(let name) = choice {
                    Button {
                        removeCustom(name)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .offset(x: 4, y: -4)
                    .help(L.s("settings.delete"))
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var addCharacterButton: some View {
        Button(action: addCustom) {
            VStack(spacing: 2) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 56, height: 60)
                Text(L.s("settings.add"))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.primary.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
        }
        .buttonStyle(.plain)
        .help(L.s("settings.add_character_help"))
    }

    private func addCustom() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .gif, .heic, .tiff, .webP]
        panel.allowsMultipleSelection = false
        panel.message = L.s("settings.choose_image")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let name = try? CustomCharacters.add(url) {
            customs = CustomCharacters.list()
            characterRaw = CharacterChoice.custom(name).raw   // select it right away
        }
    }

    private func removeCustom(_ name: String) {
        CustomCharacters.remove(name)
        customs = CustomCharacters.list()
        if characterRaw == CharacterChoice.custom(name).raw {
            characterRaw = CharacterKind.slime.rawValue   // fall back to the slime if the active one was deleted
        }
    }

    // MARK: - Shortcut recording

    private func startRecording() {
        recording = true
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleRecorded(event)
            return nil   // swallow key events while recording
        }
    }

    private func stopRecording() {
        recording = false
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
    }

    private func handleRecorded(_ event: NSEvent) {
        if event.keyCode == 53 {   // esc — cancel
            stopRecording()
            return
        }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        // Capturing a bare key globally would break typing in other apps
        guard flags.contains(.command) || flags.contains(.option) || flags.contains(.control) else {
            NSSound.beep()
            return
        }
        hotkeyKeyCode = Int(event.keyCode)
        hotkeyModifiers = Int(flags.rawValue)
        hotkeyDisplay = Self.displayString(flags: flags, event: event)
        stopRecording()
        notifyChange()
    }

    private func clearHotkey() {
        hotkeyKeyCode = -1
        hotkeyModifiers = 0
        hotkeyDisplay = ""
        notifyChange()
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: .settingsChanged, object: nil)
    }

    private static func displayString(flags: NSEvent.ModifierFlags, event: NSEvent) -> String {
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option) { s += "⌥" }
        if flags.contains(.shift) { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        return s + keyName(event)
    }

    private static func keyName(_ event: NSEvent) -> String {
        switch event.keyCode {
        case 49: return "Space"
        case 36: return "↩"
        case 48: return "⇥"
        case 51: return "⌫"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default: return event.charactersIgnoringModifiers?.uppercased() ?? "?"
        }
    }
}
