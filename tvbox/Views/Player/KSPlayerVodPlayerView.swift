import SwiftUI

#if os(iOS)
import KSPlayer
import AVKit
import UIKit

fileprivate enum PlaybackAspectRatio: String, CaseIterable {
    case original = "原始"
    case sixteenByNine = "16:9"
    case stretch = "拉伸"
    case fill = "铺满"
    case crop = "裁剪"

    var usesFixedViewport: Bool {
        self == .sixteenByNine || self == .crop
    }

    var contentMode: UIView.ContentMode {
        switch self {
        case .original, .sixteenByNine:
            return .scaleAspectFit
        case .stretch:
            return .scaleToFill
        case .fill, .crop:
            return .scaleAspectFill
        }
    }
}

extension Notification.Name {
    static let congcongPlaybackSessionWillChange = Notification.Name(
        "CongcongPlaybackSessionWillChange"
    )
}

/// SwiftUI adapter for KSPlayer's native iOS player view.
struct KSPlayerVodPlayerView: View {
    let urlString: String
    var playbackHeaders: [String: String] = [:]
    var startPosition: Double = 0
    var playbackSessionToken: UUID? = nil
    var isResolvingPlayback = false
    var onProgressChanged: ((Double, Double?) -> Void)? = nil
    var onPlaybackEnded: (() -> Void)? = nil
    var onPlaybackFailed: (() -> Void)? = nil
    /// Called when KSPlayer's native back button is pressed.
    var onBack: (() -> Void)? = nil
    var canPlayPrevious: Bool = false
    var onPlayPrevious: (() -> Void)? = nil
    var canPlayNext: Bool = false
    var onPlayNext: (() -> Void)? = nil
    var canSelectEpisode: Bool = false
    var onSelectEpisode: (() -> Void)? = nil
    var onMarkIntro: (() -> Void)? = nil
    var onMarkOutro: (() -> Void)? = nil
    var onResetIntro: (() -> Void)? = nil
    var onResetOutro: (() -> Void)? = nil
    var introLabel: String = "片头"
    var outroLabel: String = "片尾"
    var danmakuTitle: String = ""
    var danmakuEpisode: String = ""
    var displayEpisodeTitle: String = ""
    var danmakuEnabled: Bool = true
    var onDanmakuEnabledChanged: ((Bool) -> Void)? = nil
    /// Forwards native toolbar actions to the host without replacing KSPlayer's handling.
    var onPlayerAction: ((PlayerButtonType) -> Void)? = nil

    var body: some View {
        if let url = Self.makeURL(from: urlString) {
            KSPlayerUIView(
                url: url,
                playbackHeaders: playbackHeaders,
                startPosition: max(0, startPosition),
                playbackSessionToken: playbackSessionToken,
                isResolvingPlayback: isResolvingPlayback,
                onProgressChanged: onProgressChanged,
                onPlaybackEnded: onPlaybackEnded,
                onPlaybackFailed: onPlaybackFailed,
                onBack: onBack,
                onPlayerAction: onPlayerAction,
                canPlayPrevious: canPlayPrevious,
                onPlayPrevious: onPlayPrevious,
                canPlayNext: canPlayNext,
                onPlayNext: onPlayNext,
                canSelectEpisode: canSelectEpisode,
                onSelectEpisode: onSelectEpisode,
                onMarkIntro: onMarkIntro,
                onMarkOutro: onMarkOutro,
                onResetIntro: onResetIntro,
                onResetOutro: onResetOutro,
                introLabel: introLabel,
                outroLabel: outroLabel,
                danmakuTitle: danmakuTitle,
                danmakuEpisode: danmakuEpisode,
                displayEpisodeTitle: displayEpisodeTitle,
                danmakuEnabled: danmakuEnabled,
                onDanmakuEnabledChanged: onDanmakuEnabledChanged
            )
            .background(Color.clear)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.yellow)
                Text("播放地址无效")
                    .foregroundColor(.white)
                    .font(.headline)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
        }
    }

    private static func makeURL(from value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        return URL(string: encoded)
    }
}

private final class CongcongKSVideoPlayerView: IOSVideoPlayerView, UIGestureRecognizerDelegate {
    private static let supportedPlaybackRates: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
    private weak var interactivePopGestureRecognizer: UIGestureRecognizer?
    private weak var inlineSuperview: UIView?
    private var inlineFrameConstraints: [NSLayoutConstraint] = []
    private var inlineTranslatesAutoresizingMaskIntoConstraints = false
    private var restoreTask: DispatchWorkItem?
    private var inlineRestorationGeneration = 0
    private var waitingForFullscreenDismissal = false
    /// 逐帧跟随容器 bounds 时的稳定计数/上一次采样值。
    private var settleStableFrames = 0
    private var settleLastBounds = CGRect.zero
    /// 旋转未结束前仍以 60fps 跟随容器，避免画面被旧 frame 卡住。
    private static let inlineSettleStepDelay: TimeInterval = 1.0 / 60.0
    private static let inlineSettleStableFrames = 3
    /// 收尾前至少跟随的帧数（约 0.2s），覆盖 KSPlayer 迟到的 frame 写入。
    private static let inlineSettleMinimumFrames = 12
    // KSPlayer moves this exact view into its native full-screen controller.
    // Keep the playback layer alive until the view has been reattached inline.
    private var preservingFullscreenPlayer = false
    private var routeButtonLayoutInstalled = false
    /// KSPlayer 的 AVPlayer 后端不会消费 KSOptions.startPlayTime，
    /// 因此在 readyToPlay 后由宿主显式 seek 一次。
    fileprivate var pendingStartPosition: TimeInterval = 0
    fileprivate var didApplyStartPosition = false
    private var didStartInitialPlayback = false
    private var startPositionRetryCount = 0
    private let startPositionCoverView = UIView()
    private var startPositionCoverInstalled = false
    fileprivate var canShowPlaybackControl = false
    fileprivate var hasDisplayedCurrentVideoFrame = false
    fileprivate var canShowPlayerControls: Bool {
        canShowPlaybackControl
            && ((hasDisplayedCurrentVideoFrame && hasPlaybackAdvanced) || playbackFailed)
    }
    private var playbackFailed = false
    fileprivate var onPlaybackFailure: (() -> Void)?
    private var hasPlaybackAdvanced = false
    private weak var observedVideoLayer: AVPlayerLayer?
    private var firstFrameObservation: NSKeyValueObservation?
    private var firstFrameStartPosition: TimeInterval = 0
    private var startPositionGeneration = 0
    private var startPositionRetryWorkItem: DispatchWorkItem?
    /// SwiftUI 可能在 KSPlayer 全屏转场期间重新配置同一个 UIView。
    /// 将媒体身份保存在原生视图上，避免把重挂载误判为新会话并重复 set(url:)。
    fileprivate var configuredPlaybackURL: URL?
    fileprivate var configuredPlaybackHeaders: [String: String] = [:]
    fileprivate var configuredPlaybackSessionToken: UUID?
    // Keep the selected rate independent from KSPlayer's transient menu/player
    // rebuilds. Applying a rate must never recreate the current media item.
    fileprivate var desiredPlaybackRate: Float = 1.0
    private let deviceStatusView = UIView()
    private let deviceTimeLabel = UILabel()
    private let deviceBatteryIconView = UIImageView()
    private let deviceBatteryLabel = UILabel()
    private var deviceStatusTimer: Timer?
    private var playbackSessionObserver: NSObjectProtocol?
    var customControlsLayout: ((Bool) -> Void)?
    var customControlsFitLayout: (() -> Void)?
    var customControlsRefresh: (() -> Void)?
    private var isSliderDragging = false
    private var sliderSeekCommitted = false
    private var panStartPoint: CGPoint?
    private var nativePanDirection: KSPanDirection?
    private var pendingSeekTarget: TimeInterval?
    private var seekRequestID = 0
    private var autoplayRetryWorkItem: DispatchWorkItem?
    private var selectedAspectRatio: PlaybackAspectRatio = .original
    private weak var aspectRatioRenderView: UIView?
    private var aspectRatioEdgeConstraints: [NSLayoutConstraint] = []
    private var aspectRatioViewportConstraints: [NSLayoutConstraint] = []
    private var isAspectRatioFullscreen = false

    override var isMaskShow: Bool {
        didSet {
            updateDeviceStatus(isLandscape: landscapeButton.isSelected)
            owningViewController?.setNeedsStatusBarAppearanceUpdate()
        }
    }

    override func updateUI(isFullScreen: Bool) {
        if isFullScreen {
            restoreTask?.cancel()
            restoreTask = nil
            inlineRestorationGeneration &+= 1
            waitingForFullscreenDismissal = false
            preservingFullscreenPlayer = true
            captureInlineLayout()
        } else {
            // Keep this flag set while KSPlayer dismisses its controller. The
            // native completion reattaches the same view; only then can it be
            // treated as an ordinary inline SwiftUI view again.
            preservingFullscreenPlayer = true
            waitingForFullscreenDismissal = true
        }

        // KSPlayer 的原生全屏控制器会在呈现完成后写入同一个全局掩码。
        // 这里提前写入，确保 UIKit 在 present 的那一帧就允许横屏，避免
        // 被应用默认的 portrait 掩码卡住。
        KSOptions.supportedInterfaceOrientations = isFullScreen ? .landscapeRight : .portrait
        // 在 present/dismiss 开始前更新方向，避免等转场结束后才开始旋转。
        if isFullScreen {
            OrientationLock.landscape()
        } else {
            OrientationLock.portrait()
        }
        super.updateUI(isFullScreen: isFullScreen)

        // KSPlayer 默认在横屏时隐藏方向按钮，导致用户只能依赖系统手势退出。
        // 保留同一个原生按钮，确保横屏右下角始终有明确的退出全屏入口。
        landscapeButton.isHidden = false
        landscapeButton.isEnabled = true

        // KSPlayer owns the presentation controller. Keep the app orientation
        // in sync with that controller instead of layering another full-screen
        // SwiftUI presentation on top of it.
        DispatchQueue.main.async {
            self.syncInteractivePopGesture()
            self.landscapeButton.isHidden = false
        }

        if !isFullScreen {
            scheduleInlineRestoration()
        }
    }

    override func updateUI(isLandscape: Bool) {
        super.updateUI(isLandscape: isLandscape)
        // KSPlayer 在 landscape 分支会将按钮隐藏；这里覆盖该默认行为。
        landscapeButton.isHidden = false
        landscapeButton.isEnabled = true
        styleControlLayers(isLandscape: isLandscape)
        updateDeviceStatus(isLandscape: isLandscape)
        customControlsLayout?(isLandscape)
        owningViewController?.setNeedsStatusBarAppearanceUpdate()
    }

    override func slider(value: Double, event: ControlEvents) {
        switch event {
        case .touchDown:
            isSliderDragging = true
            sliderSeekCommitted = false
            pendingSeekTarget = nil
            // The base implementation only updates the preview value here;
            // it does not seek until the release event.
            super.slider(value: value, event: event)
        case .valueChanged:
            // KSPlayer's independent pan recognizer can emit valueChanged
            // without a preceding UIControl touchDown.
            if !isSliderDragging {
                isSliderDragging = true
                sliderSeekCommitted = false
            }
            pendingSeekTarget = nil
            super.slider(value: value, event: event)
        case .touchUpInside, .touchCancel:
            guard !sliderSeekCommitted else { return }
            sliderSeekCommitted = true
            isSliderDragging = false
            // KSSlider's base path only seeks for touchUpInside. Treat a
            // cancelled touch as the final position too, and let the base
            // implementation perform the single seek.
            super.slider(value: value, event: .touchUpInside)
        default:
            super.slider(value: value, event: event)
        }
    }

    override func seek(
        time: TimeInterval,
        completion: @escaping ((Bool) -> Void)
    ) {
        guard time.isFinite else {
            completion(false)
            return
        }

        seekRequestID &+= 1
        let requestID = seekRequestID
        pendingSeekTarget = max(0, min(time, toolBar.totalTime > 0 ? toolBar.totalTime : time))
        let target = pendingSeekTarget ?? max(0, time)

        // Keep the target visible until KSPlayer confirms this particular seek.
        // A stale playback tick must not move the thumb back to the pre-seek time.
        super.seek(time: target) { [weak self] success in
            DispatchQueue.main.async {
                guard let self, self.seekRequestID == requestID else { return }
                if success {
                    self.toolBar.currentTime = target
                }
                self.pendingSeekTarget = nil
                completion(success)
            }
        }
    }

    override func player(
        layer: KSPlayerLayer,
        currentTime: TimeInterval,
        totalTime: TimeInterval
    ) {
        guard playerLayer === layer else { return }
        updatePlaybackControlIfPlaying(layer: layer)
        // IOSVideoPlayerView normally guards this internally, but its private
        // drag flag does not cover every KSSlider tracking path. Keep the
        // user's preview thumb from being overwritten by playback callbacks.
        if let pendingSeekTarget {
            if abs(toolBar.totalTime - totalTime) > 0.1 {
                toolBar.totalTime = totalTime
            }
            toolBar.currentTime = pendingSeekTarget
            return
        }
        if isSliderDragging || toolBar.timeSlider.isTracking {
            if abs(toolBar.totalTime - totalTime) > 0.1 {
                toolBar.totalTime = totalTime
            }
            return
        }
        super.player(layer: layer, currentTime: currentTime, totalTime: totalTime)
    }

    override func resetPlayer() {
        super.resetPlayer()
        // resetPlayer() restores KSPlayer's default replay button visibility;
        // this app uses the toolbar button as the sole play/pause affordance.
        replayButton.isHidden = true
        if !canShowPlaybackControl {
            showPlaybackLoadingIndicator()
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        installPlaybackSessionObserverIfNeeded()
        if window == nil {
            deviceStatusTimer?.invalidate()
            deviceStatusTimer = nil
        }
        applyTransparentSurfaces()
        syncInteractivePopGesture()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyDisplayAspectRatio(selectedAspectRatio, isFullscreenLandscape: isAspectRatioFullscreen)
        customControlsFitLayout?()
    }

    fileprivate func applyDisplayAspectRatio(
        _ ratio: PlaybackAspectRatio,
        isFullscreenLandscape: Bool
    ) {
        selectedAspectRatio = ratio
        isAspectRatioFullscreen = isFullscreenLandscape
        guard let renderView = playerLayer?.player.view,
              renderView.superview === self else { return }

        if aspectRatioRenderView !== renderView {
            NSLayoutConstraint.deactivate(aspectRatioViewportConstraints)
            aspectRatioRenderView = renderView
            aspectRatioEdgeConstraints = constraints.filter { constraint in
                let referencesRenderView = (constraint.firstItem as? UIView) === renderView
                    || (constraint.secondItem as? UIView) === renderView
                let edgeAttribute = [.top, .bottom, .leading, .trailing].contains(constraint.firstAttribute)
                return referencesRenderView && edgeAttribute
            }
            aspectRatioViewportConstraints = [
                renderView.centerXAnchor.constraint(equalTo: centerXAnchor),
                renderView.centerYAnchor.constraint(equalTo: centerYAnchor),
                renderView.widthAnchor.constraint(equalTo: renderView.heightAnchor, multiplier: 16.0 / 9.0),
                renderView.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor),
                renderView.heightAnchor.constraint(lessThanOrEqualTo: heightAnchor)
            ]
            let matchHeight = renderView.heightAnchor.constraint(equalTo: heightAnchor)
            let matchWidth = renderView.widthAnchor.constraint(equalTo: widthAnchor)
            matchHeight.priority = .defaultHigh
            matchWidth.priority = UILayoutPriority(749)
            aspectRatioViewportConstraints.append(contentsOf: [matchHeight, matchWidth])
        }

        let usesViewport = ratio.usesFixedViewport && isFullscreenLandscape
        if usesViewport {
            let isWideViewport = bounds.width >= bounds.height
            aspectRatioViewportConstraints
                .filter { $0.firstAttribute == .height && $0.relation == .equal && ($0.secondItem as? UIView) === self }
                .forEach { $0.priority = isWideViewport ? .defaultHigh : UILayoutPriority(749) }
            aspectRatioViewportConstraints
                .filter { $0.firstAttribute == .width && $0.relation == .equal && ($0.secondItem as? UIView) === self }
                .forEach { $0.priority = isWideViewport ? UILayoutPriority(749) : .defaultHigh }
            NSLayoutConstraint.deactivate(aspectRatioEdgeConstraints)
            NSLayoutConstraint.activate(aspectRatioViewportConstraints)
        } else {
            NSLayoutConstraint.deactivate(aspectRatioViewportConstraints)
            NSLayoutConstraint.activate(aspectRatioEdgeConstraints)
        }

        playerLayer?.player.contentMode = ratio.contentMode
        renderView.setNeedsLayout()
    }

    deinit {
        deviceStatusTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
        if let playbackSessionObserver {
            NotificationCenter.default.removeObserver(playbackSessionObserver)
        }
    }

    private func installPlaybackSessionObserverIfNeeded() {
        guard playbackSessionObserver == nil else { return }
        playbackSessionObserver = NotificationCenter.default.addObserver(
            forName: .congcongPlaybackSessionWillChange,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let self,
                  let token = notification.userInfo?["sessionToken"] as? UUID,
                  self.configuredPlaybackSessionToken == token else {
                return
            }
            self.pauseCurrentPlaybackForSessionChange()
        }
    }

    private func pauseCurrentPlaybackForSessionChange() {
        // Keep the current fullscreen frame mounted while the next URL resolves.
        // replacePlayback stops and releases this layer before the new one starts.
        playerLayer?.pause()
    }

    private func installDeviceStatusViewIfNeeded() {
        guard deviceStatusView.superview == nil else { return }
        deviceStatusView.translatesAutoresizingMaskIntoConstraints = false
        deviceStatusView.backgroundColor = .clear
        deviceStatusView.isOpaque = false
        deviceStatusView.layer.zPosition = 150
        deviceTimeLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        deviceBatteryIconView.image = UIImage(systemName: "battery.100")
        deviceBatteryIconView.tintColor = .white
        deviceBatteryIconView.contentMode = .scaleAspectFit
        deviceBatteryIconView.setContentHuggingPriority(.required, for: .horizontal)
        deviceBatteryIconView.setContentCompressionResistancePriority(.required, for: .horizontal)
        deviceBatteryLabel.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        [deviceTimeLabel, deviceBatteryLabel].forEach {
            $0.textColor = .white
            $0.shadowColor = UIColor.black.withAlphaComponent(0.85)
            $0.shadowOffset = CGSize(width: 0, height: 1)
        }
        let batteryStack = UIStackView(arrangedSubviews: [deviceBatteryIconView, deviceBatteryLabel])
        batteryStack.axis = .horizontal
        batteryStack.spacing = 3
        batteryStack.alignment = .center
        let stack = UIStackView(arrangedSubviews: [deviceTimeLabel, batteryStack])
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        deviceStatusView.addSubview(stack)
        controllerView.addSubview(deviceStatusView)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: deviceStatusView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: deviceStatusView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: deviceStatusView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: deviceStatusView.bottomAnchor),
            deviceBatteryIconView.widthAnchor.constraint(equalToConstant: 22),
            deviceBatteryIconView.heightAnchor.constraint(equalToConstant: 14),
            deviceStatusView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -14),
            deviceStatusView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 8),
            deviceStatusView.heightAnchor.constraint(equalToConstant: 22)
        ])
        UIDevice.current.isBatteryMonitoringEnabled = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(deviceBatteryLevelDidChange),
            name: UIDevice.batteryLevelDidChangeNotification,
            object: UIDevice.current
        )
        deviceStatusTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.refreshDeviceStatus()
        }
        refreshDeviceStatus()
    }

    @objc private func deviceBatteryLevelDidChange() {
        refreshDeviceStatus()
    }

    private func refreshDeviceStatus() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        deviceTimeLabel.text = formatter.string(from: Date())
        let level = UIDevice.current.batteryLevel
        if level >= 0 {
            // UIDevice reports the system value as a 0...1 fraction. Do not
            // quantize it to the old five-percent steps.
            deviceBatteryLabel.text = "\(Int((level * 100).rounded()))%"
        } else {
            deviceBatteryLabel.text = ""
        }
    }

    private func updateDeviceStatus(isLandscape: Bool) {
        installDeviceStatusViewIfNeeded()
        deviceStatusView.isHidden = !isLandscape || !isMaskShow
        if isLandscape { refreshDeviceStatus() }
    }

    fileprivate func installRouteButtonLayout() {
        guard !routeButtonLayoutInstalled else { return }
        routeButtonLayoutInstalled = true

        // KSPlayer 默认把 routeButton 放进顶部 navigationBar；移到控制层右侧中部，
        // 避免横屏时和标题/返回按钮挤在一起，也避免重复显示。
        navigationBar.removeArrangedSubview(routeButton)
        routeButton.removeFromSuperview()
        controllerView.addSubview(routeButton)
        routeButton.translatesAutoresizingMaskIntoConstraints = false
        routeButton.layer.zPosition = 120
        NSLayoutConstraint.activate([
            routeButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -12),
            routeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            routeButton.heightAnchor.constraint(equalToConstant: 30),
        ])
    }

    private func styleControlLayers(isLandscape: Bool) {
        // 横屏时播放器可能在视频上下出现留边；控制层本身不能把留边固化成黑色。
        // 控制层和按钮都不应固化为黑色背景。
        let colors: [CGColor]
        if isLandscape {
            colors = [UIColor.clear.cgColor, UIColor.clear.cgColor]
        } else {
            let color = UIColor.black.withAlphaComponent(0.5).cgColor
            colors = [color, UIColor.clear.cgColor]
        }
        topMaskView.gradientLayer.colors = colors
        bottomMaskView.gradientLayer.colors = colors
        topMaskView.backgroundColor = .clear
        bottomMaskView.backgroundColor = .clear
        topMaskView.isOpaque = false
        bottomMaskView.isOpaque = false
    }

    override func player(layer: KSPlayerLayer, state: KSPlayerState) {
        guard playerLayer === layer else { return }
        super.player(layer: layer, state: state)
        installFirstFrameObservation(for: layer)
        // KSPlayer's centered replay button is redundant with the toolbar
        // play button in this app. It is especially distracting while a new
        // episode is preparing because the native paused callback briefly
        // makes it visible before autoplay resumes.
        replayButton.isHidden = true
        switch state {
        case .initialized, .preparing, .readyToPlay:
            showPlaybackLoadingIndicator()
        case .buffering:
            if !hidePlaybackLoadingIndicatorIfVideoIsPlaying(layer: layer) {
                showPlaybackLoadingIndicator()
            }
        case .bufferFinished:
            if layer.player.isPlaying {
                updatePlaybackControlIfPlaying(layer: layer)
            } else {
                showPlaybackLoadingIndicator()
                if !hasDisplayedCurrentVideoFrame, didStartInitialPlayback {
                    requestInitialPlayback(layer: layer)
                }
            }
        case .paused:
            if hidePlaybackLoadingIndicatorIfVideoIsPlaying(layer: layer)
                || (hasDisplayedCurrentVideoFrame && hasPlaybackAdvanced) {
                hidePlaybackLoadingIndicator()
            } else {
                showPlaybackLoadingIndicator()
                if didStartInitialPlayback {
                    // KSPlayer emits a transient paused callback while its
                    // backend is transitioning into playback. Keep loading
                    // visible and retry until the first frame is ready.
                    requestInitialPlayback(layer: layer)
                }
            }
        case .playedToTheEnd:
            hidePlaybackLoadingIndicator()
        case .error:
            autoplayRetryWorkItem?.cancel()
            autoplayRetryWorkItem = nil
            playbackFailed = true
            hidePlaybackLoadingIndicator()
            canShowPlaybackControl = true
            customControlsRefresh?()
            toolBar.playButton.isEnabled = true
            startPositionCoverView.isHidden = true
            DispatchQueue.main.async { [weak self] in
                self?.onPlaybackFailure?()
            }
        }
        guard state == .readyToPlay else { return }

        // KSPlayer can replace its backend during preparation. Re-apply only
        // the rate to the current backend; do not call set(url:) or seek.
        applyPlaybackRate(desiredPlaybackRate, persist: false, rebuildMenu: false)

        startInitialPlaybackIfNeeded(layer: layer)

        // KSPlayer 2.3.4 每次 readyToPlay 都会重建一次默认倍速菜单，默认只到 2x。
        // 在它完成初始化后覆盖菜单，避免切集或重连时选项又被恢复。
        rebuildPlaybackRateMenu()
        DispatchQueue.main.async { [weak self, weak layer] in
            guard let self, let layer, self.playerLayer === layer else { return }
            self.isMaskShow = true
            self.customControlsLayout?(self.landscapeButton.isSelected)
            self.customControlsRefresh?()
        }
    }

    private func installStartPositionCoverIfNeeded() {
        guard !startPositionCoverInstalled else { return }
        startPositionCoverInstalled = true
        startPositionCoverView.translatesAutoresizingMaskIntoConstraints = false
        startPositionCoverView.backgroundColor = .black
        startPositionCoverView.isOpaque = true
        startPositionCoverView.layer.zPosition = 400
        contentOverlayView.addSubview(startPositionCoverView)
        NSLayoutConstraint.activate([
            startPositionCoverView.leadingAnchor.constraint(equalTo: contentOverlayView.leadingAnchor),
            startPositionCoverView.trailingAnchor.constraint(equalTo: contentOverlayView.trailingAnchor),
            startPositionCoverView.topAnchor.constraint(equalTo: contentOverlayView.topAnchor),
            startPositionCoverView.bottomAnchor.constraint(equalTo: contentOverlayView.bottomAnchor)
        ])
    }

    fileprivate func prepareInitialPlayback(startPosition: TimeInterval) {
        startPositionGeneration &+= 1
        startPositionRetryWorkItem?.cancel()
        startPositionRetryWorkItem = nil
        pendingStartPosition = VodPlaybackState.normalizedProgress(startPosition)
        didApplyStartPosition = false
        didStartInitialPlayback = false
        canShowPlaybackControl = false
        hasDisplayedCurrentVideoFrame = false
        playbackFailed = false
        hasPlaybackAdvanced = false
        firstFrameObservation?.invalidate()
        firstFrameObservation = nil
        observedVideoLayer = nil
        firstFrameStartPosition = pendingStartPosition
        startPositionRetryCount = 0
        installStartPositionCoverIfNeeded()
        startPositionCoverView.isHidden = pendingStartPosition <= 0.5
        toolBar.playButton.isEnabled = pendingStartPosition <= 0.5
        toolBar.playButton.alpha = 0
        replayButton.isHidden = true
        autoplayRetryWorkItem?.cancel()
        autoplayRetryWorkItem = nil
        showPlaybackLoadingIndicator()
        customControlsRefresh?()
    }

    private func startInitialPlaybackIfNeeded(layer: KSPlayerLayer) {
        guard !didStartInitialPlayback else { return }
        guard pendingStartPosition > 0.5, pendingStartPosition.isFinite else {
            didStartInitialPlayback = true
            startPositionCoverView.isHidden = true
            toolBar.playButton.isEnabled = true
            requestInitialPlayback(layer: layer)
            return
        }
        guard !didApplyStartPosition else { return }

        // KSPlayer queues seek requests internally when the backend is not yet
        // seekable. Wait without issuing a seek so the app retry loop cannot
        // race that internal deferred seek.
        guard layer.player.isReadyToPlay, layer.player.seekable else {
            retryStartPositionWhenSeekable(layer: layer)
            return
        }

        toolBar.playButton.isEnabled = false
        didApplyStartPosition = true
        let requestedPosition = pendingStartPosition
        let duration = layer.player.duration
        let validDuration = duration.isFinite && duration > 0 ? duration : 0
        let target: TimeInterval
        if validDuration > 0 {
            // A completed/invalid resume point should replay from the start,
            // not seek to EOF and immediately trigger end-of-item behavior.
            guard requestedPosition < validDuration - 1 else {
                startInitialPlaybackFromBeginning(layer: layer)
                return
            }
            target = min(requestedPosition, validDuration)
        } else {
            target = requestedPosition
        }
        firstFrameStartPosition = target
        let generation = startPositionGeneration
        layer.player.seek(time: target) { [weak self, weak layer] success in
            DispatchQueue.main.async {
                guard let self,
                      let layer,
                      self.playerLayer === layer,
                      self.startPositionGeneration == generation else { return }
                self.startPositionRetryWorkItem?.cancel()
                self.startPositionRetryWorkItem = nil
                if success {
                    self.didStartInitialPlayback = true
                    self.pendingStartPosition = 0
                    self.startPositionCoverView.isHidden = true
                    self.toolBar.playButton.isEnabled = true
                    self.requestInitialPlayback(layer: layer)
                    return
                }

                // Do not retry a failed seek: KSPlayer may already have
                // accepted it into its own deferred-seek path.
                self.startInitialPlaybackFromBeginning(layer: layer)
            }
        }
    }

    private func retryStartPositionWhenSeekable(layer: KSPlayerLayer) {
        guard startPositionRetryWorkItem == nil else { return }
        guard startPositionRetryCount < 8 else {
            startInitialPlaybackFromBeginning(layer: layer)
            return
        }

        startPositionRetryCount += 1
        let generation = startPositionGeneration
        let workItem = DispatchWorkItem { [weak self, weak layer] in
            guard let self,
                  let layer,
                  self.playerLayer === layer,
                  self.startPositionGeneration == generation else { return }
            self.startPositionRetryWorkItem = nil
            self.startInitialPlaybackIfNeeded(layer: layer)
        }
        startPositionRetryWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    private func startInitialPlaybackFromBeginning(layer: KSPlayerLayer) {
        guard playerLayer === layer else { return }
        startPositionRetryWorkItem?.cancel()
        startPositionRetryWorkItem = nil
        pendingStartPosition = 0
        firstFrameStartPosition = 0
        didApplyStartPosition = false
        didStartInitialPlayback = true
        startPositionCoverView.isHidden = true
        toolBar.playButton.isEnabled = true
        requestInitialPlayback(layer: layer)
    }

    private func requestInitialPlayback(layer: KSPlayerLayer) {
        guard playerLayer === layer,
              didStartInitialPlayback,
              !(hasDisplayedCurrentVideoFrame && hasPlaybackAdvanced && layer.player.isPlaying),
              autoplayRetryWorkItem == nil else { return }
        if layer.player.isReadyToPlay, !layer.player.isPlaying {
            showPlaybackLoadingIndicator()
            play()
        }
        if layer.player.isPlaying, hasDisplayedCurrentVideoFrame {
            updatePlaybackControlIfPlaying(layer: layer)
            if hasPlaybackAdvanced {
                return
            }
        }
        let workItem = DispatchWorkItem { [weak self, weak layer] in
            guard let self,
                  let layer,
                  self.playerLayer === layer,
                  self.didStartInitialPlayback,
                  !(self.hasDisplayedCurrentVideoFrame
                    && self.hasPlaybackAdvanced
                    && layer.player.isPlaying) else { return }
            self.autoplayRetryWorkItem = nil
            guard layer.state != .error else {
                self.hidePlaybackLoadingIndicator()
                return
            }
            if layer.player.isPlaying {
                self.updatePlaybackControlIfPlaying(layer: layer)
                if self.hasDisplayedCurrentVideoFrame, self.hasPlaybackAdvanced {
                    return
                }
            } else {
                self.showPlaybackLoadingIndicator()
                if layer.player.isReadyToPlay {
                    self.play()
                }
            }
            self.requestInitialPlayback(layer: layer)
        }
        autoplayRetryWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
    }

    private func updatePlaybackControlIfPlaying(layer: KSPlayerLayer) {
        guard playerLayer === layer, layer.player.isPlaying else { return }
        if !canShowPlaybackControl {
            autoplayRetryWorkItem?.cancel()
            autoplayRetryWorkItem = nil
            canShowPlaybackControl = true
            toolBar.playButton.isSelected = true
            customControlsRefresh?()
        }

        if layer.player.tracks(mediaType: .video).isEmpty {
            hasDisplayedCurrentVideoFrame = true
            hasPlaybackAdvanced = true
        } else {
            installFirstFrameObservation(for: layer)
            if !hasPlaybackAdvanced {
                let currentTime = layer.player.currentPlaybackTime
                if currentTime.isFinite, currentTime - firstFrameStartPosition >= 0.08 {
                    hasPlaybackAdvanced = true
                }
            }
            // Non-AVPlayer KSPlayer backends do not expose AVPlayerLayer's
            // first-frame signal. Only infer readiness after playback time
            // has actually advanced from this session's start point.
            if observedVideoLayer == nil {
                let currentTime = layer.player.currentPlaybackTime
                if currentTime.isFinite, currentTime - firstFrameStartPosition >= 0.25 {
                    hasDisplayedCurrentVideoFrame = true
                    hasPlaybackAdvanced = true
                }
            }
        }
        if hasDisplayedCurrentVideoFrame {
            autoplayRetryWorkItem?.cancel()
            autoplayRetryWorkItem = nil
            hidePlaybackLoadingIndicator()
        } else {
            showPlaybackLoadingIndicator()
        }
    }

    private func installFirstFrameObservation(for layer: KSPlayerLayer) {
        guard playerLayer === layer,
              let renderLayer = layer.player.view?.layer as? AVPlayerLayer else { return }
        // The initial KVO delivery below also reports a layer that was ready
        // before observation began. Re-entering the frame callback synchronously
        // here can recurse through autoplay -> controls -> observation until the
        // main-thread stack overflows.
        guard observedVideoLayer !== renderLayer else { return }

        firstFrameObservation?.invalidate()
        observedVideoLayer = renderLayer
        firstFrameObservation = renderLayer.observe(
            \.isReadyForDisplay,
            options: [.initial, .new]
        ) { [weak self, weak layer] renderLayer, _ in
            guard renderLayer.isReadyForDisplay else { return }
            DispatchQueue.main.async {
                guard let self, let layer,
                      self.playerLayer === layer,
                      self.observedVideoLayer === renderLayer,
                      layer.player.view?.layer === renderLayer else { return }
                self.markFirstVideoFrameDisplayed(for: layer, renderedBy: renderLayer)
            }
        }
    }

    private func markFirstVideoFrameDisplayed(for layer: KSPlayerLayer, renderedBy renderLayer: AVPlayerLayer) {
        guard playerLayer === layer,
              observedVideoLayer === renderLayer,
              layer.player.view?.layer === renderLayer else { return }
        hasDisplayedCurrentVideoFrame = true
        if !hasPlaybackAdvanced {
            let currentTime = layer.player.currentPlaybackTime
            if currentTime.isFinite, currentTime - firstFrameStartPosition >= 0.08 {
                hasPlaybackAdvanced = true
            }
        }
        if layer.player.isPlaying {
            hidePlaybackLoadingIndicator()
            if hasPlaybackAdvanced {
                autoplayRetryWorkItem?.cancel()
                autoplayRetryWorkItem = nil
                if !canShowPlaybackControl {
                    canShowPlaybackControl = true
                    toolBar.playButton.isSelected = true
                }
                customControlsRefresh?()
            } else {
                // Playback may have started at a resume timestamp that is
                // rounded by the backend. The rendered frame is enough to hide
                // the loader; keep retrying only for control-state readiness.
                requestInitialPlayback(layer: layer)
            }
        } else {
            // AVPlayerLayer may expose a paused frame before the playback
            // clock advances. Keep the loader over that still frame and start
            // playback immediately; hide the loader on the first time tick.
            autoplayRetryWorkItem?.cancel()
            autoplayRetryWorkItem = nil
            showPlaybackLoadingIndicator()
            requestInitialPlayback(layer: layer)
        }
    }

    private func showPlaybackLoadingIndicator() {
        loadingIndector.isHidden = false
        loadingIndector.startAnimating()
    }

    @discardableResult
    private func hidePlaybackLoadingIndicatorIfVideoIsPlaying(layer: KSPlayerLayer) -> Bool {
        guard playerLayer === layer,
              layer.player.isPlaying,
              hasDisplayedCurrentVideoFrame else { return false }
        hidePlaybackLoadingIndicator()
        return true
    }

    private func hidePlaybackLoadingIndicator() {
        loadingIndector.stopAnimating()
        loadingIndector.isHidden = true
    }

    override func player(layer: KSPlayerLayer, finish error: Error?) {
        // An old layer can finish asynchronously while a new episode is being
        // installed. Ignore it so it cannot advance the new episode again.
        guard playerLayer === layer else { return }
        super.player(layer: layer, finish: error)
    }

    private func normalizedPlaybackRate(_ raw: Float) -> Float {
        guard raw.isFinite, raw > 0 else { return 1.0 }
        return Self.supportedPlaybackRates.min {
            abs($0 - raw) < abs($1 - raw)
        } ?? 1.0
    }

    private func applyPlaybackRate(
        _ rawRate: Float,
        persist: Bool,
        rebuildMenu: Bool
    ) {
        let rate = normalizedPlaybackRate(rawRate)
        let apply = { [weak self] in
            guard let self else { return }
            self.desiredPlaybackRate = rate
            if persist {
                UserDefaults.standard.set(Double(rate), forKey: HawkConfig.PLAY_SPEED)
            }
            guard let player = self.playerLayer?.player else {
                if rebuildMenu { self.rebuildPlaybackRateMenu() }
                return
            }

            // The rate setter changes the existing AVPlayer backend in place.
            // Keep a defensive position checkpoint so a backend implementation
            // that momentarily resets its time cannot restart the episode.
            let position = player.currentPlaybackTime
            let wasPlaying = player.isPlaying
            player.playbackRate = rate
            if position.isFinite, position > 0,
               abs(player.currentPlaybackTime - position) > 0.25 {
                player.seek(time: position) { [weak self] success in
                    guard success, wasPlaying else { return }
                    DispatchQueue.main.async {
                        self?.playerLayer?.player.play()
                    }
                }
            }
            if rebuildMenu {
                self.rebuildPlaybackRateMenu()
            }
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }

    fileprivate func rebuildPlaybackRateMenu() {
        guard #available(iOS 14.0, *) else { return }
        let current = normalizedPlaybackRate(
            playerLayer?.player.playbackRate ?? desiredPlaybackRate
        )
        let actions = Self.supportedPlaybackRates.map { rate in
            UIAction(
                title: String(format: "%.2gx", rate),
                state: abs(rate - current) < 0.01 ? .on : .off
            ) { [weak self] _ in
                self?.applyPlaybackRate(rate, persist: true, rebuildMenu: true)
            }
        }
        toolBar.playbackRateButton.menu = UIMenu(title: "倍速", children: actions)
        toolBar.playbackRateButton.showsMenuAsPrimaryAction = true
        toolBar.playbackRateButton.setTitle(nil, for: .normal)
        toolBar.playbackRateButton.setImage(UIImage(systemName: "speedometer"), for: .normal)
        toolBar.playbackRateButton.accessibilityLabel = "倍速"
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        applyTransparentSurfaces()
        // KSPlayer performs the actual reparenting in its dismissal
        // completion. Restore constraints only after that callback, never by
        // racing it with an early addSubview from our side.
        if !waitingForFullscreenDismissal,
           !landscapeButton.isSelected,
           superview === inlineSuperview {
            waitForInlineLayout(generation: inlineRestorationGeneration, attempt: 0)
        }
        syncInteractivePopGesture()
    }

    private func captureInlineLayout() {
        guard let container = superview else { return }
        if inlineSuperview === container {
            return
        }
        inlineSuperview = container
        inlineFrameConstraints = inlineLayoutConstraints(in: container)
        inlineTranslatesAutoresizingMaskIntoConstraints = translatesAutoresizingMaskIntoConstraints
    }

    private func inlineLayoutConstraints(in container: UIView) -> [NSLayoutConstraint] {
        var result = container.constraints.filter { constraint in
            constraint.firstItem === self || constraint.secondItem === self
        }
        result.append(contentsOf: constraints.filter { constraint in
            guard constraint.firstItem === self || constraint.secondItem === self else {
                return false
            }
            return constraint.firstAttribute == .width
                || constraint.firstAttribute == .height
                || constraint.secondAttribute == .width
                || constraint.secondAttribute == .height
        })
        return result
    }

    private func scheduleInlineRestoration() {
        restoreTask?.cancel()
        inlineRestorationGeneration &+= 1
        let generation = inlineRestorationGeneration
        let completeDismissal: (Bool) -> Void = { [weak self] wasCancelled in
            guard let self,
                  self.inlineRestorationGeneration == generation else { return }
            if wasCancelled {
                self.waitingForFullscreenDismissal = false
                return
            }
            self.waitingForFullscreenDismissal = false
            self.waitForInlineLayout(generation: generation, attempt: 0)
        }

        // The render-view dismissal animation is disabled, so begin inline
        // layout restoration as soon as the controller transition completes.
        if let coordinator = owningViewController?.transitionCoordinator {
            let registered = coordinator.animate(alongsideTransition: nil) { context in
                completeDismissal(context.isCancelled)
            }
            if !registered {
                scheduleInlineLayoutCheck(generation: generation, delay: Self.inlineSettleStepDelay) {
                    completeDismissal(false)
                }
            }
        } else {
            scheduleInlineLayoutCheck(generation: generation, delay: Self.inlineSettleStepDelay) {
                completeDismissal(false)
            }
        }
    }

    private func waitForInlineLayout(generation: Int, attempt: Int) {
        guard inlineRestorationGeneration == generation,
              !landscapeButton.isSelected,
              let container = inlineSuperview else { return }
        if attempt == 0 {
            resetInlineSettling()
        }

        guard superview === container else {
            // KSPlayer 还没把播放器放回内联容器；等它的 dismiss completion。
            guard attempt < 90 else {
                restoreInlineLayout(in: container)
                return
            }
            scheduleInlineLayoutCheck(generation: generation, delay: Self.inlineSettleStepDelay) { [weak self] in
                self?.waitForInlineLayout(generation: generation, attempt: attempt + 1)
            }
            return
        }

        // 不管窗口是否已经转回竖屏，先把播放器锁定到容器当前的真实尺寸。
        // KSPlayer 的 dismiss completion 会写入进入全屏前捕获的 frame，那是
        // 旧坐标系的值，会让画面先缩成左上角的小方块再弹回。这里在旋转的每
        // 一帧都跟着容器走，画面就随容器一起平滑变化。
        applyInlineFrame(container.bounds)

        if container.bounds.equalTo(settleLastBounds) {
            settleStableFrames += 1
        } else {
            settleStableFrames = 0
            settleLastBounds = container.bounds
        }

        // 容器尺寸连续几帧不再变化，说明旋转的布局已经稳定下来。
        // 同时要求至少跟随若干帧：KSPlayer 的 dismissal completion 可能比
        // 转场协调器的回调晚一点写入它缓存的 frame，过早收尾会被它覆盖。
        let settled = settleStableFrames >= Self.inlineSettleStableFrames
            && attempt >= Self.inlineSettleMinimumFrames
        guard settled || attempt >= 90 else {
            scheduleInlineLayoutCheck(generation: generation, delay: Self.inlineSettleStepDelay) { [weak self] in
                self?.waitForInlineLayout(generation: generation, attempt: attempt + 1)
            }
            return
        }

        restoreInlineLayout(in: container)
    }

    private func scheduleInlineLayoutCheck(
        generation: Int,
        delay: TimeInterval,
        action: @escaping () -> Void
    ) {
        restoreTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self, self.inlineRestorationGeneration == generation else { return }
            action()
        }
        restoreTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
    }

    private func restoreInlineLayout(in container: UIView) {
        guard !landscapeButton.isSelected, superview === container else { return }
        restoreTask?.cancel()
        restoreTask = nil

        translatesAutoresizingMaskIntoConstraints = inlineTranslatesAutoresizingMaskIntoConstraints
        if inlineFrameConstraints.isEmpty {
            // SwiftUI owns this representable's frame. Reapplying the value
            // captured before rotation writes coordinates from the old layout.
            translatesAutoresizingMaskIntoConstraints = true
        } else {
            NSLayoutConstraint.activate(inlineFrameConstraints)
        }
        applyInlineFrame(container.bounds)
        resetInlineSettling()
        applyTransparentSurfaces()
        container.setNeedsLayout()
        container.layoutIfNeeded()
        setNeedsLayout()
        updateUI(isLandscape: false)
        preservingFullscreenPlayer = false

        // 最后再校验一次：KSPlayer 的 completion 或旋转的收尾布局有可能在
        // 这里之后才写 frame，把它拉回容器真实尺寸，避免残留错位。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self,
                  !self.landscapeButton.isSelected,
                  self.superview === container else { return }
            self.applyInlineFrame(container.bounds)
        }
    }

    /// 把播放器同步到内联容器的当前尺寸。
    ///
    /// 退出全屏时窗口正在旋转，容器每一帧的尺寸都不一样。用容器的实时
    /// bounds 而不是缓存的 frame，画面就会跟着容器一起变化；同时打开
    /// autoresizing，让容器 bounds 变化时 UIKit 自动跟随，避免轮询之间的
    /// 空档出现错位。
    private func applyInlineFrame(_ bounds: CGRect) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        if needsFrameUpdate(frame, bounds) {
            frame = bounds
        }
        resetRenderLayerFrame()
    }

    /// KSPlayer 的转场动画会把真正渲染视频的 view 搬到 window 级容器上做
    /// 缩放动画，结束后只把它插回原父视图，frame/transform 仍是动画终态。
    /// 播放器容器自己被 SwiftUI 重新布局，这层却不会，于是画面停在错误的
    /// 位置和尺寸上——这正是"缩到左上角"的那一块。这里按父视图当前 bounds
    /// 复位。只在转场结束后调用，转场期间调用会打断动画。
    private func resetRenderLayerFrame() {
        guard let renderView = playerLayer?.player.view else { return }
        if renderView.transform != .identity {
            renderView.transform = .identity
        }
        guard let parent = renderView.superview else { return }
        let target = parent.bounds
        guard target.width > 0, target.height > 0 else { return }
        if needsFrameUpdate(renderView.frame, target) {
            renderView.frame = target
        }
    }

    private func needsFrameUpdate(_ current: CGRect, _ target: CGRect) -> Bool {
        abs(current.origin.x - target.origin.x) > 0.5
            || abs(current.origin.y - target.origin.y) > 0.5
            || abs(current.size.width - target.size.width) > 0.5
            || abs(current.size.height - target.size.height) > 0.5
    }

    private func resetInlineSettling() {
        settleStableFrames = 0
        settleLastBounds = .zero
    }

    fileprivate var isPreservingFullscreenPlayer: Bool {
        preservingFullscreenPlayer || landscapeButton.isSelected
    }

    /// Stop and release the current media item before installing another URL.
    /// Pausing alone leaves the old AVPlayerItem and audio pipeline alive.
    func stopCurrentPlayback(reportFinalProgress: Bool = true) {
        startPositionGeneration &+= 1
        startPositionRetryWorkItem?.cancel()
        startPositionRetryWorkItem = nil
        let layer = playerLayer
        let progressHandler = playTimeDidChange
        playTimeDidChange = nil
        autoplayRetryWorkItem?.cancel()
        autoplayRetryWorkItem = nil
        firstFrameObservation?.invalidate()
        firstFrameObservation = nil
        observedVideoLayer = nil
        layer?.delegate = nil

        // SwiftUI dismantleUIView 可能先于 DetailView.onDisappear 触发；
        // 先把播放器最后的有效位置回传，避免页面退出时丢掉尾部进度。
        if reportFinalProgress, let player = layer?.player {
            let current = player.currentPlaybackTime
            let duration = player.duration
            if current.isFinite, current > 0 {
                progressHandler?(current, duration.isFinite && duration > 0 ? duration : 0)
            }
        }
        layer?.pause()
        layer?.stop()
        playerLayer = nil
        pendingStartPosition = 0
        didApplyStartPosition = false
        didStartInitialPlayback = false
        canShowPlaybackControl = false
        hasDisplayedCurrentVideoFrame = false
        playbackFailed = false
        hasPlaybackAdvanced = false
        startPositionRetryCount = 0
        startPositionCoverView.isHidden = true
        toolBar.playButton.isEnabled = true
        toolBar.playButton.alpha = 0
        replayButton.isHidden = true
        hidePlaybackLoadingIndicator()
        configuredPlaybackURL = nil
        configuredPlaybackHeaders = [:]
        configuredPlaybackSessionToken = nil
    }

    func replacePlayback(url: URL, options: KSOptions) {
        let oldLayer = playerLayer
        oldLayer?.delegate = nil
        // The detail flow checkpoints history before rotating the session token.
        // Never send the retired layer's final callback through the new session.
        playTimeDidChange = nil

        // Stop the old audio pipeline before KSPlayer constructs the replacement layer.
        // Keep its view attached until set(url:) swaps it.
        oldLayer?.pause()
        oldLayer?.stop()
        super.set(url: url, options: options)
        if let playerLayer {
            installFirstFrameObservation(for: playerLayer)
        }
    }

    private func applyTransparentSurfaces() {
        backgroundColor = .clear
        isOpaque = false
        contentOverlayView.backgroundColor = .clear
        contentOverlayView.isOpaque = false
        controllerView.backgroundColor = .clear
        controllerView.isOpaque = false
        topMaskView.backgroundColor = .clear
        bottomMaskView.backgroundColor = .clear
        playerLayer?.player.view?.backgroundColor = .clear
        playerLayer?.player.view?.isOpaque = false

        if landscapeButton.isSelected, let fullScreenViewController = owningViewController {
            fullScreenViewController.view.backgroundColor = .clear
            fullScreenViewController.view.isOpaque = false
        }
    }

    private func syncInteractivePopGesture() {
        // Full-screen controller may not have a navigation controller. The
        // slider exclusion must remain active there as well.
        // KSPlayer currently leaves this delegate unset. Only claim it when
        // it is available (or already ours), so a future KSPlayer delegate is
        // never overwritten on every view lifecycle callback.
        if panGesture.delegate == nil || panGesture.delegate === self {
            panGesture.delegate = self
        }
        // KSPlayer's 2x long-press recognizer has its own delegate. The
        // control-area exclusion in gestureRecognizer(_:shouldReceive:) only
        // works for recognizers whose delegate is this view; previously only
        // panGesture was wired, so long presses below the progress bar still
        // reached KSPlayer and enabled 2x playback.
        if longPressGesture.delegate == nil || longPressGesture.delegate === self {
            longPressGesture.delegate = self
        }
        panGesture.cancelsTouchesInView = false
        guard let navigationController = owningNavigationController,
              let popGesture = navigationController.interactivePopGestureRecognizer else {
            return
        }

        if interactivePopGestureRecognizer !== popGesture {
            interactivePopGestureRecognizer = popGesture
            // 让系统边缘返回优先识别，避免播放器原生横滑手势吞掉左边缘返回。
            panGesture.require(toFail: popGesture)
        }

        popGesture.isEnabled = !landscapeButton.isSelected
    }

    private var owningNavigationController: UINavigationController? {
        owningViewController?.navigationController
    }

    private var owningViewController: UIViewController? {
        var responder: UIResponder? = self
        while let next = responder?.next {
            if let viewController = next as? UIViewController {
                return viewController
            }
            responder = next
        }
        return nil
    }

    // KSPlayer 的原生 pan 手势同时处理横向进度、左侧亮度和右侧音量。
    // 这里只在进度条区域拒绝 pan，让 KSSlider 独占这块触摸区域，避免
    // 拖动滑块时原生 pan 又写回播放时间导致小圆点乱跳。
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        let touchPoint = touch.location(in: self)
        // 控制栏（进度条及其下方区域）只交给原生按钮和滑块处理，
        // 禁止左右调速/调进度以及 KSPlayer 长按 2x 手势抢占触摸。
        if (gestureRecognizer === panGesture || gestureRecognizer === longPressGesture),
           isControlBarTouchArea(touchPoint) {
            return false
        }
        guard gestureRecognizer === panGesture else { return true }
        panStartPoint = touchPoint
        return true
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === panGesture,
              let pan = gestureRecognizer as? UIPanGestureRecognizer else {
            return true
        }

        let velocity = pan.velocity(in: self)
        guard abs(velocity.x) > abs(velocity.y), abs(velocity.x) > 1 else {
            return true
        }

        let touchPoint = panStartPoint ?? pan.location(in: self)
        panStartPoint = nil
        // Keep the portrait left-edge swipe available for UINavigationController.
        if !landscapeButton.isSelected && touchPoint.x <= 32 {
            return false
        }
        return !isProgressSliderTouchArea(touchPoint)
    }

    private func isProgressSliderTouchArea(_ point: CGPoint) -> Bool {
        guard !toolBar.timeSlider.isHidden,
              toolBar.timeSlider.bounds.width > 0,
              toolBar.timeSlider.bounds.height > 0 else {
            return false
        }

        var sliderFrame = toolBar.timeSlider.convert(toolBar.timeSlider.bounds, to: self)
        // Include a generous but local hit-protection band around the visual
        // track. This prevents a horizontal seek gesture from stealing a
        // thumb drag while leaving the rest of the video surface available.
        sliderFrame = sliderFrame.insetBy(dx: -20, dy: -28)
        if sliderFrame.contains(point) {
            return true
        }

        // Some KSPlayer layouts make the slider's bounds very short while
        // the surrounding toolbar row is taller. Protect that row as well,
        // but only across the slider's horizontal span.
        let rowFrame = CGRect(
            x: sliderFrame.minX,
            y: sliderFrame.midY - 28,
            width: sliderFrame.width,
            height: 56
        )
        return rowFrame.contains(point)
    }

    private func isControlBarTouchArea(_ point: CGPoint) -> Bool {
        guard !toolBar.isHidden else { return false }
        var toolbarFrame = toolBar.convert(toolBar.bounds, to: self)
        toolbarFrame = toolbarFrame.insetBy(dx: -18, dy: -24)
        guard !toolBar.timeSlider.isHidden,
              toolBar.timeSlider.bounds.width > 0,
              toolBar.timeSlider.bounds.height > 0 else {
            return toolbarFrame.contains(point)
        }

        let sliderFrame = toolBar.timeSlider.convert(toolBar.timeSlider.bounds, to: self)
        let controlsBounds = controllerView.convert(controllerView.bounds, to: self)
        let areaBelowProgress = CGRect(
            x: controlsBounds.minX,
            y: sliderFrame.maxY,
            width: controlsBounds.width,
            height: max(0, controlsBounds.maxY - sliderFrame.maxY)
        )
        return toolbarFrame.contains(point)
            || isProgressSliderTouchArea(point)
            || areaBelowProgress.contains(point)
    }

    override func panGestureBegan(location point: CGPoint, direction: KSPanDirection) {
        nativePanDirection = direction
        if direction == .horizontal {
            // KSPlayer owns the seek math and target preview. Do not replace
            // its default velocity-to-time mapping with a second calculation.
            pendingSeekTarget = nil
            sliderSeekCommitted = false
        }
        super.panGestureBegan(location: point, direction: direction)
    }

    override func panGestureChanged(velocity point: CGPoint, direction: KSPanDirection) {
        super.panGestureChanged(velocity: point, direction: direction)
        if direction == .horizontal, toolBar.currentTime.isFinite {
            pendingSeekTarget = toolBar.currentTime
        }
    }

    override func panGestureEnded() {
        if nativePanDirection == .horizontal {
            // panGestureEnded in KSPlayer commits exactly this preview value
            // through slider(.touchUpInside). Keep it protected from the last
            // stale playback callback while that seek is in flight.
            pendingSeekTarget = toolBar.currentTime
        }
        super.panGestureEnded()
        nativePanDirection = nil
    }
}

private struct KSPlayerUIView: UIViewRepresentable {
    private static let supportedPlaybackRates: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    let url: URL
    let playbackHeaders: [String: String]
    let startPosition: Double
    let playbackSessionToken: UUID?
    let isResolvingPlayback: Bool
    let onProgressChanged: ((Double, Double?) -> Void)?
    let onPlaybackEnded: (() -> Void)?
    let onPlaybackFailed: (() -> Void)?
    let onBack: (() -> Void)?
    let onPlayerAction: ((PlayerButtonType) -> Void)?
    let canPlayPrevious: Bool
    let onPlayPrevious: (() -> Void)?
    let canPlayNext: Bool
    let onPlayNext: (() -> Void)?
    let canSelectEpisode: Bool
    let onSelectEpisode: (() -> Void)?
    let onMarkIntro: (() -> Void)?
    let onMarkOutro: (() -> Void)?
    let onResetIntro: (() -> Void)?
    let onResetOutro: (() -> Void)?
    let introLabel: String
    let outroLabel: String
    let danmakuTitle: String
    let danmakuEpisode: String
    let displayEpisodeTitle: String
    let danmakuEnabled: Bool
    let onDanmakuEnabledChanged: ((Bool) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onProgressChanged: onProgressChanged,
            onPlaybackEnded: onPlaybackEnded,
            onPlaybackFailed: onPlaybackFailed,
            onBack: onBack,
            onPlayerAction: onPlayerAction,
            canPlayPrevious: canPlayPrevious,
            canPlayNext: canPlayNext,
            canSelectEpisode: canSelectEpisode,
            onPlayPrevious: onPlayPrevious,
            onPlayNext: onPlayNext,
            onSelectEpisode: onSelectEpisode,
            onMarkIntro: onMarkIntro,
            onMarkOutro: onMarkOutro,
            onResetIntro: onResetIntro,
            onResetOutro: onResetOutro,
            introLabel: introLabel,
            outroLabel: outroLabel,
            danmakuTitle: danmakuTitle,
            danmakuEpisode: danmakuEpisode,
            displayEpisodeTitle: displayEpisodeTitle,
            danmakuEnabled: danmakuEnabled,
            onDanmakuEnabledChanged: onDanmakuEnabledChanged
        )
    }

    func makeUIView(context: Context) -> CongcongKSVideoPlayerView {
        // KSPlayer's native full-screen controller temporarily reparents this
        // view. SwiftUI may ask the representable for its view again while
        // that transition is still in flight; reuse the retained instance so
        // the playback session is not torn down and recreated.
        if let retainedView = context.coordinator.retainedPlayerView {
            context.coordinator.configure(retainedView)
            retainedView.customControlsLayout = { [weak coordinator = context.coordinator] isLandscape in
                coordinator?.updateActionButtonsLayout(isLandscape: isLandscape)
            }
            let shouldConfigure = synchronizeCoordinator(context.coordinator, with: retainedView)
            if shouldConfigure {
                configure(retainedView, coordinator: context.coordinator)
            }
            return retainedView
        }

        let view = CongcongKSVideoPlayerView()
        context.coordinator.retainedPlayerView = view
        context.coordinator.configure(view)
        view.customControlsLayout = { [weak coordinator = context.coordinator] isLandscape in
            coordinator?.updateActionButtonsLayout(isLandscape: isLandscape)
        }
        _ = synchronizeCoordinator(context.coordinator, with: view)
        configure(view, coordinator: context.coordinator)
        return view
    }

    func updateUIView(_ view: CongcongKSVideoPlayerView, context: Context) {
        let shouldConfigure = synchronizeCoordinator(context.coordinator, with: view)
        guard shouldConfigure else { return }
        configure(view, coordinator: context.coordinator)
    }

    private func synchronizeCoordinator(
        _ coordinator: Coordinator,
        with view: CongcongKSVideoPlayerView
    ) -> Bool {
        let tokenChanged = coordinator.playbackSessionToken != playbackSessionToken
        let mediaChanged = coordinator.url != url
        let headersChanged = coordinator.playbackHeaders != playbackHeaders
        if tokenChanged {
            coordinator.playbackSessionToken = playbackSessionToken
        }
        if headersChanged {
            coordinator.playbackHeaders = playbackHeaders
        }
        if isResolvingPlayback && (tokenChanged || mediaChanged || headersChanged) {
            coordinator.pendingPlaybackReload = true
        }
        coordinator.onProgressChanged = isResolvingPlayback ? nil : onProgressChanged
        coordinator.onPlaybackEnded = isResolvingPlayback ? nil : onPlaybackEnded
        coordinator.onPlaybackFailed = isResolvingPlayback ? nil : onPlaybackFailed
        coordinator.onBack = onBack
        coordinator.onPlayerAction = onPlayerAction
        coordinator.onPlayPrevious = onPlayPrevious
        coordinator.onPlayNext = onPlayNext
        coordinator.onSelectEpisode = onSelectEpisode
        coordinator.onMarkIntro = onMarkIntro
        coordinator.onMarkOutro = onMarkOutro
        coordinator.onResetIntro = onResetIntro
        coordinator.onResetOutro = onResetOutro
        coordinator.updateMarkerLabels(intro: introLabel, outro: outroLabel)
        coordinator.updateDanmakuMetadata(
            title: danmakuTitle,
            episode: danmakuEpisode,
            displayEpisodeTitle: displayEpisodeTitle
        )
        coordinator.updateDanmakuEnabled(danmakuEnabled)
        coordinator.onDanmakuEnabledChanged = onDanmakuEnabledChanged
        view.onPlaybackFailure = { [weak coordinator] in
            coordinator?.reportPlaybackFailure()
        }
        coordinator.installActionButtons(
            on: view,
            canPlayPrevious: canPlayPrevious,
            canPlayNext: canPlayNext,
            canSelectEpisode: canSelectEpisode
        )
        coordinator.setPlaybackResolving(isResolvingPlayback)
        let canPlayPrevious = self.canPlayPrevious
        let canPlayNext = self.canPlayNext
        let canSelectEpisode = self.canSelectEpisode
        view.customControlsRefresh = { [weak coordinator, weak view] in
            guard let coordinator, let view else { return }
            coordinator.installActionButtons(
                on: view,
                canPlayPrevious: canPlayPrevious,
                canPlayNext: canPlayNext,
                canSelectEpisode: canSelectEpisode
            )
        }
        coordinator.updateActionButtonsLayout(isLandscape: view.landscapeButton.isSelected)
        view.customControlsLayout = { [weak coordinator] isLandscape in
            coordinator?.updateActionButtonsLayout(isLandscape: isLandscape)
        }
        let shouldConfigure = !isResolvingPlayback
            && (tokenChanged || mediaChanged || headersChanged || coordinator.pendingPlaybackReload)
        if shouldConfigure {
            coordinator.pendingPlaybackReload = false
        }
        return shouldConfigure
    }

    static func dismantleUIView(_ view: CongcongKSVideoPlayerView, coordinator: Coordinator) {
        // A native full-screen transition can temporarily make SwiftUI think
        // the representable disappeared. Do not tear down its layer or
        // coordinator callbacks; the same view is still owned by KSPlayer and
        // will be reattached when dismissal completes.
        guard !view.isPreservingFullscreenPlayer else { return }
        coordinator.tearDownDanmaku()
        view.stopCurrentPlayback()
        view.backBlock = nil
        view.delegate = nil
    }

    private func configure(_ view: CongcongKSVideoPlayerView, coordinator: Coordinator) {
        coordinator.url = url
        coordinator.playbackSessionToken = playbackSessionToken
        view.customControlsFitLayout = { [weak coordinator] in
            coordinator?.refreshToolbarLayout()
        }
        let needsPlaybackReplacement = view.playerLayer == nil
            || view.configuredPlaybackURL != url
            || view.configuredPlaybackHeaders != playbackHeaders
            || view.configuredPlaybackSessionToken != playbackSessionToken

        // 全屏进出只是同一个播放器 UIView 的重挂载，不能重置进度或重新
        // 安装媒体。否则 KSPlayer 会先从 0 开始，再执行一次恢复 seek。
        if needsPlaybackReplacement {
            coordinator.resetPlaybackFailure()
            view.prepareInitialPlayback(startPosition: startPosition)
            view.configuredPlaybackURL = url
            view.configuredPlaybackHeaders = playbackHeaders
            view.configuredPlaybackSessionToken = playbackSessionToken
        }
        // KSPlayer configures the audio session too. This app is foreground-only
        // for VOD: returning to the desktop must pause instead of continuing
        // audio in the background.
        KSOptions.setAudioSession()
        KSOptions.canBackgroundPlay = false
        // KSPlayer couples this flag to both prepareToPlay() and playback.
        // Keep its native initialization/autoplay path enabled.
        KSOptions.isAutoPlay = true
        // KSPlayer 原生 pan 手势：横向调进度，左侧纵向调亮度，右侧纵向调音量。
        // 显式开启，避免外部全局配置或旧版本默认值把这些交互关闭。
        KSOptions.enableBrightnessGestures = true
        KSOptions.enableVolumeGestures = true
        let options = KSOptions()
        options.preferredForwardBufferDuration = 8
        options.maxBufferDuration = 60
        options.isAccurateSeek = false
        playbackHeaders.forEach { options.appendHeader([$0.key: $0.value]) }
        // Start position is restored by the guarded seek path above. Leaving a
        // second native start-time request enabled can race that single seek.
        options.startPlayTime = 0
        let savedRate = UserDefaults.standard.object(forKey: HawkConfig.PLAY_SPEED) as? Double ?? 1.0
        let initialRate = Self.normalizedPlaybackRate(
            from: savedRate
        )
        view.desiredPlaybackRate = initialRate
        options.startPlayRate = initialRate
        options.registerRemoteControll = false
        // 本应用只提供点播，不启用画中画；尤其不能让播放器在内联状态下
        // 因切后台或系统事件自动进入 PiP。
        options.canStartPictureInPictureAutomaticallyFromInline = false
        if needsPlaybackReplacement {
            view.replacePlayback(url: url, options: options)
        }
        view.backgroundColor = .clear
        view.isOpaque = false
        view.contentOverlayView.backgroundColor = .clear
        view.controllerView.backgroundColor = .clear
        view.playerLayer?.player.view?.backgroundColor = .clear
        view.playerLayer?.player.view?.isOpaque = false
        // 完全移除 PiP 入口；投屏仍保留为独立的 AirPlay route 按钮。
        view.toolBar.pipButton.isHidden = true
        view.toolBar.pipButton.isEnabled = false
        view.routeButton.isHidden = false
        view.routeButton.tintColor = .white
        view.routeButton.activeTintColor = .systemOrange
        view.installRouteButtonLayout()
        view.toolBar.playbackRateButton.setTitle(nil, for: .normal)
        view.toolBar.playbackRateButton.setImage(UIImage(systemName: "speedometer"), for: .normal)
        view.toolBar.playbackRateButton.tintColor = .white
        view.toolBar.playbackRateButton.accessibilityLabel = "倍速"
        // Keep the persisted selection visible even before the first ready
        // callback rebuilds KSPlayer's native controls.
        view.rebuildPlaybackRateMenu()
        view.landscapeButton.isHidden = false
        view.landscapeButton.isEnabled = true
        coordinator.installActionButtons(
            on: view,
            canPlayPrevious: canPlayPrevious,
            canPlayNext: canPlayNext,
            canSelectEpisode: canSelectEpisode
        )
        coordinator.updateActionButtonsLayout(isLandscape: view.landscapeButton.isSelected)
        coordinator.installDanmaku(on: view)
        view.playTimeDidChange = { [weak coordinator] current, total in
            guard let coordinator else { return }
            coordinator.updatePlaybackTimeline(currentTime: current, duration: total)
        }
    }

    private static func normalizedPlaybackRate(from raw: Double) -> Float {
        let value = raw.isFinite && raw > 0 ? Float(raw) : 1.0
        return supportedPlaybackRates.min(by: { abs($0 - value) < abs($1 - value) }) ?? 1.0
    }

    final class Coordinator: NSObject, PlayerControllerDelegate {
        private struct PendingDanmakuSeek {
            let target: TimeInterval
            let startedAt: TimeInterval
        }

        var url: URL?
        var playbackHeaders: [String: String] = [:]
        var playbackSessionToken: UUID?
        var pendingPlaybackReload = false
        var onProgressChanged: ((Double, Double?) -> Void)?
        var onPlaybackEnded: (() -> Void)?
        var onPlaybackFailed: (() -> Void)?
        var onBack: (() -> Void)?
        var onPlayerAction: ((PlayerButtonType) -> Void)?
        var onPlayPrevious: (() -> Void)?
        var onPlayNext: (() -> Void)?
        var onSelectEpisode: (() -> Void)?
        var onMarkIntro: (() -> Void)?
        var onMarkOutro: (() -> Void)?
        var onResetIntro: (() -> Void)?
        var onResetOutro: (() -> Void)?
        var onDanmakuEnabledChanged: ((Bool) -> Void)?
        private var danmakuTitle: String
        private var danmakuEpisode: String
        private var displayEpisodeTitle: String
        private var danmakuEnabled: Bool
        private var danmakuSettings = DanmakuDisplaySettings.load()
        private var danmakuStatusText = "准备搜索弹幕"
        private var loadedDanmakuKey: String?
        private var loadingDanmakuKey: String?
        private weak var danmakuView: DanmakuOverlayView?
        private weak var danmakuStatusLabel: UILabel?
        private var danmakuStatusDismissWorkItem: DispatchWorkItem?
        private var isShowingDanmakuSearchToast = false
        private var pendingDanmakuStatusToast: String?
        private var danmakuRetryWorkItem: DispatchWorkItem?
        private var danmakuRetryKey: String?
        private var danmakuRetryAttempt = 0
        private var danmakuSettingsPanel: DanmakuSettingsPanelView?
        private var danmakuSearchPanel: DanmakuSearchPanelView?
        private var danmakuTask: Task<Void, Never>?
        private var danmakuLoadRequestID = UUID()
        private var danmakuSearchTask: Task<Void, Never>?
        private var danmakuResultTask: Task<Void, Never>?
        private var danmakuSearchResults: [DanmuSearchResult] = []
        private var danmakuResultRequestID = UUID()
        private var danmakuLayoutConstraints: [NSLayoutConstraint] = []
        private var lastPlayerTime: TimeInterval = 0
        private var lastPlayerDuration: TimeInterval = 0
        private var pendingDanmakuSeek: PendingDanmakuSeek?
        private var didReportPlaybackFailure = false
        private let previousButton = UIButton(type: .system)
        private let rewindButton = UIButton(type: .system)
        private let forwardButton = UIButton(type: .system)
        private let nextButton = UIButton(type: .system)
        private let verticalRewindButton = UIButton(type: .system)
        private let verticalForwardButton = UIButton(type: .system)
        private let verticalSeekStack = UIStackView()
        private let volumeButton = UIButton(type: .system)
        private let episodeButton = UIButton(type: .system)
        private let aspectRatioButton = UIButton(type: .system)
        private let danmakuButton = UIButton(type: .system)
        private let introButton = UIButton(type: .system)
        private let outroButton = UIButton(type: .system)
        private var fittedTimeLabelWidthConstraint: NSLayoutConstraint?
        private var introLabel = "片头"
        private var outroLabel = "片尾"
        /// Strongly retain the native view across SwiftUI's transient
        /// dismantle/re-make cycle during KSPlayer full-screen transitions.
        /// The view's delegate and callbacks are weak, so this does not form
        /// a retain cycle with the coordinator.
        fileprivate var retainedPlayerView: CongcongKSVideoPlayerView?
        private var playerView: IOSVideoPlayerView?
        private var canPlayPrevious = false
        private var canPlayNext = false
        private var canSelectEpisode = false
        private var isLandscape = false
        private var selectedAspectRatio: PlaybackAspectRatio = .original
        private var volumeButtonState = PlaybackVolumeState()
        private var verticalSeekConstraints: [NSLayoutConstraint] = []
        private var appWillResignActiveObserver: NSObjectProtocol?

        init(
            onProgressChanged: ((Double, Double?) -> Void)?,
            onPlaybackEnded: (() -> Void)?,
            onPlaybackFailed: (() -> Void)?,
            onBack: (() -> Void)?,
            onPlayerAction: ((PlayerButtonType) -> Void)?,
            canPlayPrevious _: Bool,
            canPlayNext _: Bool,
            canSelectEpisode _: Bool,
            onPlayPrevious: (() -> Void)?,
            onPlayNext: (() -> Void)?,
            onSelectEpisode: (() -> Void)?,
            onMarkIntro: (() -> Void)?,
            onMarkOutro: (() -> Void)?,
            onResetIntro: (() -> Void)?,
            onResetOutro: (() -> Void)?,
            introLabel: String,
            outroLabel: String,
            danmakuTitle: String,
            danmakuEpisode: String,
            displayEpisodeTitle: String,
            danmakuEnabled: Bool,
            onDanmakuEnabledChanged: ((Bool) -> Void)?
        ) {
            self.onProgressChanged = onProgressChanged
            self.onPlaybackEnded = onPlaybackEnded
            self.onPlaybackFailed = onPlaybackFailed
            self.onBack = onBack
            self.onPlayerAction = onPlayerAction
            self.onPlayPrevious = onPlayPrevious
            self.onPlayNext = onPlayNext
            self.onSelectEpisode = onSelectEpisode
            self.onMarkIntro = onMarkIntro
            self.onMarkOutro = onMarkOutro
            self.onResetIntro = onResetIntro
            self.onResetOutro = onResetOutro
            self.introLabel = introLabel
            self.outroLabel = outroLabel
            self.danmakuTitle = danmakuTitle
            self.danmakuEpisode = danmakuEpisode
            self.displayEpisodeTitle = displayEpisodeTitle
            self.danmakuEnabled = danmakuEnabled
            self.onDanmakuEnabledChanged = onDanmakuEnabledChanged
            danmakuSettings.enabled = danmakuEnabled
            danmakuSettings.save()
            super.init()
            appWillResignActiveObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.willResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                // 点播不允许在后台继续播放；暂停当前 KSPlayer 会话而不销毁
                // 播放器，回到前台后由详情页的网络/会话恢复逻辑重新验证。
                self?.retainedPlayerView?.playerLayer?.pause()
            }
        }

        deinit {
            if let appWillResignActiveObserver {
                NotificationCenter.default.removeObserver(appWillResignActiveObserver)
            }
        }

        func configure(_ view: IOSVideoPlayerView) {
            view.delegate = self
            view.backBlock = { [weak self] in
                self?.onBack?()
            }
        }

        func updateDanmakuMetadata(title: String, episode: String, displayEpisodeTitle: String) {
            let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedEpisode = episode.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedDisplayEpisode = displayEpisodeTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let metadataChanged = normalizedTitle != danmakuTitle || normalizedEpisode != danmakuEpisode
            danmakuTitle = normalizedTitle
            danmakuEpisode = normalizedEpisode
            self.displayEpisodeTitle = normalizedDisplayEpisode
            updatePlayerTitle()
            guard metadataChanged else { return }
            loadedDanmakuKey = nil
            cancelDanmakuRetry(resetAttempts: true)
            invalidateDanmakuLoad()
            danmakuSearchTask?.cancel()
            danmakuResultTask?.cancel()
            danmakuSearchPanel?.removeFromSuperview()
            danmakuSearchPanel = nil
            danmakuSearchResults = []
            danmakuView?.clear()
            setDanmakuStatus("正在搜索弹幕", showsToast: false)
            guard let danmakuView else { return }
            loadDanmaku(into: danmakuView)
        }

        private func updatePlayerTitle() {
            let title = danmakuTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isLandscape, !displayEpisodeTitle.isEmpty else {
                playerView?.titleLabel.text = title
                return
            }
            playerView?.titleLabel.text = "\(title) \(displayEpisodeTitle)"
        }

        func updateDanmakuEnabled(_ enabled: Bool) {
            guard danmakuEnabled != enabled else { return }
            danmakuEnabled = enabled
            danmakuSettings.enabled = enabled
            danmakuSettings.save()
            danmakuView?.isHidden = !enabled
            danmakuView?.updateSettings(danmakuSettings)
            updateDanmakuButton()
            updateDanmakuPanel()
            if !enabled {
                cancelDanmakuRetry(resetAttempts: true)
                invalidateDanmakuLoad()
                danmakuSearchTask?.cancel()
                danmakuResultTask?.cancel()
                danmakuSearchPanel?.removeFromSuperview()
                danmakuSearchPanel = nil
                loadingDanmakuKey = nil
                setDanmakuStatus("弹幕已关闭")
                return
            }
            guard enabled, let danmakuView else { return }
            loadDanmaku(into: danmakuView)
            danmakuView.update(currentTime: lastPlayerTime, duration: lastPlayerDuration, playbackRate: currentPlaybackRate)
        }

        private func updateDanmakuSettings(_ settings: DanmakuDisplaySettings) {
            let previousEnabled = danmakuEnabled
            danmakuSettings = settings.normalized
            danmakuSettings.save()
            danmakuView?.updateSettings(danmakuSettings)
            danmakuView?.update(currentTime: lastPlayerTime, duration: lastPlayerDuration, playbackRate: currentPlaybackRate)
            if previousEnabled != danmakuSettings.enabled {
                updateDanmakuEnabled(danmakuSettings.enabled)
                onDanmakuEnabledChanged?(danmakuSettings.enabled)
            } else {
                updateDanmakuPanel()
            }
        }

        func installDanmaku(on view: IOSVideoPlayerView) {
            installDanmakuStatus(in: view)
            if let existing = danmakuView {
                if existing.superview !== view.contentOverlayView {
                    existing.removeFromSuperview()
                    view.contentOverlayView.addSubview(existing)
                    existing.translatesAutoresizingMaskIntoConstraints = false
                }
                updateDanmakuLayout(in: view)
                existing.isHidden = !danmakuEnabled
                existing.updateSettings(danmakuSettings)
                loadDanmaku(into: existing)
                return
            }

            let overlay = DanmakuOverlayView()
            overlay.translatesAutoresizingMaskIntoConstraints = false
            overlay.isHidden = !danmakuEnabled
            overlay.setPlaybackActive(false)
            overlay.updateSettings(danmakuSettings)
            view.contentOverlayView.addSubview(overlay)
            overlay.layer.zPosition = 100
            danmakuView = overlay
            updateDanmakuLayout(in: view)
            loadDanmaku(into: overlay)
        }

        private func updateDanmakuLayout(in view: IOSVideoPlayerView) {
            NSLayoutConstraint.deactivate(danmakuLayoutConstraints)
            let targetView: UIView
            if selectedAspectRatio.usesFixedViewport,
               isLandscape,
               let renderView = view.playerLayer?.player.view {
                targetView = renderView
            } else {
                targetView = view.contentOverlayView
            }
            guard let danmakuView else { return }
            danmakuLayoutConstraints = [
                danmakuView.leadingAnchor.constraint(equalTo: targetView.leadingAnchor),
                danmakuView.trailingAnchor.constraint(equalTo: targetView.trailingAnchor),
                danmakuView.topAnchor.constraint(equalTo: targetView.topAnchor),
                danmakuView.bottomAnchor.constraint(equalTo: targetView.bottomAnchor)
            ]
            NSLayoutConstraint.activate(danmakuLayoutConstraints)
        }

        func tearDownDanmaku() {
            pendingDanmakuSeek = nil
            invalidateDanmakuLoad()
            danmakuSearchTask?.cancel()
            danmakuSearchTask = nil
            danmakuResultTask?.cancel()
            danmakuResultTask = nil
            danmakuStatusDismissWorkItem?.cancel()
            cancelDanmakuRetry(resetAttempts: true)
            danmakuSettingsPanel?.removeFromSuperview()
            danmakuSettingsPanel = nil
            danmakuSearchPanel?.removeFromSuperview()
            danmakuSearchPanel = nil
            danmakuSearchResults = []
            loadedDanmakuKey = nil
            loadingDanmakuKey = nil
            danmakuView?.clear()
            danmakuView?.removeFromSuperview()
            danmakuView = nil
            danmakuStatusLabel?.removeFromSuperview()
            danmakuStatusLabel = nil
        }

        func updateDanmaku(currentTime: TimeInterval, duration: TimeInterval) {
            danmakuView?.update(currentTime: currentTime, duration: duration, playbackRate: currentPlaybackRate)
        }

        private func loadDanmaku(into overlay: DanmakuOverlayView, showsSearchToast: Bool = true) {
            let title = danmakuTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let episode = danmakuEpisode.trimmingCharacters(in: .whitespacesAndNewlines)
            guard danmakuEnabled else { return }
            guard !title.isEmpty else {
                setDanmakuStatus("影片标题不可用，无法搜索弹幕")
                return
            }
            let key = "\(title)\u{1F}\(episode)"
            guard loadedDanmakuKey != key, loadingDanmakuKey != key else { return }
            if danmakuRetryKey == key, danmakuRetryWorkItem != nil { return }
            if danmakuRetryKey != key {
                cancelDanmakuRetry(resetAttempts: true)
                danmakuRetryKey = key
            }
            danmakuRetryWorkItem?.cancel()
            danmakuRetryWorkItem = nil

            invalidateDanmakuLoad()
            let requestID = UUID()
            danmakuLoadRequestID = requestID
            loadingDanmakuKey = key
            overlay.clear()
            if showsSearchToast {
                showDanmakuSearchToast()
            } else {
                setDanmakuStatus("正在搜索弹幕", showsToast: false)
            }

            danmakuTask = Task { @MainActor [weak self, weak overlay] in
                let cues = await DanmuService.shared.loadCues(title: title, episode: episode)
                guard !Task.isCancelled,
                      let self,
                      self.danmakuLoadRequestID == requestID,
                      let overlay,
                      self.danmakuView === overlay,
                      self.loadingDanmakuKey == key else { return }
                self.loadingDanmakuKey = nil
                self.danmakuTask = nil
                if !cues.isEmpty {
                    self.cancelDanmakuRetry(resetAttempts: true)
                    self.loadedDanmakuKey = key
                    self.setDanmakuStatus("已加载 \(cues.count) 条弹幕")
                } else {
                    if self.danmakuRetryAttempt < 2 {
                        self.setDanmakuStatus("暂未获取到弹幕，稍后重试", showsToast: false)
                        self.scheduleDanmakuRetry(for: key, requestID: requestID, overlay: overlay)
                    } else {
                        self.cancelDanmakuRetry(resetAttempts: true)
                        self.setDanmakuStatus("暂未获取到弹幕")
                    }
                }
                overlay.setCues(cues)
                overlay.isHidden = !self.danmakuEnabled || cues.isEmpty
                overlay.updateSettings(self.danmakuSettings)
                // A cue request can finish between two KSPlayer time
                // callbacks. Seed the overlay with the latest known time
                // so the first comments are rendered immediately.
                overlay.update(currentTime: self.lastPlayerTime, duration: self.lastPlayerDuration, playbackRate: self.currentPlaybackRate)
            }
        }

        private func invalidateDanmakuLoad() {
            danmakuLoadRequestID = UUID()
            danmakuTask?.cancel()
            danmakuTask = nil
            loadingDanmakuKey = nil
        }

        private func scheduleDanmakuRetry(
            for key: String,
            requestID: UUID,
            overlay: DanmakuOverlayView
        ) {
            guard danmakuRetryAttempt < 2 else { return }
            let delay: TimeInterval = danmakuRetryAttempt == 0 ? 2 : 5
            danmakuRetryAttempt += 1
            let workItem = DispatchWorkItem { [weak self, weak overlay] in
                guard let self, let overlay,
                      self.danmakuEnabled,
                      self.danmakuLoadRequestID == requestID,
                      self.danmakuRetryKey == key,
                      self.danmakuView === overlay else { return }
                self.danmakuRetryWorkItem = nil
                self.setDanmakuStatus("正在重试弹幕加载", showsToast: false)
                self.loadDanmaku(into: overlay, showsSearchToast: false)
            }
            danmakuRetryWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }

        private func cancelDanmakuRetry(resetAttempts: Bool) {
            danmakuRetryWorkItem?.cancel()
            danmakuRetryWorkItem = nil
            if resetAttempts {
                danmakuRetryKey = nil
                danmakuRetryAttempt = 0
            }
        }

        private func installDanmakuStatus(in view: IOSVideoPlayerView) {
            if let danmakuStatusLabel, danmakuStatusLabel.superview === view.contentOverlayView { return }
            danmakuStatusLabel?.removeFromSuperview()
            let label = UILabel()
            label.translatesAutoresizingMaskIntoConstraints = false
            label.textAlignment = .center
            label.font = .systemFont(ofSize: 13, weight: .medium)
            label.textColor = .white
            label.backgroundColor = UIColor.black.withAlphaComponent(0.68)
            label.layer.cornerRadius = 8
            label.clipsToBounds = true
            label.numberOfLines = 2
            label.alpha = 0
            label.isHidden = true
            label.layer.zPosition = 220
            view.contentOverlayView.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: view.contentOverlayView.centerXAnchor),
                label.topAnchor.constraint(equalTo: view.contentOverlayView.safeAreaLayoutGuide.topAnchor, constant: 18),
                label.widthAnchor.constraint(lessThanOrEqualTo: view.contentOverlayView.widthAnchor, constant: -32),
                label.widthAnchor.constraint(greaterThanOrEqualToConstant: 150)
            ])
            danmakuStatusLabel = label
        }

        private func setDanmakuStatus(_ text: String, showsToast: Bool = true) {
            danmakuStatusText = text
            updateDanmakuPanel()
            guard let label = danmakuStatusLabel else { return }
            if isShowingDanmakuSearchToast {
                if showsToast, text != "正在搜索弹幕" {
                    pendingDanmakuStatusToast = text
                }
                return
            }
            danmakuStatusDismissWorkItem?.cancel()
            guard showsToast else {
                label.layer.removeAllAnimations()
                label.alpha = 0
                label.isHidden = true
                return
            }
            label.text = "  \(text)  "
            label.isHidden = false
            UIView.animate(withDuration: 0.16) { label.alpha = 1 }
            let workItem = DispatchWorkItem { [weak label] in
                UIView.animate(withDuration: 0.25) {
                    label?.alpha = 0
                } completion: { _ in
                    label?.isHidden = true
                }
            }
            danmakuStatusDismissWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5, execute: workItem)
        }

        private func showDanmakuSearchToast() {
            danmakuStatusText = "正在搜索弹幕"
            pendingDanmakuStatusToast = nil
            updateDanmakuPanel()
            guard let label = danmakuStatusLabel else { return }
            danmakuStatusDismissWorkItem?.cancel()
            isShowingDanmakuSearchToast = true
            label.text = "  正在搜索弹幕  "
            label.isHidden = false
            UIView.animate(withDuration: 0.12) { label.alpha = 1 }
            let workItem = DispatchWorkItem { [weak self, weak label] in
                guard let self else { return }
                self.isShowingDanmakuSearchToast = false
                self.danmakuStatusDismissWorkItem = nil
                if let pending = self.pendingDanmakuStatusToast {
                    self.pendingDanmakuStatusToast = nil
                    self.setDanmakuStatus(pending)
                } else {
                    UIView.animate(withDuration: 0.2) {
                        label?.alpha = 0
                    } completion: { _ in
                        label?.isHidden = true
                    }
                }
            }
            danmakuStatusDismissWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.95, execute: workItem)
        }

        private func updateDanmakuPanel() {
            danmakuSettingsPanel?.update(settings: danmakuSettings, status: danmakuStatusText)
        }

        private func updateDanmakuButton() {
            danmakuButton.setImage(nil, for: .normal)
            danmakuButton.setTitle("弹幕", for: .normal)
            danmakuButton.setTitleColor(danmakuEnabled ? .systemOrange : .white, for: .normal)
            danmakuButton.accessibilityValue = danmakuEnabled ? "已开启" : "已关闭"
        }

        private func forceReloadDanmaku() {
            guard danmakuEnabled else {
                setDanmakuStatus("请先开启弹幕")
                return
            }
            loadedDanmakuKey = nil
            cancelDanmakuRetry(resetAttempts: true)
            invalidateDanmakuLoad()
            guard let danmakuView else {
                setDanmakuStatus("播放器尚未就绪")
                return
            }
            loadDanmaku(into: danmakuView)
        }

        private func openDanmakuSearch() {
            guard danmakuEnabled, let playerView else {
                setDanmakuStatus("请先开启弹幕")
                return
            }
            cancelDanmakuRetry(resetAttempts: true)
            invalidateDanmakuLoad()
            danmakuSettingsPanel?.removeFromSuperview()
            danmakuSettingsPanel = nil
            danmakuSearchPanel?.removeFromSuperview()

            let panel = DanmakuSearchPanelView(query: danmakuTitle)
            panel.translatesAutoresizingMaskIntoConstraints = false
            panel.layer.zPosition = 360
            panel.onSearch = { [weak self, weak panel] query in
                guard let self, let panel else { return }
                self.searchDanmakuResults(query: query, in: panel)
            }
            panel.onSelect = { [weak self, weak panel] index in
                guard let self, let panel else { return }
                self.loadSelectedDanmakuResult(at: index, in: panel)
            }
            panel.onClose = { [weak self, weak panel] in
                guard let panel else { return }
                self?.danmakuSearchTask?.cancel()
                self?.danmakuResultTask?.cancel()
                self?.danmakuResultRequestID = UUID()
                panel.removeFromSuperview()
                if self?.danmakuSearchPanel === panel { self?.danmakuSearchPanel = nil }
                if let self, self.loadedDanmakuKey == nil, let overlay = self.danmakuView {
                    self.loadDanmaku(into: overlay)
                }
            }
            // 将弹窗安装在播放器根视图最上层，而不是控制栏内部；这样弹窗
            // 覆盖的区域会先收到触摸，不会误触到底下的倍速、选集等控件。
            playerView.addSubview(panel)
            playerView.bringSubviewToFront(panel)
            NSLayoutConstraint.activate([
                panel.leadingAnchor.constraint(equalTo: playerView.leadingAnchor),
                panel.trailingAnchor.constraint(equalTo: playerView.trailingAnchor),
                panel.topAnchor.constraint(equalTo: playerView.topAnchor),
                panel.bottomAnchor.constraint(equalTo: playerView.bottomAnchor)
            ])
            danmakuSearchPanel = panel
            searchDanmakuResults(query: danmakuTitle, in: panel)
        }

        private func searchDanmakuResults(query: String, in panel: DanmakuSearchPanelView) {
            let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
            danmakuSearchTask?.cancel()
            danmakuResultTask?.cancel()
            danmakuResultRequestID = UUID()
            danmakuSearchResults = []
            guard !query.isEmpty else {
                panel.update(results: [], status: "请输入影片名称", loading: false)
                return
            }
            panel.update(results: [], status: "正在搜索弹幕", loading: true)
            danmakuSearchTask = Task { @MainActor [weak self, weak panel] in
                do {
                    let results = try await DanmuService.shared.searchResults(
                        title: query,
                        episode: self?.danmakuEpisode ?? ""
                    )
                    guard !Task.isCancelled, let self, let panel,
                          self.danmakuSearchPanel === panel else { return }
                    self.danmakuSearchResults = results
                    panel.update(
                        results: results,
                        status: results.isEmpty ? "未找到弹幕结果" : "找到 \(results.count) 个结果，选择后开始加载",
                        loading: false
                    )
                } catch is CancellationError {
                    return
                } catch {
                    guard !Task.isCancelled, let self, let panel,
                          self.danmakuSearchPanel === panel else { return }
                    panel.update(results: [], status: "搜索失败：\(error.localizedDescription)", loading: false)
                }
            }
        }

        private func loadSelectedDanmakuResult(at index: Int, in panel: DanmakuSearchPanelView) {
            guard danmakuEnabled, danmakuSearchResults.indices.contains(index),
                  let overlay = danmakuView else { return }
            danmakuSearchTask?.cancel()
            danmakuResultTask?.cancel()
            cancelDanmakuRetry(resetAttempts: true)
            invalidateDanmakuLoad()
            overlay.clear()
            let requestID = UUID()
            danmakuResultRequestID = requestID
            let requestedTitle = danmakuTitle
            let requestedEpisode = danmakuEpisode
            let matchingIndices = danmakuSearchResults.indices.filter {
                DanmakuEpisodeMatcher.matches(
                    requestedEpisode: requestedEpisode,
                    title: danmakuSearchResults[$0].name
                )
            }
            let otherIndices = danmakuSearchResults.indices.filter { $0 != index }
            let matchingOthers = otherIndices.filter { matchingIndices.contains($0) }
            let candidateIndices = [index] + matchingOthers + otherIndices.filter { !matchingIndices.contains($0) }
            var seenIndices = Set<Int>()
            let attempts = candidateIndices
                .filter { seenIndices.insert($0).inserted }
                .prefix(3)
                .map { danmakuSearchResults[$0] }
            panel.update(results: danmakuSearchResults, status: "正在加载第 1 / \(attempts.count) 条", loading: true)

            danmakuResultTask = Task { @MainActor [weak self, weak panel, weak overlay] in
                guard let self else { return }
                for (offset, result) in attempts.enumerated() {
                    guard !Task.isCancelled, self.danmakuResultRequestID == requestID,
                          let panel, let overlay, self.danmakuSearchPanel === panel else { return }
                    if offset > 0 {
                        panel.update(
                            results: self.danmakuSearchResults,
                            status: "上一条不可用，快速尝试第 \(offset + 1) / \(attempts.count) 条",
                            loading: true
                        )
                    }
                    do {
                        let cues = try await DanmuService.shared.loadSearchResult(
                            result,
                            title: requestedTitle,
                            episode: requestedEpisode
                        )
                        guard !Task.isCancelled, self.danmakuResultRequestID == requestID else { return }
                        guard !cues.isEmpty else { continue }
                        overlay.setCues(cues)
                        overlay.isHidden = false
                        overlay.updateSettings(self.danmakuSettings)
                        overlay.update(currentTime: self.lastPlayerTime, duration: self.lastPlayerDuration, playbackRate: self.currentPlaybackRate)
                        self.loadedDanmakuKey = "\(self.danmakuTitle)\u{1F}\(self.danmakuEpisode)"
                        self.setDanmakuStatus("已加载 \(cues.count) 条弹幕")
                        panel.removeFromSuperview()
                        self.danmakuSearchPanel = nil
                        return
                    } catch is CancellationError {
                        return
                    } catch {
                        continue
                    }
                }
                guard !Task.isCancelled, self.danmakuResultRequestID == requestID,
                      let panel, self.danmakuSearchPanel === panel else { return }
                panel.update(results: self.danmakuSearchResults, status: "这些结果均无法加载，请重新搜索", loading: false)
                self.setDanmakuStatus("弹幕结果加载失败")
            }
        }

        @objc private func danmakuPressed() {
            guard let playerView else { return }
            if let danmakuSettingsPanel {
                danmakuSettingsPanel.removeFromSuperview()
                self.danmakuSettingsPanel = nil
                return
            }

            let panel = DanmakuSettingsPanelView(settings: danmakuSettings, status: danmakuStatusText)
            panel.translatesAutoresizingMaskIntoConstraints = false
            panel.layer.zPosition = 350
            panel.onSettingsChanged = { [weak self] settings in
                self?.updateDanmakuSettings(settings)
            }
            panel.onSearch = { [weak self] in self?.openDanmakuSearch() }
            panel.onClose = { [weak self, weak panel] in
                panel?.removeFromSuperview()
                self?.danmakuSettingsPanel = nil
            }
            playerView.addSubview(panel)
            playerView.bringSubviewToFront(panel)
            NSLayoutConstraint.activate([
                panel.leadingAnchor.constraint(equalTo: playerView.leadingAnchor),
                panel.trailingAnchor.constraint(equalTo: playerView.trailingAnchor),
                panel.topAnchor.constraint(equalTo: playerView.topAnchor),
                panel.bottomAnchor.constraint(equalTo: playerView.bottomAnchor)
            ])
            danmakuSettingsPanel = panel
        }

        func installActionButtons(
            on view: IOSVideoPlayerView,
            canPlayPrevious: Bool,
            canPlayNext: Bool,
            canSelectEpisode: Bool
        ) {
            playerView = view
            view.titleLabel.textColor = .white
            updatePlayerTitle()
            configureButton(previousButton, imageName: "backward.end", label: "上一集", action: #selector(previousPressed), weight: .light)
            configureButton(rewindButton, imageName: "gobackward.15", label: "后退15秒", action: #selector(rewindPressed))
            configureButton(forwardButton, imageName: "goforward.15", label: "前进15秒", action: #selector(forwardPressed))
            configureButton(nextButton, imageName: "forward.end", label: "下一集", action: #selector(nextPressed), weight: .light)
            configureButton(verticalRewindButton, imageName: "gobackward.15", label: "后退15秒", action: #selector(rewindPressed))
            configureButton(verticalForwardButton, imageName: "goforward.15", label: "前进15秒", action: #selector(forwardPressed))
            configureButton(volumeButton, imageName: "speaker.wave.2", label: "音量", action: #selector(volumePressed), weight: .light)
            setVolumeButtonIcon(isMuted: view.volumeViewSlider.value <= 0.02)
            configureButton(episodeButton, imageName: "list.bullet", label: "选集", action: #selector(selectEpisodePressed))
            configureButton(aspectRatioButton, imageName: "aspectratio", label: "画面比例", action: #selector(aspectRatioPressed))
            aspectRatioButton.menu = makeAspectRatioMenu()
            aspectRatioButton.showsMenuAsPrimaryAction = true
            configureTextButton(danmakuButton, title: "弹幕", width: 40, label: "弹幕设置", action: #selector(danmakuPressed))
            configureMarkerButton(introButton, title: introLabel, label: "标记片头", action: #selector(markIntroPressed), resetAction: #selector(resetIntroPressed))
            configureMarkerButton(outroButton, title: outroLabel, label: "标记片尾", action: #selector(markOutroPressed), resetAction: #selector(resetOutroPressed))

            let padLayout = UIDevice.current.userInterfaceIdiom == .pad
            let buttonWidth = CGFloat(
                padLayout
                    ? PlaybackToolbarLayoutPolicy.padButtonWidth
                    : PlaybackToolbarLayoutPolicy.phoneButtonWidth
            )
            verticalSeekStack.axis = .vertical
            verticalSeekStack.alignment = .center
            verticalSeekStack.distribution = .fillEqually
            verticalSeekStack.spacing = 12
            verticalSeekStack.translatesAutoresizingMaskIntoConstraints = false
            verticalSeekStack.addArrangedSubview(verticalRewindButton)
            verticalSeekStack.addArrangedSubview(verticalForwardButton)
            if verticalSeekStack.superview !== view.controllerView {
                NSLayoutConstraint.deactivate(verticalSeekConstraints)
                view.controllerView.addSubview(verticalSeekStack)
                verticalSeekConstraints = [
                    verticalSeekStack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -14),
                    verticalSeekStack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                    verticalSeekStack.widthAnchor.constraint(equalToConstant: buttonWidth + 4),
                    verticalRewindButton.heightAnchor.constraint(equalToConstant: buttonWidth),
                    verticalForwardButton.heightAnchor.constraint(equalToConstant: buttonWidth)
                ]
                NSLayoutConstraint.activate(verticalSeekConstraints)
            }

            self.canPlayPrevious = canPlayPrevious
            self.canPlayNext = canPlayNext
            self.canSelectEpisode = canSelectEpisode
            let toolbar = view.toolBar
            let orderedViews: [UIView] = [
                rewindButton,
                toolbar.playButton,
                forwardButton,
                toolbar.timeLabel,
                previousButton,
                nextButton,
                volumeButton,
                toolbar.playbackRateButton,
                aspectRatioButton,
                episodeButton,
                danmakuButton,
                introButton,
                outroButton,
                view.landscapeButton
            ]
            let currentToolbarViews = toolbar.arrangedSubviews
            let needsToolbarSync = currentToolbarViews.count != orderedViews.count
                || !zip(currentToolbarViews, orderedViews).allSatisfy { pair in
                    pair.0 === pair.1
                }
            if needsToolbarSync {
                for arranged in toolbar.arrangedSubviews {
                    toolbar.removeArrangedSubview(arranged)
                    if !orderedViews.contains(where: { $0 === arranged }) {
                        arranged.removeFromSuperview()
                    }
                }
                for arranged in orderedViews {
                    toolbar.addArrangedSubview(arranged)
                }
            }
            // Keep every action in the toolbar; only the time label flexes.
            toolbar.axis = .horizontal
            toolbar.alignment = .center
            toolbar.distribution = .fill
            let toolbarSpacing = CGFloat(
                padLayout
                    ? PlaybackToolbarLayoutPolicy.padSpacing
                    : PlaybackToolbarLayoutPolicy.phoneSpacing
            )
            toolbar.spacing = toolbarSpacing
            toolbar.setCustomSpacing(toolbarSpacing, after: toolbar.playbackRateButton)
            toolbar.timeLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            toolbar.timeLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
            toolbar.timeLabel.lineBreakMode = .byClipping
            ensureWidthConstraint(toolbar.playButton, constant: buttonWidth, relation: .equal)
            ensureWidthConstraint(toolbar.playbackRateButton, constant: buttonWidth, relation: .equal)
            ensureWidthConstraint(view.landscapeButton, constant: buttonWidth, relation: .equal)
            for arranged in orderedViews where arranged !== toolbar.timeLabel {
                arranged.setContentCompressionResistancePriority(.required, for: .horizontal)
                arranged.setContentHuggingPriority(.required, for: .horizontal)
            }
            toolbar.playButton.isEnabled = !isResolvingPlayback
            updateActionButtons(
                canPlayPrevious: canPlayPrevious,
                canPlayNext: canPlayNext,
                canSelectEpisode: canSelectEpisode
            )
            refreshToolbarLayout()
            updateControlVisibility(isVisible: view.isMaskShow)
        }

        func updateActionButtons(canPlayPrevious: Bool, canPlayNext: Bool, canSelectEpisode: Bool) {
            self.canPlayPrevious = canPlayPrevious
            self.canPlayNext = canPlayNext
            self.canSelectEpisode = canSelectEpisode
            updateActionButtonsLayout(isLandscape: isLandscape)
        }

        func updateMarkerLabels(intro: String, outro: String) {
            introLabel = intro
            outroLabel = outro
            introButton.setTitle(intro, for: .normal)
            outroButton.setTitle(outro, for: .normal)
        }

        func updateActionButtonsLayout(isLandscape: Bool) {
            self.isLandscape = isLandscape
            updatePlayerTitle()
            // 剧集导航只在横屏显示；横屏固定占位，避免集数变化时控制栏横向跳动。
            previousButton.isHidden = !isLandscape
            nextButton.isHidden = !isLandscape
            previousButton.isEnabled = isLandscape && canPlayPrevious
            nextButton.isEnabled = isLandscape && canPlayNext
            previousButton.alpha = canPlayPrevious ? 1 : 0.45
            nextButton.alpha = canPlayNext ? 1 : 0.45
            episodeButton.isHidden = !isLandscape || !canSelectEpisode
            aspectRatioButton.isHidden = !isLandscape
            rewindButton.isHidden = !isLandscape
            forwardButton.isHidden = !isLandscape
            verticalSeekStack.isHidden = isLandscape
            danmakuButton.isHidden = !isLandscape
            updateDanmakuButton()
            aspectRatioButton.menu = makeAspectRatioMenu()
            (playerView as? CongcongKSVideoPlayerView)?.applyDisplayAspectRatio(
                selectedAspectRatio,
                isFullscreenLandscape: isLandscape
            )
            if let playerView {
                updateDanmakuLayout(in: playerView)
            }
            refreshToolbarLayout()
            applyControlVisibility()
        }

        func refreshToolbarLayout() {
            guard let playerView else { return }
            let toolbar = playerView.toolBar
            let availableWidth = Double(toolbar.bounds.width)
            guard availableWidth.isFinite, availableWidth > 0 else { return }

            let isPad = UIDevice.current.userInterfaceIdiom == .pad
            let spacing = CGFloat(
                isPad
                    ? PlaybackToolbarLayoutPolicy.padSpacing
                    : PlaybackToolbarLayoutPolicy.phoneSpacing
            )
            if abs(toolbar.spacing - spacing) > 0.1 {
                toolbar.spacing = spacing
            }
            if abs(toolbar.customSpacing(after: toolbar.playbackRateButton) - spacing) > 0.1 {
                toolbar.setCustomSpacing(spacing, after: toolbar.playbackRateButton)
            }

            let visibleControls = desiredToolbarControls(for: playerView)
            let widths = Dictionary(uniqueKeysWithValues: visibleControls.map { control in
                (control, toolbarWidth(for: control, in: playerView))
            })
            let decision = PlaybackToolbarLayoutPolicy.layout(
                availableWidth: availableWidth,
                controls: visibleControls,
                widths: widths,
                spacing: Double(spacing)
            )
            updateFittedTimeLabelWidth(
                decision.timeLabelWidth,
                intrinsicWidth: toolbar.timeLabel.intrinsicContentSize.width
            )
        }

        private func desiredToolbarControls(
            for playerView: IOSVideoPlayerView
        ) -> [PlaybackToolbarControl] {
            var controls: [PlaybackToolbarControl] = []
            if isLandscape { controls.append(.rewind) }
            controls.append(.play)
            if isLandscape { controls.append(.forward) }
            controls.append(.timeLabel)
            if isLandscape {
                controls.append(contentsOf: [.previous, .next])
            }
            controls.append(contentsOf: [.volume, .speed])
            if isLandscape {
                controls.append(.aspectRatio)
                if canSelectEpisode { controls.append(.episode) }
                controls.append(.danmaku)
            }
            controls.append(contentsOf: [.intro, .outro])
            controls.append(.fullscreen)
            return controls
        }

        private func toolbarWidth(
            for control: PlaybackToolbarControl,
            in playerView: IOSVideoPlayerView
        ) -> Double {
            switch control {
            case .rewind: return fixedWidth(of: rewindButton)
            case .play: return fixedWidth(of: playerView.toolBar.playButton)
            case .forward: return fixedWidth(of: forwardButton)
            case .timeLabel: return Double(playerView.toolBar.timeLabel.intrinsicContentSize.width)
            case .previous: return fixedWidth(of: previousButton)
            case .next: return fixedWidth(of: nextButton)
            case .volume: return fixedWidth(of: volumeButton)
            case .speed: return fixedWidth(of: playerView.toolBar.playbackRateButton)
            case .aspectRatio: return fixedWidth(of: aspectRatioButton)
            case .episode: return fixedWidth(of: episodeButton)
            case .danmaku: return fixedWidth(of: danmakuButton)
            case .intro: return fixedWidth(of: introButton)
            case .outro: return fixedWidth(of: outroButton)
            case .fullscreen: return fixedWidth(of: playerView.landscapeButton)
            }
        }

        private func fixedWidth(of view: UIView) -> Double {
            let constraintWidth = equalWidthConstraint(for: view)?.constant ?? 0
            let measuredWidth = max(constraintWidth, view.intrinsicContentSize.width)
            return Double(max(0, measuredWidth))
        }

        private func updateFittedTimeLabelWidth(_ width: Double, intrinsicWidth: CGFloat) {
            guard let timeLabel = playerView?.toolBar.timeLabel else { return }
            let targetWidth = CGFloat(width)
            let needsFixedWidth = targetWidth + 0.5 < intrinsicWidth
            if needsFixedWidth {
                if let fittedTimeLabelWidthConstraint {
                    if abs(fittedTimeLabelWidthConstraint.constant - targetWidth) > 0.5 {
                        fittedTimeLabelWidthConstraint.constant = targetWidth
                    }
                } else {
                    let constraint = timeLabel.widthAnchor.constraint(equalToConstant: targetWidth)
                    constraint.priority = .required
                    constraint.isActive = true
                    fittedTimeLabelWidthConstraint = constraint
                }
            } else if let fittedTimeLabelWidthConstraint {
                fittedTimeLabelWidthConstraint.isActive = false
                self.fittedTimeLabelWidthConstraint = nil
            }
        }

        private func applyToolbarButtonVisibility() {
            rewindButton.isHidden = !controlsVisible || !isLandscape
            forwardButton.isHidden = !controlsVisible || !isLandscape
            previousButton.isHidden = !controlsVisible || !isLandscape
            nextButton.isHidden = !controlsVisible || !isLandscape
            volumeButton.isHidden = !controlsVisible
            playerView?.toolBar.playbackRateButton.isHidden = !controlsVisible
            aspectRatioButton.isHidden = !controlsVisible || !isLandscape
            episodeButton.isHidden = !controlsVisible || !isLandscape || !canSelectEpisode
            danmakuButton.isHidden = !controlsVisible || !isLandscape
            introButton.isHidden = !controlsVisible
            outroButton.isHidden = !controlsVisible
            playerView?.landscapeButton.isHidden = !controlsVisible
        }

        func updateControlVisibility(isVisible: Bool) {
            controlsVisible = isVisible
            applyControlVisibility()
        }

        private var controlsVisible = true
        private var isResolvingPlayback = false

        func setPlaybackResolving(_ isResolving: Bool) {
            isResolvingPlayback = isResolving
            playerView?.toolBar.playButton.isEnabled = !isResolving
            // A URL replacement can report paused before autoplay begins.
            // Hide the transient play triangle until this item starts or errors.
            applyControlVisibility()
        }

        private func applyControlVisibility() {
            let alpha: CGFloat = controlsVisible ? 1 : 0
            applyToolbarButtonVisibility()
            UIView.animate(withDuration: 0.2) {
                self.verticalSeekStack.alpha = self.controlsVisible && !self.isLandscape ? 1 : 0
                self.playerView?.routeButton.alpha = alpha
                self.playerView?.routeButton.isHidden = !self.controlsVisible
                let canShowPlaybackControl = (self.playerView as? CongcongKSVideoPlayerView)?
                    .canShowPlayerControls == true
                self.playerView?.toolBar.playButton.alpha = self.controlsVisible
                    && !self.isResolvingPlayback
                    && canShowPlaybackControl ? 1 : 0
                self.playerView?.toolBar.playbackRateButton.alpha = alpha
                self.introButton.alpha = alpha
                self.outroButton.alpha = alpha
                self.danmakuButton.alpha = alpha
                self.aspectRatioButton.alpha = alpha
            }
        }

        private func configureButton(
            _ button: UIButton,
            imageName: String,
            label: String,
            action: Selector,
            weight: UIImage.SymbolWeight = .regular
        ) {
            let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 16, weight: weight)
            button.setImage(UIImage(systemName: imageName, withConfiguration: symbolConfiguration), for: .normal)
            button.tintColor = .white
            button.accessibilityLabel = label
            button.translatesAutoresizingMaskIntoConstraints = false
            let isPad = UIDevice.current.userInterfaceIdiom == .pad
            ensureWidthConstraint(
                button,
                constant: CGFloat(
                    isPad
                        ? PlaybackToolbarLayoutPolicy.padButtonWidth
                        : PlaybackToolbarLayoutPolicy.phoneButtonWidth
                ),
                relation: .equal
            )
            button.backgroundColor = .clear
            button.layer.backgroundColor = UIColor.clear.cgColor
            button.layer.shadowColor = UIColor.clear.cgColor
            button.layer.shadowOpacity = 0
            button.layer.shadowRadius = 0
            button.layer.shadowOffset = .zero
            button.layer.cornerRadius = 0
            button.clipsToBounds = false
            button.removeTarget(self, action: action, for: .primaryActionTriggered)
            button.addTarget(self, action: action, for: .primaryActionTriggered)
        }

        private func configureTextButton(
            _ button: UIButton,
            title: String,
            width: CGFloat,
            label: String,
            action: Selector
        ) {
            button.setImage(nil, for: .normal)
            button.setTitle(title, for: .normal)
            button.setTitleColor(.white, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
            button.accessibilityLabel = label
            button.translatesAutoresizingMaskIntoConstraints = false
            let minimumTargetWidth = CGFloat(
                UIDevice.current.userInterfaceIdiom == .pad
                    ? PlaybackToolbarLayoutPolicy.padButtonWidth
                    : PlaybackToolbarLayoutPolicy.phoneButtonWidth
            )
            let resolvedWidth = max(width, minimumTargetWidth)
            ensureWidthConstraint(button, constant: resolvedWidth, relation: .equal)
            button.backgroundColor = .clear
            button.layer.backgroundColor = UIColor.clear.cgColor
            button.layer.shadowColor = UIColor.clear.cgColor
            button.layer.shadowOpacity = 0
            button.layer.shadowRadius = 0
            button.layer.shadowOffset = .zero
            button.layer.cornerRadius = 0
            button.clipsToBounds = false
            button.removeTarget(self, action: action, for: .primaryActionTriggered)
            button.addTarget(self, action: action, for: .primaryActionTriggered)
        }

        private func configureMarkerButton(_ button: UIButton, title: String, label: String, action: Selector, resetAction: Selector) {
            button.setTitle(title, for: .normal)
            button.setTitleColor(.white, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
            button.titleLabel?.adjustsFontSizeToFitWidth = true
            button.titleLabel?.minimumScaleFactor = 0.7
            button.titleLabel?.lineBreakMode = .byClipping
            button.accessibilityLabel = label
            button.accessibilityHint = "轻点设置当前时间，长按清除标记"
            button.translatesAutoresizingMaskIntoConstraints = false
            ensureWidthConstraint(
                button,
                constant: UIDevice.current.userInterfaceIdiom == .pad ? 64 : 58,
                relation: .equal
            )
            button.backgroundColor = .clear
            button.layer.backgroundColor = UIColor.clear.cgColor
            button.layer.shadowColor = UIColor.clear.cgColor
            button.layer.shadowOpacity = 0
            button.layer.shadowRadius = 0
            button.layer.shadowOffset = .zero
            button.layer.cornerRadius = 0
            button.clipsToBounds = false
            button.removeTarget(self, action: action, for: .primaryActionTriggered)
            button.addTarget(self, action: action, for: .primaryActionTriggered)
            for gesture in button.gestureRecognizers ?? [] where gesture is UILongPressGestureRecognizer {
                button.removeGestureRecognizer(gesture)
            }
            let longPress = UILongPressGestureRecognizer(target: self, action: resetAction)
            longPress.minimumPressDuration = 0.65
            button.addGestureRecognizer(longPress)
        }

        private func equalWidthConstraint(for view: UIView) -> NSLayoutConstraint? {
            var currentView: UIView? = view
            while let ancestor = currentView {
                if let constraint = ancestor.constraints.first(where: {
                    ($0.firstItem as? UIView) === view
                        && $0.firstAttribute == .width
                        && $0.relation == .equal
                        && $0.secondItem == nil
                }) {
                    return constraint
                }
                currentView = ancestor.superview
            }
            return nil
        }

        private func ensureWidthConstraint(
            _ view: UIView,
            constant: CGFloat,
            relation: NSLayoutConstraint.Relation
        ) {
            if let existing = equalWidthConstraint(for: view).flatMap({ existing in
                existing.relation == relation ? existing : nil
            }) {
                existing.constant = constant
                return
            }
            if let existing = view.constraints.first(where: {
                ($0.firstItem as? UIView) === view
                    && $0.firstAttribute == .width
                    && $0.relation == relation
                    && $0.secondItem == nil
            }) {
                existing.constant = constant
                return
            }
            let constraint = relation == .equal
                ? view.widthAnchor.constraint(equalToConstant: constant)
                : view.widthAnchor.constraint(greaterThanOrEqualToConstant: constant)
            constraint.isActive = true
        }

        @objc private func previousPressed() {
            guard canPlayPrevious else { return }
            onPlayPrevious?()
        }

        @objc private func rewindPressed() {
            guard let playerView, playerView.toolBar.isSeekable else { return }
            let target = max(0, playerView.toolBar.currentTime - 15)
            playerView.seek(time: target) { _ in }
        }

        @objc private func forwardPressed() {
            guard let playerView, playerView.toolBar.isSeekable else { return }
            let target = min(
                playerView.toolBar.totalTime,
                playerView.toolBar.currentTime + 15
            )
            playerView.seek(time: target) { _ in }
        }

        @objc private func nextPressed() {
            guard canPlayNext else { return }
            onPlayNext?()
        }

        @objc private func selectEpisodePressed() {
            onSelectEpisode?()
        }

        @objc private func aspectRatioPressed() {}

        private func makeAspectRatioMenu() -> UIMenu {
            UIMenu(title: "画面比例", children: PlaybackAspectRatio.allCases.map { ratio in
                UIAction(
                    title: ratio.rawValue,
                    state: ratio == selectedAspectRatio ? .on : .off
                ) { [weak self] _ in
                    self?.selectAspectRatio(ratio)
                }
            })
        }

        private func selectAspectRatio(_ ratio: PlaybackAspectRatio) {
            selectedAspectRatio = ratio
            aspectRatioButton.menu = makeAspectRatioMenu()
            (playerView as? CongcongKSVideoPlayerView)?.applyDisplayAspectRatio(
                ratio,
                isFullscreenLandscape: isLandscape
            )
            if let playerView {
                updateDanmakuLayout(in: playerView)
            }
        }

        @objc private func markIntroPressed() {
            onMarkIntro?()
        }

        @objc private func markOutroPressed() {
            onMarkOutro?()
        }

        @objc private func resetIntroPressed(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began else { return }
            onResetIntro?()
        }

        @objc private func resetOutroPressed(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began else { return }
            onResetOutro?()
        }

        @objc private func volumePressed() {
            guard let playerView else { return }
            let slider = playerView.volumeViewSlider
            let newVolume = volumeButtonState.toggle(currentVolume: slider.value)
            slider.setValue(newVolume, animated: false)
            setVolumeButtonIcon(isMuted: newVolume <= 0.02)
            slider.sendActions(for: .valueChanged)
        }

        private func setVolumeButtonIcon(isMuted: Bool) {
            let symbol = isMuted ? "speaker.slash" : "speaker.wave.2"
            let configuration = UIImage.SymbolConfiguration(pointSize: 16, weight: .light)
            volumeButton.setImage(UIImage(systemName: symbol, withConfiguration: configuration), for: .normal)
        }

        func playerController(state _: KSPlayerState) {
            updateDanmakuPlaybackActivity()
        }

        func playerController(currentTime: TimeInterval, totalTime: TimeInterval) {
            updatePlaybackTimeline(currentTime: currentTime, duration: totalTime)
        }

        func updatePlaybackTimeline(currentTime: TimeInterval, duration: TimeInterval) {
            let updatedDanmaku = updateDanmakuTime(currentTime: currentTime, duration: duration)
            let reportedTime = updatedDanmaku ? currentTime : estimatedPostSeekTime() ?? currentTime
            onProgressChanged?(reportedTime, duration > 0 ? duration : nil)
        }

        func playerController(finish error: Error?) {
            danmakuView?.reset()
            guard error == nil else {
                DispatchQueue.main.async { [weak self] in
                    self?.reportPlaybackFailure()
                }
                return
            }
            DispatchQueue.main.async { [weak self] in
                self?.onPlaybackEnded?()
            }
        }

        func resetPlaybackFailure() {
            didReportPlaybackFailure = false
        }

        func reportPlaybackFailure() {
            guard !didReportPlaybackFailure else { return }
            didReportPlaybackFailure = true
            onPlaybackFailed?()
        }

        func playerController(maskShow: Bool) {
            updateControlVisibility(isVisible: maskShow)
        }

        func playerController(action: PlayerButtonType) {
            // KSPlayer already performs the native action. Forward it after
            // that handling so the host can observe back/rate/PiP actions.
            onPlayerAction?(action)
        }

        func playerController(bufferedCount _: Int, consumeTime _: TimeInterval) {}

        func playerController(seek time: TimeInterval) {
            updateDanmakuTime(
                currentTime: time,
                duration: lastPlayerDuration,
                isSeek: true
            )
        }

        @discardableResult
        func updateDanmakuTime(
            currentTime: TimeInterval,
            duration: TimeInterval,
            isSeek: Bool = false
        ) -> Bool {
            let boundedTime = max(0, currentTime.isFinite ? currentTime : 0)
            let boundedDuration = max(0, duration.isFinite ? duration : 0)
            if isSeek {
                pendingDanmakuSeek = PendingDanmakuSeek(
                    target: boundedTime,
                    startedAt: ProcessInfo.processInfo.systemUptime
                )
            } else if shouldIgnoreStaleTimeAfterSeek(boundedTime) {
                if boundedDuration > 0 { lastPlayerDuration = boundedDuration }
                return false
            }

            lastPlayerTime = boundedTime
            lastPlayerDuration = boundedDuration
            updateDanmakuPlaybackActivity()
            danmakuView?.update(
                currentTime: lastPlayerTime,
                duration: lastPlayerDuration,
                playbackRate: currentPlaybackRate,
                forceTimelineSync: isSeek
            )
            return true
        }

        private func shouldIgnoreStaleTimeAfterSeek(_ currentTime: TimeInterval) -> Bool {
            guard let pendingDanmakuSeek else { return false }
            let elapsed = max(0, ProcessInfo.processInfo.systemUptime - pendingDanmakuSeek.startedAt)
            guard elapsed < 2.5 else {
                self.pendingDanmakuSeek = nil
                return false
            }

            let expectedTime = pendingDanmakuSeek.target
                + elapsed * DanmakuTimelinePolicy.playbackRate(currentPlaybackRate)
            let matchesTarget = abs(currentTime - pendingDanmakuSeek.target) <= 1.25
            let matchesRunningTimeline = abs(currentTime - expectedTime) <= 1.25
            guard matchesTarget || matchesRunningTimeline else { return true }
            self.pendingDanmakuSeek = nil
            return false
        }

        private func estimatedPostSeekTime() -> TimeInterval? {
            guard let pendingDanmakuSeek else { return nil }
            let elapsed = max(0, ProcessInfo.processInfo.systemUptime - pendingDanmakuSeek.startedAt)
            return pendingDanmakuSeek.target
                + elapsed * DanmakuTimelinePolicy.playbackRate(currentPlaybackRate)
        }

        private func updateDanmakuPlaybackActivity() {
            danmakuView?.setPlaybackActive(
                DanmakuTimelinePolicy.isPlaybackActive(
                    isPlaying: playerView?.playerLayer?.player.isPlaying ?? false
                )
            )
        }

        private var currentPlaybackRate: Double {
            Double(playerView?.playerLayer?.player.playbackRate ?? 1)
        }
    }
}
#else
struct KSPlayerVodPlayerView: View {
    let urlString: String
    var startPosition: Double = 0
    var onProgressChanged: ((Double, Double?) -> Void)? = nil
    var onPlaybackEnded: (() -> Void)? = nil

    var body: some View {
        Text("KSPlayer 仅支持 iOS 播放")
    }
}
#endif
