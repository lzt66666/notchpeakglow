import AppKit
import CoreGraphics

// PeakGlow App 图标绘制（Liquid Glass 风格）
// 画布 1024：深色玻璃底盘 + 刘海 + 彩虹光晕 + 玻璃高光

let size = 1024
let ctx = CGContext(
    data: nil, width: size, height: size,
    bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

let W = CGFloat(size), H = CGFloat(size)

// 1) 玻璃底盘 squircle：深蓝黑渐变（屏幕质感）
let sqRect = CGRect(x: 0, y: 0, width: W, height: H)
let sqPath = squircle(sqRect, radius: W * 0.2335)
ctx.saveGState()
ctx.addPath(sqPath)
ctx.clip()
let bgColors = [
    CGColor(red: 0.16, green: 0.17, blue: 0.22, alpha: 1),
    CGColor(red: 0.07, green: 0.075, blue: 0.11, alpha: 1),
] as CFArray
let bgGrad = CGGradient(
    colorsSpace: nil, colors: bgColors, locations: [0, 1])!
ctx.drawLinearGradient(
    bgGrad,
    start: CGPoint(x: W * 0.2, y: H),
    end: CGPoint(x: W * 0.8, y: 0),
    options: [])

// 2) 底部环境光（暗部微光，避免死黑）
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

// 3) 彩虹光晕：刘海下半椭圆轨道上 96 个细密色点，色相连续流转
let notchW = W * 0.30, notchH = W * 0.098
let notchRect = CGRect(
    x: W * 0.5 - notchW / 2, y: H - W * 0.062 - notchH,
    width: notchW, height: notchH)
let notchCenter = CGPoint(x: notchRect.midX, y: notchRect.midY)
let orbitRX = W * 0.175, orbitRY = W * 0.135

ctx.setBlendMode(.screen)
let N = 96
for i in 0..<N {
    let t = CGFloat(i) / CGFloat(N - 1)
    // 下半椭圆：θ 从 π（左端）经 3π/2（正下）到 2π（右端）
    let theta = .pi + t * .pi
    let spotCenter = CGPoint(
        x: notchCenter.x + cos(theta) * orbitRX,
        y: notchCenter.y + sin(theta) * orbitRY)   // sin 在 (π,2π) 为负 → 轨道在刘海下方
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
// 中心亮核（克制，避免过曝）
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
ctx.setBlendMode(.normal)

// 4) 刘海：纯黑胶囊，顶部居中（盖在光晕之上）
let notchPath = CGPath(
    roundedRect: notchRect,
    cornerWidth: notchH / 2, cornerHeight: notchH / 2,
    transform: nil)
ctx.setFillColor(CGColor(red: 0.02, green: 0.02, blue: 0.03, alpha: 1))
ctx.addPath(notchPath)
ctx.fillPath()
// 刘海内缘微光（摄像头环暗示）
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.10))
ctx.setLineWidth(3)
ctx.addPath(notchPath)
ctx.strokePath()

// 5) Liquid Glass 高光：左上弧形高光带
ctx.setBlendMode(.screen)
let hlColors = [
    CGColor(red: 1, green: 1, blue: 1, alpha: 0.0),
    CGColor(red: 1, green: 1, blue: 1, alpha: 0.30),
    CGColor(red: 1, green: 1, blue: 1, alpha: 0.0),
] as CFArray
let hlGrad = CGGradient(colorsSpace: nil, colors: hlColors, locations: [0, 0.5, 1])!
// 沿左上边缘的细弧：用一个旋转椭圆环带模拟
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
ctx.setBlendMode(.normal)
ctx.restoreGState()   // 结束 squircle 裁剪

// 6) 玻璃外描边（1.5% 宽度，半透明白）
ctx.saveGState()
ctx.addPath(squircle(sqRect, radius: W * 0.2335))
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.14))
ctx.setLineWidth(W * 0.012)
ctx.strokePath()
ctx.restoreGState()

// 输出
let img = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: img)
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: "AppIcon_1024.png"))
print("saved AppIcon_1024.png")

/// macOS 连续圆角近似：四段圆角 + 中间直线，半径 r
func squircle(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}
