import SwiftUI

struct BarView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var orchestrator: Orchestrator
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            inputRow
            Divider().padding(.vertical, 10)
            contentArea
        }
        .padding(18)
        .frame(width: 624, height: 424)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.15), lineWidth: 1)
        }
        .padding(18)
        .onAppear { focusInput() }
        .background(
            Button("") { state.hidePanel() }
                .keyboardShortcut(.cancelAction)
                .hidden()
        )
    }

    private var inputRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "command")
                .font(.title2)
                .foregroundStyle(.secondary)
            TextField("What should your Mac do?", text: $orchestrator.input)
                .textFieldStyle(.plain)
                .font(.title2)
                .focused($inputFocused)
                .onSubmit { orchestrator.submit() }
            if orchestrator.isBusy {
                ProgressView().controlSize(.small)
            }
        }
    }

    private var contentArea: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let error = orchestrator.errorText {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
                if let pending = orchestrator.pending {
                    confirmationCard(pending)
                }
                ForEach(orchestrator.steps) { step in
                    StepRow(step: step)
                }
                if let answer = orchestrator.answer {
                    Text(answer)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
                if orchestrator.steps.isEmpty && orchestrator.answer == nil
                    && orchestrator.errorText == nil && orchestrator.pending == nil {
                    hintView
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var hintView: some View {
        VStack(alignment: .leading, spacing: 10) {
            let model = orchestrator.endpoints.selected?.model ?? ""
            if model.isEmpty {
                Label("No model configured yet.", systemImage: "key.fill")
                Text("Open Settings, pick an endpoint (OpenRouter is preset), load the model list and choose a model.")
                    .foregroundStyle(.secondary)
                Button("Open Settings") { state.openSettings() }
            } else {
                Text("Examples")
                    .font(.headline)
                VStack(alignment: .leading, spacing: 4) {
                    Text("· \"Mute my volume\"")
                    Text("· \"Create a folder called Invites on my Desktop\"")
                    Text("· \"How much free disk space is left?\"")
                    Text("· \"Open Safari with github.com\"")
                }
                .foregroundStyle(.secondary)
                Text("Esc closes. The hotkey works everywhere.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func confirmationCard(_ commands: [CommandSpec]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Potentially destructive — review before running:", systemImage: "exclamationmark.shield.fill")
                .foregroundStyle(.orange)
            ForEach(Array(commands.enumerated()), id: \.offset) { _, command in
                VStack(alignment: .leading, spacing: 4) {
                    if !command.note.isEmpty {
                        Text(command.note).font(.callout).bold()
                    }
                    Text(command.code)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            HStack {
                Button("Cancel") { orchestrator.cancelPending() }
                Spacer()
                Button("Run commands") { orchestrator.confirmPending() }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
            }
        }
        .padding(12)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private func focusInput() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            inputFocused = true
        }
    }
}

struct StepRow: View {
    let step: Step
    @State private var expanded = false

    private var iconName: String {
        if step.isInspect { return "magnifyingglass" }
        return step.kind.lowercased().contains("apple") ? "scroll" : "terminal"
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 6) {
                Text(step.code)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                if !step.output.isEmpty {
                    Text(step.output)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
        } label: {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .frame(width: 16)
                Text(step.title)
                    .lineLimit(1)
                Spacer()
                statusView
            }
        }
    }

    @ViewBuilder private var statusView: some View {
        switch step.status {
        case .running:
            ProgressView().controlSize(.mini)
        case .ok:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }
}
