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
                Picker(L.t("언어", "Language"), selection: $languageRaw) {
                    Text(L.t("시스템 설정 따름", "Follow System")).tag(AppLanguage.system.rawValue)
                    Text("한국어").tag(AppLanguage.korean.rawValue)
                    Text("English").tag(AppLanguage.english.rawValue)
                }
                .pickerStyle(.menu)
            } header: {
                Text(L.t("일반", "General"))
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
                                    Button(L.t("이름 변경…", "Rename…")) { beginRename(name) }
                                    Button(L.t("삭제", "Delete"), role: .destructive) { removeCustom(name) }
                                }
                        }
                        addCharacterButton
                    }
                    .padding(.vertical, 2)
                }

                Toggle(L.t("휙 던질 수 있게", "Throwable (flick to toss)"), isOn: $throwEnabled)
                Toggle(L.t("자유롭게 돌아다니기", "Wander around the screen"), isOn: $wanderEnabled)
            } header: {
                Text(L.t("캐릭터", "Character"))
            } footer: {
                Text(L.t("+ 로 이미지를 캐릭터로 추가할 수 있어요. 투명 배경 PNG가 잘 어울립니다. (커스텀 캐릭터는 표정 없이 움직임만 적용)",
                         "Use + to add an image as a character. Transparent PNGs work best. (Custom characters get motion but no facial expressions.)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                calendarIntegrationRow
                if calendar.access == .authorized {
                    Toggle(L.t("달력 탭에 일정 표시", "Show events in Calendar tab"), isOn: $showCalendar)
                    Toggle(L.t("일정 알림 (말풍선)", "Event alerts (speech bubble)"), isOn: $eventAlerts)
                    if eventAlerts {
                        Picker(L.t("알림 시점", "Alert timing"), selection: $eventAlertLead) {
                            Text(L.t("5분 전", "5 min before")).tag(5)
                            Text(L.t("10분 전", "10 min before")).tag(10)
                            Text(L.t("15분 전", "15 min before")).tag(15)
                            Text(L.t("30분 전", "30 min before")).tag(30)
                        }
                        .pickerStyle(.menu)
                    }
                }
            } header: {
                Text(L.t("연동", "Integrations"))
            } footer: {
                Text(L.t("macOS 캘린더에 연결된 계정의 일정을 읽습니다.",
                         "Reads events from accounts connected to macOS Calendar."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Text(L.t("할 일 목록 열기 / 닫기", "Open / close the to-do list"))
                    Spacer()
                    Button {
                        recording ? stopRecording() : startRecording()
                    } label: {
                        Text(recording
                             ? L.t("키를 누르세요 (esc 취소)", "Press keys (esc to cancel)")
                             : (hotkeyDisplay.isEmpty ? L.t("단축키 등록", "Record Shortcut") : hotkeyDisplay))
                            .frame(minWidth: 130)
                    }
                    if !hotkeyDisplay.isEmpty && !recording {
                        Button(action: clearHotkey) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(L.t("단축키 해제", "Remove shortcut"))
                    }
                }
            } header: {
                Text(L.t("글로벌 단축키", "Global Shortcut"))
            } footer: {
                Text(L.t("어느 앱에서든 목록을 열고 바로 입력할 수 있어요. ⌘/⌥/⌃ 중 하나를 포함해야 합니다.",
                         "Open the list and start typing from any app. Must include ⌘, ⌥, or ⌃."))
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
        .alert(L.t("캐릭터 이름", "Character Name"), isPresented: $showRename) {
            TextField(L.t("이름", "Name"), text: $renameText)
            Button(L.t("저장", "Save")) {
                if let target = renameTarget {
                    CustomCharacters.setDisplayName(renameText, for: target)
                }
                renameTarget = nil
            }
            Button(L.t("취소", "Cancel"), role: .cancel) { renameTarget = nil }
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
                Text(L.t("캘린더", "Calendar"))
                Spacer()
                Button(L.t("연동하기", "Connect")) { calendar.requestAccess() }
            }
        case .denied:
            HStack {
                Text(L.t("캘린더", "Calendar"))
                Spacer()
                Text(L.t("권한 꺼짐", "Access denied"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(L.t("시스템 설정 열기", "Open System Settings")) { calendar.openPrivacySettings() }
            }
        case .authorized:
            HStack {
                Text(L.t("캘린더", "Calendar"))
                Spacer()
                Label(L.t("연동됨", "Connected"), systemImage: "checkmark.circle.fill")
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
                    .help(L.t("삭제", "Delete"))
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
                Text(L.t("추가", "Add"))
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
        .help(L.t("이미지 파일을 캐릭터로 추가", "Add an image file as a character"))
    }

    private func addCustom() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .gif, .heic, .tiff, .webP]
        panel.allowsMultipleSelection = false
        panel.message = L.t("캐릭터로 쓸 이미지를 선택하세요 (투명 배경 PNG 추천)",
                            "Choose an image for your character (transparent PNG recommended)")
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
