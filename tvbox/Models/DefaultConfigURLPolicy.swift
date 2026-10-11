import Foundation

enum DefaultConfigURLPolicy {
    static let bundledURL = "bundle://xgzy_config_all.json"
    static let legacyURL = "https://ghproxy.net/https://raw.githubusercontent.com/JackEric6/movie/refs/heads/xgzy-config-20260922/movie2_xgzy_all"

    static func migratedURL(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return isLegacyDefaultURL(trimmed) ? bundledURL : trimmed
    }

    private static func isLegacyDefaultURL(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        if value.caseInsensitiveCompare(legacyURL) == .orderedSame { return true }
        guard let components = URLComponents(string: value),
              let host = components.host?.lowercased() else { return false }
        let path = components.path.lowercased()
        let isKnownConfigHost = host == "ghproxy.net"
            || host == "raw.githubusercontent.com"
            || host.hasSuffix(".githubusercontent.com")
        return isKnownConfigHost
            && (path.contains("movie2_xgzy_all") || path.contains("xgzy-config"))
    }
}
