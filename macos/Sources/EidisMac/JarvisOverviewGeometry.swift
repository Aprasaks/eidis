import CoreGraphics

/// Shared geometry for the center slot and its independent video surface.
enum JarvisOverviewGeometry {
    static func centerWidth(innerWidth: CGFloat, height: CGFloat) -> CGFloat {
        min(innerWidth * 0.25, height * 0.47)
    }
    static func coreFrame(width: CGFloat, height: CGFloat) -> CGRect {
        let outer = min(32, max(12, width * 0.015))
        let gap: CGFloat = width < 1120 ? 10 : 16
        let innerWidth = max(0,width - 2 * outer)
        let center = centerWidth(innerWidth: innerWidth,height:height)
        let left = max(0,(innerWidth - center - 2 * gap) * 0.5)
        // Match the workroom's minimal close-only 28pt top row. Keep the
        // original video in the center and leave its bottom for live dialogue.
        let columnTop: CGFloat = 10 + 28
        let columnHeight = max(0, height - columnTop - 14)
        let size = max(0, min(center * 0.74, columnHeight * 0.40))
        return CGRect(x: outer + left + gap + (center - size) / 2,
                      y: columnTop + (columnHeight - size) * 0.42,
                      width: size, height: size)
    }
}
