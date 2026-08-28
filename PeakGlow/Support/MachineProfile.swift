import IOKit
import Foundation
import AppKit

/// 机型检测：自动匹配该机型的稳定满载整机功率（用于功率→负载百分比换算）。
/// 依据：IORegistry product-name + 芯片名 + 物理核数 + 内建屏分辨率。
struct MachineProfile {
    enum Family: String {
        case air, pro14, pro16, unknown
    }

    let family: Family
    let productName: String
    let chipName: String
    let coreCount: Int
    /// 中档阈值建议（W）
    let suggestedMediumWatts: Double
    /// 高档阈值建议（W）
    let suggestedHighWatts: Double
    /// 过热判定温度阈值（°C，SMC die 温度口径）；nil = 无该机型数据（不启用温度判据）
    let overheatTempThreshold: Double?
    /// 过热解除温度阈值（°C）
    let overheatCoolThreshold: Double?

    /// 检测结果缓存（进程内只检测一次）
    static let current: MachineProfile = detect()

    static func detect() -> MachineProfile {
        let model = sysctlString("hw.model") ?? "unknown"
        let chip = sysctlString("machdep.cpu.brand_string") ?? "Apple Silicon"
        let cores = sysctlInt("hw.physicalcpu")

        var product = model
        if let name = ioProductName(), !name.isEmpty {
            product = name
        }

        let lower = (product + " " + chip).lowercased()

        // 家族判断：产品名优先，屏幕物理分辨率兜底
        let pixelW = NotchedScreenFinder.find()
            .map { $0.frame.width * $0.backingScaleFactor } ?? 0
        let family: Family
        if lower.contains("macbook air") {
            family = .air
        } else if lower.contains("macbook pro") {
            if lower.contains("16-inch") || pixelW >= 3400 {
                family = .pro16
            } else {
                family = .pro14
            }
        } else if lower.contains("macbook") {
            family = .pro14   // 无尺寸信息的 MacBook 按保守处理
        } else {
            family = .unknown // 台式机：功率信号意义有限，用通用回退值
        }

        // 阈值建议（W）：
        // Pro：中 30 / 高 55（用户标定）
        // Air：持续满载仅 18-24W，瞬时尖峰 30-45W 转瞬即逝 →
        //      高 19 落在持续满载区间（须持续负载才触发），
        //      中 13 高于日常轻载（~10W）避免误触
        let medium: Double
        let high: Double
        switch family {
        case .air:   medium = 13; high = 19
        case .pro14: medium = 30; high = 55
        case .pro16: medium = 30; high = 55
        case .unknown: medium = 30; high = 55
        }

        // 过热判定温度阈值（°C，SMC Tp die 温度口径）：
        // Pro 有风扇：powermetrics 实测降频点 avg≥95/max≥98 → Tp max 阈值 96
        // Air 无风扇：节流稳态 avg 96-99 / max 103-105；无风扇散热弱需更早介入 → 触发 95 / 解除 88
        let hotT: Double?, coolT: Double?
        switch family {
        case .air:
            hotT = 98.0; coolT = 88.0    // 空闲 Tp≈40-55，日常负载峰值 ~80；95+ 即贴顶节流前兆
        case .pro14, .pro16:
            hotT = 96.0; coolT = 90.0
        case .unknown:
            hotT = nil; coolT = nil      // 无数据机型仅靠 thermalState 判定
        }

        return MachineProfile(
            family: family,
            productName: product,
            chipName: chip,
            coreCount: cores,
            suggestedMediumWatts: medium,
            suggestedHighWatts: high,
            overheatTempThreshold: hotT,
            overheatCoolThreshold: coolT)
    }

    /// 简短描述（设置面板显示）
    var summary: String {
        "\(productName) · \(chipName) \(coreCount)核"
    }

    // MARK: - 私有

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
        return String(cString: buf).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sysctlInt(_ name: String) -> Int {
        var v: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &v, &size, nil, 0) == 0 else { return 0 }
        return Int(v)
    }

    private static func ioProductName() -> String? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }
        guard let data = IORegistryEntrySearchCFProperty(
            service, kIOServicePlane, "product-name" as CFString,
            kCFAllocatorDefault, IOOptionBits(kIORegistryIterateRecursively)
        ) as? Data else { return nil }
        return String(data: data, encoding: .utf8)?
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
