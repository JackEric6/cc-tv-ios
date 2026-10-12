import Foundation

struct DanmuAPIMatch: Equatable, Sendable {
    let animeTitle: String
    let episodeTitle: String
    let videoURL: String
    let mediaType: String

    var displayTitle: String {
        [animeTitle, episodeTitle].filter { !$0.isEmpty }.joined(separator: " ")
    }
}

enum DanmuMatchRequestPolicy {
    static func fileName(title: String, episode: String) -> String {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanEpisode = episode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanEpisode.isEmpty else { return cleanTitle }

        if let seasonEpisode = capture(#"(?i)S\s*0*(\d+)\s*E\s*0*(\d+)"#, in: cleanEpisode, groups: 2),
           let season = Int(seasonEpisode[0]), let number = Int(seasonEpisode[1]) {
            return "\(cleanTitle) S\(String(format: "%02d", season))E\(String(format: "%02d", number))"
        }

        let season = capture(#"(?i)(?:第\s*0*(\d+)\s*季|S\s*0*(\d+))"#, in: cleanEpisode, groups: 2)
            .flatMap { $0.compactMap { Int($0) }.first }
        let episodeNumber = capture(#"(?i)(?:第\s*0*(\d+)\s*(?:集|话|期|回)|EP?\s*0*(\d+))"#, in: cleanEpisode, groups: 2)
            .flatMap { $0.compactMap { Int($0) }.first }
            ?? capture(#"第\s*([零〇一二两三四五六七八九十百]+)\s*(?:集|话|期|回)"#, in: cleanEpisode, groups: 1)
                .flatMap { $0.first.flatMap(chineseNumber) }
            ?? capture(#"^\s*0*(\d+)\s*(?:集|话|期|回)?\s*$"#, in: cleanEpisode, groups: 1)
                .flatMap { $0.first.flatMap { Int($0) } }

        if let episodeNumber {
            let seasonNumber = season ?? 1
            return "\(cleanTitle) S\(String(format: "%02d", seasonNumber))E\(String(format: "%02d", episodeNumber))"
        }
        return "\(cleanTitle) \(cleanEpisode)"
    }

    static func requestBody(fileName: String) -> Data? {
        try? JSONSerialization.data(withJSONObject: ["fileName": fileName])
    }

    static func parseMatches(_ body: String) -> [DanmuAPIMatch] {
        guard let data = body.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }

        let matched = (root["isMatched"] as? Bool)
            ?? ((root["isMatched"] as? NSNumber)?.boolValue)
        guard matched != false else { return [] }

        let payload = root["data"] as? [String: Any] ?? root
        guard let matches = payload["matches"] as? [[String: Any]] else { return [] }
        return matches.compactMap { item in
            let url = string(item["url"]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let components = URLComponents(string: url),
                  let scheme = components.scheme?.lowercased(),
                  ["http", "https"].contains(scheme),
                  components.host != nil else { return nil }
            return DanmuAPIMatch(
                animeTitle: string(item["animeTitle"]),
                episodeTitle: string(item["episodeTitle"]),
                videoURL: url,
                mediaType: string(item["typeDescription"] ?? item["type"])
            )
        }
    }

    static func commentURL(baseURL: String, videoURL: String) -> String? {
        guard let media = URLComponents(string: videoURL),
              let mediaScheme = media.scheme?.lowercased(),
              ["http", "https"].contains(mediaScheme),
              media.host != nil else { return nil }
        guard let base = URL(string: baseURL),
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + ([basePath, "api/v2/comment"].filter { !$0.isEmpty }.joined(separator: "/"))
        components.queryItems = [
            URLQueryItem(name: "url", value: videoURL),
            URLQueryItem(name: "format", value: "json")
        ]
        return components.url?.absoluteString
    }

    private static func capture(_ pattern: String, in value: String, groups: Int) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              match.numberOfRanges > groups else { return nil }
        return (1...groups).compactMap { index in
            guard let range = Range(match.range(at: index), in: value) else { return nil }
            return String(value[range])
        }
    }

    private static func string(_ value: Any?) -> String {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return ""
    }

    private static func chineseNumber(_ value: String) -> Int? {
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
}
