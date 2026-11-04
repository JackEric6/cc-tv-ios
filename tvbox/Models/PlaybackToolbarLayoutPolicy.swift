import Foundation

enum PlaybackToolbarControl: String, CaseIterable, Hashable {
    case rewind
    case play
    case forward
    case timeLabel
    case previous
    case next
    case volume
    case speed
    case aspectRatio
    case episode
    case danmaku
    case intro
    case outro
    case fullscreen
}

struct PlaybackToolbarLayoutDecision {
    let timeLabelWidth: Double
    let occupiedWidth: Double
}

enum PlaybackToolbarLayoutPolicy {
    static let phoneButtonWidth = 28.0
    static let padButtonWidth = 34.0
    static let nativeButtonWidth = 30.0
    static let playbackRateButtonWidth = 28.0
    static let phoneDanmakuButtonWidth = 40.0
    static let padDanmakuButtonWidth = 52.0
    static let phoneMarkerButtonWidth = 52.0
    static let padMarkerButtonWidth = 64.0
    static let verticalSeekStackWidth = 46.0
    static let verticalSeekButtonHeight = 42.0
    static let phoneSpacing = 5.0
    static let padSpacing = 10.0
    static let phonePlaybackRateSpacing = 10.0
    static let padPlaybackRateSpacing = 16.0
    static let minimumTimeLabelWidth = 80.0

    static func layout(
        availableWidth: Double,
        controls: [PlaybackToolbarControl],
        widths: [PlaybackToolbarControl: Double],
        spacing: Double,
        customSpacingAfter: [PlaybackToolbarControl: Double] = [:]
    ) -> PlaybackToolbarLayoutDecision {
        let safeAvailableWidth = max(0, availableWidth.isFinite ? availableWidth : 0)
        let safeSpacing = max(0, spacing.isFinite ? spacing : 0)
        let timeLabelWidth = min(
            max(0, widths[.timeLabel] ?? 0),
            max(0, safeAvailableWidth - fixedControlsWidth(
                controls: controls,
                widths: widths,
                spacing: safeSpacing,
                customSpacingAfter: customSpacingAfter
            ))
        )
        let occupiedWidth = fixedControlsWidth(
            controls: controls,
            widths: widths,
            spacing: safeSpacing,
            customSpacingAfter: customSpacingAfter
        ) + timeLabelWidth

        return PlaybackToolbarLayoutDecision(
            timeLabelWidth: timeLabelWidth,
            occupiedWidth: occupiedWidth
        )
    }

    private static func fixedControlsWidth(
        controls: [PlaybackToolbarControl],
        widths: [PlaybackToolbarControl: Double],
        spacing: Double,
        customSpacingAfter: [PlaybackToolbarControl: Double]
    ) -> Double {
        let fixedWidth = controls
            .filter { $0 != .timeLabel }
            .reduce(0.0) { partial, control in
                let width = widths[control, default: 0]
                return partial + max(0, width.isFinite ? width : 0)
            }
        let gaps = zip(controls, controls.dropFirst()).reduce(0.0) { total, pair in
            let requestedGap = customSpacingAfter[pair.0] ?? spacing
            return total + max(0, requestedGap.isFinite ? requestedGap : 0)
        }
        return fixedWidth + gaps
    }
}
