import Foundation

enum PlaybackRequestHeaderPolicy {
    private static let sourceReferers: [String: String] = [
        "ffzy": "https://ffzy5.tv/"
    ]

    static let androidDefaultUserAgent =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36"

    static func applyingSourceReferer(
        to headers: [String: String],
        sourceKey: String
    ) -> [String: String] {
        let key = sourceKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let referer = sourceReferers[key] else { return headers }

        var result = headers
        result.keys
            .filter { $0.caseInsensitiveCompare("Referer") == .orderedSame }
            .forEach { result.removeValue(forKey: $0) }
        result["Referer"] = referer
        return result
    }
}
