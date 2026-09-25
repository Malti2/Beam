import Foundation

struct ChatMessage: Codable {
    let role: String
    let content: String
}

enum ClientError: LocalizedError {
    case badURL
    case http(Int, String)
    case empty

    var errorDescription: String? {
        switch self {
        case .badURL: return "Invalid endpoint URL."
        case .http(let code, let message): return "HTTP \(code): \(message)"
        case .empty: return "The model returned an empty response."
        }
    }
}

// Talks to any OpenAI-compatible endpoint: GET /models and
// POST /chat/completions with a Bearer key.
struct OpenAIClient {
    var timeout: TimeInterval = 120

    func fetchModels(baseURL: String, apiKey: String) async throws -> [String] {
        guard let url = URL(string: baseURL + "/models") else { throw ClientError.badURL }
        var request = URLRequest(url: url, timeoutInterval: 30)
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response, data)
        struct ModelsResponse: Decodable {
            struct Model: Decodable { let id: String }
            let data: [Model]
        }
        let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)
        return decoded.data.map { $0.id }.sorted()
    }

    func chat(baseURL: String, apiKey: String, model: String, messages: [ChatMessage]) async throws -> String {
        guard let url = URL(string: baseURL + "/chat/completions") else { throw ClientError.badURL }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Beam", forHTTPHeaderField: "X-Title")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        struct Body: Encodable {
            let model: String
            let messages: [ChatMessage]
            let temperature: Double
        }
        request.httpBody = try JSONEncoder().encode(Body(model: model, messages: messages, temperature: 0.2))
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response, data)
        struct ChatResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String? }
                let message: Message
            }
            let choices: [Choice]
        }
        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content, !content.isEmpty else {
            throw ClientError.empty
        }
        return content
    }

    private struct APIError: Decodable { let message: String }

    private func check(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            var message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if let container = try? JSONDecoder().decode([String: APIError].self, from: data),
               let apiError = container["error"] {
                message = apiError.message
            }
            if message.count > 300 {
                message = String(message.prefix(300)) + "…"
            }
            throw ClientError.http(http.statusCode, message)
        }
    }
}
