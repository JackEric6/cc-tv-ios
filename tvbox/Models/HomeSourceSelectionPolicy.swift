import Foundation

enum HomeSourceSelectionPolicy {
    static let defaultSourceKey = "guazi"

    static func selection(forSettingsCode code: String) -> (key: String, title: String)? {
        return switch code.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "7701": ("guazi", "瓜子")
        case "8801": ("xgzy", "西瓜")
        case "9901": nil
        default: nil
        }
    }

    static func startupKey(savedKey: String?) -> String? {
        guard let savedKey else { return nil }
        let normalized = savedKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty,
              !["jianpian", "fan_jianpian", "fan_jp", "yutu"].contains(normalized) else {
            return nil
        }
        return normalized
    }
}
