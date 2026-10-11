import Foundation

enum DanmuAPISelectionPolicy {
    static func candidates(
        explicit: String?,
        useDefault: Bool,
        saved: String?,
        configured: String?,
        builtin: String
    ) -> [String] {
        guard let builtinURL = normalized(builtin) else { return [] }

        if let explicitURL = normalized(explicit) {
            return unique([explicitURL, builtinURL])
        }
        guard !useDefault else { return [builtinURL] }

        let preferredURL = normalized(saved) ?? normalized(configured) ?? builtinURL
        return unique([preferredURL, builtinURL])
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
