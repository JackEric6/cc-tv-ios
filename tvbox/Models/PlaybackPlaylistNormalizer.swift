import Foundation

enum PlaybackPlaylistNormalizer {
    struct Fields: Equatable {
        let playFrom: String
        let playURL: String
    }

    static func normalize(playFrom rawPlayFrom: Any?, playURL rawPlayURL: Any?) -> Fields {
        var playFrom = stringValue(rawPlayFrom)
        var playURL = stringValue(rawPlayURL)

        if let groups = rawPlayURL as? [String: Any], !groups.isEmpty {
            let keys = groups.keys.sorted()
            let values = keys.compactMap { key -> (String, String)? in
                let value = stringValue(groups[key])
                return key.isEmpty || value.isEmpty ? nil : (key, value)
            }
            if !values.isEmpty {
                playFrom = values.map { $0.0 }.joined(separator: "$$$")
                playURL = values.map { $0.1 }.joined(separator: "$$$")
            }
        }

        playFrom = normalizeGroupSeparators(playFrom)
        playURL = normalizeGroupSeparators(playURL)
        let expectedCount = max(groupCount(playFrom), groupCount(playURL))
        if expectedCount > 1 {
            playFrom = normalizeCommaGroups(playFrom, expectedCount: expectedCount)
            playURL = normalizeCommaGroups(playURL, expectedCount: expectedCount)
        }

        let flags = playFrom.components(separatedBy: "$$$")
        let urls = playURL.components(separatedBy: "$$$")
        if flags.count > urls.count, urls.count == 1 {
            playFrom = flags.first ?? ""
        }
        return Fields(playFrom: playFrom, playURL: playURL)
    }

    private static func stringValue(_ value: Any?) -> String {
        guard let value, !(value is NSNull) else { return "" }
        if let string = value as? String { return string.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let number = value as? NSNumber { return number.stringValue }
        if let array = value as? [Any] {
            return array.map { stringValue($0) }.filter { !$0.isEmpty }.joined(separator: "$$$")
        }
        return ""
    }

    private static func normalizeGroupSeparators(_ value: String) -> String {
        value.replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "|||", with: "$$$")
            .replacingOccurrences(of: ",,,", with: "$$$")
    }

    private static func groupCount(_ value: String) -> Int {
        value.isEmpty ? 0 : value.components(separatedBy: "$$$").count
    }

    private static func normalizeCommaGroups(_ value: String, expectedCount: Int) -> String {
        guard !value.isEmpty, !value.contains("$$$"), expectedCount > 1 else { return value }
        let groups = value.components(separatedBy: CharacterSet(charactersIn: ",，"))
        guard groups.count == expectedCount,
              groups.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            return value
        }
        return groups.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: "$$$")
    }
}
