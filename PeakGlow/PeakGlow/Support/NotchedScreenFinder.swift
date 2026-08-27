import AppKit

enum NotchedScreenFinder {
    /// 找到带刘海的内建屏幕（auxiliaryTopLeftArea 仅刘海屏非 nil）
    static func find() -> NSScreen? {
        NSScreen.screens.first { $0.auxiliaryTopLeftArea != nil }
    }

    /// 刘海精确矩形（全局 AppKit 坐标，屏幕坐标系原点在左下）
    static func notchRect(of screen: NSScreen) -> CGRect? {
        guard let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea else { return nil }
        return CGRect(
            x: left.maxX,
            y: left.minY,
            width: right.minX - left.maxX,
            height: left.height)
    }

    /// 刘海中心 x（全局坐标）
    static func notchCenterX(of screen: NSScreen) -> CGFloat? {
        notchRect(of: screen)?.midX
    }
}
