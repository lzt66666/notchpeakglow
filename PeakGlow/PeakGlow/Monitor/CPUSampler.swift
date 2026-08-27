import Foundation

/// Mach API CPU 采样：总占用率 + 滑动平均
final class CPUSampler {
    var onSample: ((Double) -> Void)?

    private var timer: Timer?
    private var prevIdle: UInt64 = 0
    private var prevTotal: UInt64 = 0
    private var hasPrev = false
    private var window: [Double] = []
    private let windowSize = 5

    func start(interval: TimeInterval) {
        stop()
        hasPrev = false
        window.removeAll()
        // 首次立即采样建立基线
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard let (idle, total) = Self.readTicks() else { return }
        defer {
            prevIdle = idle
            prevTotal = total
            hasPrev = true
        }
        guard hasPrev, total > prevTotal else { return }

        let idleDelta = Double(idle - prevIdle)
        let totalDelta = Double(total - prevTotal)
        let usage = max(0, min(1, 1.0 - idleDelta / totalDelta))

        window.append(usage)
        if window.count > windowSize { window.removeFirst() }
        let avg = window.reduce(0, +) / Double(window.count)
        onSample?(avg)
    }

    /// 返回 (idle ticks, total ticks)
    private static func readTicks() -> (UInt64, UInt64)? {
        var count = natural_t(0)
        var pointer: processor_info_array_t?
        var infoCount = mach_msg_type_number_t(0)
        let result = host_processor_info(
            mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &pointer, &infoCount)
        guard result == KERN_SUCCESS, let ptr = pointer else { return nil }
        defer {
            let size = vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: ptr)), size)
        }

        let strideCount = Int(infoCount) / Int(CPU_STATE_MAX)
        var idle: UInt64 = 0
        var total: UInt64 = 0
        let base = UnsafeRawPointer(ptr).assumingMemoryBound(to: integer_t.self)
        for core in 0..<strideCount {
            let off = core * Int(CPU_STATE_MAX)
            idle &+= UInt64(base[off + Int(CPU_STATE_IDLE)])
            total &+= UInt64(base[off + Int(CPU_STATE_USER)])
            total &+= UInt64(base[off + Int(CPU_STATE_SYSTEM)])
            total &+= UInt64(base[off + Int(CPU_STATE_IDLE)])
            total &+= UInt64(base[off + Int(CPU_STATE_NICE)])
        }
        return (idle, total)
    }
}
