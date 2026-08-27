import AppKit
import Metal
import QuartzCore

/// CAMetalLayer 宿主视图：主线程 Timer 驱动渲染（common mode，空闲自动停止）
final class GlowMetalView: NSView {
    override var wantsUpdateLayer: Bool { true }
    private(set) var renderer: GlowRenderer?
    private var renderTimer: Timer?
    private var timerHz: Double = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func makeBackingLayer() -> CALayer {
        let layer = CAMetalLayer()
        layer.pixelFormat = .rgba16Float
        layer.framebufferOnly = true
        layer.isOpaque = false
        layer.backgroundColor = NSColor.clear.cgColor
        return layer
    }

    func setup(screen: NSScreen, notchRectGlobal: CGRect) {
        guard let metalLayer = layer as? CAMetalLayer else { return }
        metalLayer.contentsScale = screen.backingScaleFactor
        // 显式同步 bounds（AppKit 可能不替我们更新自定义 backing layer）
        if metalLayer.bounds != bounds {
            metalLayer.bounds = bounds
        }
        if renderer == nil {
            renderer = GlowRenderer(layer: metalLayer)
        }
        updateDrawableSize()
        updateNotchCenter(notchRectGlobal: notchRectGlobal)
    }

    /// macOS 的 CAMetalLayer.drawableSize 不随 bounds 自动更新，必须手动同步
    private func updateDrawableSize() {
        guard let metalLayer = layer as? CAMetalLayer else { return }
        let size = CGSize(width: bounds.width * metalLayer.contentsScale,
                          height: bounds.height * metalLayer.contentsScale)
        if metalLayer.drawableSize != size {
            metalLayer.drawableSize = size
        }
    }

    override func layout() {
        super.layout()
        updateDrawableSize()
    }

    /// 档位变化时由外部调用：唤醒渲染
    func wake() {
        renderer?.wake()
        startTimerIfNeeded()
    }

    func sleep() {
        renderTimer?.invalidate()
        renderTimer = nil
    }

    private func startTimerIfNeeded() {
        let hz = AppSettings.shared.frameRate
        if renderTimer != nil, timerHz == hz { return }
        renderTimer?.invalidate()
        let t = Timer(timeInterval: 1.0 / hz, target: self,
                      selector: #selector(renderTick(_:)),
                      userInfo: nil, repeats: true)
        t.tolerance = 0.004
        RunLoop.main.add(t, forMode: .common)
        renderTimer = t
        timerHz = hz
    }
    private var tickCount = 0

    @objc private func renderTick(_ timer: Timer) {
        tickCount += 1
        guard let renderer else {
            timer.invalidate()
            renderTimer = nil
            return
        }
        renderer.renderFrame(now: CACurrentMediaTime())
        // 完全淡出后停止（零 CPU/GPU）
        if renderer.isIdle {
            timer.invalidate()
            renderTimer = nil
        }
    }

    /// notch 中心 → 本视图像素坐标（左上原点）。
    /// 纯算术：不依赖 convert()（实测其在非翻转视图/无边框窗口下结果错误）
    func updateNotchCenter(notchRectGlobal: CGRect) {
        guard let metalLayer = layer as? CAMetalLayer else { return }
        lastNotchRect = notchRectGlobal
        guard let winFrame = window?.frame else { return }
        let scale = metalLayer.contentsScale
        let x = (notchRectGlobal.midX - winFrame.minX) * scale
        // 中心上移半个刘海高度（光晕锚定屏幕顶边，围绕刘海下半与两侧）
        let y = (winFrame.maxY - notchRectGlobal.midY) * scale
            - notchRectGlobal.height * 0.5 * scale
        renderer?.notchCenterPixels = CGPoint(x: x, y: y)
    }

    private var lastNotchRect: CGRect?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, let n = lastNotchRect {
            updateNotchCenter(notchRectGlobal: n)
        }
    }
}
