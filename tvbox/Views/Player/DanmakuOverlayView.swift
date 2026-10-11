#if os(iOS)
import QuartzCore
import UIKit

/// Positions comments from the media clock so buffering and rate changes cannot make tracks drift.
final class DanmakuOverlayView: UIView {
    private struct ActiveCue {
        let cue: DanmuCue
        let trajectory: DanmakuScrollTrajectory
        let lane: Int
        let layer: CATextLayer
    }

    private var cues: [DanmuCue] = []
    private var activeCues: [String: ActiveCue] = [:]
    private var maximumCueTextLength = 0
    private var nextCueIndex = 0
    private var displayLink: CADisplayLink?
    private var mediaTime: TimeInterval = 0
    private var mediaDuration: TimeInterval = 0
    private var playbackRate = 1.0
    private var wallClockAnchor: CFTimeInterval = 0
    private var hasTimeAnchor = false
    private var playbackActive = true
    private var lastLayoutSize = CGSize.zero
    private var layoutIsReady = false
    private var settings = DanmakuDisplaySettings()

    private let minimumActiveWindow: TimeInterval = 5
    private let maxCuesPerFrame = 40
    private let minimumLaneGap = 18.0
    private let timelineLayer = CALayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        isUserInteractionEnabled = false
        backgroundColor = .clear
        clipsToBounds = true
        accessibilityElementsHidden = true
        timelineLayer.masksToBounds = true
        layer.addSublayer(timelineLayer)
    }

    deinit {
        displayLink?.invalidate()
    }

    func setCues(_ cues: [DanmuCue]) {
        var seen = Set<String>()
        self.cues = cues
            .sorted {
                if $0.timeMs == $1.timeMs { return $0.id < $1.id }
                return $0.timeMs < $1.timeMs
            }
            .filter { seen.insert($0.id).inserted }
        maximumCueTextLength = self.cues.map { $0.text.utf16.count }.max() ?? 0
        reset()
    }

    func updateSettings(_ settings: DanmakuDisplaySettings) {
        let now = currentTimelineTime()
        self.settings = settings.normalized
        layoutIsReady = bounds.width > 0 && bounds.height > 0
        clearActiveCues()
        nextCueIndex = lowerBound(for: max(0, now - activeDisplayWindow))
        if layoutIsReady, hasTimeAnchor, !cues.isEmpty {
            render(at: now)
        }
    }

    func setPlaybackActive(_ active: Bool) {
        guard playbackActive != active else { return }
        if playbackActive, hasTimeAnchor {
            mediaTime = currentTimelineTime()
        }
        playbackActive = active
        wallClockAnchor = CACurrentMediaTime()
        synchronizeTimelineLayer()
        displayLink?.isPaused = !active
    }

    /// The player supplies media time; the display link only interpolates between callbacks.
    func update(currentTime: TimeInterval, duration: TimeInterval = 0, playbackRate: Double = 1) {
        let boundedTime = max(0, currentTime.isFinite ? currentTime : 0)
        let didSeek = DanmakuTimelinePolicy.didSeek(
            from: hasTimeAnchor ? currentTimelineTime() : nil,
            to: boundedTime
        )

        mediaDuration = max(0, duration.isFinite ? duration : 0)
        mediaTime = boundedTime
        self.playbackRate = DanmakuTimelinePolicy.playbackRate(playbackRate)
        wallClockAnchor = CACurrentMediaTime()
        hasTimeAnchor = true
        synchronizeTimelineLayer()

        if didSeek {
            clearActiveCues()
            nextCueIndex = lowerBound(for: max(0, boundedTime - activeDisplayWindow))
        }

        if window != nil, !cues.isEmpty {
            startDisplayLinkIfNeeded()
        }
        render(at: boundedTime)
    }

    func reset() {
        clearActiveCues()
        nextCueIndex = 0
        mediaTime = 0
        mediaDuration = 0
        playbackRate = 1
        wallClockAnchor = CACurrentMediaTime()
        hasTimeAnchor = false
        synchronizeTimelineLayer()
    }

    func clear() {
        reset()
        cues.removeAll(keepingCapacity: false)
        stopDisplayLink()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            stopDisplayLink()
        } else if !cues.isEmpty {
            startDisplayLinkIfNeeded()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let layoutChanged = bounds.size != lastLayoutSize
        if layoutChanged {
            lastLayoutSize = bounds.size
            layoutIsReady = bounds.width > 0 && bounds.height > 0
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            timelineLayer.frame = bounds
            CATransaction.commit()
            clearActiveCues()
            guard layoutIsReady, hasTimeAnchor, !cues.isEmpty else { return }
            let now = currentTimelineTime()
            nextCueIndex = lowerBound(for: max(0, now - activeDisplayWindow))
            render(at: now)
        } else {
            layoutIsReady = bounds.width > 0 && bounds.height > 0
            if timelineLayer.frame != bounds {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                timelineLayer.frame = bounds
                CATransaction.commit()
            }
        }
    }

    private func startDisplayLinkIfNeeded() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(displayLinkTick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 8, maximum: 15, preferred: 12)
        link.add(to: .main, forMode: .common)
        link.isPaused = !playbackActive
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func displayLinkTick(_ link: CADisplayLink) {
        guard hasTimeAnchor else { return }
        let time = currentTimelineTime()
        render(at: mediaDuration > 0 ? min(time, mediaDuration) : time)
    }

    private func currentTimelineTime() -> TimeInterval {
        guard playbackActive, hasTimeAnchor else { return mediaTime }
        return mediaTime + max(0, CACurrentMediaTime() - wallClockAnchor) * playbackRate
    }

    private func render(at time: TimeInterval) {
        guard layoutIsReady, bounds.width > 0, bounds.height > 0 else { return }
        removeExpiredCues(at: time)

        var emitted = 0
        while nextCueIndex < cues.count, emitted < maxCuesPerFrame {
            let cue = cues[nextCueIndex]
            let cueTime = TimeInterval(cue.timeMs) / 1000
            guard cueTime <= time else { break }
            nextCueIndex += 1

            let duration = displayDuration(for: cue)
            guard DanmakuTimelinePolicy.shouldDisplayCue(age: time - cueTime, duration: duration) else {
                continue
            }
            place(cue, startTime: cueTime, at: time, duration: duration)
            emitted += 1
        }
    }

    private func place(_ cue: DanmuCue, startTime: TimeInterval, at time: TimeInterval, duration: TimeInterval) {
        let size = max(12, min(36, CGFloat(cue.size) * settings.sizeScale))
        let font = UIFont.systemFont(ofSize: size, weight: .regular)
        let textWidth = (cue.text as NSString).size(withAttributes: [.font: font]).width
        let cueWidth = max(24, ceil(textWidth) + 8)
        let trajectory = DanmakuScrollTrajectory(
            startTime: startTime,
            duration: duration,
            width: Double(cueWidth)
        )
        let rows = availableLaneCount
        guard rows > 0 else { return }

        let existingByLane = Dictionary(grouping: activeCues.values, by: \.lane)
        guard let lane = (0..<rows).first(where: { lane in
            let existing = (existingByLane[lane] ?? []).map(\.trajectory)
            return DanmakuTimelinePolicy.canPlace(
                trajectory,
                with: existing,
                at: time,
                viewportWidth: Double(bounds.width),
                minimumGap: minimumLaneGap
            )
        }) else {
            return
        }

        let opacity = CGFloat(settings.opacity) / 100
        let textLayer = CATextLayer()
        textLayer.contentsScale = UIScreen.main.scale
        textLayer.alignmentMode = .center
        textLayer.isWrapped = false
        textLayer.truncationMode = .none
        textLayer.bounds = CGRect(x: 0, y: 0, width: cueWidth, height: ceil(font.lineHeight))
        textLayer.position = CGPoint(
            x: bounds.width + cueWidth / 2,
            y: (CGFloat(lane) + 0.5) * laneHeight
        )
        textLayer.string = NSAttributedString(
            string: cue.text,
            attributes: [
                .font: font,
                .foregroundColor: displayColor(for: cue).withAlphaComponent(opacity),
                .strokeColor: UIColor.black.withAlphaComponent(opacity),
                .strokeWidth: -4.0
            ]
        )
        timelineLayer.addSublayer(textLayer)
        let animation = CABasicAnimation(keyPath: "position.x")
        animation.fromValue = bounds.width + cueWidth / 2
        animation.toValue = -cueWidth / 2
        animation.beginTime = startTime
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.fillMode = .both
        animation.isRemovedOnCompletion = false
        textLayer.add(animation, forKey: "danmaku.scroll")
        let active = ActiveCue(cue: cue, trajectory: trajectory, lane: lane, layer: textLayer)
        activeCues[cue.id] = active
    }

    private func removeExpiredCues(at time: TimeInterval) {
        let expired = activeCues.values.filter { time - $0.trajectory.startTime > $0.trajectory.duration }
        for active in expired {
            active.layer.removeFromSuperlayer()
            activeCues.removeValue(forKey: active.cue.id)
        }
    }

    private func clearActiveCues() {
        activeCues.values.forEach { $0.layer.removeFromSuperlayer() }
        activeCues.removeAll(keepingCapacity: true)
    }

    private func synchronizeTimelineLayer() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        timelineLayer.speed = 0
        timelineLayer.timeOffset = mediaTime
        timelineLayer.beginTime = 0
        if playbackActive, hasTimeAnchor {
            timelineLayer.speed = Float(playbackRate)
            timelineLayer.beginTime = CACurrentMediaTime()
        }
        CATransaction.commit()
    }

    private var laneHeight: CGFloat {
        CGFloat(DanmakuTimelinePolicy.trackHeight(
            viewportHeight: Double(bounds.height),
            sizeScale: Double(settings.sizeScale)
        ))
    }

    private var availableLaneCount: Int {
        guard laneHeight > 0 else { return 0 }
        return min(settings.rowCount, max(1, Int(bounds.height / laneHeight)))
    }

    private func displayDuration(for cue: DanmuCue) -> TimeInterval {
        let fontSize = max(12, min(36, CGFloat(cue.size) * settings.sizeScale))
        let font = UIFont.systemFont(ofSize: fontSize, weight: .regular)
        let textSize = (cue.text as NSString).size(withAttributes: [.font: font])
        let cueWidth = max(24, ceil(textSize.width) + 8)
        return DanmakuTimelinePolicy.scrollingDuration(
            baseDuration: settings.scrollDuration,
            viewportWidth: Double(bounds.width),
            cueWidth: Double(cueWidth)
        )
    }

    private var activeDisplayWindow: TimeInterval {
        DanmakuTimelinePolicy.activeDisplayWindow(
            baseDuration: settings.scrollDuration,
            viewportWidth: Double(bounds.width),
            maximumTextLength: maximumCueTextLength,
            maximumFontSize: Double(max(12, min(36, 36 * settings.sizeScale))),
            minimumWindow: minimumActiveWindow
        )
    }

    private func displayColor(for cue: DanmuCue) -> UIColor {
        if settings.randomColors {
            let palette: [UInt32] = [0xFFFFFF, 0xFF6B6B, 0xFFD166, 0x62D6A5, 0x72B7FF, 0xE7A6FF]
            let hash = cue.id.utf8.reduce(0) { ($0 &* 31 &+ Int($1)) % palette.count }
            return UIColor(rgb: palette[hash])
        }
        return UIColor(rgb: UInt32(truncatingIfNeeded: cue.color))
    }

    private func lowerBound(for time: TimeInterval) -> Int {
        let target = Int(max(0, time) * 1000)
        var low = 0
        var high = cues.count
        while low < high {
            let mid = (low + high) / 2
            if cues[mid].timeMs < target { low = mid + 1 } else { high = mid }
        }
        return low
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xff) / 255,
                  green: CGFloat((rgb >> 8) & 0xff) / 255,
                  blue: CGFloat(rgb & 0xff) / 255,
                  alpha: 1)
    }
}
#endif
