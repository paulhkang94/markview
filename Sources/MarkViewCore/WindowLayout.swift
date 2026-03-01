import CoreGraphics

/// Shared window layout constants and sizing math.
/// Centralizes magic numbers used by MarkViewApp, ContentView, and tests.
public enum WindowLayout {
    public static let previewWidthFraction: CGFloat = 0.55
    public static let editorWidthFraction: CGFloat = 0.80
    public static let previewMinWidth: CGFloat = 800
    public static let editorMinWidth: CGFloat = 900
    public static let minHeight: CGFloat = 600

    /// Default window size on launch, based on the main screen's visible frame.
    public static func defaultWindowSize(for visibleFrame: CGRect?) -> CGSize {
        guard let frame = visibleFrame else {
            return CGSize(width: 900, height: 800)
        }
        return CGSize(
            width: max(frame.width * previewWidthFraction, previewMinWidth),
            height: max(frame.height * 0.85, minHeight)
        )
    }

    /// Target width when toggling editor visibility.
    public static func width(showEditor: Bool, in visibleFrame: CGRect) -> CGFloat {
        let fraction = showEditor ? editorWidthFraction : previewWidthFraction
        let minWidth = showEditor ? editorMinWidth : previewMinWidth
        return max(visibleFrame.width * fraction, minWidth)
    }

    /// Centered frame after a width change, preserving Y origin and height.
    public static func resizedFrame(currentFrame: CGRect, visibleFrame: CGRect, showEditor: Bool) -> CGRect {
        let newWidth = width(showEditor: showEditor, in: visibleFrame)
        let newX = visibleFrame.origin.x + (visibleFrame.width - newWidth) / 2
        return CGRect(x: newX, y: currentFrame.origin.y, width: newWidth, height: currentFrame.height)
    }
}
