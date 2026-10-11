import Foundation

enum DanmakuTimelinePolicy {
    static func hasUsableRendererLayout(
        viewportWidth: Double,
        viewportHeight: Double,
        rendererWidth: Double,
        rendererHeight: Double
    ) -> Bool {
        [viewportWidth, viewportHeight, rendererWidth, rendererHeight]
            .allSatisfy { $0.isFinite && $0 > 0 }
    }

    static func trackHeight(viewportHeight: Double) -> Double {
        guard viewportHeight.isFinite, viewportHeight > 0 else { return 0 }
        return min(viewportHeight, 44)
    }

    static func trackRegionHeight(
        viewportHeight: Double,
        rowCount: Int,
        trackHeight: Double
    ) -> Double {
        guard viewportHeight.isFinite, viewportHeight > 0,
              trackHeight.isFinite, trackHeight > 0 else { return 0 }
        return min(viewportHeight, Double(max(1, rowCount)) * trackHeight)
    }

    static func isPlaybackActive(isPlaying: Bool) -> Bool {
        isPlaying
    }

    static func playbackRate(_ value: Double) -> Double {
        guard value.isFinite, value > 0 else { return 1 }
        return min(max(value, 0.25), 4)
    }

    static func didSeekBackward(
        from previousTime: TimeInterval?,
        to currentTime: TimeInterval,
        tolerance: TimeInterval = 0.5
    ) -> Bool {
        guard let previousTime,
              previousTime.isFinite,
              currentTime.isFinite,
              previousTime >= 0,
              currentTime >= 0 else { return false }
        return currentTime < previousTime - max(0, tolerance)
    }

    static func didSeek(
        from expectedTime: TimeInterval?,
        to currentTime: TimeInterval,
        tolerance: TimeInterval = 1
    ) -> Bool {
        guard let expectedTime,
              expectedTime.isFinite,
              currentTime.isFinite,
              expectedTime >= 0,
              currentTime >= 0 else { return false }
        return abs(currentTime - expectedTime) > max(0, tolerance)
    }

    static func shouldDisplayCue(age: TimeInterval, duration: TimeInterval) -> Bool {
        age.isFinite && duration.isFinite && age >= 0 && age <= duration
    }

    static func canFollowScrollingBullet(
        previousRightEdge: Double,
        previousSpeed: Double,
        nextSpeed: Double,
        viewportWidth: Double,
        minimumGap: Double
    ) -> Bool {
        guard previousRightEdge.isFinite,
              previousSpeed.isFinite,
              nextSpeed.isFinite,
              viewportWidth.isFinite,
              minimumGap.isFinite,
              previousSpeed > 0,
              nextSpeed > 0,
              viewportWidth > 0 else { return false }
        guard previousRightEdge <= viewportWidth - max(0, minimumGap) else { return false }
        guard nextSpeed > previousSpeed else { return true }

        let catchUpTime = (viewportWidth - previousRightEdge) / (nextSpeed - previousSpeed)
        let previousExitTime = previousRightEdge / previousSpeed
        return catchUpTime >= previousExitTime
    }
}
