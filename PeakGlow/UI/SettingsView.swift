import AppKit
import SwiftUI
import ServiceManagement

/// 独立设置窗口（单例）
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var panel: NSPanel?

    func show() {
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false)
        p.title = "PeakGlow 设置"
        p.isReleasedWhenClosed = false
        p.level = .floating
        p.contentView = NSHostingView(rootView: SettingsView())
        p.center()
        p.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel = p
    }
}

struct SettingsView: View {
    @ObservedObject private var app = AppState.shared
    private let s = AppSettings.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // 负载
                GroupBox("负载（整机功率）") {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                        sliderRow("中档阈值", mediumW, range: 8...50, format: "%.0fW")
                        sliderRow("高档阈值", highW, range: 20...90, format: "%.0fW")
                        sliderRow("滞回区间", hyst, range: 1...10, format: "%.0fW")
                        sliderRow("切换保持时间", hold, range: 0.5...10, format: "%.1fs")
                        sliderRow("采样周期", interval, range: 0.2...3, format: "%.1fs")
                    }
                    .padding(8)
                    HStack(spacing: 6) {
                        Image(systemName: "chip")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(MachineProfile.current.summary) · 建议 \(Int(MachineProfile.current.suggestedMediumWatts))W/\(Int(MachineProfile.current.suggestedHighWatts))W")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("应用建议值") {
                            s.mediumWatts = MachineProfile.current.suggestedMediumWatts
                            s.highWatts = MachineProfile.current.suggestedHighWatts
                        }
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }

                // 外观
                GroupBox("外观") {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                        sliderRow("光晕大小", scaleB, range: 0.4...1.6, format: "%.0f%%")
                        sliderRow("光晕强度", intensity, range: 0.2...2, format: "%.1f×")
                        sliderRow("中档透明度", alpha, range: 0.2...0.8, format: "%.0f%%")
                        sliderRow("呼吸频率", pulse, range: 0.2...2, format: "%.1fHz")
                        sliderRow("HDR 强度系数", hdr, range: 1...8, format: "%.1f×")
                        sliderRow("帧率上限", fps, range: 15...60, format: "%.0ffps")
                    }
                    .padding(8)
                }

                // 行为
                GroupBox("行为") {
                    VStack(alignment: .leading, spacing: 10) {
                        sliderRow("悬停驻留时长", dwell, range: 0.2...1.5, format: "%.1fs")
                        Toggle("登录时启动", isOn: launchAtLogin)
                    }
                    .padding(8)
                }

                HStack {
                    Spacer()
                    Button("恢复默认") { s.resetAll() }
                }
            }
            .padding(16)
        }
        .frame(width: 460, height: 520)
    }

    // MARK: - 绑定

    private var mediumW: Binding<Double> {
        Binding(get: { s.mediumWatts }, set: { s.mediumWatts = $0 })
    }
    private var highW: Binding<Double> {
        Binding(get: { s.highWatts }, set: { s.highWatts = $0 })
    }
    private var hyst: Binding<Double> {
        Binding(get: { s.hysteresisWatts }, set: { s.hysteresisWatts = $0 })
    }
    private var hold: Binding<Double> {
        Binding(get: { s.holdOnSeconds }, set: { s.holdOnSeconds = $0 })
    }
    private var interval: Binding<Double> {
        Binding(get: { s.sampleInterval }, set: { s.sampleInterval = $0 })
    }
    private var scaleB: Binding<Double> {
        Binding(get: { s.glowScale }, set: { s.glowScale = $0 })
    }
    private var intensity: Binding<Double> {
        Binding(get: { s.glowIntensity }, set: { s.glowIntensity = $0 })
    }
    private var alpha: Binding<Double> {
        Binding(get: { s.mediumAlpha }, set: { s.mediumAlpha = $0 })
    }
    private var pulse: Binding<Double> {
        Binding(get: { s.pulseHz }, set: { s.pulseHz = $0 })
    }
    private var hdr: Binding<Double> {
        Binding(get: { s.hdrFactor }, set: { s.hdrFactor = $0 })
    }
    private var fps: Binding<Double> {
        Binding(get: { s.frameRate }, set: { s.frameRate = $0 })
    }
    private var dwell: Binding<Double> {
        Binding(get: { s.hoverDwell }, set: { s.hoverDwell = $0 })
    }
    private var launchAtLogin: Binding<Bool> {
        Binding(get: { SMAppService.mainApp.status == .enabled },
                set: { on in
                    do {
                        if on {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        NSLog("PeakGlow: SMAppService error \(error)")
                    }
                })
    }

    private func sliderRow(_ title: String, _ value: Binding<Double>,
                           range: ClosedRange<Double>, format: String) -> some View {
        GridRow {
            Text(title)
            Slider(value: value, in: range)
            Text(String(format: format, value.wrappedValue))
                .monospacedDigit()
                .frame(width: 52, alignment: .trailing)
                .foregroundStyle(.secondary)
        }
    }
}
