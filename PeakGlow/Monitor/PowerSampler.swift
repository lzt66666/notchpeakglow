import IOKit
import Foundation

/// SMC 整机功率采样（Apple Silicon: "PSTR" 键, flt 类型, 单位 W）。
/// 调用方式与开源项目 stats 一致：selector=2 (kernelIndex)，data8 承载子命令。
/// 用户态 IOKit 调用，无需任何权限。
final class PowerSampler {
    // 与 SMC 驱动约定的结构体布局（字段顺序/类型不可改动）
    private struct SMCKeyData {
        typealias SMCBytes = (
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)

        struct Vers {
            var major: UInt8 = 0
            var minor: UInt8 = 0
            var build: UInt8 = 0
            var reserved: UInt8 = 0
            var release: UInt16 = 0
        }
        struct LimitData {
            var version: UInt16 = 0
            var length: UInt16 = 0
            var cpuPLimit: UInt32 = 0
            var gpuPLimit: UInt32 = 0
            var memPLimit: UInt32 = 0
        }
        struct KeyInfo {
            var dataSize: UInt32 = 0
            var dataType: UInt32 = 0
            var dataAttributes: UInt8 = 0
        }

        var key: UInt32 = 0
        var vers = Vers()
        var pLimitData = LimitData()
        var keyInfo = KeyInfo()
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes = SMCBytes(
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    private var conn: io_connect_t = 0
    private var opened = false

    private static let kernelIndex: UInt8 = 2
    private static let readKeyInfo: UInt8 = 9
    private static let readBytes: UInt8 = 5
    private static let typeFloat: UInt32 = 0x66_6C_74_20  // 'flt '

    /// 返回整机功率（W），不可用返回 nil
    func readWatts() -> Double? {
        guard openIfNeeded() else { return nil }
        guard let data = readKey("PSTR"), data.count >= 4 else { return nil }

        // flt 数据按主机字节序（小端）load（与 stats 的解析一致）
        let bits = UInt32(data[0])
            | UInt32(data[1]) << 8
            | UInt32(data[2]) << 16
            | UInt32(data[3]) << 24
        let watts = Float32(bitPattern: bits)
        guard watts.isFinite, watts >= 0, watts < 500 else { return nil }
        return Double(watts)
    }

    // MARK: - SMC 两步读取

    private func readKey(_ keyStr: String) -> [UInt8]? {
        let key: UInt32 = keyStr.utf8.reduce(0) { $0 << 8 | UInt32($1) }

        var input = SMCKeyData()
        var output = SMCKeyData()

        // 第一步：查 keyInfo（大小/类型）
        input.key = key
        input.data8 = Self.readKeyInfo
        var kr = call(Self.kernelIndex, input: &input, output: &output)
        guard kr == KERN_SUCCESS, output.keyInfo.dataSize > 0 else { return nil }

        // 第二步：读数据
        let size = Int(min(output.keyInfo.dataSize, 32))
        let dataType = output.keyInfo.dataType
        input.keyInfo.dataSize = output.keyInfo.dataSize
        input.data8 = Self.readBytes
        kr = call(Self.kernelIndex, input: &input, output: &output)
        guard kr == KERN_SUCCESS else { return nil }
        guard dataType == Self.typeFloat else { return nil }

        return withUnsafeBytes(of: output.bytes) { raw in
            Array(raw.prefix(size))
        }
    }

    private func call(_ index: UInt8,
                      input: inout SMCKeyData, output: inout SMCKeyData) -> kern_return_t {
        let size = MemoryLayout<SMCKeyData>.stride
        var outSize = size
        return withUnsafeMutablePointer(to: &input) { inPtr in
            withUnsafeMutablePointer(to: &output) { outPtr in
                IOConnectCallStructMethod(
                    conn, UInt32(index),
                    inPtr, size,
                    outPtr, &outSize)
            }
        }
    }

    private func openIfNeeded() -> Bool {
        if opened { return conn != 0 }
        opened = true
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != IO_OBJECT_NULL else { return false }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &conn) == KERN_SUCCESS else {
            conn = 0
            return false
        }
        return true
    }

    deinit {
        if conn != 0 {
            IOServiceClose(conn)
        }
    }
}
