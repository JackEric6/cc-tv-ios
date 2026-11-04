import Foundation

@main
struct VerifyPlayerToolbarLayout {
    private static let phoneWidths: [PlaybackToolbarControl: Double] = [
        .rewind: PlaybackToolbarLayoutPolicy.phoneButtonWidth,
        .play: PlaybackToolbarLayoutPolicy.nativeButtonWidth,
        .forward: PlaybackToolbarLayoutPolicy.phoneButtonWidth,
        .timeLabel: 180,
        .previous: PlaybackToolbarLayoutPolicy.phoneButtonWidth,
        .next: PlaybackToolbarLayoutPolicy.phoneButtonWidth,
        .volume: PlaybackToolbarLayoutPolicy.phoneButtonWidth,
        .speed: PlaybackToolbarLayoutPolicy.playbackRateButtonWidth,
        .aspectRatio: PlaybackToolbarLayoutPolicy.phoneButtonWidth,
        .episode: PlaybackToolbarLayoutPolicy.phoneButtonWidth,
        .danmaku: PlaybackToolbarLayoutPolicy.phoneDanmakuButtonWidth,
        .intro: PlaybackToolbarLayoutPolicy.phoneMarkerButtonWidth,
        .outro: PlaybackToolbarLayoutPolicy.phoneMarkerButtonWidth,
        .fullscreen: PlaybackToolbarLayoutPolicy.nativeButtonWidth
    ]

    private static let padWidths: [PlaybackToolbarControl: Double] = [
        .rewind: PlaybackToolbarLayoutPolicy.padButtonWidth,
        .play: PlaybackToolbarLayoutPolicy.nativeButtonWidth,
        .forward: PlaybackToolbarLayoutPolicy.padButtonWidth,
        .timeLabel: 180,
        .previous: PlaybackToolbarLayoutPolicy.padButtonWidth,
        .next: PlaybackToolbarLayoutPolicy.padButtonWidth,
        .volume: PlaybackToolbarLayoutPolicy.padButtonWidth,
        .speed: PlaybackToolbarLayoutPolicy.playbackRateButtonWidth,
        .aspectRatio: PlaybackToolbarLayoutPolicy.padButtonWidth,
        .episode: PlaybackToolbarLayoutPolicy.padButtonWidth,
        .danmaku: PlaybackToolbarLayoutPolicy.padDanmakuButtonWidth,
        .intro: PlaybackToolbarLayoutPolicy.padMarkerButtonWidth,
        .outro: PlaybackToolbarLayoutPolicy.padMarkerButtonWidth,
        .fullscreen: PlaybackToolbarLayoutPolicy.nativeButtonWidth
    ]

    private static let landscapeControls: [PlaybackToolbarControl] = [
        .rewind, .play, .forward, .timeLabel, .previous, .next, .volume,
        .speed, .aspectRatio, .episode, .danmaku, .intro, .outro, .fullscreen
    ]

    private static let portraitControls: [PlaybackToolbarControl] = [
        .play, .timeLabel, .volume, .speed, .intro, .outro, .fullscreen
    ]

    static func main() {
        precondition(PlaybackToolbarLayoutPolicy.phoneButtonWidth == 28)
        precondition(PlaybackToolbarLayoutPolicy.padButtonWidth == 34)
        precondition(PlaybackToolbarLayoutPolicy.nativeButtonWidth == 30)
        precondition(PlaybackToolbarLayoutPolicy.playbackRateButtonWidth == 28)
        precondition(PlaybackToolbarLayoutPolicy.phoneSpacing == 5)
        precondition(PlaybackToolbarLayoutPolicy.padSpacing == 10)
        precondition(PlaybackToolbarLayoutPolicy.phonePlaybackRateSpacing == 10)
        precondition(PlaybackToolbarLayoutPolicy.padPlaybackRateSpacing == 16)
        precondition(PlaybackToolbarLayoutPolicy.phoneMarkerButtonWidth == 52)
        precondition(PlaybackToolbarLayoutPolicy.padMarkerButtonWidth == 64)
        precondition(PlaybackToolbarLayoutPolicy.verticalSeekStackWidth == 46)
        precondition(PlaybackToolbarLayoutPolicy.verticalSeekButtonHeight == 42)

        var checks = 0
        let phoneLandscapeWidths = [812.0, 844, 852, 874, 896, 926]
        let padLandscapeWidths = [1024.0, 1080, 1112, 1180, 1194, 1366]

        for screenWidth in phoneLandscapeWidths {
            verifyLandscape(
                screenWidth: screenWidth,
                isPad: false,
                canSelectEpisode: true
            )
            verifyLandscape(
                screenWidth: screenWidth,
                isPad: false,
                canSelectEpisode: false
            )
            checks += 2
        }

        for screenWidth in padLandscapeWidths {
            verifyLandscape(
                screenWidth: screenWidth,
                isPad: true,
                canSelectEpisode: true
            )
            verifyLandscape(
                screenWidth: screenWidth,
                isPad: true,
                canSelectEpisode: false
            )
            checks += 2
        }

        // Exercise repeated portrait/landscape transitions without changing
        // which controls are present in landscape.
        let rotationWidths = [812.0, 844, 1024, 1180, 874, 1194]
        for cycle in 0..<12_000 {
            let screenWidth = rotationWidths[cycle % rotationWidths.count]
            let isPad = screenWidth >= 1024
            let isLandscape = cycle.isMultiple(of: 2)
            verifyScenario(
                screenWidth: screenWidth,
                isPad: isPad,
                isLandscape: isLandscape,
                canSelectEpisode: cycle.isMultiple(of: 5)
            )
            checks += 1
        }

        // Deterministic landscape widths include common split-view sizes on iPad.
        var seed: UInt64 = 0x5EED
        for _ in 0..<20_000 {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1
            let isPad = seed.isMultiple(of: 3)
            let screenWidth = isPad
                ? 1_024.0 + Double(seed % 721)
                : 812.0 + Double(seed % 115)
            verifyLandscape(
                screenWidth: screenWidth,
                isPad: isPad,
                canSelectEpisode: seed.isMultiple(of: 5)
            )
            checks += 1
        }

        print("PLAYER TOOLBAR LAYOUT CHECKS PASSED: \(checks) landscape, rotation, and split-view scenarios")
    }

    private static func verifyScenario(
        screenWidth: Double,
        isPad: Bool,
        isLandscape: Bool,
        canSelectEpisode: Bool
    ) {
        guard isLandscape else {
            let controls = portraitControls
            let availableWidth = screenWidth - (isPad ? 64 : 28)
            let widths = isPad ? padWidths : phoneWidths
            let decision = PlaybackToolbarLayoutPolicy.layout(
                availableWidth: availableWidth,
                controls: controls,
                widths: widths,
                spacing: isPad
                    ? PlaybackToolbarLayoutPolicy.padSpacing
                    : PlaybackToolbarLayoutPolicy.phoneSpacing,
                customSpacingAfter: [
                    .speed: isPad
                        ? PlaybackToolbarLayoutPolicy.padPlaybackRateSpacing
                        : PlaybackToolbarLayoutPolicy.phonePlaybackRateSpacing
                ]
            )
            precondition(decision.occupiedWidth <= availableWidth + 0.001)
            return
        }

        verifyLandscape(
            screenWidth: screenWidth,
            isPad: isPad,
            canSelectEpisode: canSelectEpisode
        )
    }

    private static func verifyLandscape(
        screenWidth: Double,
        isPad: Bool,
        canSelectEpisode: Bool
    ) {
        let availableWidth = screenWidth - (isPad ? 64 : 28)
        let spacing = isPad
            ? PlaybackToolbarLayoutPolicy.padSpacing
            : PlaybackToolbarLayoutPolicy.phoneSpacing
        let playbackRateSpacing = isPad
            ? PlaybackToolbarLayoutPolicy.padPlaybackRateSpacing
            : PlaybackToolbarLayoutPolicy.phonePlaybackRateSpacing
        var controls = landscapeControls
        if !canSelectEpisode {
            controls.removeAll { $0 == .episode }
        }

        let widths = isPad ? padWidths : phoneWidths
        let decision = PlaybackToolbarLayoutPolicy.layout(
            availableWidth: availableWidth,
            controls: controls,
            widths: widths,
            spacing: spacing,
            customSpacingAfter: [.speed: playbackRateSpacing]
        )

        precondition(controls.contains(.rewind))
        precondition(controls.contains(.play))
        precondition(controls.contains(.forward))
        precondition(controls.contains(.previous))
        precondition(controls.contains(.next))
        precondition(controls.contains(.volume))
        precondition(controls.contains(.speed))
        precondition(controls.contains(.aspectRatio))
        precondition(controls.contains(.danmaku))
        precondition(controls.contains(.intro))
        precondition(controls.contains(.outro))
        precondition(controls.contains(.fullscreen))
        precondition(controls.contains(.episode) == canSelectEpisode)
        precondition(spacing == (isPad ? 10 : 5))
        precondition(playbackRateSpacing == (isPad ? 16 : 10))
        precondition(decision.timeLabelWidth >= PlaybackToolbarLayoutPolicy.minimumTimeLabelWidth)
        precondition(decision.occupiedWidth <= availableWidth + 0.001)
    }
}
