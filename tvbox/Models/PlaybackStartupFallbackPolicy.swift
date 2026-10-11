import Foundation

enum PlaybackStartupFallbackPolicy {
    static let timeout: TimeInterval = 20
    static let requiredProgressAdvance: TimeInterval = 1

    static func shouldFallback(
        elapsed: TimeInterval,
        startingProgress: TimeInterval,
        currentProgress: TimeInterval
    ) -> Bool {
        guard elapsed.isFinite,
              startingProgress.isFinite,
              currentProgress.isFinite,
              elapsed >= timeout else { return false }
        return currentProgress < startingProgress + requiredProgressAdvance
    }
}
