import Foundation

enum DanmakuCacheKey {
    static func make(title: String, episode: String) -> String? {
        let normalizedTitle = normalizeTitle(title)
        guard !normalizedTitle.isEmpty else { return nil }
        return "\(normalizedTitle)\u{1F}\(normalizeEpisode(episode))"
    }

    static func normalizeTitle(_ value: String) -> String {
        var title = value
            .replacingOccurrences(of: "&nbsp;", with: " ", options: .caseInsensitive)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        title = title.replacingOccurrences(
            of: #"(?i)\b(?:2160p|1080p|720p|480p|4k|8k|uhd|fhd|hd)\b"#,
            with: "",
            options: .regularExpression
        )
        for suffix in ["超清", "高清", "蓝光", "国语", "粤语", "中字", "未删减", "完整版"] {
            title = title.replacingOccurrences(of: suffix, with: "", options: .caseInsensitive)
        }
        let folded = title.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "zh_CN")
        )
        let scalars = folded.unicodeScalars.filter {
            !CharacterSet.whitespacesAndNewlines.contains($0)
                && !CharacterSet.punctuationCharacters.contains($0)
                && !CharacterSet.symbols.contains($0)
        }
        return String(String.UnicodeScalarView(scalars)).lowercased()
    }

    static func normalizeEpisode(_ value: String) -> String {
        let episode = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !episode.isEmpty else { return "feature" }

        if let seasonEpisode = capture(
            #"(?i)S\s*0*(\d+)\s*E\s*0*(\d+)"#,
            in: episode,
            groups: 2
        ) {
            return "s\(integerString(seasonEpisode[0]))e\(integerString(seasonEpisode[1]))"
        }

        let season = capture(#"第\s*0*(\d+)\s*季"#, in: episode, groups: 1)?.first
            ?? capture(#"(?i)S\s*0*(\d+)"#, in: episode, groups: 1)?.first
        let episodeNumber = capture(#"第\s*0*(\d+)\s*(?:集|话|期|回)"#, in: episode, groups: 1)?.first
            ?? capture(#"(?i)(?:^|[^A-Za-z])EP?\s*0*(\d+)"#, in: episode, groups: 1)?.first
            ?? capture(#"^\s*0*(\d+)\s*(?:集|话|期|回)?\s*$"#, in: episode, groups: 1)?.first
            ?? capture(#"第\s*([零〇一二两三四五六七八九十百]+)\s*(?:集|话|期|回)"#, in: episode, groups: 1)
                .flatMap { $0.first.flatMap(chineseInteger) }

        if let episodeNumber {
            let seasonPart = season.map { "s\(integerString($0))" } ?? ""
            return "\(seasonPart)e\(integerString(episodeNumber))"
        }

        let folded = episode.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "zh_CN")
        )
        let scalars = folded.unicodeScalars.filter {
            !CharacterSet.whitespacesAndNewlines.contains($0)
                && !CharacterSet.punctuationCharacters.contains($0)
                && !CharacterSet.symbols.contains($0)
        }
        let label = String(String.UnicodeScalarView(scalars)).lowercased()
        return label.isEmpty ? "feature" : "label:\(label)"
    }

    private static func capture(_ pattern: String, in value: String, groups: Int) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              match.numberOfRanges > groups else { return nil }
        var values: [String] = []
        for index in 1...groups {
            guard let range = Range(match.range(at: index), in: value) else { return nil }
            values.append(String(value[range]))
        }
        return values
    }

    private static func integerString(_ value: String) -> String {
        String(Int(value) ?? 0)
    }

    private static func chineseInteger(_ value: String) -> String? {
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
        return number > 0 ? String(number) : nil
    }
}
