import Foundation

enum PreviewLevel: Int, CaseIterable {
    case low = 0, medium = 1, high = 2, auto = 3, overheat = 4

    var label: String {
        switch self {
        case .low: return "关闭"
        case .medium: return "中"
        case .high: return "高"
        case .auto: return "自动"
        case .overheat: return "降频"
        }
    }
}

/// 设置存取（全部主线程访问：采样Timer/CADisplayLink渲染/SwiftUI均在主线程，无需锁）
final class AppSettings {
    static let shared = AppSettings()
    static let changedNotification = Notification.Name("AppSettingsChanged")

    private let d = UserDefaults.standard

    // MARK: - Keys
    private enum Key {
        static let mediumWatts = "mediumWatts"
        static let highWatts = "highWatts"
        static let holdOnSeconds = "holdOnSeconds"
        static let hysteresisWatts = "hysteresisWatts"
        static let sampleInterval = "sampleInterval"
        static let glowScale = "glowScale"
        static let glowIntensity = "glowIntensity"
        static let mediumAlpha = "mediumAlpha"
        static let pulseHz = "pulseHz"
        static let hdrFactor = "hdrFactor"
        static let overheatGain = "overheatGain"
        static let overheatScale = "overheatScale"
        static let frameRate = "frameRate"
        static let hoverDwell = "hoverDwell"
        static let previewLevel = "previewLevel"
        static let powerTuned = "powerTuned"
        static let firstRunDone = "firstRunDone"
        static let overheatAlarm = "overheatAlarm"
        static let overheatAlertEnabled = "overheatAlertEnabled"
    }

    // MARK: - Defaults
    // 注：以下为作者实机调校后的出厂默认值
    struct Defaults {
        static let mediumWatts = MachineProfile.current.suggestedMediumWatts
        static let highWatts = MachineProfile.current.suggestedHighWatts
        static let holdOnSeconds = 1.2
        static let hysteresisWatts = 4.0
        static let sampleInterval = 0.5
        static let glowScale = 0.68
        static let glowIntensity = 0.73
        static let mediumAlpha = 0.75
        static let pulseHz = 0.5
        static let hdrFactor = 2.1
        static let overheatGain = 4.5
        static let overheatScale = 1.3
        static let frameRate = 30.0
        static let hoverDwell = 0.3
        static let previewLevel = PreviewLevel.auto.rawValue
        static let powerTuned = false
        static let firstRunDone = false
    }

    private func get<T>(_ key: String, _ fallback: T) -> T {
        let v = d.object(forKey: key)
        return (v as? T) ?? fallback
    }

    private func set<T>(_ value: T, _ key: String) {
        d.set(value, forKey: key)
        NotificationCenter.default.post(name: Self.changedNotification, object: nil)
    }

    // MARK: - 负载（瓦数阈值）
    var mediumWatts: Double {
        get { get(Key.mediumWatts, Defaults.mediumWatts) }
        set { set(Double(newValue), Key.mediumWatts) }
    }
    var highWatts: Double {
        get { get(Key.highWatts, Defaults.highWatts) }
        set { set(Double(newValue), Key.highWatts) }
    }
    var holdOnSeconds: Double {
        get { get(Key.holdOnSeconds, Defaults.holdOnSeconds) }
        set { set(Double(newValue), Key.holdOnSeconds) }
    }
    var hysteresisWatts: Double {
        get { get(Key.hysteresisWatts, Defaults.hysteresisWatts) }
        set { set(Double(newValue), Key.hysteresisWatts) }
    }
    var sampleInterval: Double {
        get { get(Key.sampleInterval, Defaults.sampleInterval) }
        set { set(Double(newValue), Key.sampleInterval) }
    }

    // MARK: - 外观
    /// 光晕整体缩放（0.4–1.6，长宽等比）
    var glowScale: Double {
        get { get(Key.glowScale, Defaults.glowScale) }
        set { set(Double(newValue), Key.glowScale) }
    }
    var glowIntensity: Double {
        get { get(Key.glowIntensity, Defaults.glowIntensity) }
        set { set(Double(newValue), Key.glowIntensity) }
    }
    var mediumAlpha: Double {
        get { get(Key.mediumAlpha, Defaults.mediumAlpha) }
        set { set(Double(newValue), Key.mediumAlpha) }
    }
    var pulseHz: Double {
        get { get(Key.pulseHz, Defaults.pulseHz) }
        set { set(Double(newValue), Key.pulseHz) }
    }
    var hdrFactor: Double {
        get { get(Key.hdrFactor, Defaults.hdrFactor) }
        set { set(Double(newValue), Key.hdrFactor) }
    }
    /// 过热红光相对蓝色的额外增益（×），1.0=与蓝同亮度
    var overheatGain: Double {
        get { get(Key.overheatGain, Defaults.overheatGain) }
        set { set(Double(newValue), Key.overheatGain) }
    }
    /// 过热红光相对蓝的尺寸倍率（红闪时光晕膨胀）
    var overheatScale: Double {
        get { get(Key.overheatScale, Defaults.overheatScale) }
        set { set(Double(newValue), Key.overheatScale) }
    }
    var frameRate: Double {
        get { get(Key.frameRate, Defaults.frameRate) }
        set { set(Double(newValue), Key.frameRate) }
    }

    // MARK: - 行为
    var hoverDwell: Double {
        get { get(Key.hoverDwell, Defaults.hoverDwell) }
        set { set(Double(newValue), Key.hoverDwell) }
    }
    var previewLevelRaw: Int {
        get { get(Key.previewLevel, Defaults.previewLevel) }
        set { set(newValue, Key.previewLevel) }
    }
    /// 机型自动调优是否已应用过（仅首次启动写入建议值，之后不覆盖手动调整）
    var powerTuned: Bool {
        get { get(Key.powerTuned, Defaults.powerTuned) }
        set { set(newValue, Key.powerTuned) }
    }
    /// 首次启动引导是否已展示
    var firstRunDone: Bool {
        get { get(Key.firstRunDone, false) }
        set { set(newValue, Key.firstRunDone) }
    }
    /// 真实过热告警状态（ThermalMonitor 写入，重启后由其重新评估）
    var overheatAlarm: Bool {
        get { get(Key.overheatAlarm, false) }
        set { set(newValue, Key.overheatAlarm) }
    }
    /// 过热降频提醒开关（不想被打扰的用户可关闭；关闭后预览"热"档仍可用）
    var overheatAlertEnabled: Bool {
        get { get(Key.overheatAlertEnabled, true) }
        set { set(newValue, Key.overheatAlertEnabled) }
    }

    var preview: PreviewLevel { PreviewLevel(rawValue: previewLevelRaw) ?? .auto }

    func resetAll() {
        mediumWatts = Defaults.mediumWatts
        highWatts = Defaults.highWatts
        holdOnSeconds = Defaults.holdOnSeconds
        hysteresisWatts = Defaults.hysteresisWatts
        sampleInterval = Defaults.sampleInterval
        glowScale = Defaults.glowScale
        glowIntensity = Defaults.glowIntensity
        mediumAlpha = Defaults.mediumAlpha
        pulseHz = Defaults.pulseHz
        hdrFactor = Defaults.hdrFactor
        overheatGain = Defaults.overheatGain
        overheatScale = Defaults.overheatScale
        frameRate = Defaults.frameRate
        hoverDwell = Defaults.hoverDwell
        previewLevelRaw = Defaults.previewLevel
        powerTuned = Defaults.powerTuned
    }
}
