import AppKit
import SwiftUI

/// 刘海气泡菜单（Dynamic Island 风格）
final class BubblePanelController: NSObject {
    private var panel: NSPanel?
    private let hover: NotchHoverController
    /// 代数令牌：防止旧隐藏动画的 completion 关掉新弹出的气泡
    private var generation = 0

    init(hover: NotchHoverController) {
        self.hover = hover
        super.init()
        hover.onShowBubble = { [weak self] in self?.show() }
        hover.onHideBubble = { [weak self] in self?.hide() }
        hover.bubbleFrameProvider = { [weak self] in self?.panel?.frame }
    }

    private func makePanel(notch: CGRect) -> NSPanel {
        let size = CGSize(width: 320, height: 210)
        let frame = CGRect(
            x: notch.midX - size.width / 2,
            y: notch.minY - size.height - 8,
            width: size.width,
            height: size.height)

        let p = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 2)
        p.collectionBehavior = [.moveToActiveSpace, .ignoresCycle]
        p.isMovable = false
        p.hidesOnDeactivate = false
        p.acceptsMouseMovedEvents = true

        let view = BubbleContentView(onClose: { [weak self] in
            self?.hover.dismissNow()
        }).environmentObject(AppState.shared)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)
        p.contentView = hosting
        return p
    }

    func show() {
        guard let screen = NotchedScreenFinder.find(),
              let notch = NotchedScreenFinder.notchRect(of: screen) else { return }

        generation += 1
        let p: NSPanel
        if let panel {
            p = panel
        } else {
            p = makePanel(notch: notch)
            panel = p
        }
        p.setFrameOrigin(CGPoint(x: notch.midX - p.frame.width / 2,
                                 y: notch.minY - p.frame.height - 8))
        p.alphaValue = 1
        AppState.shared.bubbleVisible = true
        p.orderFrontRegardless()
    }

    func hide() {
        let gen = generation
        guard let panel else { return }
        AppState.shared.bubbleVisible = false
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, gen == self.generation else { return }
            panel.orderOut(nil)
            panel.alphaValue = 1
        })
    }
}
