import Darwin
import AppKit
import Foundation
import SystemConfiguration

enum CLIError: LocalizedError {
    case repositoryNotFound
    case commandFailed(String)
    case invalidOutput(String)
    case commandTimedOut(String)

    var errorDescription: String? {
        switch self {
        case .repositoryNotFound:
            "Could not find the Mole repository root."
        case let .commandFailed(message):
            message
        case let .invalidOutput(message):
            message
        case let .commandTimedOut(command):
            "\(command) timed out. The task was stopped so the app can continue."
        }
    }
}

struct CLIResult: Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

private final class ProcessBox: @unchecked Sendable {
    let process: Process

    init(_ process: Process) {
        self.process = process
    }
}

private final class ProcessRunState: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false
    private let continuation: CheckedContinuation<CLIResult, Error>
    private let stdout: FileHandle
    private let stderr: FileHandle
    private let stdoutURL: URL
    private let stderrURL: URL

    init(
        continuation: CheckedContinuation<CLIResult, Error>,
        stdout: FileHandle,
        stderr: FileHandle,
        stdoutURL: URL,
        stderrURL: URL
    ) {
        self.continuation = continuation
        self.stdout = stdout
        self.stderr = stderr
        self.stdoutURL = stdoutURL
        self.stderrURL = stderrURL
    }

    func readResult(exitCode: Int32) -> CLIResult {
        let stdoutData = (try? Data(contentsOf: stdoutURL)) ?? Data()
        let stderrData = (try? Data(contentsOf: stderrURL)) ?? Data()
        return CLIResult(
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? "",
            exitCode: exitCode
        )
    }

    func finish(_ result: Result<CLIResult, Error>) {
        lock.lock()
        guard !didResume else {
            lock.unlock()
            return
        }
        didResume = true
        lock.unlock()

        try? stdout.close()
        try? stderr.close()
        defer {
            try? FileManager.default.removeItem(at: stdoutURL)
            try? FileManager.default.removeItem(at: stderrURL)
        }

        switch result {
        case let .success(value):
            continuation.resume(returning: value)
        case let .failure(error):
            continuation.resume(throwing: error)
        }
    }
}

actor LocalCLIBackend {
    private struct NetworkCounter {
        var rxBytes: UInt64
        var txBytes: UInt64
        var timestamp: Date
    }

    private let fileManager = FileManager.default
    let repositoryRoot: URL
    private var previousNetworkCounters: [String: NetworkCounter] = [:]
    private var previousCPUTicks: [natural_t]?
    private var rxHistory: [Double] = []
    private var txHistory: [Double] = []
    private var cachedGPU: [StatusSnapshot.GPU] = []
    private var lastGPUAt: Date?

    init() throws {
        guard let root = Self.findRepositoryRoot() else {
            throw CLIError.repositoryNotFound
        }
        repositoryRoot = root
    }

    func status() async throws -> StatusSnapshot {
        var snapshot: StatusSnapshot
        if fileManager.isExecutableFile(atPath: repositoryRoot.appending(path: "bin/status-go").path) {
            let output = try await runExecutable(repositoryRoot.appending(path: "bin/status-go"), arguments: ["--json"]).stdout
            snapshot = try decode(StatusSnapshot.self, from: output)
        } else {
            return try await localStatusSnapshot()
        }

        let liveNetwork = localNetworkSnapshot()
        if !liveNetwork.isEmpty {
            snapshot.network = liveNetwork
            snapshot.networkHistory = StatusSnapshot.NetworkHistory(rxHistory: rxHistory, txHistory: txHistory)
        }
        if snapshot.batteries?.isEmpty ?? true {
            snapshot.batteries = await localBatterySnapshot()
        }
        if snapshot.proxy?.enabled == nil {
            snapshot.proxy = localProxySnapshot()
        }
        if snapshot.topProcesses?.isEmpty ?? true {
            snapshot.topProcesses = await localTopProcesses()
        }
        return snapshot
    }

    func analyze(path: String? = nil) async throws -> AnalyzeOutput {
        var arguments = ["--json"]
        if let path, !path.isEmpty {
            arguments.append(path)
        }

        let output: String
        if fileManager.isExecutableFile(atPath: repositoryRoot.appending(path: "bin/analyze-go").path) {
            output = try await runExecutable(repositoryRoot.appending(path: "bin/analyze-go"), arguments: arguments).stdout
        } else if let go = findExecutable(named: "go") {
            output = try await run(go.path, arguments: ["run", "./cmd/analyze"] + arguments).stdout
        } else {
            return try await localAnalyze(path: path)
        }
        return try decode(AnalyzeOutput.self, from: output)
    }

    private func localAnalyze(path: String? = nil) async throws -> AnalyzeOutput {
        let targetPath = path.flatMap { $0.isEmpty ? nil : $0 } ?? FileManager.default.homeDirectoryForCurrentUser.path

        return await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager()
            let rootURL = URL(filePath: targetPath).standardizedFileURL
            let keys: Set<URLResourceKey> = [
                .isDirectoryKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .fileSizeKey,
                .fileAllocatedSizeKey,
                .totalFileSizeKey,
                .totalFileAllocatedSizeKey
            ]
            let children = (try? fileManager.contentsOfDirectory(
                at: rootURL,
                includingPropertiesForKeys: Array(keys),
                options: []
            )) ?? []
            let largeFileThreshold: Int64 = 50 * 1024 * 1024
            let maxVisitedItems = 220_000
            var visitedItems = 0
            var entries: [AnalyzeEntry] = []
            var largeFiles: [AnalyzeFile] = []
            var totalFiles: Int64 = 0

            func allocatedSize(for values: URLResourceValues) -> Int64 {
                let size = values.totalFileAllocatedSize ??
                    values.fileAllocatedSize ??
                    values.totalFileSize ??
                    values.fileSize ??
                    0
                return Int64(max(0, size))
            }

            func scanDirectory(_ directoryURL: URL) -> (size: Int64, files: Int64, largeFiles: [AnalyzeFile]) {
                guard visitedItems < maxVisitedItems else {
                    return (0, 0, [])
                }

                var size: Int64 = 0
                var files: Int64 = 0
                var foundLargeFiles: [AnalyzeFile] = []
                guard let enumerator = fileManager.enumerator(
                    at: directoryURL,
                    includingPropertiesForKeys: Array(keys),
                    options: [.skipsPackageDescendants],
                    errorHandler: { _, _ in true }
                ) else {
                    return (0, 0, [])
                }

                for case let url as URL in enumerator {
                    visitedItems += 1
                    if visitedItems >= maxVisitedItems {
                        break
                    }

                    guard let values = try? url.resourceValues(forKeys: keys),
                          values.isSymbolicLink != true else {
                        continue
                    }

                    if values.isRegularFile == true {
                        files += 1
                        let fileSize = allocatedSize(for: values)
                        size += fileSize
                        if fileSize >= largeFileThreshold {
                            foundLargeFiles.append(AnalyzeFile(
                                name: url.lastPathComponent,
                                path: url.path,
                                size: fileSize
                            ))
                        }
                    } else if values.isDirectory != true {
                        size += allocatedSize(for: values)
                    }
                }

                return (size, files, foundLargeFiles)
            }

            for child in children {
                guard let values = try? child.resourceValues(forKeys: keys),
                      values.isSymbolicLink != true else {
                    continue
                }

                if values.isDirectory == true {
                    let result = scanDirectory(child)
                    entries.append(AnalyzeEntry(
                        name: child.lastPathComponent,
                        path: child.path,
                        size: result.size,
                        isDir: true,
                        insight: false,
                        cleanable: false
                    ))
                    totalFiles += result.files
                    largeFiles.append(contentsOf: result.largeFiles)
                } else if values.isRegularFile == true {
                    let fileSize = allocatedSize(for: values)
                    entries.append(AnalyzeEntry(
                        name: child.lastPathComponent,
                        path: child.path,
                        size: fileSize,
                        isDir: false,
                        insight: false,
                        cleanable: false
                    ))
                    totalFiles += 1
                    if fileSize >= largeFileThreshold {
                        largeFiles.append(AnalyzeFile(
                            name: child.lastPathComponent,
                            path: child.path,
                            size: fileSize
                        ))
                    }
                }
            }

            let sortedEntries = entries.sorted { $0.size > $1.size }
            let sortedLargeFiles = largeFiles.sorted { $0.size > $1.size }

            return AnalyzeOutput(
                path: rootURL.path,
                overview: path == nil,
                entries: sortedEntries,
                largeFiles: Array(sortedLargeFiles.prefix(100)),
                totalSize: sortedEntries.reduce(0) { $0 + $1.size },
                totalFiles: totalFiles
            )
        }.value
    }

    func installedApps() async throws -> [InstalledApp] {
        let result = try await runMole(arguments: ["uninstall", "--list"], disablesOperationLog: true)
        return try decode([InstalledApp].self, from: result.stdout)
    }

    func history() async throws -> HistoryPayload {
        let result = try await runMole(arguments: ["history", "--json"])
        return try decode(HistoryPayload.self, from: result.stdout)
    }

    func cleanDryRunPreview() async throws -> String {
        let result = try await runMole(arguments: ["clean", "--dry-run"], timeoutSeconds: 120, disablesOperationLog: true)
        return result.stdout
    }

    func cleanNow() async throws -> String {
        let result = try await runMole(arguments: ["clean"], timeoutSeconds: 300)
        return [result.stdout, result.stderr]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
    }

    func cleanCategory(displayName: String, paths: [String]) async throws -> String {
        let home = fileManager.homeDirectoryForCurrentUser.standardizedFileURL.path
        var moved: [String] = []
        var skipped: [String] = []
        var failures: [String] = []

        for path in paths {
            let url = URL(fileURLWithPath: path).standardizedFileURL
            let standardizedPath = url.path
            guard isUserCleanPath(standardizedPath, home: home), fileManager.fileExists(atPath: standardizedPath) else {
                skipped.append(standardizedPath)
                continue
            }

            do {
                var resultingURL: NSURL?
                try fileManager.trashItem(at: url, resultingItemURL: &resultingURL)
                moved.append(standardizedPath)
            } catch {
                failures.append("\(standardizedPath): \(error.localizedDescription)")
            }
        }

        var lines = ["\(displayName) cleanup finished."]
        lines.append("Moved to Trash: \(moved.count)")
        if !moved.isEmpty {
            lines.append(contentsOf: moved.map { "  moved: \($0)" })
        }
        if !skipped.isEmpty {
            lines.append("Skipped: \(skipped.count)")
            lines.append(contentsOf: skipped.map { "  - \($0)" })
        }
        if !failures.isEmpty {
            lines.append("Failed: \(failures.count)")
            lines.append(contentsOf: failures.map { "  ! \($0)" })
        }
        return lines.joined(separator: "\n")
    }

    func moveAnalyzeItemToTrash(path: String) async throws -> String {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let standardizedPath = url.path

        guard fileManager.fileExists(atPath: standardizedPath) else {
            throw CLIError.commandFailed("Path no longer exists: \(standardizedPath)")
        }
        guard isSafeAnalyzeTrashPath(standardizedPath) else {
            throw CLIError.commandFailed("Mole refused to move this protected path to Trash: \(standardizedPath)")
        }

        let resultingPath: String? = try await withCheckedThrowingContinuation { continuation in
            NSWorkspace.shared.recycle([url]) { recycledURLs, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: recycledURLs[url]?.path)
                }
            }
        }

        return [
            "Moved to Trash: 1",
            "  moved: \(standardizedPath)",
            resultingPath.map { "  trash: \($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }

    func permissionStatus() async -> PermissionStatus {
        async let fullDisk = fullDiskAccessGranted()
        async let sudo = sudoSessionAvailable()
        return await PermissionStatus(fullDiskAccessGranted: fullDisk, sudoSessionAvailable: sudo)
    }

    func optimizePreview() async throws -> String {
        let result = try await runMole(arguments: ["optimize", "--dry-run"], timeoutSeconds: 180)
        return [result.stdout, result.stderr]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
    }

    func optimizeWithAdministratorPrivileges() async throws -> String {
        if ProcessInfo.processInfo.environment["MOLE_TEST_MODE"] == "1" ||
            ProcessInfo.processInfo.environment["MOLE_TEST_NO_AUTH"] == "1" {
            throw CLIError.commandFailed("Administrator authorization is disabled in test mode.")
        }

        let command = privilegedShellCommand(arguments: ["optimize"])
        let script = "do shell script \(appleScriptLiteral(command)) with administrator privileges"
        let result = try await runExecutable(
            URL(filePath: "/usr/bin/osascript"),
            arguments: ["-e", script],
            timeoutSeconds: 600,
            disablesAuthentication: false
        )
        return [result.stdout, result.stderr]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
    }

    func cleanCategorySizes() async -> [CleanCategorySize] {
        var snapshots: [CleanCategorySize] = []
        for category in cleanCategoryPaths() {
            var size: Int64 = 0
            var detailItems: [CleanCategoryDetail] = []
            for path in category.paths {
                let itemSize = await diskUsageBytes(for: path)
                guard itemSize > 0 else { continue }
                size += itemSize
                detailItems.append(CleanCategoryDetail(path: path, sizeBytes: itemSize))
            }
            snapshots.append(CleanCategorySize(nameKey: category.nameKey, sizeBytes: size, detailItems: detailItems))
        }
        return snapshots
    }

    func uninstallDryRunPreview(appName: String, autoConfirm: Bool = false) async throws -> String {
        let result = try await runMole(
            arguments: ["uninstall", "--dry-run", appName],
            timeoutSeconds: 180,
            standardInput: autoConfirm ? "y\n" : nil,
            disablesOperationLog: true
        )
        return result.stdout
    }

    func uninstallApp(appName: String) async throws -> String {
        let result = try await runMole(
            arguments: ["uninstall", appName],
            timeoutSeconds: 300,
            standardInput: "y\n",
            disablesAuthentication: false
        )
        return result.stdout
    }

    func runMoleCommand(arguments: [String], timeoutSeconds: TimeInterval = 90, standardInput: String? = nil) async throws -> String {
        let result = try await runMole(arguments: arguments, timeoutSeconds: timeoutSeconds, standardInput: standardInput)
        let output = [result.stdout, result.stderr]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
        return output
    }

    private func runMole(
        arguments: [String],
        timeoutSeconds: TimeInterval = 90,
        standardInput: String? = nil,
        disablesOperationLog: Bool = false,
        disablesAuthentication: Bool = true
    ) async throws -> CLIResult {
        try await runExecutable(
            repositoryRoot.appending(path: "mole"),
            arguments: arguments,
            timeoutSeconds: timeoutSeconds,
            standardInput: standardInput,
            disablesOperationLog: disablesOperationLog,
            disablesAuthentication: disablesAuthentication
        )
    }

    private func runExecutable(
        _ executable: URL,
        arguments: [String],
        timeoutSeconds: TimeInterval = 90,
        standardInput: String? = nil,
        disablesOperationLog: Bool = false,
        disablesAuthentication: Bool = true
    ) async throws -> CLIResult {
        try await run(
            executable.path,
            arguments: arguments,
            timeoutSeconds: timeoutSeconds,
            standardInput: standardInput,
            disablesOperationLog: disablesOperationLog,
            disablesAuthentication: disablesAuthentication
        )
    }

    private func run(
        _ executable: String,
        arguments: [String],
        timeoutSeconds: TimeInterval = 90,
        standardInput: String? = nil,
        disablesOperationLog: Bool = false,
        disablesAuthentication: Bool = true
    ) async throws -> CLIResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(filePath: executable)
            process.arguments = arguments
            process.currentDirectoryURL = repositoryRoot
            process.environment = processEnvironment(
                disablesOperationLog: disablesOperationLog,
                disablesAuthentication: disablesAuthentication
            )
            let stdin = Pipe()
            process.standardInput = stdin

            let temporaryDirectory = FileManager.default.temporaryDirectory
            let id = UUID().uuidString
            let stdoutURL = temporaryDirectory.appending(path: "molecube-\(id)-stdout.log")
            let stderrURL = temporaryDirectory.appending(path: "molecube-\(id)-stderr.log")
            FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
            FileManager.default.createFile(atPath: stderrURL.path, contents: nil)

            guard let stdout = try? FileHandle(forWritingTo: stdoutURL),
                  let stderr = try? FileHandle(forWritingTo: stderrURL) else {
                continuation.resume(throwing: CLIError.commandFailed("Could not create command output files."))
                return
            }

            process.standardOutput = stdout
            process.standardError = stderr

            let state = ProcessRunState(
                continuation: continuation,
                stdout: stdout,
                stderr: stderr,
                stdoutURL: stdoutURL,
                stderrURL: stderrURL
            )
            let processBox = ProcessBox(process)

            process.terminationHandler = { process in
                let result = state.readResult(exitCode: process.terminationStatus)

                if process.terminationStatus == 0 {
                    state.finish(.success(result))
                } else {
                    let message = result.stderr.isEmpty ? result.stdout : result.stderr
                    state.finish(.failure(CLIError.commandFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))))
                }
            }

            do {
                try process.run()
                if let standardInput {
                    stdin.fileHandleForWriting.write(Data(standardInput.utf8))
                }
                try? stdin.fileHandleForWriting.close()
                Task.detached {
                    try? await Task.sleep(for: .seconds(timeoutSeconds))
                    if processBox.process.isRunning {
                        processBox.process.terminate()
                        try? await Task.sleep(for: .seconds(2))
                    }
                    if processBox.process.isRunning {
                        processBox.process.interrupt()
                        try? await Task.sleep(for: .seconds(1))
                    }
                    if processBox.process.isRunning {
                        processBox.process.terminate()
                    }
                    state.finish(.failure(CLIError.commandTimedOut(([executable] + arguments).joined(separator: " "))))
                }
            } catch {
                state.finish(.failure(error))
            }
        }
    }

    private func localStatusSnapshot() async throws -> StatusSnapshot {
        let disk = try localDiskSnapshot()
        let memory = try await localMemorySnapshot()
        let network = localNetworkSnapshot()
        let batteries = await localBatterySnapshot()
        let topProcesses = await localTopProcesses()
        let gpu = await localGPUSnapshot()
        let logicalCPU = ProcessInfo.processInfo.activeProcessorCount
        let load = currentLoadAverage()
        let cpuUsage = currentCPUUsage() ?? min(max(load / Double(max(logicalCPU, 1)) * 100, 0), 100)
        let healthScore = computeHealthScore(diskUsage: disk.usedPercent, memoryUsage: memory?.usedPercent, cpuUsage: cpuUsage)

        return StatusSnapshot(
            collectedAt: nil,
            host: Host.current().localizedName,
            platform: "macOS",
            uptime: formatUptime(ProcessInfo.processInfo.systemUptime),
            uptimeSeconds: UInt64(ProcessInfo.processInfo.systemUptime),
            procs: UInt64(topProcesses.count),
            hardware: nil,
            healthScore: healthScore,
            healthScoreMessage: nil,
            cpu: StatusSnapshot.CPU(
                usage: cpuUsage,
                perCore: nil,
                perCoreEstimated: nil,
                load1: load,
                load5: nil,
                load15: nil,
                coreCount: logicalCPU,
                logicalCPU: logicalCPU,
                pCoreCount: nil,
                eCoreCount: nil
            ),
            gpu: gpu,
            memory: memory,
            disks: [disk],
            trashSize: nil,
            trashApprox: nil,
            diskIO: nil,
            network: network,
            networkHistory: network.isEmpty ? nil : StatusSnapshot.NetworkHistory(
                rxHistory: rxHistory,
                txHistory: txHistory
            ),
            proxy: localProxySnapshot(),
            batteries: batteries,
            thermal: nil,
            topProcesses: topProcesses
        )
    }

    private func localDiskSnapshot() throws -> StatusSnapshot.Disk {
        let path = FileManager.default.homeDirectoryForCurrentUser.path
        let attributes = try fileManager.attributesOfFileSystem(forPath: path)
        let total = (attributes[.systemSize] as? NSNumber)?.uint64Value ?? 0
        let free = (attributes[.systemFreeSize] as? NSNumber)?.uint64Value ?? 0
        let used = total > free ? total - free : 0
        let usedPercent = total > 0 ? Double(used) / Double(total) * 100 : 0
        return StatusSnapshot.Disk(
            mount: "/",
            device: nil,
            mountpoint: "/",
            total: total,
            used: used,
            free: free,
            usedPercent: usedPercent,
            fstype: nil,
            external: false
        )
    }

    private func localMemorySnapshot() async throws -> StatusSnapshot.Memory? {
        let total = ProcessInfo.processInfo.physicalMemory
        guard total > 0 else { return nil }

        do {
            let output = try await run("/usr/bin/vm_stat", arguments: []).stdout
            let pageSize = parseVMStatPageSize(output) ?? 4096
            let pages = parseVMStatPages(output)
            let active = pages["Pages active"] ?? 0
            let inactive = pages["Pages inactive"] ?? 0
            let wired = pages["Pages wired down"] ?? 0
            let compressed = pages["Pages occupied by compressor"] ?? 0
            let usedPages = active + inactive + wired + compressed
            let used = min(usedPages * pageSize, total)
            let usedPercent = Double(used) / Double(total) * 100
            return StatusSnapshot.Memory(
                total: total,
                used: used,
                available: total > used ? total - used : 0,
                usedPercent: usedPercent,
                swapUsed: nil,
                swapTotal: nil,
                cached: nil,
                pressure: nil
            )
        } catch {
            return nil
        }
    }

    private func currentCPUUsage() -> Double? {
        var cpuInfo = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &cpuInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return nil }
        let ticks = [
            cpuInfo.cpu_ticks.0,
            cpuInfo.cpu_ticks.1,
            cpuInfo.cpu_ticks.2,
            cpuInfo.cpu_ticks.3
        ]

        guard let previousCPUTicks else {
            self.previousCPUTicks = ticks
            return nil
        }
        self.previousCPUTicks = ticks

        let deltas = zip(ticks, previousCPUTicks).map { current, previous in
            current >= previous ? Double(current - previous) : 0
        }
        let total = deltas.reduce(0, +)
        guard total > 0 else { return nil }
        let idle = deltas[Int(CPU_STATE_IDLE)]
        return min(max((total - idle) / total * 100, 0), 100)
    }

    private func localGPUSnapshot() async -> [StatusSnapshot.GPU]? {
        if let lastGPUAt, Date().timeIntervalSince(lastGPUAt) < 600, !cachedGPU.isEmpty {
            return cachedGPU
        }

        do {
            let output = try await run("/usr/sbin/system_profiler", arguments: ["-json", "SPDisplaysDataType"], timeoutSeconds: 4).stdout
            let gpus = try decodeSystemProfilerGPU(output)
            if !gpus.isEmpty {
                cachedGPU = gpus
                lastGPUAt = Date()
                return gpus
            }
        } catch {
            return cachedGPU.isEmpty ? nil : cachedGPU
        }

        return cachedGPU.isEmpty ? nil : cachedGPU
    }

    private func decodeSystemProfilerGPU(_ output: String) throws -> [StatusSnapshot.GPU] {
        struct Payload: Decodable {
            var displays: [Display]

            enum CodingKeys: String, CodingKey {
                case displays = "SPDisplaysDataType"
            }
        }
        struct Display: Decodable {
            var name: String?
            var vram: String?
            var vendor: String?
            var metal: String?
            var cores: String?

            enum CodingKeys: String, CodingKey {
                case name = "_name"
                case vram = "spdisplays_vram"
                case vendor = "spdisplays_vendor"
                case metal = "spdisplays_metal"
                case cores = "sppci_cores"
            }
        }

        guard let data = output.data(using: .utf8) else { return [] }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        return payload.displays.compactMap { display in
            guard let name = display.name, !name.isEmpty else { return nil }
            let note = [display.vram.map { "VRAM \($0)" }, display.metal, display.vendor]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
            return StatusSnapshot.GPU(
                name: name,
                usage: nil,
                memoryUsed: nil,
                memoryTotal: nil,
                coreCount: display.cores.flatMap(Int.init),
                note: note.isEmpty ? nil : note
            )
        }
    }

    private func localNetworkSnapshot() -> [StatusSnapshot.Network] {
        let now = Date()
        let counters = collectInterfaceCounters()
        let ips = collectInterfaceIPs()
        var snapshots: [StatusSnapshot.Network] = []
        var totalRxRate = 0.0
        var totalTxRate = 0.0

        for (name, counter) in counters.sorted(by: { $0.key < $1.key }) {
            guard name != "lo0" else { continue }
            let previous = previousNetworkCounters[name]
            let elapsed = previous.map { max(now.timeIntervalSince($0.timestamp), 0.001) } ?? 0
            let rxRate = previous.map { bytesPerSecond(current: counter.rxBytes, previous: $0.rxBytes, elapsed: elapsed) / 1_048_576 } ?? 0
            let txRate = previous.map { bytesPerSecond(current: counter.txBytes, previous: $0.txBytes, elapsed: elapsed) / 1_048_576 } ?? 0
            let ip = ips[name]

            if ip != nil || rxRate > 0 || txRate > 0 {
                totalRxRate += rxRate
                totalTxRate += txRate
                snapshots.append(
                    StatusSnapshot.Network(
                        name: name,
                        rxRateMBs: rxRate,
                        txRateMBs: txRate,
                        ip: ip
                    )
                )
            }
        }

        previousNetworkCounters = counters.mapValues {
            NetworkCounter(rxBytes: $0.rxBytes, txBytes: $0.txBytes, timestamp: now)
        }
        appendNetworkHistory(rx: totalRxRate, tx: totalTxRate)

        return snapshots.isEmpty ? ips.sorted(by: { $0.key < $1.key }).map {
            StatusSnapshot.Network(name: $0.key, rxRateMBs: 0, txRateMBs: 0, ip: $0.value)
        } : snapshots
    }

    private func localProxySnapshot() -> StatusSnapshot.Proxy {
        guard let proxies = SCDynamicStoreCopyProxies(nil) as? [String: Any] else {
            return StatusSnapshot.Proxy(enabled: false, type: nil, host: nil)
        }

        let candidates: [(enableKey: String, type: String, hostKey: String?)] = [
            (kSCPropNetProxiesSOCKSEnable as String, "SOCKS", kSCPropNetProxiesSOCKSProxy as String),
            (kSCPropNetProxiesHTTPEnable as String, "HTTP", kSCPropNetProxiesHTTPProxy as String),
            (kSCPropNetProxiesHTTPSEnable as String, "HTTPS", kSCPropNetProxiesHTTPSProxy as String),
            (kSCPropNetProxiesProxyAutoConfigEnable as String, "PAC", kSCPropNetProxiesProxyAutoConfigURLString as String),
            (kSCPropNetProxiesProxyAutoDiscoveryEnable as String, "WPAD", nil)
        ]

        for candidate in candidates where proxyFlag(proxies[candidate.enableKey]) {
            let host = candidate.hostKey.flatMap { proxies[$0] as? String }
            return StatusSnapshot.Proxy(enabled: true, type: candidate.type, host: host)
        }

        return StatusSnapshot.Proxy(enabled: false, type: nil, host: nil)
    }

    private func proxyFlag(_ value: Any?) -> Bool {
        if let number = value as? NSNumber {
            return number.intValue != 0
        }
        if let bool = value as? Bool {
            return bool
        }
        return false
    }

    private func collectInterfaceCounters() -> [String: (rxBytes: UInt64, txBytes: UInt64)] {
        var result: [String: (rxBytes: UInt64, txBytes: UInt64)] = [:]
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let firstAddress = addresses else { return result }
        defer { freeifaddrs(firstAddress) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = firstAddress
        while let current = cursor {
            let interface = current.pointee
            defer { cursor = interface.ifa_next }

            guard let address = interface.ifa_addr,
                  Int32(address.pointee.sa_family) == AF_LINK,
                  let rawData = interface.ifa_data else {
                continue
            }

            let name = String(cString: interface.ifa_name)
            let data = rawData.assumingMemoryBound(to: if_data.self).pointee
            result[name] = (UInt64(data.ifi_ibytes), UInt64(data.ifi_obytes))
        }

        return result
    }

    private func collectInterfaceIPs() -> [String: String] {
        var result: [String: String] = [:]
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let firstAddress = addresses else { return result }
        defer { freeifaddrs(firstAddress) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = firstAddress
        while let current = cursor {
            let interface = current.pointee
            defer { cursor = interface.ifa_next }

            guard let address = interface.ifa_addr,
                  Int32(address.pointee.sa_family) == AF_INET else {
                continue
            }

            let name = String(cString: interface.ifa_name)
            guard name != "lo0" else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let resultCode = getnameinfo(
                address,
                socklen_t(address.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            if resultCode == 0 {
                let hostLength = host.firstIndex(of: 0) ?? host.count
                result[name] = String(decoding: host.prefix(hostLength).map(UInt8.init(bitPattern:)), as: UTF8.self)
            }
        }

        return result
    }

    private func bytesPerSecond(current: UInt64, previous: UInt64, elapsed: TimeInterval) -> Double {
        guard current >= previous else { return 0 }
        return Double(current - previous) / elapsed
    }

    private func appendNetworkHistory(rx: Double, tx: Double) {
        rxHistory.append(rx)
        txHistory.append(tx)
        if rxHistory.count > 60 {
            rxHistory.removeFirst(rxHistory.count - 60)
        }
        if txHistory.count > 60 {
            txHistory.removeFirst(txHistory.count - 60)
        }
    }

    private func localBatterySnapshot() async -> [StatusSnapshot.Battery] {
        do {
            let output = try await run("/usr/bin/pmset", arguments: ["-g", "batt"]).stdout
            guard let percent = parseBatteryPercent(output) else { return [] }
            let health = await localBatteryHealth()
            let lowercased = output.lowercased()
            let status: String?
            if lowercased.contains("charging") {
                status = "charging"
            } else if lowercased.contains("discharging") {
                status = "discharging"
            } else if lowercased.contains("charged") {
                status = "charged"
            } else {
                status = nil
            }

            return [
                StatusSnapshot.Battery(
                    percent: percent,
                    status: status,
                    timeLeft: parseBatteryTimeLeft(output),
                    health: health.health,
                    cycleCount: health.cycleCount,
                    capacity: health.capacity
                )
            ]
        } catch {
            return []
        }
    }

    private func localBatteryHealth() async -> (health: String?, cycleCount: Int?, capacity: Int?) {
        do {
            let output = try await run("/usr/sbin/ioreg", arguments: ["-rn", "AppleSmartBattery"], timeoutSeconds: 2).stdout
            let cycleCount = parseIORegInt(output, key: "CycleCount")
            let design = parseIORegInt(output, key: "DesignCapacity")
            let nominal = parseIORegInt(output, key: "NominalChargeCapacity")
            let rawMax = parseIORegInt(output, key: "AppleRawMaxCapacity")
            let capacity = batteryHealthPercent(design: design, nominal: nominal, rawMax: rawMax)
            return (capacity.map { $0 >= 80 ? "Normal" : "Service Recommended" }, cycleCount, capacity)
        } catch {
            return (nil, nil, nil)
        }
    }

    private func localTopProcesses() async -> [StatusSnapshot.ProcessInfo] {
        do {
            let output = try await run("/bin/ps", arguments: ["-axo", "pid,ppid,pcpu,pmem,rss,comm", "-r"]).stdout
            return output
                .split(separator: "\n")
                .dropFirst()
                .prefix(8)
                .compactMap { parseProcessLine(String($0)) }
        } catch {
            return []
        }
    }

    private func parseProcessLine(_ line: String) -> StatusSnapshot.ProcessInfo? {
        let parts = line.split(maxSplits: 5, whereSeparator: \.isWhitespace).map(String.init)
        guard parts.count >= 6 else { return nil }
        let command = parts[5]
        return StatusSnapshot.ProcessInfo(
            pid: Int(parts[0]),
            ppid: Int(parts[1]),
            name: URL(filePath: command).lastPathComponent,
            command: command,
            cpu: Double(parts[2]),
            memory: Double(parts[3]),
            memoryBytes: UInt64(parts[4]).map { $0 * 1024 }
        )
    }

    private func parseBatteryPercent(_ output: String) -> Double? {
        guard let percentIndex = output.firstIndex(of: "%") else { return nil }
        let prefix = output[..<percentIndex].reversed()
        let digits = String(prefix.prefix { $0.isNumber }.reversed())
        return Double(digits)
    }

    private func parseBatteryTimeLeft(_ output: String) -> String? {
        for token in output.split(whereSeparator: \.isWhitespace) {
            if token.contains(":") && token.allSatisfy({ $0.isNumber || $0 == ":" }) {
                return String(token)
            }
        }
        return nil
    }

    private func parseIORegInt(_ output: String, key: String) -> Int? {
        for line in output.split(separator: "\n").map(String.init) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("\"\(key)\"") else { continue }
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let digits = parts[1].filter { $0.isNumber }
            if let value = Int(String(digits)), value > 0 {
                return value
            }
        }
        return nil
    }

    private func batteryHealthPercent(design: Int?, nominal: Int?, rawMax: Int?) -> Int? {
        guard let design, design > 0 else { return nil }
        let capacity = (nominal ?? 0) > 0 ? nominal : rawMax
        guard let capacity, capacity > 0 else { return nil }
        let percent = Int((Double(capacity) * 100 / Double(design)).rounded())
        return min(max(percent, 0), 100)
    }

    private func currentLoadAverage() -> Double {
        var loads = [Double](repeating: 0, count: 3)
        guard getloadavg(&loads, Int32(loads.count)) > 0 else { return 0 }
        return loads[0]
    }

    private func computeHealthScore(diskUsage: Double?, memoryUsage: Double?, cpuUsage: Double?) -> Int {
        var score = 100.0
        if let diskUsage {
            score -= max(0, diskUsage - 70) * 0.8
        }
        if let memoryUsage {
            score -= max(0, memoryUsage - 75) * 0.45
        }
        if let cpuUsage {
            score -= max(0, cpuUsage - 80) * 0.25
        }
        return Int(min(max(score.rounded(), 0), 100))
    }

    private func formatUptime(_ uptime: TimeInterval) -> String {
        let days = Int(uptime) / 86_400
        let hours = (Int(uptime) % 86_400) / 3_600
        if days > 0 {
            return "\(days)d \(hours)h"
        }
        return "\(hours)h"
    }

    private func parseVMStatPageSize(_ output: String) -> UInt64? {
        guard let range = output.range(of: "page size of ") else { return nil }
        let suffix = output[range.upperBound...]
        let digits = suffix.prefix { $0.isNumber }
        return UInt64(digits)
    }

    private func parseVMStatPages(_ output: String) -> [String: UInt64] {
        var result: [String: UInt64] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = String(parts[0])
            let rawValue = parts[1]
                .filter { $0.isNumber }
            if let value = UInt64(String(rawValue)) {
                result[key] = value
            }
        }
        return result
    }

    private func cleanCategoryPaths() -> [(nameKey: String, paths: [String])] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            ("browserCache", [
                "\(home)/Library/Caches/com.google.Chrome",
                "\(home)/Library/Caches/Google/Chrome",
                "\(home)/Library/Caches/com.apple.Safari",
                "\(home)/Library/Caches/Firefox",
                "\(home)/Library/Application Support/Firefox/Profiles"
            ]),
            ("developerCache", [
                "\(home)/Library/Developer/Xcode/DerivedData",
                "\(home)/Library/Caches/org.swift.swiftpm",
                "\(home)/Library/Caches/go-build",
                "\(home)/go/pkg/mod",
                "\(home)/.npm",
                "\(home)/.gradle/caches",
                "\(home)/Library/Caches/CocoaPods"
            ]),
            ("systemLogs", [
                "\(home)/Library/Logs",
                "\(home)/Library/DiagnosticReports"
            ]),
            ("aiToolCache", [
                "\(home)/.codex",
                "\(home)/.cache/huggingface",
                "\(home)/Library/Caches/com.anthropic.claudefordesktop",
                "\(home)/Library/Application Support/Claude"
            ]),
            ("trash", [
                "\(home)/.Trash"
            ])
        ]
    }

    private func isUserCleanPath(_ path: String, home: String) -> Bool {
        guard path.hasPrefix(home + "/") else { return false }
        let protectedPaths = [
            home,
            "\(home)/Desktop",
            "\(home)/Documents",
            "\(home)/Downloads",
            "\(home)/Library",
            "\(home)/.Trash",
            "\(home)/.ssh",
            "\(home)/.gnupg"
        ]
        return !protectedPaths.contains(path)
    }

    private func isSafeAnalyzeTrashPath(_ path: String) -> Bool {
        let home = fileManager.homeDirectoryForCurrentUser.standardizedFileURL.path
        guard path != "/", path != home else { return false }

        let protectedExactPaths: Set<String> = [
            "/Applications",
            "/Library",
            "/Network",
            "/System",
            "/Users",
            "/Volumes",
            "/bin",
            "/dev",
            "/etc",
            "/private",
            "/sbin",
            "/tmp",
            "/usr",
            "/var",
            home,
            "\(home)/Desktop",
            "\(home)/Documents",
            "\(home)/Downloads",
            "\(home)/Library",
            "\(home)/Movies",
            "\(home)/Music",
            "\(home)/Pictures",
            "\(home)/Public",
            "\(home)/.Trash",
            "\(home)/.ssh",
            "\(home)/.gnupg"
        ]
        if protectedExactPaths.contains(path) {
            return false
        }

        let protectedPrefixes = [
            "/System/",
            "/Library/Apple/",
            "/bin/",
            "/dev/",
            "/etc/",
            "/private/",
            "/sbin/",
            "/usr/",
            "/var/",
            "\(home)/.Trash/"
        ]
        return !protectedPrefixes.contains { path.hasPrefix($0) }
    }

    private func diskUsageBytes(for path: String) async -> Int64 {
        guard fileManager.fileExists(atPath: path) else { return 0 }
        do {
            let output = try await run("/usr/bin/du", arguments: ["-sk", path]).stdout
            guard let kilobytes = Int64(output.split(whereSeparator: \.isWhitespace).first ?? "") else {
                return 0
            }
            return kilobytes * 1024
        } catch {
            return 0
        }
    }

    private func fullDiskAccessGranted() async -> Bool? {
        let home = fileManager.homeDirectoryForCurrentUser.path
        let protectedPaths = [
            "\(home)/Library/Messages/chat.db",
            "\(home)/Library/Mail",
            "\(home)/Library/Safari/CloudTabs.db"
        ]

        for path in protectedPaths {
            guard fileManager.fileExists(atPath: path) else { continue }
            if fileManager.isReadableFile(atPath: path) {
                return true
            }
            do {
                _ = try fileManager.attributesOfItem(atPath: path)
                return true
            } catch {
                return false
            }
        }

        return nil
    }

    private func sudoSessionAvailable() async -> Bool {
        do {
            _ = try await run(
                "/usr/bin/sudo",
                arguments: ["-n", "true"],
                timeoutSeconds: 4,
                disablesAuthentication: false
            )
            return true
        } catch {
            return false
        }
    }

    private func privilegedShellCommand(arguments: [String]) -> String {
        let path = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ].joined(separator: ":")
        let user = NSUserName()
        let home = fileManager.homeDirectoryForCurrentUser.path
        let molePath = repositoryRoot.appending(path: "mole").path
        let quotedArguments = arguments.map(shellQuote).joined(separator: " ")

        return [
            "export PATH=\(shellQuote(path))",
            "export HOME=\(shellQuote(home))",
            "export USER=\(shellQuote(user))",
            "export LOGNAME=\(shellQuote(user))",
            "export SUDO_USER=\(shellQuote(user))",
            "export CLICOLOR=0",
            "export NO_COLOR=1",
            "cd \(shellQuote(repositoryRoot.path))",
            "\(shellQuote(molePath)) \(quotedArguments) 2>&1"
        ].joined(separator: "; ")
    }

    private func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func appleScriptLiteral(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    private func processEnvironment(
        disablesOperationLog: Bool = false,
        disablesAuthentication: Bool = true
    ) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let defaultPath = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ].joined(separator: ":")
        if let existingPath = environment["PATH"], !existingPath.isEmpty {
            environment["PATH"] = "\(defaultPath):\(existingPath)"
        } else {
            environment["PATH"] = defaultPath
        }
        if disablesAuthentication {
            environment["MOLE_TEST_NO_AUTH"] = "1"
        } else {
            environment.removeValue(forKey: "MOLE_TEST_NO_AUTH")
        }
        environment["CLICOLOR"] = "0"
        environment["NO_COLOR"] = "1"
        if disablesOperationLog {
            environment["MO_NO_OPLOG"] = "1"
        }
        return environment
    }

    private func findExecutable(named name: String) -> URL? {
        let paths = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)",
            "/bin/\(name)"
        ]
        for path in paths where fileManager.isExecutableFile(atPath: path) {
            return URL(filePath: path)
        }
        return nil
    }

    private func decode<T: Decodable>(_ type: T.Type, from output: String) throws -> T {
        guard let data = output.data(using: .utf8) else {
            throw CLIError.invalidOutput("Command output is not UTF-8.")
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw CLIError.invalidOutput("Could not decode JSON: \(error.localizedDescription)")
        }
    }

    private static func findRepositoryRoot() -> URL? {
        var candidates: [URL] = []
        if let explicit = ProcessInfo.processInfo.environment["MOLECUBE_REPOSITORY_ROOT"], !explicit.isEmpty {
            candidates.append(URL(filePath: explicit))
        }
        candidates.append(URL(filePath: FileManager.default.currentDirectoryPath))

        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL)
        }

        candidates.append(URL(filePath: #filePath).deletingLastPathComponent())

        for start in candidates {
            if let root = walkUp(from: start) {
                return root
            }
        }
        return nil
    }

    private static func walkUp(from start: URL) -> URL? {
        var url = start.standardizedFileURL
        while true {
            let mole = url.appending(path: "mole").path
            let goMod = url.appending(path: "go.mod").path
            let bin = url.appending(path: "bin").path
            if FileManager.default.isExecutableFile(atPath: mole),
               FileManager.default.fileExists(atPath: goMod),
               FileManager.default.fileExists(atPath: bin) {
                return url
            }

            let parent = url.deletingLastPathComponent()
            if parent.path == url.path {
                return nil
            }
            url = parent
        }
    }
}
