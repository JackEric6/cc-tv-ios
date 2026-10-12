import Foundation

enum DanmakuEpisodeMatcher {
    private static let markedNumberPatterns = [
        #"(?i)S\s*\d+\s*E\s*0*(\d+)"#,
        #"第\s*0*(\d+)\s*(?:集|话|期|回)"#,
        #"(?i)(?:^|[\s【\[(])EP?\s*0*(\d+)(?:$|[\s】\])])"#,
        #"(?i)(?:^|[\s_.-])(?:EP)?\s*0*(\d+)$"#
    ]
    private static let chineseEpisodePattern = #"第\s*([零〇一二两三四五六七八九十百]+)\s*(?:集|话|期|回)"#

    static func matches(
        requestedEpisode: String,
        title: String,
        explicitNumber: Int = -1
    ) -> Bool {
        let requested = normalize(requestedEpisode)
        let candidate = normalize(title)
        guard !requested.isEmpty else { return true }
        guard let requestedNumber = episodeNumber(in: requestedEpisode) else {
            return candidate.contains(requested)
        }
        if explicitNumber == requestedNumber { return true }
        return episodeNumber(in: title) == requestedNumber
    }

    static func episodeNumber(in value: String) -> Int? {
        for pattern in markedNumberPatterns {
            if let number = captureNumber(pattern, in: value) { return number }
        }
        if let text = captureText(chineseEpisodePattern, in: value),
           let number = chineseInteger(text) {
            return number
        }
        guard let regex = try? NSRegularExpression(pattern: #"^\s*0*(\d+)\s*(?:集|话|期|回)?\s*$"#),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let range = Range(match.range(at: 1), in: value) else { return nil }
        return Int(value[range])
    }

    private static func captureNumber(_ pattern: String, in value: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) else { return nil }
        let matchRange = match.numberOfRanges > 1 ? match.range(at: 1) : match.range
        guard let range = Range(matchRange, in: value) else { return nil }
        return Int(value[range])
    }

    private static func captureText(_ pattern: String, in value: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let range = Range(match.range(at: 1), in: value) else { return nil }
        return String(value[range])
    }

    private static func chineseInteger(_ value: String) -> Int? {
        let digits: [Character: Int] = [
            "零": 0, "〇": 0, "一": 1, "二": 2, "两": 2, "三": 3,
            "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9
        ]
        var total = 0
        var current = 0
        for character in value {
            if let digit = digits[character] {
                current = digit
            } else if character == "十" {
                total += (current == 0 ? 1 : current) * 10
                current = 0
            } else if character == "百" {
                total += (current == 0 ? 1 : current) * 100
                current = 0
            } else {
                return nil
            }
        }
        let number = total + current
        return number > 0 ? number : nil
    }

    private static func normalize(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
            .lowercased()
    }
}
