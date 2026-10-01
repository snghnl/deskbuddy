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

        case .button(let label, let style, let action):
            if style == .primary {
                Button(label) { session.perform(action) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button(label) { session.perform(action) }
                    .buttonStyle(.bordered)
            }

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

        case .divider:
            Divider().opacity(0.5)

        case .textField(let id, let label, let placeholder, _):
            VStack(alignment: .leading, spacing: 4) {
                if let label { caption(label) }
                TextField(placeholder ?? "", text: binding(id))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
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
