import AppKit

/// 刘海顶部光晕窗口：全穿透、不截图、非全屏空间
final class GlowWindow {
    private var panel: NSPanel?
    private var metalView: GlowMetalView?
    private var currentScreen: NSScreen?
    private var headroomTimer: Timer?
    private var pendingLevel: LoadLevel?

    // MARK: - 生命周期

    func start() {
        reposition()
        startHeadroomPolling()
        observeScreenChanges()
    }

    func shutdown() {
        headroomTimer?.invalidate()
        metalView?.sleep()
        panel?.orderOut(nil)
    }

    // MARK: - 对外

    func setLevel(_ level: LoadLevel) {
        pendingLevel = level
        metalView?.renderer?.targetLevel = level
        metalView?.wake()
    }

    func setPaused(_ paused: Bool) {
        if let r = metalView?.renderer { r.paused = paused }
        if paused {
            metalView?.sleep()
        } else {
            metalView?.wake()
        }
    }

    // MARK: - 布局

    func reposition() {
        guard let screen = NotchedScreenFinder.find(),
              let notch = NotchedScreenFinder.notchRect(of: screen) else {
            panel?.orderOut(nil)
            return
        }
        currentScreen = screen

        // 光晕整体等比缩放：窗口（限制框）与 shader 椭圆同步缩放
        let scale = CGFloat(AppSettings.shared.glowScale)
        let width = 720.0 * scale
        let height = 210.0 * scale
        let frame = CGRect(
            x: notch.midX - width / 2,
            y: screen.frame.maxY - height,   // 贴屏幕顶端（窗口坐标原点左下）
            width: width,
            height: height)

        let isNewPanel = (panel == nil)
        if let panel {
            // 帧未变化时跳过 setFrame，避免渲染中无谓的层变更
            if panel.frame != frame {
                panel.setFrame(frame, display: true)
            }
        } else {
            let p = NSPanel(
                contentRect: frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false
            p.ignoresMouseEvents = true
            p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
            p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            p.sharingType = .none          // 不出现在截图/录屏
            p.isMovable = false

            let view = GlowMetalView(frame: NSRect(origin: .zero, size: frame.size))
            view.autoresizingMask = [.width, .height]
            p.contentView = view
            metalView = view
            panel = p
        }

        metalView?.setup(screen: screen, notchRectGlobal: notch)
        // 应用 pending 档位（renderer 可能刚创建）
        if let lvl = pendingLevel {
            metalView?.renderer?.targetLevel = lvl
        }

        // EDR/HDR 配置（仅窗口创建时一次）
        if isNewPanel, let metalLayer = metalView?.layer as? CAMetalLayer {
            metalLayer.wantsExtendedDynamicRangeContent = true
            metalLayer.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
            updateHeadroom(screen: screen)
        }

        metalView?.wake()
        panel?.orderFrontRegardless()
    }

    private func updateHeadroom(screen: NSScreen) {
        let h = screen.maximumExtendedDynamicRangeColorComponentValue
        metalView?.renderer?.headroom = Float(max(1.0, h))
    }

    private func startHeadroomPolling() {
        headroomTimer?.invalidate()
        headroomTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            if let s = self?.currentScreen {
                self?.updateHeadroom(screen: s)
            }
        }
    }

    private func observeScreenChanges() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
            self?.reposition()
        }
    }
}
