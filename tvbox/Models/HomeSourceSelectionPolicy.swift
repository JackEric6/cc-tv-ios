import Foundation

enum HomeSourceSelectionPolicy {
    static let defaultSourceKey = "guazi"

    static func startupKey(savedKey: String?) -> String? {
        guard let savedKey else { return nil }
        let normalized = savedKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "xgzy" || normalized == "jianpian" {
            return defaultSourceKey
        }
        return savedKey
    }
}
