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
    case more
    case fullscreen
}

struct PlaybackToolbarLayoutDecision {
    let hiddenControls: Set<PlaybackToolbarControl>
    let timeLabelWidth: Double
    let occupiedWidth: Double
}

enum PlaybackToolbarLayoutPolicy {
    static let phoneButtonWidth = 44.0
    static let padButtonWidth = 48.0
    static let phoneSpacing = 10.0
    static let padSpacing = 12.0
    static let minimumTimeLabelWidth = 110.0

    private static let overflowPriority: [PlaybackToolbarControl] = [
        .intro,
        .outro,
        .aspectRatio,
        .danmaku,
        .episode,
        .previous,
        .next,
        .rewind,
        .forward
    ]

    static func layout(
        availableWidth: Double,
        controls: [PlaybackToolbarControl],
        widths: [PlaybackToolbarControl: Double],
        spacing: Double,
        minimumTimeLabelWidth: Double
    ) -> PlaybackToolbarLayoutDecision {
        let orderedControls = controls.filter { $0 != .more }
        var hiddenControls = Set<PlaybackToolbarControl>()
        let minimumTimeWidth = max(0, minimumTimeLabelWidth)
        var timeLabelWidth = max(minimumTimeWidth, widths[.timeLabel] ?? minimumTimeWidth)
        let safeAvailableWidth = max(0, availableWidth)
        let safeSpacing = max(0, spacing)

        func arrangedControls() -> [PlaybackToolbarControl] {
            var visible = orderedControls.filter { !hiddenControls.contains($0) }
            if !hiddenControls.isEmpty {
                if let fullscreenIndex = visible.firstIndex(of: .fullscreen) {
                    visible.insert(.more, at: fullscreenIndex)
                } else {
                    visible.append(.more)
                }
            }
            return visible
        }

        func occupiedWidth() -> Double {
            let visible = arrangedControls()
            guard !visible.isEmpty else { return 0 }
            let controlsWidth = visible.reduce(0.0) { partial, control in
                let width = control == .timeLabel
                    ? timeLabelWidth
                    : widths[control, default: 0]
                return partial + max(0, width.isFinite ? width : 0)
            }
            let gaps = safeSpacing * Double(max(0, visible.count - 1))
            return controlsWidth + gaps
        }

        for control in overflowPriority where occupiedWidth() > safeAvailableWidth {
            guard orderedControls.contains(control) else { continue }
            hiddenControls.insert(control)
        }

        if occupiedWidth() > safeAvailableWidth {
            let nonTimeWidth = occupiedWidth() - timeLabelWidth
            timeLabelWidth = max(minimumTimeWidth, safeAvailableWidth - nonTimeWidth)
        }

        if occupiedWidth() > safeAvailableWidth {
            let emergencyPriority: [PlaybackToolbarControl] = [.volume, .speed]
            for control in emergencyPriority where occupiedWidth() > safeAvailableWidth {
                guard orderedControls.contains(control) else { continue }
                hiddenControls.insert(control)
            }
        }

        let remainingTimeWidth = max(0, safeAvailableWidth - (occupiedWidth() - timeLabelWidth))
        let fullTimeWidth = max(minimumTimeWidth, widths[.timeLabel] ?? minimumTimeWidth)
        timeLabelWidth = min(fullTimeWidth, remainingTimeWidth)

        return PlaybackToolbarLayoutDecision(
            hiddenControls: hiddenControls,
            timeLabelWidth: timeLabelWidth,
            occupiedWidth: occupiedWidth()
        )
    }
}
