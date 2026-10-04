import A2UIPlugin
import AppKit
import SwiftUI

/// A panel's content: the document's components, then the last error if a command failed
struct A2UIPanelView: View {
    let session: A2UISession

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            A2UINodeView(node: session.document, session: session)
            if let error = session.error {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Draws one component and, through itself, its children
struct A2UINodeView: View {
    let node: A2UINode
    @Bindable var session: A2UISession

    var body: some View {
        switch node {
        case .text(let text, let style):
            Text(text)
                .font(font(for: style))
                .foregroundStyle(style == .caption ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .fixedSize(horizontal: false, vertical: true)
                // Keeps a title clear of the panel's close button
                .padding(.trailing, style == .title ? 16 : 0)

        case .icon(let name, let size, let color):
            Image(systemName: name)
                .font(.system(size: size))
                .foregroundStyle(style(for: color))

        case .image(let source, let height):
            A2UIImageView(source: source)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

        case .progress(let value, let label):
            VStack(alignment: .leading, spacing: 4) {
                if let label { caption(label) }
                if let value {
                    ProgressView(value: value)
                } else {
                    ProgressView().controlSize(.small)
                }
            }

        case .divider:
            Divider().opacity(0.5)

        case .row(let children, let align):
            HStack(spacing: 8) {
                if align != .leading { Spacer(minLength: 0) }
                nodes(children)
                if align != .trailing { Spacer(minLength: 0) }
            }

        case .column(let children):
            VStack(alignment: .leading, spacing: 8) { nodes(children) }

        case .card(let children):
            VStack(alignment: .leading, spacing: 8) { nodes(children) }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))

        case .list(let children, let height):
            ScrollView {
                VStack(alignment: .leading, spacing: 6) { nodes(children) }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: height)

        case .tabs(let key, let id, let tabs, let selected):
            let current = session.selectedTabs[key] ?? selected
            VStack(alignment: .leading, spacing: 8) {
                Picker("", selection: Binding(get: { current }, set: { index in
                    session.select(tab: index, of: key, id: id, title: tabs[index].title)
                })) {
                    ForEach(tabs.indices, id: \.self) { index in
                        Text(tabs[index].title).tag(index)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                nodes(tabs[current].children)
            }

        case .textField(let id, let label, let placeholder, _, let multiline):
            VStack(alignment: .leading, spacing: 4) {
                if let label { caption(label) }
                if multiline {
                    TextField(placeholder ?? "", text: binding(id), axis: .vertical)
                        .lineLimit(4, reservesSpace: true)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                } else {
                    TextField(placeholder ?? "", text: binding(id))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                }
            }

        case .select(let id, let label, let options, _, let style):
            VStack(alignment: .leading, spacing: 4) {
                if let label { caption(label) }
                Picker(label ?? "", selection: binding(id)) {
                    ForEach(options, id: \.value) { option in
                        Text(option.label).tag(option.value)
                    }
                }
                .labelsHidden()
                .font(.system(size: 12))
                .modifier(SelectStyleModifier(style: style))
            }

        case .checkbox(let id, let label, _, let style):
            let isOn = Binding(get: { session.values[id] == "true" }, set: { session.values[id] = $0 ? "true" : "false" })
            if style == .switch {
                Toggle(label, isOn: isOn).toggleStyle(.switch).controlSize(.small).font(.system(size: 12))
            } else {
                Toggle(label, isOn: isOn).toggleStyle(.checkbox).font(.system(size: 12))
            }

        case .slider(let id, let label, let range, let step, _):
            let value = Binding(get: { Double(session.values[id] ?? "") ?? range.lowerBound },
                                set: { new in session.values[id] = A2UINode.format(step.map { (new / $0).rounded() * $0 } ?? new) })
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    if let label { caption(label) }
                    Spacer(minLength: 0)
                    Text(session.values[id] ?? "")
                        .font(.system(size: 10, design: .rounded).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if let step {
                    Slider(value: value, in: range, step: step).controlSize(.small)
                } else {
                    Slider(value: value, in: range).controlSize(.small)
                }
            }

        case .dateTime(let id, let label, let mode, _):
            let formatter = mode.formatter()
            let date = Binding(get: { formatter.date(from: session.values[id] ?? "") ?? Date() },
                               set: { session.values[id] = formatter.string(from: $0) })
            VStack(alignment: .leading, spacing: 4) {
                if let label { caption(label) }
                DatePicker("", selection: date, displayedComponents: components(for: mode))
                    .labelsHidden()
                    .datePickerStyle(.field)
                    .font(.system(size: 12))
                    .fixedSize()
            }

        case .button(let label, let style, let action):
            if style == .primary {
                Button(label) { session.perform(action) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button(label) { session.perform(action) }
                    .buttonStyle(.bordered)
            }
        }
    }

    private func nodes(_ children: [A2UINode]) -> some View {
        ForEach(children.indices, id: \.self) { index in
            A2UINodeView(node: children[index], session: session)
        }
    }

    private func binding(_ id: String) -> Binding<String> {
        Binding(get: { session.values[id] ?? "" }, set: { session.values[id] = $0 })
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
    }

    private func font(for style: A2UINode.TextStyle) -> Font {
        switch style {
        case .title: .system(size: 13, weight: .semibold)
        case .body: .system(size: 12)
        case .caption: .system(size: 10)
        }
    }

    private func style(for color: A2UINode.IconColor) -> AnyShapeStyle {
        switch color {
        case .primary: AnyShapeStyle(.primary)
        case .secondary: AnyShapeStyle(.secondary)
        case .accent: AnyShapeStyle(.tint)
        case .red: AnyShapeStyle(.red)
        case .orange: AnyShapeStyle(.orange)
        case .yellow: AnyShapeStyle(.yellow)
        case .green: AnyShapeStyle(.green)
        case .blue: AnyShapeStyle(.blue)
        case .purple: AnyShapeStyle(.purple)
        case .pink: AnyShapeStyle(.pink)
        }
    }

    private func components(for mode: A2UINode.DateTimeMode) -> DatePickerComponents {
        switch mode {
        case .date: .date
        case .time: .hourAndMinute
        case .dateTime: [.date, .hourAndMinute]
        }
    }
}

/// A picture from the web or from disk, filling its frame without stretching
private struct A2UIImageView: View {
    let source: A2UINode.ImageSource

    var body: some View {
        switch source {
        case .remote(let url):
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFit()
                case .failure: missing
                default: ProgressView().controlSize(.small)
                }
            }
        case .file(let url):
            if let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                missing
            }
        }
    }

    private var missing: some View {
        Image(systemName: "photo")
            .font(.system(size: 20))
            .foregroundStyle(.tertiary)
    }
}

private struct SelectStyleModifier: ViewModifier {
    let style: A2UINode.SelectStyle

    func body(content: Content) -> some View {
        switch style {
        case .menu: content.pickerStyle(.menu).fixedSize()
        case .radio: content.pickerStyle(.radioGroup)
        }
    }
}
