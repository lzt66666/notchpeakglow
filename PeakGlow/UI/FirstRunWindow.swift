import AppKit
import SwiftUI

/// 首次启动引导窗口：告知用户无 Dock/菜单栏图标，通过刘海交互
enum FirstRunWindow {
    static func showIfNeeded() {
        guard !AppSettings.shared.firstRunDone else { return }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false)
        panel.title = "欢迎使用 PeakGlow"
        panel.isReleasedWhenClosed = false
        panel.level = .floating

        let view = FirstRunContentView {
            panel.orderOut(nil)
        }
        panel.contentView = NSHostingView(rootView: view)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        AppSettings.shared.firstRunDone = true
    }
}

private struct FirstRunContentView: View {
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)

            Text("PeakGlow 已在后台运行")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 10) {
                Label {
                    Text("本应用**没有 Dock 图标**，也**不占用菜单栏**空间")
                } icon: {
                    Image(systemName: "eye.slash")
                        .foregroundStyle(.secondary)
                }
                Label {
                    Text("将鼠标指针移到屏幕顶部的**刘海（摄像头区域）**并停留片刻，即可呼出控制气泡")
                } icon: {
                    Image(systemName: "camera.metering.center")
                        .foregroundStyle(.secondary)
                }
                Label {
                    Text("气泡中可预览效果、调整设置或退出应用")
                } icon: {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)

            Button("我知道了") {
                onClose()
            }
            .keyboardShortcut(.defaultAction)
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 420)
    }
}
