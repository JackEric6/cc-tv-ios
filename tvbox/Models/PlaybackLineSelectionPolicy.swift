import Foundation

enum PlaybackLineSelectionPolicy {
    enum SourceKind: Equatable {
        case feifan
        case xintong
    }

    static func sourceKind(sourceKey: String, sourceName: String, sourceAPI: String) -> SourceKind? {
        let key = sourceKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let name = sourceName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let host = URLComponents(string: sourceAPI)?.host?.lowercased() ?? ""

        if key == "fhw88" || key == "xintong" || name.contains("鑫同") || host == "cj.ffzyapi.com" {
            return .xintong
        }
        if key == "ffzy" || key == "feifan" || key == "feifazy"
            || name.contains("非凡") || host == "api.ffzyapi.com" {
            return .feifan
        }
        return nil
    }

    static func preferredFlagSubstring(sourceKey: String, sourceName: String, sourceAPI: String) -> String? {
        switch sourceKind(sourceKey: sourceKey, sourceName: sourceName, sourceAPI: sourceAPI) {
        case .feifan, .xintong:
            return "ffm3u8"
        case nil:
            return nil
        }
    }

    static func preservesPlayerPageReferer(sourceKey: String, sourceName: String, sourceAPI: String) -> Bool {
        sourceKind(sourceKey: sourceKey, sourceName: sourceName, sourceAPI: sourceAPI) != nil
    }

    static func preferredFlag(in flags: [String], sourceKey: String, sourceName: String, sourceAPI: String) -> String? {
        guard let preferred = preferredFlagSubstring(
            sourceKey: sourceKey,
            sourceName: sourceName,
            sourceAPI: sourceAPI
        ) else { return nil }
        return flags.first { $0.localizedCaseInsensitiveContains(preferred) }
    }

    static func preferredDyttLineIndex(flags: [String], urls: [String]) -> Int? {
        let count = min(flags.count, urls.count)
        guard count > 0 else { return nil }
        let normalized = (0..<count).map { normalize(flags[$0]) }
        if let index = normalized.firstIndex(of: "dyttm3u8") { return index }
        return normalized.firstIndex(of: "dyyttm3u8")
    }

    private static func normalize(_ flag: String) -> String {
        let scalars = flag.lowercased().unicodeScalars.filter {
            (97...122).contains($0.value) || (48...57).contains($0.value)
        }
        return String(String.UnicodeScalarView(scalars))
    }
}
