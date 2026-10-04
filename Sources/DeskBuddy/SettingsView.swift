import AppKit
import DeskBuddyCore
import DeskBuddyMacUI
import SwiftUI
import UniformTypeIdentifiers

extension Notification.Name {
    /// Posted whenever a setting changes so AppDelegate can re-apply
    /// wandering, hotkey registration, menus, and language.
    static let settingsChanged = Notification.Name("DeskBuddy.settingsChanged")
}

enum SettingsKeys {
    static let language = AppLanguage.defaultsKey
    /// Seconds before notification bubbles close themselves; 0 keeps them until clicked
    static let bubbleAutoHide = "DeskBuddy.bubbleAutoHide"
    static let character = "DeskBuddy.character"
    static let throwEnabled = "DeskBuddy.throwEnabled"
    static let wander = "DeskBuddy.wander"
    static let hotkeyKeyCode = "DeskBuddy.hotkeyKeyCode"
    static let hotkeyModifiers = "DeskBuddy.hotkeyModifiers"
    static let hotkeyDisplay = "DeskBuddy.hotkeyDisplay"
    static let autoUpdateCheck = "DeskBuddy.autoUpdateCheck"
    /// Tag of the newest release the buddy has already announced — keeps it from nagging
    static let lastNotifiedVersion = "DeskBuddy.lastNotifiedVersion"
    /// Version we updated away from, read once on the next launch to announce the update
    static let updatedFrom = "DeskBuddy.updatedFrom"
}

struct SettingsView: View {
    @ObservedObject var updates: UpdateService
    let slots: SlotRegistry

    @AppStorage(SettingsKeys.language) private var languageRaw = AppLanguage.system.rawValue
    @AppStorage(SettingsKeys.character) private var characterRaw = CharacterKind.buddy.rawValue
    @AppStorage(SettingsKeys.bubbleAutoHide) private var bubbleAutoHide = 0
    @AppStorage(SettingsKeys.throwEnabled) private var throwEnabled = true
    @AppStorage(SettingsKeys.wander) private var wanderEnabled = false
    @AppStorage(SettingsKeys.hotkeyKeyCode) private var hotkeyKeyCode = -1
    @AppStorage(SettingsKeys.hotkeyModifiers) private var hotkeyModifiers = 0
    @AppStorage(SettingsKeys.hotkeyDisplay) private var hotkeyDisplay = ""
    @AppStorage(SettingsKeys.autoUpdateCheck) private var autoUpdateCheck = true

    @State private var recording = false
    @State private var keyMonitor: Any?
    @State private var customs: [String] = []
    @State private var renameTarget: String?
    @State private var renameText = ""
    @State private var showRename = false

    var body: some View {
        Form {
            ForEach(sections, id: \.id) { section in
                Section {
                    section.content().swiftUI
                } header: {
                    Text(section.title())
                } footer: {
                    if let footer = section.footer {
                        Text(footer())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 380, height: 500)
        .onChange(of: languageRaw) { notifyChange() }
        .onChange(of: throwEnabled) { notifyChange() }
        .onChange(of: wanderEnabled) { notifyChange() }
        .onAppear { customs = CustomCharacters.list() }
        .onDisappear(perform: stopRecording)
        .alert(strings.s("settings.character_name"), isPresented: $showRename) {
            TextField(strings.s("settings.name"), text: $renameText)
            Button(strings.s("settings.save")) {
                if let target = renameTarget {
                    CustomCharacters.setDisplayName(renameText, for: target)
                }
                renameTarget = nil
            }
            Button(strings.s("settings.cancel"), role: .cancel) { renameTarget = nil }
        }
    }

    /// The built-in sections, merged by order with the ones features contribute
    private var sections: [SettingsSection] {
        let builtIn = [
            SettingsSection(id: "general", order: 100,
                            title: { strings.s("settings.general") },
                            footer: { strings.s("settings.bubble_auto_hide_footer") }) { generalRows },
            SettingsSection(id: "character", order: 200,
                            title: { strings.s("settings.character") },
                            footer: { strings.s("settings.character_footer") }) { characterRows },
            SettingsSection(id: "shortcut", order: 400,
                            title: { strings.s("settings.global_shortcut") },
                            footer: { strings.s("settings.hotkey_footer") }) { shortcutRows },
            SettingsSection(id: "updates", order: 600,
                            title: { strings.s("settings.updates") }) { updatesRows },
        ]
        return (builtIn + slots.contributions(to: CoreSlots.settingsSections)).sorted { $0.order < $1.order }
    }

    @ViewBuilder
    private var generalRows: some View {
        Picker(strings.s("settings.language"), selection: $languageRaw) {
            Text(strings.s("settings.follow_system")).tag(AppLanguage.system.rawValue)
            Text("한국어").tag(AppLanguage.korean.rawValue)
            Text("English").tag(AppLanguage.english.rawValue)
        }
        .pickerStyle(.menu)

        Picker(strings.s("settings.bubble_auto_hide"), selection: $bubbleAutoHide) {
            Text(strings.s("settings.when_clicked")).tag(0)
            ForEach([5, 10, 30], id: \.self) { seconds in
                Text(strings.f("settings.after_seconds", seconds)).tag(seconds)
            }
            Text(strings.s("settings.after_1min")).tag(60)
        }
        .pickerStyle(.menu)
    }

    @ViewBuilder
    private var characterRows: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(CharacterKind.allCases) { kind in
                    characterOption(.builtin(kind), label: kind.label)
                }
                ForEach(customs, id: \.self) { name in
                    characterOption(.custom(name), label: CustomCharacters.displayName(name), deletable: true)
                        .contextMenu {
                            Button(strings.s("settings.rename")) { beginRename(name) }
                            Button(strings.s("settings.delete"), role: .destructive) { removeCustom(name) }
                        }
                }
                addCharacterButton
            }
            .padding(.vertical, 2)
        }

        Toggle(strings.s("settings.throwable"), isOn: $throwEnabled)
        Toggle(strings.s("settings.wander"), isOn: $wanderEnabled)
    }

    private var shortcutRows: some View {
        HStack {
            Text(strings.s("settings.hotkey_action"))
            Spacer()
            Button {
                recording ? stopRecording() : startRecording()
            } label: {
                Text(recording
                     ? strings.s("settings.press_keys")
                     : (hotkeyDisplay.isEmpty ? strings.s("settings.record_shortcut") : hotkeyDisplay))
                    .frame(minWidth: 130)
            }
            if !hotkeyDisplay.isEmpty && !recording {
                Button(action: clearHotkey) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(strings.s("settings.remove_shortcut"))
            }
        }
    }

    @ViewBuilder
    private var updatesRows: some View {
        LabeledContent(strings.s("settings.current_version")) {
            Text(UpdateService.currentVersion.description)
                .foregroundStyle(.secondary)
        }
        updateRow
        Toggle(strings.s("settings.auto_update_check"), isOn: $autoUpdateCheck)
    }

    private func beginRename(_ name: String) {
        renameTarget = name
        renameText = CustomCharacters.displayName(name)
        showRename = true
    }

    // MARK: - Updates

    @ViewBuilder
    private var updateRow: some View {
        switch updates.phase {
        case .checking:
            progressRow(strings.s("settings.checking_for_updates"))

        case .downloading:
            progressRow(strings.s("settings.downloading_update"))

        case .installing:
            progressRow(strings.s("settings.installing_update"))

        case .available(let tag):
            LabeledContent(strings.f("settings.update_available", tag)) {
                HStack(spacing: 10) {
                    if let notes = updates.pending?.notes {
                        Link(strings.s("settings.release_notes"), destination: notes)
                            .font(.caption)
                    }
                    Button(strings.s("settings.install_update")) {
                        guard let update = updates.pending else { return }
                        Task { await updates.install(update) }
                    }
                }
            }

        case .idle, .upToDate, .failed:
            LabeledContent(strings.s("settings.update_status")) {
                HStack(spacing: 10) {
                    if !checkResultText.isEmpty {
                        Text(checkResultText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help(checkResultText)
                    }
                    Button(strings.s("settings.check_for_updates")) {
                        Task { await updates.check(userInitiated: true) }
                    }
                }
            }
        }
    }

    private func progressRow(_ label: String) -> some View {
        LabeledContent(strings.s("settings.update_status")) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var checkResultText: String {
        switch updates.phase {
        case .upToDate:
            if let checked = updates.lastChecked {
                strings.f("settings.up_to_date_at", checked.formatted(date: .omitted, time: .shortened))
            } else {
                strings.s("settings.up_to_date")
            }
        case .failed(let message): message
        default: ""
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
                    .help(strings.s("settings.delete"))
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
                Text(strings.s("settings.add"))
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
        .help(strings.s("settings.add_character_help"))
    }

    private func addCustom() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .gif, .heic, .tiff, .webP]
        panel.allowsMultipleSelection = false
        panel.message = strings.s("settings.choose_image")
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
            characterRaw = CharacterKind.buddy.rawValue   // fall back to the built-in one if the active character was deleted
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
