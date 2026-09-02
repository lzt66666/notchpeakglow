import Foundation
import Combine

/// 全局可观察状态（气泡显示用）
final class AppState: ObservableObject {
    static let shared = AppState()

    /// 气泡是否可见：不可见时冻结 @Published 更新，避免 SwiftUI 每秒空转重渲染
    var bubbleVisible = false
    @Published var watts: Double = 0
    @Published var effectiveLevel: LoadLevel = .low
    /// 真实过热降频告警激活中（区分于普通高档）
    @Published var overheatAlarm = false
    @Published var preview: PreviewLevel {
        didSet { AppSettings.shared.previewLevelRaw = preview.rawValue }
    }

    private init() {
        preview = AppSettings.shared.preview
    }
}
