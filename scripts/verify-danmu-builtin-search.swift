import Foundation

@main
struct VerifyDanmuBuiltinSearch {
    static func main() {
        precondition(DanmuBuiltinSearchPolicy.shouldSearchFocusedEpisode(episodeNumber: 1))
        precondition(DanmuBuiltinSearchPolicy.shouldSearchFocusedEpisode(episodeNumber: 25))
        precondition(!DanmuBuiltinSearchPolicy.shouldSearchFocusedEpisode(episodeNumber: 0))

        precondition(!DanmuBuiltinSearchPolicy.shouldRunFallbackSearch(episodeNumber: 5, focusedCandidateCount: 2))
        precondition(DanmuBuiltinSearchPolicy.shouldRunFallbackSearch(episodeNumber: 5, focusedCandidateCount: 0))
        precondition(DanmuBuiltinSearchPolicy.shouldRunFallbackSearch(episodeNumber: 0, focusedCandidateCount: 0))

        print("DANMU BUILTIN SEARCH PRIORITY CHECKS PASSED")
    }
}
