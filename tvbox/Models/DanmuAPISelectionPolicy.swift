import Foundation

enum DanmuAPISelectionPolicy {
    static func candidates(
        explicit: String?,
        useDefault: Bool,
        saved: String?,
        configured: String?,
        builtin: String,
        fallbacks: [String] = []
    ) -> [String] {
        let builtinURLs = unique(([builtin] + fallbacks).compactMap(normalized))
        guard !builtinURLs.isEmpty else { return [] }

        if let explicitURL = normalized(explicit) {
            return unique([explicitURL] + builtinURLs)
        }
        guard !useDefault else { return builtinURLs }

        let preferredURL = normalized(saved) ?? normalized(configured)
        return unique(([preferredURL] + builtinURLs).compactMap { $0 })
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0.lowercased()).inserted }
    }
}
