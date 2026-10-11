#if os(iOS)
import DanmakuKit
import UIKit

/// Media-time scheduler backed by DanmakuKit's asynchronous cells and lane collision checks.
final class DanmakuOverlayView: UIView {
    private let renderer = DanmakuKit.DanmakuView()
    private var rendererHeightConstraint: NSLayoutConstraint!
    private var cues: [DanmuCue] = []
    private var nextCueIndex = 0
    private var displayLink: CADisplayLink?
    private var mediaTime: TimeInterval = 0
    private var mediaDuration: TimeInterval = 0
    private var playbackRate = 1.0
    private var wallClockAnchor: CFTimeInterval = 0
    private var hasTimeAnchor = false
    private var playbackActive = true
    private var lastLayoutSize = CGSize.zero
    private var rendererLayoutIsReady = false
    private var settings = DanmakuDisplaySettings()

    private let maxCuesPerFrame = 40

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

        renderer.translatesAutoresizingMaskIntoConstraints = false
        renderer.backgroundColor = .clear
        renderer.isUserInteractionEnabled = false
        renderer.enableCellReusable = true
        renderer.isOverlap = false
        addSubview(renderer)
        rendererHeightConstraint = renderer.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            renderer.leadingAnchor.constraint(equalTo: leadingAnchor),
            renderer.trailingAnchor.constraint(equalTo: trailingAnchor),
            renderer.topAnchor.constraint(equalTo: topAnchor),
            rendererHeightConstraint
        ])
    }

    deinit {
        displayLink?.invalidate()
        renderer.stop()
    }

    func setCues(_ cues: [DanmuCue]) {
        var seen = Set<String>()
        self.cues = cues
            .sorted {
                if $0.timeMs == $1.timeMs { return $0.id < $1.id }
                return $0.timeMs < $1.timeMs
            }
            .filter { seen.insert($0.id).inserted }
        reset()
    }

    func updateSettings(_ settings: DanmakuDisplaySettings) {
        let now = currentTimelineTime()
        self.settings = settings.normalized
        rendererLayoutIsReady = false
        applyTrackSettings()
        setNeedsLayout()
        layoutIfNeeded()
        applyTrackSettings()
        if rendererLayoutIsReady {
            renderer.clean()
        }
        nextCueIndex = lowerBound(for: max(0, now - max(fixedDuration, self.settings.scrollDuration)))
        if rendererLayoutIsReady {
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

        if active {
            ensureRendererPlaying()
        } else if renderer.status == .play {
            renderer.pause()
        }
        displayLink?.isPaused = !active
    }

    /// The player supplies media time; the display link only interpolates between callbacks.
    func update(currentTime: TimeInterval, duration: TimeInterval = 0, playbackRate: Double = 1) {
        let boundedTime = max(0, currentTime.isFinite ? currentTime : 0)
        let hadTimeAnchor = hasTimeAnchor
        let expectedTime = hadTimeAnchor ? currentTimelineTime() : nil
        let didSeek = DanmakuTimelinePolicy.didSeek(
            from: expectedTime,
            to: boundedTime
        )
        let normalizedRate = DanmakuTimelinePolicy.playbackRate(playbackRate)
        let rateChanged = hadTimeAnchor && abs(self.playbackRate - normalizedRate) > 0.02

        mediaDuration = max(0, duration.isFinite ? duration : 0)
        mediaTime = boundedTime
        self.playbackRate = normalizedRate
        wallClockAnchor = CACurrentMediaTime()
        hasTimeAnchor = true

        if !hadTimeAnchor || didSeek {
            renderer.clean()
            let activeWindow = max(fixedDuration, settings.scrollDuration)
            nextCueIndex = lowerBound(for: max(0, boundedTime - activeWindow))
        } else if rateChanged {
            renderer.clean()
            nextCueIndex = lowerBound(for: max(0, boundedTime - max(fixedDuration, settings.scrollDuration)))
        }

        if window != nil, !cues.isEmpty {
            startDisplayLinkIfNeeded()
        }
        render(at: boundedTime)
    }

    func reset() {
        renderer.stop()
        nextCueIndex = 0
        mediaTime = 0
        mediaDuration = 0
        playbackRate = 1
        wallClockAnchor = CACurrentMediaTime()
        hasTimeAnchor = false
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
            rendererLayoutIsReady = false
        }
        guard layoutChanged || !rendererLayoutIsReady else { return }
        applyTrackSettings()
        guard rendererLayoutIsReady, hasTimeAnchor, !cues.isEmpty else { return }
        render(at: currentTimelineTime())
    }

    private func applyTrackSettings() {
        guard bounds.width.isFinite, bounds.height.isFinite,
              bounds.width > 0, bounds.height > 0 else {
            rendererLayoutIsReady = false
            return
        }

        let rowCount = max(1, settings.rowCount)
        let viewportWidth = Double(bounds.width)
        let viewportHeight = Double(bounds.height)
        let trackHeight = DanmakuTimelinePolicy.trackHeight(
            viewportHeight: viewportHeight,
            sizeScale: Double(settings.sizeScale)
        )
        let regionHeight = DanmakuTimelinePolicy.trackRegionHeight(
            viewportHeight: viewportHeight,
            rowCount: rowCount,
            trackHeight: trackHeight
        )

        guard trackHeight.isFinite, trackHeight > 0,
              regionHeight.isFinite, regionHeight > 0 else {
            rendererLayoutIsReady = false
            return
        }

        rendererHeightConstraint.constant = CGFloat(regionHeight)
        renderer.setNeedsLayout()
        renderer.layoutIfNeeded()
        guard DanmakuTimelinePolicy.hasUsableRendererLayout(
            viewportWidth: viewportWidth,
            viewportHeight: viewportHeight,
            rendererWidth: Double(renderer.bounds.width),
            rendererHeight: Double(renderer.bounds.height)
        ) else {
            rendererLayoutIsReady = false
            setNeedsLayout()
            return
        }

        renderer.displayArea = 1
        renderer.trackHeight = CGFloat(trackHeight)
        renderer.layoutIfNeeded()
        rendererLayoutIsReady = true
    }

    private func startDisplayLinkIfNeeded() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(displayLinkTick(_:)))
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
        guard rendererLayoutIsReady,
              bounds.width > 0, bounds.height > 0 else { return }
        ensureRendererPlaying()

        var emitted = 0
        while nextCueIndex < cues.count, emitted < maxCuesPerFrame {
            let cue = cues[nextCueIndex]
            let cueTime = TimeInterval(cue.timeMs) / 1000
            guard cueTime <= time else { break }
            nextCueIndex += 1

            let mediaDuration = displayDuration(for: cue)
            let age = time - cueTime
            guard DanmakuTimelinePolicy.shouldDisplayCue(age: age, duration: mediaDuration) else { continue }
            emit(cue, age: age, mediaDuration: mediaDuration)
            emitted += 1
        }
    }

    private func emit(_ cue: DanmuCue, age: TimeInterval, mediaDuration: TimeInterval) {
        let size = max(12, min(36, CGFloat(cue.size) * settings.sizeScale))
        let font = UIFont.systemFont(ofSize: size)
        let color = displayColor(for: cue)
        let model = TimedDanmakuCellModel(
            cue: cue,
            font: font,
            color: color,
            opacity: CGFloat(settings.opacity) / 100,
            mediaDuration: mediaDuration,
            playbackRate: playbackRate
        )
        let progress = Float(min(max(age / mediaDuration, 0), 1))
        renderer.sync(danmaku: model, at: progress)
    }

    private func displayDuration(for cue: DanmuCue) -> TimeInterval {
        let fontSize = max(12, min(36, CGFloat(cue.size) * settings.sizeScale))
        let font = UIFont.systemFont(ofSize: fontSize)
        let textSize = (cue.text as NSString).size(withAttributes: [.font: font])
        let cueWidth = max(24, ceil(textSize.width) + 8)
        return DanmakuTimelinePolicy.scrollingDuration(
            baseDuration: settings.scrollDuration,
            viewportWidth: Double(bounds.width),
            cueWidth: Double(cueWidth)
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

    private func ensureRendererPlaying() {
        guard rendererLayoutIsReady else { return }
        if renderer.status != .play {
            renderer.play()
        }
        if !playbackActive, renderer.status == .play {
            renderer.pause()
        }
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

private final class TimedDanmakuCellModel: DanmakuCellModel {
    let cue: DanmuCue
    let font: UIFont
    let color: UIColor
    let opacity: CGFloat
    let mediaDuration: TimeInterval
    let playbackRate: Double
    let size: CGSize
    var track: UInt?

    var identifier: String { cue.id }
    var cellClass: DanmakuCell.Type { TimedDanmakuCell.self }
    var displayTime: Double { mediaDuration / playbackRate }
    var type: DanmakuCellType { .floating }

    init(
        cue: DanmuCue,
        font: UIFont,
        color: UIColor,
        opacity: CGFloat,
        mediaDuration: TimeInterval,
        playbackRate: Double
    ) {
        self.cue = cue
        self.font = font
        self.color = color.withAlphaComponent(opacity)
        self.opacity = opacity
        self.mediaDuration = mediaDuration
        self.playbackRate = max(0.25, playbackRate)
        let textSize = (cue.text as NSString).size(withAttributes: [.font: font])
        size = CGSize(width: max(24, ceil(textSize.width) + 8), height: max(24, ceil(textSize.height) + 4))
    }

    func isEqual(to cellModel: DanmakuCellModel) -> Bool {
        identifier == cellModel.identifier
    }
}

private final class TimedDanmakuCell: DanmakuCell {
    required init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        displayAsync = true
    }

    required init?(coder: NSCoder) { nil }

    override func displaying(_ context: CGContext, _ size: CGSize, _ isCancelled: Bool) {
        guard !isCancelled, let model = model as? TimedDanmakuCellModel else { return }
        let text = model.cue.text as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: model.font,
            .foregroundColor: model.color
        ]
        context.setLineWidth(max(0.65, model.font.pointSize * 0.04))
        context.setLineJoin(.round)
        context.setStrokeColor(UIColor.black.withAlphaComponent(model.opacity).cgColor)
        context.saveGState()
        context.setTextDrawingMode(.stroke)
        text.draw(at: CGPoint(x: 4, y: 2), withAttributes: attributes)
        context.restoreGState()
        context.setTextDrawingMode(.fill)
        text.draw(at: CGPoint(x: 4, y: 2), withAttributes: attributes)
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
