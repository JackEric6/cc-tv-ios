import Foundation

enum PlaybackRequestHeaderPolicy {
    static func applyingSourceReferer(
        to headers: [String: String],
        sourceKey: String
    ) -> [String: String] {
        guard sourceKey.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare("ffzy") == .orderedSame else {
            return headers
        }

        var result = headers
        result.keys
            .filter { $0.caseInsensitiveCompare("Referer") == .orderedSame }
            .forEach { result.removeValue(forKey: $0) }
        result["Referer"] = "https://ffzy5.tv/"
        return result
    }
}
