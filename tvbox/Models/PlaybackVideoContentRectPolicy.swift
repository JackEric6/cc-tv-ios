import CoreGraphics

enum PlaybackVideoContentMode: Equatable {
    case aspectFit
    case aspectFill
    case stretch
    case center
}

enum PlaybackVideoContentRectPolicy {
    static func videoRect(
        in containerSize: CGSize,
        videoSize: CGSize,
        contentMode: PlaybackVideoContentMode
    ) -> CGRect {
        let bounds = CGRect(origin: .zero, size: sanitizedSize(containerSize))
        guard bounds.width > 0, bounds.height > 0 else { return .zero }

        let sourceSize = sanitizedSize(videoSize)
        guard sourceSize.width > 0, sourceSize.height > 0 else { return bounds }

        switch contentMode {
        case .aspectFill, .stretch:
            return bounds
        case .aspectFit:
            let scale = min(
                bounds.width / sourceSize.width,
                bounds.height / sourceSize.height
            )
            let size = CGSize(
                width: sourceSize.width * scale,
                height: sourceSize.height * scale
            )
            return CGRect(
                x: bounds.midX - size.width / 2,
                y: bounds.midY - size.height / 2,
                width: size.width,
                height: size.height
            )
        case .center:
            let size = CGSize(
                width: min(sourceSize.width, bounds.width),
                height: min(sourceSize.height, bounds.height)
            )
            return CGRect(
                x: bounds.midX - size.width / 2,
                y: bounds.midY - size.height / 2,
                width: size.width,
                height: size.height
            )
        }
    }

    static func watermarkFrame(
        in videoRect: CGRect,
        labelSize: CGSize,
        inset: CGFloat
    ) -> CGRect? {
        let size = sanitizedSize(labelSize)
        let safeInset = max(0, inset.isFinite ? inset : 0)
        guard videoRect.width > 0,
              videoRect.height > 0,
              size.width > 0,
              size.height > 0,
              videoRect.width >= size.width + safeInset * 2,
              videoRect.height >= size.height + safeInset * 2 else {
            return nil
        }

        return CGRect(
            x: videoRect.maxX - safeInset - size.width,
            y: videoRect.minY + safeInset,
            width: size.width,
            height: size.height
        )
    }

    private static func sanitizedSize(_ size: CGSize) -> CGSize {
        CGSize(
            width: size.width.isFinite ? max(0, size.width) : 0,
            height: size.height.isFinite ? max(0, size.height) : 0
        )
    }
}
