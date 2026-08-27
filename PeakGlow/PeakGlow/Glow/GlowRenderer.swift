import Foundation
import Metal
import QuartzCore

/// Metal 渲染器：CADisplayLink 主线程驱动（单线程访问，无锁），
/// 档位间平滑过渡
final class GlowRenderer {
    // 仅主线程访问
    var targetLevel: LoadLevel = .low   // low → intensity 0
    var headroom: Float = 1.0
    var paused = false                  // 全屏/睡眠时
    /// 完全淡出后为 true，宿主视图据此暂停 displaylink（零功耗）
    private(set) var isIdle = true

    private let layer: CAMetalLayer
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState

    private var intensity: Float = 0
    private var modeMix: Float = 0
    private var lastRender: CFTimeInterval = 0
    private var startTime = CFAbsoluteTimeGetCurrent()

    /// notch 中心（像素），由主线程设置
    var notchCenterPixels: CGPoint = .zero

    init?(layer: CAMetalLayer) {
        self.layer = layer
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        layer.device = device
        guard let queue = device.makeCommandQueue() else { return nil }
        self.commandQueue = queue

        guard let lib = device.makeDefaultLibrary(),
              let fnv = lib.makeFunction(name: "vertexShader"),
              let fnf = lib.makeFunction(name: "fragmentShader") else {
            NSLog("PeakGlow: shader functions not found")
            return nil
        }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = fnv
        desc.fragmentFunction = fnf
        desc.colorAttachments[0].pixelFormat = layer.pixelFormat
        guard let pso = try? device.makeRenderPipelineState(descriptor: desc) else {
            return nil
        }
        self.pipeline = pso
        layer.isOpaque = false
    }

    /// 有新目标（档位变化/恢复）时唤醒
    func wake() {
        isIdle = false
    }

    // MARK: - 渲染（主线程，CADisplayLink 驱动）

    func renderFrame(now: CFTimeInterval) {
        if lastRender != 0, now - lastRender < (1.0 / AppSettings.shared.frameRate) * 0.9 { return }
        let s = AppSettings.shared

        let targetIntensity: Float = (paused || targetLevel == .low) ? 0 : 1
        let targetMix: Float = targetLevel == .high ? 1 : 0

        let dt = Float(min(0.1, lastRender == 0 ? 0.033 : now - lastRender))
        let fadeSpeed: Float = targetLevel == .low ? 2.0 : 1.25
        intensity += (targetIntensity - intensity) * min(1, dt * fadeSpeed)
        modeMix += (targetMix - modeMix) * min(1, dt * 1.25)
        lastRender = now

        // 完全隐藏 → 通知宿主暂停 displaylink
        if intensity < 0.004, targetIntensity == 0 {
            intensity = 0
            isIdle = true
            return
        }
        isIdle = false

        guard let drawable = layer.nextDrawable() else { return }
        let drawableSize = layer.drawableSize

        let baseBoost = 1.0 + (headroom - 1.0) * Float(s.hdrFactor)
        let userTrim = (Float(s.hdrFactor) - 3.0) * 0.5

        var uniforms = Uniforms(
            resolution: SIMD2<Float>(Float(drawableSize.width), Float(drawableSize.height)),
            notchCenter: SIMD2<Float>(Float(notchCenterPixels.x), Float(notchCenterPixels.y)),
            time: Float(CFAbsoluteTimeGetCurrent() - startTime),
            intensity: intensity * Float(s.glowIntensity),
            modeMix: modeMix,
            hdrBoost: baseBoost + userTrim,
            pulseHz: Float(s.pulseHz),
            glowScale: Float(drawableSize.height),
            mediumAlpha: Float(s.mediumAlpha))

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

        guard let cmd = commandQueue.makeCommandBuffer(),
              let encoder = cmd.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encoder.endEncoding()
        cmd.present(drawable)
        cmd.commit()
    }
}

/// 与 shader 中结构体对齐
struct Uniforms {
    var resolution: SIMD2<Float>
    var notchCenter: SIMD2<Float>
    var time: Float
    var intensity: Float
    var modeMix: Float
    var hdrBoost: Float
    var pulseHz: Float
    var glowScale: Float
    var mediumAlpha: Float
}
