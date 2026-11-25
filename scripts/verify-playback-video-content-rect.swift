import Foundation

@main
struct VerifyPlaybackVideoContentRect {
    static func main() {
        let ultraWideFit = PlaybackVideoContentRectPolicy.videoRect(
            in: CGSize(width: 1140, height: 642),
            videoSize: CGSize(width: 2560, height: 968),
            contentMode: .aspectFit
        )
        expect(ultraWideFit.minY, 105.375, "letterboxed ultra-wide top edge")
        expect(ultraWideFit.height, 431.25, "letterboxed ultra-wide height")
        expect(ultraWideFit.maxX, 1140, "letterboxed ultra-wide right edge")

        let portraitFit = PlaybackVideoContentRectPolicy.videoRect(
            in: CGSize(width: 390, height: 844),
            videoSize: CGSize(width: 1920, height: 1080),
            contentMode: .aspectFit
        )
        expect(portraitFit.minY, 312.3125, "portrait video top edge")
        expect(portraitFit.width, 390, "portrait video width")

        let viewport = CGRect(x: 0, y: 0, width: 1140, height: 642)
        for mode in [PlaybackVideoContentMode.aspectFill, .stretch] {
            let rect = PlaybackVideoContentRectPolicy.videoRect(
                in: viewport.size,
                videoSize: CGSize(width: 2560, height: 968),
                contentMode: mode
            )
            expect(rect.minY, viewport.minY, "\(mode) top edge")
            expect(rect.maxX, viewport.maxX, "\(mode) right edge")
            expect(rect.height, viewport.height, "\(mode) height")
        }

        let unknownSize = PlaybackVideoContentRectPolicy.videoRect(
            in: viewport.size,
            videoSize: .zero,
            contentMode: .aspectFit
        )
        expect(unknownSize, viewport, "unknown video size falls back to viewport")

        let markFrame = PlaybackVideoContentRectPolicy.watermarkFrame(
            in: ultraWideFit,
            labelSize: CGSize(width: 100, height: 20),
            inset: 14
        )
        guard let markFrame else {
            fatalError("Expected watermark placement for valid video content")
        }
        expect(markFrame.maxX, ultraWideFit.maxX - 14, "watermark follows video right edge")
        expect(markFrame.minY, ultraWideFit.minY + 14, "watermark follows video top edge")

        print("PLAYBACK VIDEO CONTENT RECT CHECKS PASSED")
    }

    private static func expect(_ actual: CGFloat, _ expected: CGFloat, _ name: String) {
        guard abs(actual - expected) < 0.01 else {
            fatalError("\(name): expected \(expected), got \(actual)")
        }
    }

    private static func expect(_ actual: CGRect, _ expected: CGRect, _ name: String) {
        guard abs(actual.minX - expected.minX) < 0.01,
              abs(actual.minY - expected.minY) < 0.01,
              abs(actual.width - expected.width) < 0.01,
              abs(actual.height - expected.height) < 0.01 else {
            fatalError("\(name): expected \(expected), got \(actual)")
        }
    }
}
