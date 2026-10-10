import Foundation

enum PlaybackLineSelectionPolicy {
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
