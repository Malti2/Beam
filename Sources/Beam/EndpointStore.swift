import Foundation

struct Endpoint: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var baseURL: String
    var model: String

    var normalizedBase: String {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        return base
    }
}

// Stores endpoints in UserDefaults; API keys live in the Keychain.
final class EndpointStore: ObservableObject {
    @Published var endpoints: [Endpoint] = []
    @Published var selectedID: UUID? = nil

    private let defaultsKey = "beam.endpoints"
    private let selectedKey = "beam.selectedEndpoint"

    init() {
        load()
        ensurePreset()
    }

    var selected: Endpoint? {
        if let id = selectedID, let match = endpoints.first(where: { $0.id == id }) {
            return match
        }
        return endpoints.first
    }

    func select(_ endpoint: Endpoint) {
        selectedID = endpoint.id
        save()
    }

    func add(_ endpoint: Endpoint) {
        endpoints.append(endpoint)
        if selectedID == nil { selectedID = endpoint.id }
        save()
    }

    func remove(_ endpoint: Endpoint) {
        KeychainHelper.delete(key: keychainKey(for: endpoint))
        endpoints.removeAll { $0.id == endpoint.id }
        if selectedID == endpoint.id { selectedID = endpoints.first?.id }
        save()
    }

    func update(_ endpoint: Endpoint) {
        if let index = endpoints.firstIndex(where: { $0.id == endpoint.id }) {
            endpoints[index] = endpoint
            save()
        }
    }

    func updateModel(_ model: String, for endpoint: Endpoint) {
        var copy = endpoint
        copy.model = model
        update(copy)
    }

    func keychainKey(for endpoint: Endpoint) -> String {
        "beam.endpoint.\(endpoint.id.uuidString)"
    }

    func apiKey(for endpoint: Endpoint) -> String {
        KeychainHelper.read(key: keychainKey(for: endpoint)) ?? ""
    }

    func setApiKey(_ key: String, for endpoint: Endpoint) {
        KeychainHelper.save(key: keychainKey(for: endpoint), value: key)
    }

    // Model lists are cached so reopening Settings does not refetch.
    func cachedModels(for endpoint: Endpoint) -> [String] {
        UserDefaults.standard.stringArray(forKey: modelsKey(for: endpoint)) ?? []
    }

    func cacheModels(_ models: [String], for endpoint: Endpoint) {
        UserDefaults.standard.set(models, forKey: modelsKey(for: endpoint))
    }

    private func modelsKey(for endpoint: Endpoint) -> String {
        "beam.models.\(endpoint.id.uuidString)"
    }

    private func ensurePreset() {
        guard endpoints.isEmpty else { return }
        let preset = Endpoint(name: "OpenRouter", baseURL: "https://openrouter.ai/api/v1", model: "")
        endpoints = [preset]
        selectedID = preset.id
        save()
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([Endpoint].self, from: data) {
            endpoints = decoded
        }
        if let string = UserDefaults.standard.string(forKey: selectedKey),
           let uuid = UUID(uuidString: string) {
            selectedID = uuid
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(endpoints) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
        UserDefaults.standard.set(selectedID?.uuidString, forKey: selectedKey)
    }
}
