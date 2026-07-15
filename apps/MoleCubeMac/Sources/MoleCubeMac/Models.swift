import Foundation

enum AppSection: String, CaseIterable, Identifiable {
    case clean
    case uninstall
    case optimize
    case analyze
    case status
    case settings

    var id: String { rawValue }

    static var allCases: [AppSection] {
        [.status, .clean, .uninstall, .analyze]
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case english = "en"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .simplifiedChinese: "简体中文"
        case .traditionalChinese: "繁體中文"
        case .english: "English"
        }
    }
}

enum UninstallFilter: String, CaseIterable, Identifiable {
    case installed
    case extensions

    var id: String { rawValue }
}

struct StatusSnapshot: Decodable {
    var collectedAt: String?
    var host: String?
    var platform: String?
    var uptime: String?
    var uptimeSeconds: UInt64?
    var procs: UInt64?
    var hardware: Hardware?
    var healthScore: Int?
    var healthScoreMessage: String?
    var cpu: CPU?
    var gpu: [GPU]?
    var memory: Memory?
    var disks: [Disk]?
    var trashSize: UInt64?
    var trashApprox: Bool?
    var diskIO: DiskIO?
    var network: [Network]?
    var networkHistory: NetworkHistory?
    var proxy: Proxy?
    var batteries: [Battery]?
    var thermal: Thermal?
    var topProcesses: [ProcessInfo]?

    enum CodingKeys: String, CodingKey {
        case collectedAt = "collected_at"
        case host
        case platform
        case uptime
        case uptimeSeconds = "uptime_seconds"
        case procs
        case hardware
        case healthScore = "health_score"
        case healthScoreMessage = "health_score_msg"
        case cpu
        case gpu
        case memory
        case disks
        case trashSize = "trash_size"
        case trashApprox = "trash_approx"
        case diskIO = "disk_io"
        case network
        case networkHistory = "network_history"
        case proxy
        case batteries
        case thermal
        case topProcesses = "top_processes"
    }

    struct Hardware: Decodable {
        var model: String?
        var cpuModel: String?
        var totalRAM: String?
        var diskSize: String?
        var osVersion: String?
        var refreshRate: String?

        enum CodingKeys: String, CodingKey {
            case model
            case cpuModel = "cpu_model"
            case totalRAM = "total_ram"
            case diskSize = "disk_size"
            case osVersion = "os_version"
            case refreshRate = "refresh_rate"
        }
    }

    struct CPU: Decodable {
        var usage: Double?
        var perCore: [Double]?
        var perCoreEstimated: Bool?
        var load1: Double?
        var load5: Double?
        var load15: Double?
        var coreCount: Int?
        var logicalCPU: Int?
        var pCoreCount: Int?
        var eCoreCount: Int?

        enum CodingKeys: String, CodingKey {
            case usage
            case perCore = "per_core"
            case perCoreEstimated = "per_core_estimated"
            case load1
            case load5
            case load15
            case coreCount = "core_count"
            case logicalCPU = "logical_cpu"
            case pCoreCount = "p_core_count"
            case eCoreCount = "e_core_count"
        }
    }

    struct GPU: Decodable, Identifiable {
        var id: String { name ?? UUID().uuidString }
        var name: String?
        var usage: Double?
        var memoryUsed: Double?
        var memoryTotal: Double?
        var coreCount: Int?
        var note: String?

        enum CodingKeys: String, CodingKey {
            case name
            case usage
            case memoryUsed = "memory_used"
            case memoryTotal = "memory_total"
            case coreCount = "core_count"
            case note
        }
    }

    struct Memory: Decodable {
        var total: UInt64?
        var used: UInt64?
        var available: UInt64?
        var usedPercent: Double?
        var swapUsed: UInt64?
        var swapTotal: UInt64?
        var cached: UInt64?
        var pressure: String?

        enum CodingKeys: String, CodingKey {
            case total
            case used
            case available
            case usedPercent = "used_percent"
            case swapUsed = "swap_used"
            case swapTotal = "swap_total"
            case cached
            case pressure
        }
    }

    struct Disk: Decodable, Identifiable {
        var id: String { mount ?? mountpoint ?? device ?? UUID().uuidString }
        var mount: String?
        var device: String?
        var mountpoint: String?
        var total: UInt64?
        var used: UInt64?
        var free: UInt64?
        var usedPercent: Double?
        var fstype: String?
        var external: Bool?

        var availableBytes: UInt64? {
            if let free { return free }
            guard let total, let used, total >= used else { return nil }
            return total - used
        }

        enum CodingKeys: String, CodingKey {
            case mount
            case device
            case mountpoint
            case total
            case used
            case free
            case usedPercent = "used_percent"
            case fstype
            case external
        }
    }

    struct DiskIO: Decodable {
        var readRate: Double?
        var writeRate: Double?

        enum CodingKeys: String, CodingKey {
            case readRate = "read_rate"
            case writeRate = "write_rate"
        }
    }

    struct Network: Decodable, Identifiable {
        var id: String { name ?? ip ?? UUID().uuidString }
        var name: String?
        var rxRateMBs: Double?
        var txRateMBs: Double?
        var ip: String?

        enum CodingKeys: String, CodingKey {
            case name
            case rxRateMBs = "rx_rate_mbs"
            case txRateMBs = "tx_rate_mbs"
            case ip
        }
    }

    struct NetworkHistory: Decodable {
        var rxHistory: [Double]?
        var txHistory: [Double]?

        enum CodingKeys: String, CodingKey {
            case rxHistory = "rx_history"
            case txHistory = "tx_history"
        }
    }

    struct Proxy: Decodable {
        var enabled: Bool?
        var type: String?
        var host: String?
    }

    struct Battery: Decodable, Identifiable {
        var id: String { "\(status ?? "battery")-\(cycleCount ?? 0)" }
        var percent: Double?
        var status: String?
        var timeLeft: String?
        var health: String?
        var cycleCount: Int?
        var capacity: Int?

        enum CodingKeys: String, CodingKey {
            case percent
            case status
            case timeLeft = "time_left"
            case health
            case cycleCount = "cycle_count"
            case capacity
        }
    }

    struct Thermal: Decodable {
        var cpuTemp: Double?
        var gpuTemp: Double?
        var batteryTemp: Double?
        var fanSpeed: Int?
        var fanCount: Int?
        var systemPower: Double?
        var adapterPower: Double?
        var batteryPower: Double?

        enum CodingKeys: String, CodingKey {
            case cpuTemp = "cpu_temp"
            case gpuTemp = "gpu_temp"
            case batteryTemp = "battery_temp"
            case fanSpeed = "fan_speed"
            case fanCount = "fan_count"
            case systemPower = "system_power"
            case adapterPower = "adapter_power"
            case batteryPower = "battery_power"
        }
    }

    struct ProcessInfo: Decodable, Identifiable {
        var id: String { "\(pid ?? -1)-\(name ?? command ?? "process")" }
        var pid: Int?
        var ppid: Int?
        var name: String?
        var command: String?
        var cpu: Double?
        var memory: Double?
        var memoryBytes: UInt64?

        enum CodingKeys: String, CodingKey {
            case pid
            case ppid
            case name
            case command
            case cpu
            case memory
            case memoryBytes = "memory_bytes"
        }
    }
}

struct AnalyzeOutput: Decodable, Sendable {
    var path: String
    var overview: Bool
    var entries: [AnalyzeEntry]
    var largeFiles: [AnalyzeFile]?
    var totalSize: Int64
    var totalFiles: Int64?

    enum CodingKeys: String, CodingKey {
        case path
        case overview
        case entries
        case largeFiles = "large_files"
        case totalSize = "total_size"
        case totalFiles = "total_files"
    }
}

struct AnalyzeEntry: Decodable, Identifiable, Sendable {
    var id: String { path }
    var name: String
    var path: String
    var size: Int64
    var isDir: Bool
    var insight: Bool?
    var cleanable: Bool?

    enum CodingKeys: String, CodingKey {
        case name
        case path
        case size
        case isDir = "is_dir"
        case insight
        case cleanable
    }
}

struct AnalyzeFile: Decodable, Identifiable, Sendable {
    var id: String { path }
    var name: String
    var path: String
    var size: Int64
}

struct InstalledApp: Decodable, Identifiable {
    var id: String { path.isEmpty ? name : path }
    var name: String
    var bundleID: String
    var source: String
    var uninstallName: String
    var path: String
    var size: String

    enum CodingKeys: String, CodingKey {
        case name
        case bundleID = "bundle_id"
        case source
        case uninstallName = "uninstall_name"
        case path
        case size
    }
}

struct UninstallPreview {
    var appName: String
    var appBundlePath: String?
    var relatedFiles: [String]
    var systemFiles: [String]
    var reviewOnlyFiles: [String]
    var totalSize: String?
    var itemCount: Int
    var rawOutput: String

    var relatedItemCount: Int {
        relatedFiles.count + systemFiles.count + reviewOnlyFiles.count
    }

    var relatedRows: [String] {
        let rows = relatedFiles + systemFiles.map { "System: \($0)" } + reviewOnlyFiles.map { "Review only: \($0)" }
        return rows.isEmpty ? [] : rows
    }

    var supportFiles: [String] {
        relatedFiles.filter { path in
            let lowercased = path.lowercased()
            return lowercased.contains("/application support/") ||
                lowercased.contains("/containers/") ||
                lowercased.contains("/group containers/")
        }
    }

    var cacheFiles: [String] {
        relatedFiles.filter { $0.lowercased().contains("/caches/") }
    }

    var preferenceFiles: [String] {
        relatedFiles.filter { path in
            let lowercased = path.lowercased()
            return lowercased.contains("/preferences/") || lowercased.hasSuffix(".plist")
        }
    }

    var logFiles: [String] {
        relatedFiles.filter { $0.lowercased().contains("/logs/") }
    }

    var otherFiles: [String] {
        let grouped = Set(supportFiles + cacheFiles + preferenceFiles + logFiles)
        return relatedFiles.filter { !grouped.contains($0) }
    }
}

struct HistoryPayload: Decodable {
    var sessions: [HistoryEntry]?
    var deletions: [HistoryEntry]?
}

struct HistoryEntry: Decodable, Identifiable {
    var id = UUID()
    var timestamp: String?
    var command: String?
    var action: String?
    var status: String?
    var path: String?
    var size: String?
    var startedAt: String?
    var endedAt: String?

    enum CodingKeys: String, CodingKey {
        case timestamp
        case command
        case action
        case status
        case path
        case size
        case startedAt = "started_at"
        case endedAt = "ended_at"
    }
}

struct CleanCategory: Identifiable {
    let id = UUID()
    let nameKey: String
    let detailKey: String
    var sizeBytes: Int64?
    let riskKey: String
    var selected: Bool
    var detailItems: [CleanCategoryDetail] = []
}

struct CleanCategorySize: Sendable {
    let nameKey: String
    let sizeBytes: Int64
    let detailItems: [CleanCategoryDetail]
}

struct CleanCategoryDetail: Identifiable, Sendable {
    var id: String { path }
    let path: String
    let sizeBytes: Int64
}

struct CleanPreviewItem: Identifiable {
    let id = UUID()
    let text: String
    let isPath: Bool
}

struct PermissionStatus: Sendable {
    var fullDiskAccessGranted: Bool? = nil
    var sudoSessionAvailable: Bool? = nil
}

extension Int64 {
    var formattedBytes: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}

extension UInt64 {
    var formattedBytes: String {
        ByteCountFormatter.string(fromByteCount: Int64(self), countStyle: .file)
    }
}
