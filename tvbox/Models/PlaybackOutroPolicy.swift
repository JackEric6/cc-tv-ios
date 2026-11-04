import Foundation

enum PlaybackOutroPolicy {
    static func remainingTime(currentTime: Double, duration: Double) -> Double? {
        guard currentTime.isFinite,
              duration.isFinite,
              currentTime >= 0,
              duration > 0 else {
            return nil
        }

        return max(0, duration - min(currentTime, duration))
    }

    static func shouldAdvance(
        currentTime: Double,
        duration: Double,
        remainingTime: Double
    ) -> Bool {
        guard remainingTime.isFinite, remainingTime > 0,
              let currentRemainingTime = self.remainingTime(
                currentTime: currentTime,
                duration: duration
              ) else {
            return false
        }

        return currentRemainingTime <= remainingTime
    }
}
