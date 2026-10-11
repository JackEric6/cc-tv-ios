import Foundation

@main
struct VerifyDanmakuTimeline {
    static func main() {
        precondition(DanmakuTimelinePolicy.trackHeight(viewportHeight: 390) == 44)
        precondition(DanmakuTimelinePolicy.trackRegionHeight(
            viewportHeight: 390,
            rowCount: 3,
            trackHeight: 44
        ) == 132)
        precondition(DanmakuTimelinePolicy.trackRegionHeight(
            viewportHeight: 90,
            rowCount: 3,
            trackHeight: 44
        ) == 90)
        precondition(DanmakuTimelinePolicy.isPlaybackActive(isPlaying: true))
        precondition(!DanmakuTimelinePolicy.isPlaybackActive(isPlaying: false))
        precondition(DanmakuTimelinePolicy.shouldDisplayCue(age: 2, duration: 8))
        precondition(DanmakuTimelinePolicy.shouldDisplayCue(age: 7.5, duration: 8))
        precondition(!DanmakuTimelinePolicy.shouldDisplayCue(age: 8.1, duration: 8))
        precondition(!DanmakuTimelinePolicy.shouldDisplayCue(age: -.infinity, duration: 8))
        precondition(!DanmakuTimelinePolicy.didSeekBackward(from: nil, to: 0))
        precondition(!DanmakuTimelinePolicy.didSeekBackward(from: 3, to: 4.5))
        precondition(!DanmakuTimelinePolicy.didSeekBackward(from: 10, to: 9.6))
        precondition(DanmakuTimelinePolicy.didSeekBackward(from: 10, to: 9.4))
        precondition(!DanmakuTimelinePolicy.didSeekBackward(from: 10, to: .infinity))
        precondition(!DanmakuTimelinePolicy.didSeek(from: 10, to: 10.8))
        precondition(DanmakuTimelinePolicy.didSeek(from: 10, to: 15))
        precondition(DanmakuTimelinePolicy.didSeek(from: 15, to: 10))
        precondition(!DanmakuTimelinePolicy.didSeek(from: 10, to: .infinity))
        precondition(DanmakuTimelinePolicy.playbackRate(2) == 2)
        precondition(DanmakuTimelinePolicy.playbackRate(0) == 1)
        precondition(DanmakuTimelinePolicy.playbackRate(8) == 4)
        precondition(DanmakuTimelinePolicy.canFollowScrollingBullet(
            previousRightEdge: 700,
            previousSpeed: 100,
            nextSpeed: 125,
            viewportWidth: 1000,
            minimumGap: 0
        ))
        precondition(!DanmakuTimelinePolicy.canFollowScrollingBullet(
            previousRightEdge: 900,
            previousSpeed: 100,
            nextSpeed: 125,
            viewportWidth: 1000,
            minimumGap: 0
        ))
        print("DANMAKU TIMELINE CHECKS PASSED")
    }
}
