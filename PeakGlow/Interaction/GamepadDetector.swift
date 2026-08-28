import Foundation
import GameController

/// 手柄检测：任何 GameController 设备连接 → 暂停光晕（游戏中不打扰）。
/// 纯事件驱动：只依赖系统 GCControllerDidConnect/Disconnect 通知，
/// 不做任何主动蓝牙扫描（避免射频/CPU 开销与输入卡顿嫌疑）。
/// GameController 框架在进程启动时自动枚举已连接手柄并补发 Connect 通知。
final class GamepadDetector {
    var onGamepadChange: ((Bool) -> Void)?

    private(set) var hasGamepad = false

    func start() {
        NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect, object: nil, queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
        NotificationCenter.default.addObserver(
            forName: .GCControllerDidDisconnect, object: nil, queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
        refresh()   // 启动时同步一次当前状态（含已连手柄）
    }

    func refresh() {
        let connected = !GCController.controllers().isEmpty
        if connected != hasGamepad {
            hasGamepad = connected
            NSLog("PeakGlow: gamepad \(connected ? "connected -> 光晕暂停" : "disconnected -> 光晕恢复")")
            onGamepadChange?(connected)
        }
    }
}
