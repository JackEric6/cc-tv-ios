import Foundation

@main
struct VerifyPlaybackVideoFrame {
    static func main() {
        precondition(PlaybackVideoFramePolicy.activePlaybackElapsed(
            accumulated: 0,
            resumedAt: 100,
            now: 105
        ) == 5)
        let elapsedAfterBuffer = PlaybackVideoFramePolicy.activePlaybackElapsed(
            accumulated: 5,
            resumedAt: nil,
            now: 205
        )
        precondition(elapsedAfterBuffer == 5, "Buffering time must not count toward the first-frame timeout")
        precondition(!PlaybackVideoFramePolicy.shouldRecover(
            elapsed: elapsedAfterBuffer,
            playbackAdvance: 5,
            isPlaying: true,
            hasVideoTrack: true,
            hasDisplayedFrame: false
        ))
        let elapsedAfterResume = PlaybackVideoFramePolicy.activePlaybackElapsed(
            accumulated: 5,
            resumedAt: 205,
            now: 208
        )
        precondition(elapsedAfterResume == 8)
        precondition(PlaybackVideoFramePolicy.shouldRecover(
            elapsed: elapsedAfterResume,
            playbackAdvance: 1,
            isPlaying: true,
            hasVideoTrack: true,
            hasDisplayedFrame: false
        ))
        precondition(!PlaybackVideoFramePolicy.shouldRecover(
            elapsed: 7.9,
            playbackAdvance: 5,
            isPlaying: true,
            hasVideoTrack: true,
            hasDisplayedFrame: false
        ))
        precondition(PlaybackVideoFramePolicy.shouldRecover(
            elapsed: 8,
            playbackAdvance: 1,
            isPlaying: true,
            hasVideoTrack: true,
            hasDisplayedFrame: false
        ))
        precondition(!PlaybackVideoFramePolicy.shouldRecover(
            elapsed: 9,
            playbackAdvance: 0.5,
            isPlaying: true,
            hasVideoTrack: true,
            hasDisplayedFrame: false
        ))
        precondition(!PlaybackVideoFramePolicy.shouldRecover(
            elapsed: 9,
            playbackAdvance: 5,
            isPlaying: false,
            hasVideoTrack: true,
            hasDisplayedFrame: false
        ))
        precondition(!PlaybackVideoFramePolicy.shouldRecover(
            elapsed: 9,
            playbackAdvance: 5,
            isPlaying: true,
            hasVideoTrack: false,
            hasDisplayedFrame: false
        ))
        precondition(!PlaybackVideoFramePolicy.shouldRecover(
            elapsed: 9,
            playbackAdvance: 5,
            isPlaying: true,
            hasVideoTrack: true,
            hasDisplayedFrame: true
        ))
        print("PLAYBACK VIDEO FRAME RECOVERY CHECKS PASSED")
    }
}
