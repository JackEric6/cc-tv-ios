import Foundation

@main
struct VerifyPlayerToolbarLayout {
    private static let phoneWidths: [PlaybackToolbarControl: Double] = [
        .rewind: PlaybackToolbarLayoutPolicy.phoneButtonWidth,
        .play: PlaybackToolbarLayoutPolicy.phoneButtonWidth,
        .forward: PlaybackToolbarLayoutPolicy.phoneButtonWidth,
        .timeLabel: 180,
        .previous: PlaybackToolbarLayoutPolicy.phoneButtonWidth,
        .next: PlaybackToolbarLayoutPolicy.phoneButtonWidth,
        .volume: PlaybackToolbarLayoutPolicy.phoneButtonWidth,
        .speed: PlaybackToolbarLayoutPolicy.phoneButtonWidth,
        .aspectRatio: PlaybackToolbarLayoutPolicy.phoneButtonWidth,
        .episode: PlaybackToolbarLayoutPolicy.phoneButtonWidth,
        .danmaku: PlaybackToolbarLayoutPolicy.phoneButtonWidth,
        .intro: 58,
        .outro: 58,
        .more: PlaybackToolbarLayoutPolicy.phoneButtonWidth,
        .fullscreen: PlaybackToolbarLayoutPolicy.phoneButtonWidth
    ]

    private static let padWidths: [PlaybackToolbarControl: Double] = [
        .rewind: PlaybackToolbarLayoutPolicy.padButtonWidth,
        .play: PlaybackToolbarLayoutPolicy.padButtonWidth,
        .forward: PlaybackToolbarLayoutPolicy.padButtonWidth,
        .timeLabel: 180,
        .previous: PlaybackToolbarLayoutPolicy.padButtonWidth,
        .next: PlaybackToolbarLayoutPolicy.padButtonWidth,
        .volume: PlaybackToolbarLayoutPolicy.padButtonWidth,
        .speed: PlaybackToolbarLayoutPolicy.padButtonWidth,
        .aspectRatio: PlaybackToolbarLayoutPolicy.padButtonWidth,
        .episode: PlaybackToolbarLayoutPolicy.padButtonWidth,
        .danmaku: 52,
        .intro: 64,
        .outro: 64,
        .more: PlaybackToolbarLayoutPolicy.padButtonWidth,
        .fullscreen: PlaybackToolbarLayoutPolicy.padButtonWidth
    ]

    private static let landscapeControls: [PlaybackToolbarControl] = [
        .rewind, .play, .forward, .timeLabel, .previous, .next, .volume,
        .speed, .aspectRatio, .episode, .danmaku, .intro, .outro, .fullscreen
    ]

    private static let portraitControls: [PlaybackToolbarControl] = [
        .play, .timeLabel, .volume, .speed, .intro, .outro, .fullscreen
    ]

    static func main() {
        var checks = 0

        // Scan every half-point width across phone, iPad, portrait, and landscape
        // layouts so transitions into and out of overflow are exercised directly.
        for halfPointWidth in 560...3_200 {
            let screenWidth = Double(halfPointWidth) / 2
            for isPad in [false, true] {
                for isLandscape in [false, true] {
                    for canSelectEpisode in (isLandscape ? [false, true] : [false]) {
                        verifyScenario(
                            screenWidth: screenWidth,
                            isPad: isPad,
                            isLandscape: isLandscape,
                            canSelectEpisode: canSelectEpisode
                        )
                        checks += 1
                    }
                }
            }
        }

        // Repeated rotation and split-view width changes catch stale decisions
        // that can otherwise leave controls hidden or overlap after a resize.
        let rotationWidths = [320.0, 568, 667, 744, 768, 820, 1024, 1180, 1366, 420, 540, 834]
        for cycle in 0..<12_000 {
            let screenWidth = rotationWidths[cycle % rotationWidths.count]
            let isPad = cycle.isMultiple(of: 3) || screenWidth >= 744
            let isLandscape = cycle.isMultiple(of: 2)
            verifyScenario(
                screenWidth: screenWidth,
                isPad: isPad,
                isLandscape: isLandscape,
                canSelectEpisode: cycle.isMultiple(of: 5)
            )
            checks += 1
        }

        // Deterministic pseudo-random widths cover unusual split-screen sizes.
        var seed: UInt64 = 0x5EED
        for _ in 0..<20_000 {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1
            let screenWidth = 280.0 + Double(seed % 1_521)
            let isPad = seed.isMultiple(of: 3)
            verifyScenario(
                screenWidth: screenWidth,
                isPad: isPad,
                isLandscape: seed.isMultiple(of: 2),
                canSelectEpisode: seed.isMultiple(of: 5)
            )
            checks += 1
        }

        print("PLAYER TOOLBAR LAYOUT CHECKS PASSED: \(checks) width, rotation, and overflow simulations")
    }

    private static func verifyScenario(
        screenWidth: Double,
        isPad: Bool,
        isLandscape: Bool,
        canSelectEpisode: Bool
    ) {
        let horizontalInsets = isPad ? 64.0 : 28.0
        let availableWidth = max(180, screenWidth - horizontalInsets)
        let spacing = isPad
            ? PlaybackToolbarLayoutPolicy.padSpacing
            : PlaybackToolbarLayoutPolicy.phoneSpacing
        var controls = isLandscape ? landscapeControls : portraitControls
        if isLandscape && !canSelectEpisode {
            controls.removeAll { $0 == .episode }
        }
        let widths = isPad ? padWidths : phoneWidths
        let decision = PlaybackToolbarLayoutPolicy.layout(
            availableWidth: availableWidth,
            controls: controls,
            widths: widths,
            spacing: spacing,
            minimumTimeLabelWidth: PlaybackToolbarLayoutPolicy.minimumTimeLabelWidth
        )
        verifyNoOverlap(
            decision,
            availableWidth: availableWidth,
            controls: controls,
            widths: widths,
            spacing: spacing,
            isPad: isPad
        )
    }

    private static func verifyNoOverlap(
        _ decision: PlaybackToolbarLayoutDecision,
        availableWidth: Double,
        controls: [PlaybackToolbarControl],
        widths: [PlaybackToolbarControl: Double],
        spacing: Double,
        isPad: Bool
    ) {
        precondition(widths[.more, default: 0] >= (isPad
            ? PlaybackToolbarLayoutPolicy.padButtonWidth
            : PlaybackToolbarLayoutPolicy.phoneButtonWidth))
        precondition(!decision.hiddenControls.contains(.play))
        precondition(!decision.hiddenControls.contains(.timeLabel))
        precondition(!decision.hiddenControls.contains(.fullscreen))

        var visible = controls.filter { !decision.hiddenControls.contains($0) }
        if !decision.hiddenControls.isEmpty {
            if let fullscreenIndex = visible.firstIndex(of: .fullscreen) {
                visible.insert(.more, at: fullscreenIndex)
            } else {
                visible.append(.more)
            }
        }

        var rightEdge = 0.0
        for (index, control) in visible.enumerated() {
            if index > 0 {
                let gap = spacing
                let nextLeftEdge = rightEdge + gap
                precondition(nextLeftEdge >= rightEdge + spacing - 0.001)
                rightEdge = nextLeftEdge
            }

            let width = control == .timeLabel
                ? decision.timeLabelWidth
                : widths[control, default: 0]
            precondition(width.isFinite && width >= 0)
            if control != .timeLabel {
                let minimumButtonWidth = isPad
                    ? PlaybackToolbarLayoutPolicy.padButtonWidth
                    : PlaybackToolbarLayoutPolicy.phoneButtonWidth
                precondition(width >= minimumButtonWidth)
            }
            rightEdge += width
        }

        precondition(rightEdge <= availableWidth + 0.001)
        precondition(abs(rightEdge - decision.occupiedWidth) < 0.001)
    }
}
