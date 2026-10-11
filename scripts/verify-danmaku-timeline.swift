import Foundation

@main
struct VerifyDanmakuTimeline {
    static func main() {
        precondition(!DanmakuTimelinePolicy.hasUsableRendererLayout(
            viewportWidth: 0,
            viewportHeight: 0,
            rendererWidth: 0,
            rendererHeight: 0
        ))
        precondition(!DanmakuTimelinePolicy.hasUsableRendererLayout(
            viewportWidth: 390,
            viewportHeight: 844,
            rendererWidth: 390,
            rendererHeight: 0
        ))
        precondition(DanmakuTimelinePolicy.hasUsableRendererLayout(
            viewportWidth: 390,
            viewportHeight: 844,
            rendererWidth: 390,
            rendererHeight: 132
        ))
        precondition(DanmakuTimelinePolicy.trackHeight(viewportHeight: 390) == 28)
        precondition(DanmakuTimelinePolicy.trackRegionHeight(
            viewportHeight: 390,
            rowCount: 3,
            trackHeight: 28
        ) == 84)
        precondition(DanmakuTimelinePolicy.trackRegionHeight(
            viewportHeight: 90,
            rowCount: 3,
            trackHeight: 28
        ) == 84)
        precondition(DanmakuTimelinePolicy.trackHeight(viewportHeight: 390, sizeScale: 1.6) == 48)
        let shortDuration = DanmakuTimelinePolicy.scrollingDuration(
            baseDuration: 8,
            viewportWidth: 390,
            cueWidth: 40
        )
        let longDuration = DanmakuTimelinePolicy.scrollingDuration(
            baseDuration: 8,
            viewportWidth: 390,
            cueWidth: 400
        )
        precondition(shortDuration > 8)
        precondition(longDuration > shortDuration)
        precondition(abs(430.0 / shortDuration - 790.0 / longDuration) < 0.0001)
        precondition(DanmakuTimelinePolicy.scrollingDuration(
            baseDuration: 8,
            viewportWidth: 0,
            cueWidth: 40
        ) == 0)
        let shortSeekWindow = DanmakuTimelinePolicy.activeDisplayWindow(
            baseDuration: 8,
            viewportWidth: 1000,
            maximumTextLength: 12,
            maximumFontSize: 36
        )
        let longSeekWindow = DanmakuTimelinePolicy.activeDisplayWindow(
            baseDuration: 8,
            viewportWidth: 1000,
            maximumTextLength: 80,
            maximumFontSize: 36
        )
        precondition(shortSeekWindow >= 5)
        precondition(longSeekWindow > shortSeekWindow)
        precondition(DanmakuTimelinePolicy.activeDisplayWindow(
            baseDuration: 8,
            viewportWidth: 0,
            maximumTextLength: 12,
            maximumFontSize: 36
        ) == 5)
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
        let slowCue = DanmakuScrollTrajectory(startTime: 0, duration: 10, width: 100)
        let fasterCue = DanmakuScrollTrajectory(startTime: 2, duration: 5, width: 20)
        precondition(!DanmakuTimelinePolicy.canPlace(
            fasterCue,
            with: [slowCue],
            at: 2,
            viewportWidth: 1000,
            minimumGap: 18
        ))
        let laterFastCue = DanmakuScrollTrajectory(startTime: 8.5, duration: 3, width: 20)
        precondition(DanmakuTimelinePolicy.canPlace(
            laterFastCue,
            with: [slowCue],
            at: 8.5,
            viewportWidth: 1000,
            minimumGap: 18
        ))
        let shortCueDuration = DanmakuTimelinePolicy.scrollingDuration(
            baseDuration: 8,
            viewportWidth: 1000,
            cueWidth: 40
        )
        let longCueDuration = DanmakuTimelinePolicy.scrollingDuration(
            baseDuration: 8,
            viewportWidth: 1000,
            cueWidth: 400
        )
        precondition(abs((1000 + 40) / shortCueDuration - (1000 + 400) / longCueDuration) < 0.0001)
        print("DANMAKU TIMELINE CHECKS PASSED")
    }
}
