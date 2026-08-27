import AppKit
import CoreGraphics

// PeakGlow App 图标（Xcode 26 .icon 分层格式导出）
// 图层（顶层→底层）：notch 刘海 / glow 彩虹光晕 / background 深色玻璃底盘
// 注意：icon.json layers 数组第一个元素 = 最顶层

let W: CGFloat = 1024, H: CGFloat = 1024
let outDir = "PeakGlow/Assets.xcassets/AppIcon.icon/Assets"

func makeCtx() -> CGContext {
    CGContext(
        data: nil, width: Int(W), height: Int(H),
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func save(_ ctx: CGContext, _ name: String) {
    let img = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: img)
    let png = rep.representation(using: .png, properties: [:])!
    try! png.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
    print("saved \(name).png")
}

// 几何常量
let notchW = W * 0.30, notchH = W * 0.098
let notchRect = CGRect(
    x: W * 0.5 - notchW / 2, y: H - W * 0.062 - notchH,
    width: notchW, height: notchH)
let notchCenter = CGPoint(x: notchRect.midX, y: notchRect.midY)
let orbitRX = W * 0.175, orbitRY = W * 0.135

// ============ 图层 3：background（最底层）============
// 深色玻璃底盘：对角渐变 + 底部环境微光 + 左上高光弧（全出血，系统负责 squircle 裁剪）
do {
    let ctx = makeCtx()
    let bgColors = [
        CGColor(red: 0.16, green: 0.17, blue: 0.22, alpha: 1),
        CGColor(red: 0.07, green: 0.075, blue: 0.11, alpha: 1),
    ] as CFArray
    let bgGrad = CGGradient(colorsSpace: nil, colors: bgColors, locations: [0, 1])!
    ctx.drawLinearGradient(
        bgGrad,
        start: CGPoint(x: W * 0.2, y: H),
        end: CGPoint(x: W * 0.8, y: 0),
        options: [])

    // 底部环境光（暗部微光）
    let ambColors = [
        CGColor(red: 0.25, green: 0.30, blue: 0.55, alpha: 0.35),
        CGColor(red: 0, green: 0, blue: 0, alpha: 0),
    ] as CFArray
    let ambGrad = CGGradient(colorsSpace: nil, colors: ambColors, locations: [0, 1])!
    ctx.drawRadialGradient(
        ambGrad,
        startCenter: CGPoint(x: W * 0.5, y: H * 0.08), startRadius: 0,
        endCenter: CGPoint(x: W * 0.5, y: H * 0.08), endRadius: W * 0.75,
        options: [.drawsAfterEndLocation])

    // Liquid Glass 高光：左上弧形高光带
    ctx.setBlendMode(.screen)
    let hlColors = [
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.0),
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.30),
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.0),
    ] as CFArray
    let hlGrad = CGGradient(colorsSpace: nil, colors: hlColors, locations: [0, 0.5, 1])!
    ctx.saveGState()
    let hlPath = CGMutablePath()
    hlPath.addArc(
        center: CGPoint(x: W * 0.5, y: H * 0.55),
        radius: W * 0.435,
        startAngle: .pi * 0.62, endAngle: .pi * 0.98,
        clockwise: false)
    ctx.addPath(hlPath)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    ctx.drawLinearGradient(
        hlGrad,
        start: CGPoint(x: W * 0.05, y: H * 0.95),
        end: CGPoint(x: W * 0.05, y: H * 0.55),
        options: [])
    ctx.restoreGState()

    save(ctx, "background")
}

// ============ 图层 2：glow（中层）============
// 彩虹光晕：刘海下半椭圆轨道 96 个细密色点 + 中心亮核
do {
    let ctx = makeCtx()
    ctx.setBlendMode(.screen)
    let N = 96
    for i in 0..<N {
        let t = CGFloat(i) / CGFloat(N - 1)
        let theta = .pi + t * .pi   // 下半椭圆：左端→正下→右端
        let spotCenter = CGPoint(
            x: notchCenter.x + cos(theta) * orbitRX,
            y: notchCenter.y + sin(theta) * orbitRY)
        let hue = t * 0.78   // 红(0) → 紫(0.78)
        let spotColors = [
            NSColor(hue: hue, saturation: 0.9, brightness: 1.0, alpha: 0.32).cgColor,
            CGColor(red: 0, green: 0, blue: 0, alpha: 0),
        ] as CFArray
        let grad = CGGradient(colorsSpace: nil, colors: spotColors, locations: [0, 1])!
        ctx.drawRadialGradient(
            grad,
            startCenter: spotCenter, startRadius: 0,
            endCenter: spotCenter, endRadius: W * 0.085,
            options: [.drawsAfterEndLocation])
    }
    // 中心亮核（克制）
    let coreColors = [
        CGColor(red: 0.80, green: 0.90, blue: 1.0, alpha: 0.40),
        CGColor(red: 0, green: 0, blue: 0, alpha: 0),
    ] as CFArray
    let coreGrad = CGGradient(colorsSpace: nil, colors: coreColors, locations: [0, 1])!
    ctx.drawRadialGradient(
        coreGrad,
        startCenter: notchCenter, startRadius: 0,
        endCenter: notchCenter, endRadius: W * 0.13,
        options: [])
    save(ctx, "glow")
}

// ============ 图层 1：notch（最顶层）============
// 黑色胶囊刘海 + 内缘微光
do {
    let ctx = makeCtx()
    let notchPath = CGPath(
        roundedRect: notchRect,
        cornerWidth: notchH / 2, cornerHeight: notchH / 2,
        transform: nil)
    ctx.setFillColor(CGColor(red: 0.02, green: 0.02, blue: 0.03, alpha: 1))
    ctx.addPath(notchPath)
    ctx.fillPath()
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.10))
    ctx.setLineWidth(3)
    ctx.addPath(notchPath)
    ctx.strokePath()
    save(ctx, "notch")
}
