import Foundation
import Combine

/// 全局可观察状态（气泡显示用）
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var cpuPercent: Double = 0
    @Published var watts: Double = 0
    @Published var effectiveLevel: LoadLevel = .low
    @Published var preview: PreviewLevel {
        didSet { AppSettings.shared.previewLevelRaw = preview.rawValue }
    }

    private init() {
        preview = AppSettings.shared.preview
    }
}
