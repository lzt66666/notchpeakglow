import Foundation
import AppKit
import IOKit

/// 过热降频监测 v3 —— "撞温度墙"形态检测
///
/// 核心洞察（用户实测曲线分析）：过热降频的可靠指纹不是功率塌陷也不是频率跳水，
/// 而是 **CPU 温度贴死在热墙线上进入稳态**（窗口内极差 ≤3~4°C），
/// 并保持一段稳定时间。温升爬坡期（极差大）与降温期（跌破墙线）均不告警。
///
/// 数据源：SMC Tp* die 温度最大值（用户态，同 stats 方案）
/// 兜底：ProcessInfo.thermalState == .critical 直通
final class OverheatDetector {
    var onOverheatChange: ((Bool) -> Void)?

    private(set) var overheat = false

    private struct Params {
        let hotWall: Double       // 热墙温度（°C，die 口径）
        let band: Double          // "钉住"判定的窗口内允许波动
        let stableSecs: Double    // 钉住需持续的时长
        let releaseDrop: Double   // 从墙回落多少度立即解除
    }

    private var p: Params!
    private var timer: Timer?
    private let smc = ThermalSMC.shared

    private var win: [(t: TimeInterval, v: Double)] = []
    private var pinSince: Date?

    func start(interval: TimeInterval = 1.0) {
        switch MachineProfile.current.family {
        case .air:
            p = Params(hotWall: 93, band: 3.5, stableSecs: 12, releaseDrop: 6)
        case .pro14, .pro16:
            p = Params(hotWall: 94, band: 3.5, stableSecs: 10, releaseDrop: 6)
        case .unknown:
            p = Params(hotWall: 95, band: 4.0, stableSecs: 12, releaseDrop: 6)
        }
        _ = smc.open()
        update()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.update()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func update() {
        // 用户关闭过热提醒 → 不评估
        guard AppSettings.shared.overheatAlertEnabled else {
            setOverheat(false)
            resetWindow()
            return
        }

        // 系统级直通（金标准兜底）
        if ProcessInfo.processInfo.thermalState == .critical {
            setOverheat(true)
            resetWindow()
            return
        }

        guard let t = smc.maxTPTemp() else { return }   // SMC 不可用则维持现状

        let now = Date().timeIntervalSince1970
        win.append((now, t))
        while let first = win.first, now - first.t > 15.0 {
            win.removeFirst()
        }

        let vs = win.map(\.v)
        let vmax = vs.max() ?? t
        let vmin = vs.min() ?? t

        // 撞墙判定：窗口最高温达到热墙线，且窗口极差小（温度贴墙稳定）
        let pinned = vmax >= p.hotWall && (vmax - vmin) <= p.band

        if pinned {
            if pinSince == nil { pinSince = Date() }
            if Date().timeIntervalSince(pinSince!) >= p.stableSecs {
                setOverheat(true)
            }
        } else {
            pinSince = nil
            // 温升爬坡期（极差大）/ 降温期（跌破墙线）→ 不属于过热稳态
            if overheat { setOverheat(false) }
        }
    }

    private func resetWindow() {
        win.removeAll()
        pinSince = nil
    }

    private func setOverheat(_ on: Bool) {
        guard on != overheat else { return }
        overheat = on
        NSLog("PeakGlow: overheat -> \(on)")
        onOverheatChange?(on)
    }
}

/// SMC 底层读数封装（Tp* die 温度），两步法
final class ThermalSMC {
    static let shared = ThermalSMC()
    private var conn: io_connect_t = 0
    private var opened = false

    private struct KeyData {
        typealias Bytes = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                           UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                           UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                           UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
        struct Vers { var a: UInt8 = 0; var b: UInt8 = 0; var c: UInt8 = 0; var d: UInt8 = 0; var rel: UInt16 = 0 }
        struct Limit { var v1: UInt16 = 0; var v2: UInt16 = 0; var v3: UInt32 = 0; var v4: UInt32 = 0; var v5: UInt32 = 0 }
        struct Info { var dataSize: UInt32 = 0; var dataType: UInt32 = 0; var attrs: UInt8 = 0 }
        var key: UInt32 = 0
        var vers = Vers(); var pLimitData = Limit(); var keyInfo = Info()
        var padding: UInt16 = 0; var result: UInt8 = 0; var status: UInt8 = 0
        var data8: UInt8 = 0; var data32: UInt32 = 0
        var bytes: Bytes = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    func open() -> Bool {
        if opened { return conn != 0 }
        opened = true
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != IO_OBJECT_NULL else { return false }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &conn) == KERN_SUCCESS else {
            conn = 0
            return false
        }
        return true
    }

    /// 所有 P 核 die 温度键（Tp*，flt 小端）的最大值；不可用返回 nil
    func maxTPTemp() -> Double? {
        guard conn != 0 else { return nil }
        var maxV: Double?
        for key in Self.tpKeys {
            if let v = readFloat(key), v > 20, v < 130 {
                maxV = max(maxV ?? 0, v)
            }
        }
        return maxV
    }

    private func readFloat(_ keyName: String) -> Double? {
        let fourcc: UInt32 = keyName.utf8.reduce(0) { $0 << 8 | UInt32($1) }
        var i = KeyData(), o = KeyData()
        i.key = fourcc
        i.data8 = 9                      // readKeyInfo
        guard call(&i, &o) == KERN_SUCCESS else { return nil }
        guard o.keyInfo.dataSize > 0, o.keyInfo.dataType == 0x66_6C_74_20 else { return nil }
        i.keyInfo.dataSize = o.keyInfo.dataSize
        i.data8 = 5                      // readBytes
        guard call(&i, &o) == KERN_SUCCESS else { return nil }
        var v: Double?
        withUnsafeBytes(of: o.bytes) { raw in
            let bits = UInt32(raw[0]) | UInt32(raw[1]) << 8 | UInt32(raw[2]) << 16 | UInt32(raw[3]) << 24
            v = Double(Float32(bitPattern: bits))
        }
        return v
    }

    private func call(_ i: inout KeyData, _ o: inout KeyData) -> kern_return_t {
        let size = MemoryLayout<KeyData>.stride
        var outSize = size
        return withUnsafeMutablePointer(to: &i) { ip in
            withUnsafeMutablePointer(to: &o) { op in
                IOConnectCallStructMethod(conn, 2, ip, size, op, &outSize)
            }
        }
    }

    private static let tpKeys = [
        "Tp00", "Tp04", "Tp08", "Tp0C", "Tp0G", "Tp0K", "Tp0O", "Tp0R",
        "Tp0U", "Tp0X", "Tp0a", "Tp0d", "Tp0g", "Tp0j", "Tp0m", "Tp0p",
        "Tp0u", "Tp0y", "Tp1E", "Tp1I", "Tp1Q", "Tp1U", "Tp1g",
    ]
}
