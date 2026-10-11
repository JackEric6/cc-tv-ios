import Foundation

struct DanmakuScrollPosition: Equatable {
    let left: Double
    let right: Double
}

struct DanmakuScrollTrajectory: Equatable {
    let startTime: TimeInterval
    let duration: TimeInterval
    let width: Double

    func speed(viewportWidth: Double) -> Double? {
        guard duration.isFinite, duration > 0, width.isFinite, width >= 0,
              viewportWidth.isFinite, viewportWidth > 0 else { return nil }
        return (viewportWidth + width) / duration
    }

    func position(at time: TimeInterval, viewportWidth: Double) -> DanmakuScrollPosition? {
        guard time.isFinite, startTime.isFinite, duration.isFinite, duration > 0,
              viewportWidth.isFinite, viewportWidth > 0, width.isFinite, width >= 0 else {
            return nil
        }
        let progress = min(max((time - startTime) / duration, 0), 1)
        let left = viewportWidth - (viewportWidth + width) * progress
        return DanmakuScrollPosition(left: left, right: left + width)
    }
}

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

    static func trackHeight(viewportHeight: Double, sizeScale: Double = 0.8) -> Double {
        guard viewportHeight.isFinite, viewportHeight > 0 else { return 0 }
        let normalizedScale = sizeScale.isFinite ? min(max(sizeScale, 0.1), 1.6) : 0.8
        return min(viewportHeight, max(28, 25 * normalizedScale + 8))
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

    /// Scrolling cells travel one viewport plus their own width. Scaling their
    /// lifetime by that distance keeps their pixel speed independent of text length.
    static func scrollingDuration(
        baseDuration: TimeInterval,
        viewportWidth: Double,
        cueWidth: Double
    ) -> TimeInterval {
        guard baseDuration.isFinite, baseDuration > 0,
              viewportWidth.isFinite, viewportWidth > 0,
              cueWidth.isFinite, cueWidth >= 0 else { return 0 }
        return baseDuration * (viewportWidth + cueWidth) / viewportWidth
    }

    static func activeDisplayWindow(
        baseDuration: TimeInterval,
        viewportWidth: Double,
        maximumTextLength: Int,
        maximumFontSize: Double,
        minimumWindow: TimeInterval = 5
    ) -> TimeInterval {
        guard baseDuration.isFinite, baseDuration > 0,
              viewportWidth.isFinite, viewportWidth > 0,
              maximumFontSize.isFinite, maximumFontSize > 0 else {
            return max(0, minimumWindow.isFinite ? minimumWindow : 0)
        }
        let safeLength = Double(max(0, maximumTextLength))
        let estimatedWidth = safeLength * maximumFontSize + 8
        return max(
            max(0, minimumWindow.isFinite ? minimumWindow : 0),
            scrollingDuration(
                baseDuration: baseDuration,
                viewportWidth: viewportWidth,
                cueWidth: estimatedWidth
            )
        )
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

    static func canPlace(
        _ candidate: DanmakuScrollTrajectory,
        with existing: [DanmakuScrollTrajectory],
        at time: TimeInterval,
        viewportWidth: Double,
        minimumGap: Double
    ) -> Bool {
        guard let candidatePosition = candidate.position(at: time, viewportWidth: viewportWidth),
              let candidateSpeed = candidate.speed(viewportWidth: viewportWidth),
              candidateSpeed > 0 else { return false }

        for previous in existing {
            guard let previousPosition = previous.position(at: time, viewportWidth: viewportWidth),
                  let previousSpeed = previous.speed(viewportWidth: viewportWidth),
                  previousSpeed > 0,
                  previousPosition.right > 0 else { continue }

            let gap = candidatePosition.left - previousPosition.right
            guard gap >= max(0, minimumGap) else { return false }

            if candidateSpeed > previousSpeed {
                let catchUpTime = gap / (candidateSpeed - previousSpeed)
                let previousExitTime = max(0, previousPosition.right) / previousSpeed
                if catchUpTime < previousExitTime { return false }
            }
        }

        return true
    }
}
