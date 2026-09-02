import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let sampler = CPUSampler()
    private let powerSampler = PowerSampler()
    private let thermal = OverheatDetector()
    private let stateMachine = LoadLevelStateMachine()
    private let glow = GlowWindow()
    private let hover = NotchHoverController()
    private let gamepad = GamepadDetector()
    private var bubble: BubblePanelController?

    private var lastAutoLevel: LoadLevel = .low

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 机型自动调优：仅首次启动写入建议阈值（不覆盖手动调整）
        if !AppSettings.shared.powerTuned {
            let mp = MachineProfile.current
            AppSettings.shared.mediumWatts = mp.suggestedMediumWatts
            AppSettings.shared.highWatts = mp.suggestedHighWatts
            AppSettings.shared.powerTuned = true
            NSLog("PeakGlow: machine tuned \(mp.summary) -> \(mp.suggestedMediumWatts)W/\(mp.suggestedHighWatts)W")
        }

        bubble = BubblePanelController(hover: hover)
        // 采样 → 状态机（仅整机功率信号；CPU% 仅作显示）
        var wattWindow: [Double] = []
        sampler.onSample = { [weak self] avg in
            guard let self else { return }
            let state = AppState.shared

            guard let w = powerSampler.readWatts(), w > 0 else { return }
            // 气泡不可见时不触碰 @Published（隐藏的 SwiftUI 视图无需持续重渲染）
            if state.bubbleVisible { state.watts = w }
            // 5 样本滑动平均（默认 0.5s 采样 = 2.5s 窗口），滤除瞬时尖峰
            wattWindow.append(w)
            if wattWindow.count > 5 { wattWindow.removeFirst() }
            stateMachine.update(watts: wattWindow.reduce(0, +) / Double(wattWindow.count))
        }
        stateMachine.onLevelChange = { [weak self] level in
            guard let self else { return }
            self.lastAutoLevel = level
            self.applyLevel()
        }

        // 设置变化：光晕宽度/预览即时生效
        NotificationCenter.default.addObserver(
            forName: AppSettings.changedNotification,
            object: nil, queue: .main) { [weak self] _ in
            self?.glow.reposition()
            self?.applyLevel()
            self?.sampler.start(interval: AppSettings.shared.sampleInterval)
        }

        // 手柄检测：连接任意手柄 → 暂停光晕（游戏中不打扰）
        gamepad.onGamepadChange = { [weak self] connected in
            self?.glow.setPaused(connected)
        }

        // 过热监测：真实过热时自动开启红闪（预览"热"档外的叠加通道）
        thermal.onOverheatChange = { [weak self] hot in
            guard let self else { return }
            AppSettings.shared.overheatAlarm = hot
            self.applyLevel()
        }

        // 屏幕睡眠/唤醒
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.screensDidSleepNotification,
                       object: nil, queue: .main) { [weak self] _ in
            self?.glow.setPaused(true)
        }
        ws.addObserver(forName: NSWorkspace.screensDidWakeNotification,
                       object: nil, queue: .main) { [weak self] _ in
            self?.glow.setPaused(false)
        }

        glow.start()
        hover.start()
        gamepad.start()
        thermal.start()
        sampler.start(interval: AppSettings.shared.sampleInterval)
        applyLevel()   // start 之后再应用一次（renderer 此时已创建）

        FirstRunWindow.showIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        glow.shutdown()
        sampler.stop()
    }

    /// 预览优先，否则自动档位；过热预览 = 高档蓝呼吸 + 周期红闪
    /// 真实过热（SMC Tp 温度 ≥96°C / thermalState critical）在 auto 与非关闭档下自动叠加红闪
    private func applyLevel() {
        var overheat = false
        let effective: LoadLevel
        switch AppSettings.shared.preview {
        case .auto:
            effective = lastAutoLevel
            overheat = AppSettings.shared.overheatAlarm && effective != .low
        case .overheat:
            effective = .high          // 蓝色呼吸基底 + 红闪
            overheat = true
        case .low, .medium, .high:
            effective = LoadLevel(rawValue: AppSettings.shared.preview.rawValue) ?? lastAutoLevel
        }
        AppState.shared.effectiveLevel = effective
        // 真实过热（非预览）时同步给气泡 UI 做状态区分
        AppState.shared.overheatAlarm = overheat && AppSettings.shared.preview != .overheat
            && AppSettings.shared.overheatAlarm
        glow.setOverheat(overheat, gainBoost: Float(AppSettings.shared.overheatGain))
        glow.setLevel(effective)
    }
}
