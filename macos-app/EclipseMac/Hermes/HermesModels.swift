import Foundation

struct HermesResponsesRequest: Encodable, Equatable, Sendable {
    let model: String
    let input: String
    let conversation: String
    let store: Bool
}

struct HermesResponsesResponse: Decodable, Equatable, Sendable {
    let output: [HermesOutputItem]

    func assistantText() throws -> String {
        let chunks = output
            .filter { $0.type == "message" && $0.role == "assistant" }
            .flatMap(\.content)
            .filter { $0.type == "output_text" }
            .map(\.text)
            .filter { !$0.isEmpty }

        let text = chunks.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw HermesClientError.malformedResponse("No assistant output_text found in Hermes response.")
        }
        return text
    }
}

struct HermesOutputItem: Decodable, Equatable, Sendable {
    let type: String
    let role: String?
    let content: [HermesContentItem]
}

struct HermesContentItem: Decodable, Equatable, Sendable {
    let type: String
    let text: String

    enum CodingKeys: String, CodingKey {
        case type
        case text
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
    }
}

struct HermesErrorEnvelope: Decodable, Equatable, Sendable {
    let error: HermesAPIError
}

struct HermesAPIError: Decodable, Equatable, Sendable {
    let message: String
    let type: String?
    let code: String?
}

