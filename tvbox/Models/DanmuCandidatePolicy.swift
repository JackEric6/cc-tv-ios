import Foundation

enum DanmuCandidatePolicy {
    private static let promotionalTerms = [
        "预告", "预告片", "片花", "花絮", "宣传片", "先导片", "幕后", "片段", "剪辑",
        "trailer", "teaser", "preview", "behind the scenes"
    ]

    static func automaticLoadCandidates(
        _ results: [DanmuSearchResult],
        title: String,
        episode: String
    ) -> [DanmuSearchResult] {
        let titleKey = DanmakuCacheKey.normalizeTitle(title)
        let episodeNumber = DanmakuEpisodeMatcher.episodeNumber(in: episode) ?? 0
        let requestedMovie = isMovie(episode)

        return results.filter { result in
            let label = result.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let candidateText = "\(label) \(result.url)"
            guard !containsPromotionalMarker(candidateText) else { return false }

            let isURLLabel = URL(string: label)?.scheme != nil
            let candidateTitle = DanmakuCacheKey.normalizeTitle(label)
            guard isURLLabel || titleKey.isEmpty || candidateTitle.contains(titleKey) else {
                return false
            }

            let resultIsMovie = isMovie(result.mediaType ?? "") || isMovie(label)
            if episodeNumber > 0 {
                if requestedMovie { return resultIsMovie }
                if resultIsMovie { return episodeNumber == 1 }
                return DanmakuEpisodeMatcher.matches(requestedEpisode: episode, title: label)
            }
            if requestedMovie || resultIsMovie || episode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return true
            }
            return DanmakuEpisodeMatcher.matches(requestedEpisode: episode, title: label)
                || candidateTitle.contains(DanmakuCacheKey.normalizeTitle(episode))
        }
    }

    static func isPromotional(_ value: String) -> Bool {
        containsPromotionalMarker(value)
    }

    static func isMovie(_ value: String) -> Bool {
        ["电影", "movie", "film"].contains { value.localizedCaseInsensitiveContains($0) }
    }

    private static func containsPromotionalMarker(_ value: String) -> Bool {
        if promotionalTerms.contains(where: { value.localizedCaseInsensitiveContains($0) }) {
            return true
        }
        return value.range(
            of: #"(?i)(?:^|[^A-Z0-9])PV\d*(?:$|[^A-Z0-9])"#,
            options: .regularExpression
        ) != nil
    }
}
