import Foundation

enum BridgeJSONCoding {
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(String.self),
               let date = parseISO8601(value) {
                return date
            }
            if let value = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: value)
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected ISO-8601 string or UNIX timestamp date."
            )
        }
        return decoder
    }

    private static func parseISO8601(_ value: String) -> Date? {
        for options: ISO8601DateFormatter.Options in [
            [.withInternetDateTime, .withFractionalSeconds],
            [.withInternetDateTime]
        ] {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = options
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return nil
    }
}
