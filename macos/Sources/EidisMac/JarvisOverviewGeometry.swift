import CoreGraphics

/// Shared geometry for the center slot and its independent video surface.
enum JarvisOverviewGeometry {
    static func centerWidth(innerWidth: CGFloat, height: CGFloat) -> CGFloat {
        min(innerWidth * 0.30, height * 0.58)
    }
    static func coreFrame(width: CGFloat, height: CGFloat) -> CGRect {
        let outer = min(32, max(12, width * 0.015))
        let gap: CGFloat = width < 1120 ? 10 : 16
        let innerWidth = max(0,width - 2 * outer)
        let center = centerWidth(innerWidth: innerWidth,height:height)
        let left = max(0,(innerWidth - center - 2 * gap) * 0.5)
        let columnHeight = max(0,height - 116 - 12 - 52 - 66 - 2 * gap)
        let slot = columnHeight * 0.64
        let size = max(0,min(center - 12,slot - 12))
        return CGRect(x: outer + left + gap + (center - size)/2,
                      y: 12 + 52 + 66 + 2 * gap + (slot - size)/2,
                      width:size,height:size)
    }
}
