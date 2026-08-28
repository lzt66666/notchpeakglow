import SwiftUI

struct BubbleContentView: View {
    var onClose: () -> Void
    @EnvironmentObject var app: AppState

    private var levelColor: Color {
        switch app.effectiveLevel {
        case .low: return .green
        case .medium: return .orange
        case .high: return .blue
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            // 状态行
            HStack(spacing: 10) {
                Circle()
                    .fill(app.overheatAlarm ? Color.red : levelColor)
                    .frame(width: 10, height: 10)
                if app.overheatAlarm {
                    Text("过热降频")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Image(systemName: "flame.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                } else {
                    Text("\(app.effectiveLevel.label)负载")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Spacer()
                Text(app.watts > 0.5 ? String(format: "%.1f W", app.watts) : "— W")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.92))
            }

            Divider().overlay(Color.white.opacity(0.12))

            // 预览
            VStack(alignment: .leading, spacing: 8) {
                Text("预览效果")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                HStack(spacing: 8) {
                    ForEach(PreviewLevel.allCases, id: \.rawValue) { p in
                        PreviewButton(level: p)
                    }
                }
            }

            Divider().overlay(Color.white.opacity(0.12))

            // 设置 + 退出
            HStack(spacing: 8) {
                Button {
                    SettingsWindowController.shared.show()
                    onClose()
                } label: {
                    Label("设置…", systemImage: "gearshape")
                        .font(.system(size: 13))
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
                .foregroundStyle(.white)

                Button {
                    NSApp.terminate(nil)
                } label: {
                    Label("退出", systemImage: "power")
                        .font(.system(size: 13))
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(Color.red.opacity(0.35), in: RoundedRectangle(cornerRadius: 9))
                .foregroundStyle(.white)
            }
        }
        .padding(18)
        .frame(width: 320, height: 210)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black.opacity(0.88))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.1))))
    }
}

private struct PreviewButton: View {
    let level: PreviewLevel
    @EnvironmentObject var app: AppState

    var body: some View {
        let selected: Bool = app.preview == level
        return Button {
            app.preview = level
        } label: {
            Text(level.label)
                .font(.system(size: 13, weight: .medium))
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            selected ? Color.white.opacity(0.22) : Color.white.opacity(0.08),
            in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.15)))
        .foregroundStyle(.white)
    }
}
