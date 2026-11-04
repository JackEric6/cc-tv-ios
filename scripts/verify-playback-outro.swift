import Foundation

@main
struct VerifyPlaybackOutro {
    static func main() {
        precondition(PlaybackOutroPolicy.remainingTime(currentTime: 600, duration: 720) == 120)
        precondition(PlaybackOutroPolicy.shouldAdvance(
            currentTime: 599,
            duration: 720,
            remainingTime: 121
        ))
        precondition(!PlaybackOutroPolicy.shouldAdvance(
            currentTime: 598,
            duration: 720,
            remainingTime: 121
        ))

        // The same configured tail interval applies to episodes of different lengths.
        precondition(PlaybackOutroPolicy.shouldAdvance(
            currentTime: 5_279,
            duration: 5_400,
            remainingTime: 121
        ))
        precondition(!PlaybackOutroPolicy.shouldAdvance(
            currentTime: 5_278,
            duration: 5_400,
            remainingTime: 121
        ))

        precondition(PlaybackOutroPolicy.remainingTime(currentTime: 900, duration: 720) == 0)
        precondition(PlaybackOutroPolicy.remainingTime(currentTime: .nan, duration: 720) == nil)
        precondition(PlaybackOutroPolicy.remainingTime(currentTime: 1, duration: 0) == nil)
        precondition(!PlaybackOutroPolicy.shouldAdvance(
            currentTime: 719,
            duration: 720,
            remainingTime: 0
        ))

        print("PLAYBACK OUTRO REMAINING-TIME CHECKS PASSED")
    }
}
