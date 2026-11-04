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
    static let phoneButtonWidth = 40.0
    static let padButtonWidth = 48.0
    static let phoneSpacing = 10.0
    static let padSpacing = 12.0
    static let minimumTimeLabelWidth = 80.0

    static func layout(
        availableWidth: Double,
        controls: [PlaybackToolbarControl],
        widths: [PlaybackToolbarControl: Double],
        spacing: Double
    ) -> PlaybackToolbarLayoutDecision {
        let safeAvailableWidth = max(0, availableWidth.isFinite ? availableWidth : 0)
        let safeSpacing = max(0, spacing.isFinite ? spacing : 0)
        let timeLabelWidth = min(
            max(0, widths[.timeLabel] ?? 0),
            max(0, safeAvailableWidth - fixedControlsWidth(
                controls: controls,
                widths: widths,
                spacing: safeSpacing
            ))
        )
        let occupiedWidth = fixedControlsWidth(
            controls: controls,
            widths: widths,
            spacing: safeSpacing
        ) + timeLabelWidth

        return PlaybackToolbarLayoutDecision(
            timeLabelWidth: timeLabelWidth,
            occupiedWidth: occupiedWidth
        )
    }

    private static func fixedControlsWidth(
        controls: [PlaybackToolbarControl],
        widths: [PlaybackToolbarControl: Double],
        spacing: Double
    ) -> Double {
        let fixedWidth = controls
            .filter { $0 != .timeLabel }
            .reduce(0.0) { partial, control in
                let width = widths[control, default: 0]
                return partial + max(0, width.isFinite ? width : 0)
            }
        return fixedWidth + spacing * Double(max(0, controls.count - 1))
    }
}
