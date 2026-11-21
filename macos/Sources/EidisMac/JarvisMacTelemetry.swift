import Foundation
import Combine
import Darwin
import IOKit.ps

/// Only local OS counters. A fresh sample is taken while the overview is visible.
struct JarvisMacTelemetry {
    var cpuPercent: Double?
    var memoryBytes: UInt64?
    var totalMemory: UInt64
    var diskUsed: UInt64?
    var diskAvailable: UInt64?
    var diskTotal: UInt64?
    var batteryPercent: Int?
    var powerSource: String
    var thermal: String
    var sampledAt: Date
}

@MainActor final class JarvisMacSampler: ObservableObject {
    @Published private(set) var current: JarvisMacTelemetry?
    private var previous: [UInt32]?
    func reset() { previous = nil; current = nil }
    func sample() {
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        var load = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let code = withUnsafeMutablePointer(to: &load) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        var cpu: Double?
        if code == KERN_SUCCESS {
            let ticks = [load.cpu_ticks.0, load.cpu_ticks.1, load.cpu_ticks.2, load.cpu_ticks.3]
            if let previous {
                let d = zip(ticks, previous).map { UInt64($0.0 &- $0.1) }
                let total = d.reduce(0,+)
                if total > 0 { cpu = 100 * Double(total - d[Int(CPU_STATE_IDLE)]) / Double(total) }
            }
            previous = ticks
        } else { previous = nil }
        var vm = vm_statistics64()
        var vmCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let vmCode = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &vmCount)
            }
        }
        let totalRAM = ProcessInfo.processInfo.physicalMemory
        // Non-purgeable active/inactive + wired + compressed, as an explicitly
        // labelled VM estimate rather than an imitation of Activity Monitor.
        var ram: UInt64?
        if vmCode == KERN_SUCCESS {
            let resident = UInt64(vm.active_count) + UInt64(vm.inactive_count) + UInt64(vm.wire_count) + UInt64(vm.compressor_page_count)
            let reclaimable = UInt64(vm.purgeable_count) + UInt64(vm.external_page_count)
            ram = min(totalRAM, (resident - min(resident, reclaimable)) * UInt64(vm_kernel_page_size))
        }
        var fs = statfs()
        let diskOK = statfs("/System/Volumes/Data", &fs) == 0
        let block = UInt64(fs.f_bsize)
        let used = diskOK ? (fs.f_blocks - min(fs.f_blocks, fs.f_bfree)) * block : nil
        let available = diskOK ? fs.f_bavail * block : nil
        let total = diskOK ? fs.f_blocks * block : nil
        var battery: Int?
        var power = "확인 불가"
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() {
            power = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? ?? "확인 불가"
            if let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
                for source in sources {
                    if let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String:Any],
                       desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                       let value = desc[kIOPSCurrentCapacityKey] as? Int,
                       let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0 {
                        battery = Int((Double(value) / Double(max) * 100).rounded())
                        break
                    }
                }
            }
        }
        let thermal: String
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermal = "정상"
        case .fair: thermal = "상승"
        case .serious: thermal = "높음"
        case .critical: thermal = "위험"
        @unknown default: thermal = "미확인"
        }
        current = JarvisMacTelemetry(cpuPercent: cpu, memoryBytes: ram, totalMemory: totalRAM,
                                     diskUsed: used, diskAvailable: available, diskTotal: total,
                                     batteryPercent: battery, powerSource: power, thermal: thermal, sampledAt: Date())
    }
}
