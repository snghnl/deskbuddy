import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension Notification.Name {
    /// 설정이 바뀌면 AppDelegate 가 배회·단축키 등록을 다시 반영한다
    static let settingsChanged = Notification.Name("DeskBuddy.settingsChanged")
}

enum SettingsKeys {
    static let showCalendar = "DeskBuddy.showCalendar"
    static let character = "DeskBuddy.character"
    static let throwEnabled = "DeskBuddy.throwEnabled"
    static let wander = "DeskBuddy.wander"
    static let hotkeyKeyCode = "DeskBuddy.hotkeyKeyCode"
    static let hotkeyModifiers = "DeskBuddy.hotkeyModifiers"
    static let hotkeyDisplay = "DeskBuddy.hotkeyDisplay"
}

struct SettingsView: View {
    @ObservedObject var calendar: CalendarService

    @AppStorage(SettingsKeys.character) private var characterRaw = CharacterKind.slime.rawValue
    @AppStorage(SettingsKeys.showCalendar) private var showCalendar = true
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
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(CharacterKind.allCases) { kind in
                            characterOption(.builtin(kind), label: kind.label)
                        }
                        ForEach(customs, id: \.self) { name in
                            characterOption(.custom(name), label: CustomCharacters.displayName(name), deletable: true)
                                .contextMenu {
                                    Button("이름 변경…") { beginRename(name) }
                                    Button("삭제", role: .destructive) { removeCustom(name) }
                                }
                        }
                        addCharacterButton
                    }
                    .padding(.vertical, 2)
                }

                Toggle("휙 던질 수 있게", isOn: $throwEnabled)
                Toggle("자유롭게 돌아다니기", isOn: $wanderEnabled)
            } header: {
                Text("캐릭터")
            } footer: {
                Text("+ 로 이미지를 캐릭터로 추가할 수 있어요. 투명 배경 PNG가 잘 어울립니다. (커스텀 캐릭터는 표정 없이 움직임만 적용)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                calendarIntegrationRow
                if calendar.access == .authorized {
                    Toggle("달력 탭에 일정 표시", isOn: $showCalendar)
                }
            } header: {
                Text("연동")
            } footer: {
                Text("macOS 캘린더에 연결된 계정의 일정을 읽습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Text("할 일 목록 열기 / 닫기")
                    Spacer()
                    Button {
                        recording ? stopRecording() : startRecording()
                    } label: {
                        Text(recording
                             ? "키를 누르세요 (esc 취소)"
                             : (hotkeyDisplay.isEmpty ? "단축키 등록" : hotkeyDisplay))
                            .frame(minWidth: 130)
                    }
                    if !hotkeyDisplay.isEmpty && !recording {
                        Button(action: clearHotkey) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("단축키 해제")
                    }
                }
            } header: {
                Text("글로벌 단축키")
            } footer: {
                Text("어느 앱에서든 목록을 열고 바로 입력할 수 있어요. ⌘/⌥/⌃ 중 하나를 포함해야 합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 380, height: 440)
        .onChange(of: throwEnabled) { notifyChange() }
        .onChange(of: wanderEnabled) { notifyChange() }
        .onAppear { customs = CustomCharacters.list() }
        .onDisappear(perform: stopRecording)
        .alert("캐릭터 이름", isPresented: $showRename) {
            TextField("이름", text: $renameText)
            Button("저장") {
                if let target = renameTarget {
                    CustomCharacters.setDisplayName(renameText, for: target)
                }
                renameTarget = nil
            }
            Button("취소", role: .cancel) { renameTarget = nil }
        }
    }

    private func beginRename(_ name: String) {
        renameTarget = name
        renameText = CustomCharacters.displayName(name)
        showRename = true
    }

    // MARK: - 캘린더 연동

    @ViewBuilder
    private var calendarIntegrationRow: some View {
        switch calendar.access {
        case .notDetermined:
            HStack {
                Text("캘린더")
                Spacer()
                Button("연동하기") { calendar.requestAccess() }
            }
        case .denied:
            HStack {
                Text("캘린더")
                Spacer()
                Text("권한 꺼짐")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("시스템 설정 열기") { calendar.openPrivacySettings() }
            }
        case .authorized:
            HStack {
                Text("캘린더")
                Spacer()
                Label("연동됨", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
    }

    // MARK: - 캐릭터 선택

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
                    .help("삭제")
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
                Text("추가")
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
        .help("이미지 파일을 캐릭터로 추가")
    }

    private func addCustom() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .gif, .heic, .tiff, .webP]
        panel.allowsMultipleSelection = false
        panel.message = "캐릭터로 쓸 이미지를 선택하세요 (투명 배경 PNG 추천)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let name = try? CustomCharacters.add(url) {
            customs = CustomCharacters.list()
            characterRaw = CharacterChoice.custom(name).raw   // 추가하면 바로 선택
        }
    }

    private func removeCustom(_ name: String) {
        CustomCharacters.remove(name)
        customs = CustomCharacters.list()
        if characterRaw == CharacterChoice.custom(name).raw {
            characterRaw = CharacterKind.slime.rawValue   // 쓰던 캐릭터가 지워지면 슬라임으로
        }
    }

    // MARK: - 단축키 녹화

    private func startRecording() {
        recording = true
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleRecorded(event)
            return nil   // 녹화 중에는 키 입력을 삼킨다
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
        if event.keyCode == 53 {   // esc — 취소
            stopRecording()
            return
        }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        // 수식키 없는 일반 키를 글로벌로 뺏으면 다른 앱 입력이 망가진다
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
