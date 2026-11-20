import Foundation

enum PlaybackVideoFramePolicy {
    static let firstFrameTimeout: TimeInterval = 8
    static let requiredPlaybackAdvance: TimeInterval = 1

    static func activePlaybackElapsed(
        accumulated: TimeInterval,
        resumedAt: TimeInterval?,
        now: TimeInterval
    ) -> TimeInterval {
        let priorElapsed = accumulated.isFinite ? max(0, accumulated) : 0
        guard let resumedAt, resumedAt.isFinite, now.isFinite else { return priorElapsed }
        let currentElapsed = now - resumedAt
        guard currentElapsed.isFinite else { return priorElapsed }
        return priorElapsed + max(0, currentElapsed)
    }

    static func shouldRecover(
        elapsed: TimeInterval,
        playbackAdvance: TimeInterval,
        isPlaying: Bool,
        hasVideoTrack: Bool,
        hasDisplayedFrame: Bool
    ) -> Bool {
        elapsed.isFinite
            && playbackAdvance.isFinite
            && elapsed >= firstFrameTimeout
            && playbackAdvance >= requiredPlaybackAdvance
            && isPlaying
            && hasVideoTrack
            && !hasDisplayedFrame
    }
}
