import Foundation

enum DanmuBuiltinSearchPolicy {
    static func shouldSearchFocusedEpisode(episodeNumber: Int) -> Bool {
        episodeNumber > 0
    }

    static func shouldRunFallbackSearch(episodeNumber: Int, focusedCandidateCount: Int) -> Bool {
        episodeNumber <= 0 || focusedCandidateCount == 0
    }
}
