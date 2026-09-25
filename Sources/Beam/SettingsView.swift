import SwiftUI
import AppKit
import ApplicationServices

struct SettingsView: View {
    var body: some View {
        TabView {
            EndpointSettingsView()
                .tabItem { Label("Endpoint", systemImage: "network") }
            BehaviorSettingsView()
                .tabItem { Label("Behavior", systemImage: "keyboard") }
            UpdateSettingsView()
                .tabItem { Label("Updates", systemImage: "arrow.triangle.2.circlepath") }
        }
        .frame(width: 560, height: 460)
    }
}

struct EndpointSettingsView: View {
    @EnvironmentObject var endpoints: EndpointStore
    @State private var newName = ""
    @State private var newBaseURL = ""
    @State private var newModel = ""
    @State private var newKey = ""
    @State private var keyDraft = ""
    @State private var modelFilter = ""
    @State private var models: [String] = []
    @State private var loadingModels = false
    @State private var modelError: String?

    var body: some View {
        Form {
            Section("Endpoints") {
                ForEach(endpoints.endpoints) { endpoint in
                    HStack {
                        Image(systemName: endpoints.selectedID == endpoint.id ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(endpoints.selectedID == endpoint.id ? Color.accentColor : Color.secondary)
                            .onTapGesture { endpoints.select(endpoint) }
                        VStack(alignment: .leading) {
                            Text(endpoint.name)
                            Text(endpoint.normalizedBase)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if endpoints.endpoints.count > 1 {
                            Button(role: .destructive) { endpoints.remove(endpoint) } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }

            if let selected = endpoints.selected {
                Section("Active endpoint: \(selected.name)") {
                    HStack {
                        SecureField("API key", text: $keyDraft)
                        Button("Save") {
                            endpoints.setApiKey(keyDraft, for: selected)
                            keyDraft = ""
                        }
                        .disabled(keyDraft.isEmpty)
                    }
                    if selected.normalizedBase.contains("openrouter.ai") {
                        Text("Create a key at openrouter.ai/keys. Free models work without credits (daily limit).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        TextField("Model", text: Binding(
                            get: { selected.model },
                            set: { endpoints.updateModel($0, for: selected) }
                        ))
                        Button(loadingModels ? "Loading…" : "Load models") { loadModels() }
                            .disabled(loadingModels)
                    }
                    if let modelError {
                        Text(modelError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    if !models.isEmpty {
                        TextField("Search models…", text: $modelFilter)
                        List(filteredModels, id: \.self) { model in
                            HStack {
                                Text(model).font(.callout)
                                Spacer()
                                if model == selected.model {
                                    Image(systemName: "checkmark")
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { endpoints.updateModel(model, for: selected) }
                        }
                        .frame(minHeight: 100, maxHeight: 150)
                    }
                }
            }

            Section("Add endpoint") {
                TextField("Name (e.g. OpenRouter)", text: $newName)
                TextField("Base URL (e.g. https://openrouter.ai/api/v1)", text: $newBaseURL)
                TextField("Model (optional, can be set later)", text: $newModel)
                SecureField("API key (optional)", text: $newKey)
                Button("Add endpoint") { addEndpoint() }
                    .disabled(newName.isEmpty || newBaseURL.isEmpty)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            keyDraft = ""
            if let selected = endpoints.selected {
                models = endpoints.cachedModels(for: selected)
            }
        }
        .onChange(of: endpoints.selectedID) { _ in
            modelError = nil
            models = endpoints.selected.map { endpoints.cachedModels(for: $0) } ?? []
        }
    }

    private var filteredModels: [String] {
        if modelFilter.isEmpty { return models }
        return models.filter { $0.localizedCaseInsensitiveContains(modelFilter) }
    }

    private func loadModels() {
        guard let selected = endpoints.selected else { return }
        loadingModels = true
        modelError = nil
        Task {
            do {
                let list = try await OpenAIClient().fetchModels(
                    baseURL: selected.normalizedBase,
                    apiKey: endpoints.apiKey(for: selected)
                )
                await MainActor.run {
                    models = list
                    endpoints.cacheModels(list, for: selected)
                    loadingModels = false
                    if list.isEmpty {
                        modelError = "The endpoint returned no models. Enter the model name manually."
                    }
                }
            } catch {
                await MainActor.run {
                    loadingModels = false
                    modelError = "Could not load models (\(error.localizedDescription)). Enter the model name manually."
                }
            }
        }
    }

    private func addEndpoint() {
        let endpoint = Endpoint(
            name: newName.trimmingCharacters(in: .whitespaces),
            baseURL: newBaseURL.trimmingCharacters(in: .whitespaces),
            model: newModel.trimmingCharacters(in: .whitespaces)
        )
        endpoints.add(endpoint)
        if !newKey.isEmpty {
            endpoints.setApiKey(newKey, for: endpoint)
        }
        endpoints.select(endpoint)
        newName = ""
        newBaseURL = ""
        newModel = ""
        newKey = ""
    }
}

struct BehaviorSettingsView: View {
    @EnvironmentObject var state: AppState
    @AppStorage("beam.hotkey") private var hotkeyRaw = HotkeyChoice.bothCommands.rawValue
    @AppStorage("beam.multiPass") private var multiPass = true
    @AppStorage("beam.maxPasses") private var maxPasses = 3
    @AppStorage("beam.multiCommand") private var multiCommand = true
    @State private var accessibilityTrusted = AXIsProcessTrusted()

    var body: some View {
        Form {
            Section("Global hotkey") {
                Picker("Open Beam with", selection: $hotkeyRaw) {
                    ForEach(HotkeyChoice.allCases) { choice in
                        Text(choice.title).tag(choice.rawValue)
                    }
                }
                .onChange(of: hotkeyRaw) { _ in state.restartHotkey() }
                Text("Works in every app. Needs accessibility access (below).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("How Beam works") {
                Toggle("Allow research passes (Beam may gather information first)", isOn: $multiPass)
                Stepper("Max research passes: \(maxPasses)", value: $maxPasses, in: 1...5)
                    .disabled(!multiPass)
                Toggle("Allow multiple commands in a row", isOn: $multiCommand)
            }

            Section("Permissions") {
                HStack {
                    Label(
                        accessibilityTrusted ? "Accessibility access granted" : "Accessibility access missing",
                        systemImage: accessibilityTrusted ? "checkmark.shield.fill" : "xmark.shield.fill"
                    )
                    .foregroundStyle(accessibilityTrusted ? .green : .red)
                    Spacer()
                    Button("Re-check") { accessibilityTrusted = AXIsProcessTrusted() }
                    Button("Open System Settings") { openAccessibilitySettings() }
                }
                Text("Needed for the global hotkey. AppleScript automation is asked by macOS the first time Beam controls an app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { accessibilityTrusted = AXIsProcessTrusted() }
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

struct UpdateSettingsView: View {
    @EnvironmentObject var updater: Updater
    @AppStorage("beam.autoUpdate") private var autoUpdate = true

    var body: some View {
        Form {
            Section("Version") {
                LabeledContent("Installed", value: updater.currentVersion)
                statusRow
                HStack {
                    Button("Check now") { updater.checkForUpdates() }
                        .disabled(updater.state == .checking || updater.state == .downloading)
                    if case .available = updater.state {
                        Button("Download and install") { updater.downloadAndInstall() }
                            .buttonStyle(.borderedProminent)
                    }
                }
                if case .available(let version) = updater.state, !updater.latestNotes.isEmpty {
                    Text("What's new in \(version):")
                        .font(.headline)
                    Text(updater.latestNotes)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Toggle("Check for updates automatically", isOn: $autoUpdate)
                Text("Updates come from github.com/Malti2/Beam releases. Beam restarts itself after an update.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private var statusRow: some View {
        switch updater.state {
        case .idle:
            LabeledContent("Status", value: "Not checked yet")
        case .checking:
            LabeledContent("Status", value: "Checking…")
        case .upToDate:
            LabeledContent("Status", value: "Up to date ✓")
        case .available(let version):
            LabeledContent("Status", value: "Version \(version) available")
        case .downloading:
            LabeledContent("Status", value: "Downloading…")
        case .installing:
            LabeledContent("Status", value: "Installing — Beam restarts…")
        case .failed(let message):
            LabeledContent("Status", value: message)
        }
    }
}
