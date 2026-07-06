import AppKit
import Foundation

@MainActor
final class AppViewModel: ObservableObject {
    @Published var selectedSection: AppSection = .status
    @Published var language: AppLanguage = .simplifiedChinese
    @Published var status: StatusSnapshot?
    @Published var analyzeOutput: AnalyzeOutput?
    @Published var analyzePathStack: [String] = []
    @Published var apps: [InstalledApp] = []
    @Published var selectedAppID: InstalledApp.ID?
    @Published var uninstallFilter: UninstallFilter = .installed
    @Published var historyEntries: [HistoryEntry] = []
    @Published var cleanCategories: [CleanCategory]
    @Published var selectedCleanCategoryID: CleanCategory.ID?
    @Published var selectedCleanPathIDs: Set<String> = []
    @Published var cleanPreviewItems: [CleanPreviewItem] = []
    @Published var permissionStatus = PermissionStatus()
    @Published var isScanning = false
    @Published var scanProgress = 0.0
    @Published var scanStageKey = "readyToScan"
    @Published var isLoadingStatus = false
    @Published var isLoadingApps = false
    @Published var isLoadingCleanCategories = false
    @Published var isLoadingCleanPreview = false
    @Published var isLoadingAnalyze = false
    @Published var isLoadingHistory = false
    @Published var isLoadingPermissions = false
    @Published var errorMessage: String?
    @Published var commandOutputTitle: String?
    @Published var commandOutput: String?
    @Published var isRunningCommand = false
    @Published var isCleanConfirmationPresented = false
    @Published var pendingCleanCategoryID: CleanCategory.ID?
    @Published var pendingCleanPaths: [String]?
    @Published var pendingCleanDisplayName: String?
    @Published var pendingAnalyzeDeleteEntry: AnalyzeEntry?
    @Published var deletingAnalyzePath: String?
    @Published var analyzeStatusMessage: String?
    @Published var isScanningLeftovers = false
    @Published var appPendingUninstall: InstalledApp?
    @Published var uninstallPreviews: [InstalledApp.ID: UninstallPreview] = [:]
    @Published var repositoryPath = ""
    @Published var loadSamples: [Double] = Array(repeating: 0, count: 12)

    private var backend: LocalCLIBackend?
    private var isLiveStatusRunning = false
    private var didInitializeCleanPathSelection = false
    private var lastAppsRefreshAt: Date?
    private let appInventoryCacheDuration: TimeInterval = 300

    init() {
        cleanCategories = [
            CleanCategory(nameKey: "browserCache", detailKey: "browserCacheDetail", sizeBytes: nil, riskKey: "lowRisk", selected: true),
            CleanCategory(nameKey: "developerCache", detailKey: "developerCacheDetail", sizeBytes: nil, riskKey: "mediumRisk", selected: true),
            CleanCategory(nameKey: "systemLogs", detailKey: "systemLogsDetail", sizeBytes: nil, riskKey: "lowRisk", selected: true),
            CleanCategory(nameKey: "aiToolCache", detailKey: "aiToolCacheDetail", sizeBytes: nil, riskKey: "mediumRisk", selected: false),
            CleanCategory(nameKey: "trash", detailKey: "trashDetail", sizeBytes: nil, riskKey: "highRisk", selected: false)
        ]

        do {
            let backend = try LocalCLIBackend()
            self.backend = backend
            repositoryPath = backend.repositoryRoot.path
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var selectedApp: InstalledApp? {
        if let selectedAppID, let app = apps.first(where: { $0.id == selectedAppID }) {
            return app
        }
        return apps.first
    }

    var filteredApps: [InstalledApp] {
        switch uninstallFilter {
        case .installed:
            apps
        case .extensions:
            apps.filter { app in
                let searchable = "\(app.name) \(app.bundleID) \(app.path) \(app.source)".lowercased()
                return searchable.contains("extension") || searchable.contains(".appex") || searchable.contains("plugin")
            }
        }
    }

    func selectApp(_ app: InstalledApp) {
        selectedAppID = app.id
        if uninstallPreviews[app.id] == nil {
            Task { await scanSelectedAppLeftovers(app: app) }
        }
    }

    func selectFirstFilteredAppIfNeeded() {
        let visibleApps = filteredApps
        guard !visibleApps.isEmpty else { return }
        if selectedAppID == nil || !visibleApps.contains(where: { $0.id == selectedAppID }) {
            selectedAppID = visibleApps.first?.id
        }
    }

    var selectedCleanTotal: String {
        let total = selectedCleanBytes
        guard total > 0 else { return text("notScanned") }
        return total.formattedBytes
    }

    var selectedCleanBytes: Int64 {
        cleanCategories
            .compactMap(\.sizeBytes)
            .reduce(0, +)
    }

    var hasScannedCleanCategories: Bool {
        cleanCategories.contains { $0.sizeBytes != nil }
    }

    var selectedCleanCategory: CleanCategory? {
        if let selectedCleanCategoryID,
           let category = cleanCategories.first(where: { $0.id == selectedCleanCategoryID }) {
            return category
        }
        return cleanCategories.first { ($0.sizeBytes ?? 0) > 0 } ?? cleanCategories.first
    }

    var pendingCleanCategory: CleanCategory? {
        guard let pendingCleanCategoryID else { return nil }
        return cleanCategories.first { $0.id == pendingCleanCategoryID }
    }

    var cleanConfirmationButtonText: String {
        if pendingCleanPaths != nil {
            return text("cleanSelectedPaths")
        }
        return pendingCleanCategory == nil ? text("cleanAllScannedItems") : text("cleanSelectedCategory")
    }

    var cleanConfirmationMessage: String {
        if let pendingCleanPaths, let pendingCleanDisplayName {
            return String(format: text("cleanSelectedPathsConfirmationMessage"), pendingCleanDisplayName, pendingCleanPaths.count)
        }
        if let category = pendingCleanCategory {
            return String(format: text("cleanCategoryConfirmationMessage"), text(category.nameKey))
        }
        return text("cleanConfirmationMessage")
    }

    var analyzeDeleteConfirmationMessage: String {
        guard let pendingAnalyzeDeleteEntry else { return "" }
        return String(
            format: text("analyzeDeleteConfirmationMessage"),
            pendingAnalyzeDeleteEntry.name,
            pendingAnalyzeDeleteEntry.size.formattedBytes,
            pendingAnalyzeDeleteEntry.path
        )
    }

    var selectedCleanPathCount: Int {
        selectedCleanPathIDs.count
    }

    var selectedCleanPathBytes: Int64 {
        cleanCategories
            .flatMap(\.detailItems)
            .filter { selectedCleanPathIDs.contains($0.id) }
            .map(\.sizeBytes)
            .reduce(0, +)
    }

    var selectedCleanPathTotal: String {
        selectedCleanPathBytes > 0 ? selectedCleanPathBytes.formattedBytes : text("noneSelected")
    }

    var activeAlertCount: Int {
        var count = 0
        if (status?.disks?.first?.usedPercent ?? 0) >= 85 {
            count += 1
        }
        if (status?.memory?.usedPercent ?? 0) >= 85 {
            count += 1
        }
        if selectedCleanBytes >= 5 * 1024 * 1024 * 1024 {
            count += 1
        }
        return count
    }

    var activeAlertCaption: String {
        var captions: [String] = []
        if let diskUsage = status?.disks?.first?.usedPercent, diskUsage >= 85 {
            captions.append(text("diskUsage"))
        }
        if let memoryUsage = status?.memory?.usedPercent, memoryUsage >= 85 {
            captions.append(text("memoryUsage"))
        }
        if selectedCleanBytes >= 5 * 1024 * 1024 * 1024 {
            captions.append(text("reclaimable"))
        }
        return captions.isEmpty ? text("noActiveAlerts") : captions.joined(separator: ", ")
    }

    func text(_ key: String) -> String {
        Localizer.text(key, language: language)
    }

    func startInitialLoad() async {
        await refreshStatus()
        await refreshPermissionStatus()
    }

    func runScan() async {
        guard !isScanning else { return }
        isScanning = true
        errorMessage = nil

        let stages: [(Double, String)] = [
            (0.12, "readingStatus"),
            (0.28, "loadingApps"),
            (0.48, "analyzingDisk"),
            (0.68, "readingHistory"),
            (0.86, "buildingPreview")
        ]

        for stage in stages {
            scanProgress = stage.0
            scanStageKey = stage.1
            try? await Task.sleep(for: .milliseconds(280))
            switch stage.1 {
            case "readingStatus":
                await refreshStatus()
            case "loadingApps":
                await refreshApps(force: true)
            case "analyzingDisk":
                await refreshAnalyze()
            case "readingHistory":
                await refreshHistory()
            case "buildingPreview":
                await refreshCleanCategorySizes()
            default:
                break
            }
        }

        scanProgress = 1
        scanStageKey = "scanComplete"
        isScanning = false
    }

    func refreshStatus() async {
        await refreshStatus(showLoading: true)
    }

    func startLiveStatusUpdates() async {
        guard !isLiveStatusRunning else { return }
        isLiveStatusRunning = true
        defer { isLiveStatusRunning = false }

        while !Task.isCancelled {
            await refreshStatus(showLoading: status == nil)
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private func refreshStatus(showLoading: Bool) async {
        guard let backend else { return }
        if showLoading {
            isLoadingStatus = true
        }
        defer {
            if showLoading {
                isLoadingStatus = false
            }
        }
        do {
            status = try await backend.status()
            appendLoadSample()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshCleanCategorySizes() async {
        guard let backend else { return }
        isLoadingCleanCategories = true
        defer { isLoadingCleanCategories = false }
        let snapshots = await backend.cleanCategorySizes()
        for snapshot in snapshots {
            guard let index = cleanCategories.firstIndex(where: { $0.nameKey == snapshot.nameKey }) else {
                continue
            }
            cleanCategories[index].sizeBytes = snapshot.sizeBytes
            cleanCategories[index].detailItems = snapshot.detailItems
        }
        let currentPathIDs = Set(cleanCategories.flatMap(\.detailItems).map(\.id))
        if didInitializeCleanPathSelection {
            selectedCleanPathIDs.formIntersection(currentPathIDs)
        } else {
            selectedCleanPathIDs = Set(
                cleanCategories
                    .filter(\.selected)
                    .flatMap(\.detailItems)
                    .map(\.id)
            )
            didInitializeCleanPathSelection = true
        }
        if selectedCleanCategoryID == nil || !cleanCategories.contains(where: { $0.id == selectedCleanCategoryID }) {
            selectedCleanCategoryID = cleanCategories.first { ($0.sizeBytes ?? 0) > 0 }?.id ?? cleanCategories.first?.id
        }
    }

    func scanCleanCategories() async {
        await refreshCleanCategorySizes()
    }

    func selectCleanCategory(_ category: CleanCategory) {
        selectedCleanCategoryID = category.id
    }

    func refreshAnalyze(path: String? = nil) async {
        guard let backend else { return }
        isLoadingAnalyze = true
        defer { isLoadingAnalyze = false }
        do {
            analyzeOutput = try await backend.analyze(path: path)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startAnalyzeScope(path: String? = nil) async {
        analyzePathStack = []
        analyzeStatusMessage = nil
        await refreshAnalyze(path: path)
    }

    func navigateAnalyze(to path: String) async {
        if let currentPath = analyzeOutput?.path, currentPath != path {
            analyzePathStack.append(currentPath)
        }
        analyzeStatusMessage = nil
        await refreshAnalyze(path: path)
    }

    func goBackAnalyzePath() async {
        guard let previousPath = analyzePathStack.popLast() else { return }
        analyzeStatusMessage = nil
        await refreshAnalyze(path: previousPath)
    }

    func requestAnalyzeDelete(_ entry: AnalyzeEntry) {
        pendingAnalyzeDeleteEntry = entry
    }

    func cancelPendingAnalyzeDelete() {
        pendingAnalyzeDeleteEntry = nil
    }

    func confirmPendingAnalyzeDelete() async {
        guard let backend, !isRunningCommand, deletingAnalyzePath == nil else { return }
        guard let entry = pendingAnalyzeDeleteEntry else { return }

        pendingAnalyzeDeleteEntry = nil
        let currentPath = analyzeOutput?.path
        deletingAnalyzePath = entry.path
        isRunningCommand = true
        defer {
            isRunningCommand = false
            deletingAnalyzePath = nil
        }
        errorMessage = nil
        analyzeStatusMessage = text("movingToTrash")

        do {
            let output = try await backend.moveAnalyzeItemToTrash(path: entry.path)
            removeAnalyzeEntryLocally(entry)
            analyzeStatusMessage = String(format: text("analyzeMovedToTrashInline"), entry.name)
            commandOutputTitle = "\(text("analyzeDeleteCompleteTitle")): \(entry.name)"
            commandOutput = output.isEmpty ? text("emptyOutput") : output
            await refreshAnalyze(path: currentPath)
            analyzeStatusMessage = String(format: text("analyzeMovedToTrashInline"), entry.name)
            await refreshStatus()
            await refreshHistory()
        } catch {
            analyzeStatusMessage = nil
            errorMessage = message(for: error)
        }
    }

    func loadAppsIfNeeded() async {
        await refreshApps(force: false)
    }

    func refreshApps(force: Bool = false) async {
        guard let backend else { return }
        guard !isLoadingApps else { return }
        if !force,
           !apps.isEmpty,
           let lastAppsRefreshAt,
           Date().timeIntervalSince(lastAppsRefreshAt) < appInventoryCacheDuration {
            selectFirstFilteredAppIfNeeded()
            return
        }

        isLoadingApps = true
        defer { isLoadingApps = false }
        do {
            apps = try await backend.installedApps()
            lastAppsRefreshAt = Date()
            if selectedAppID == nil || !apps.contains(where: { $0.id == selectedAppID }) {
                selectedAppID = apps.first?.id
            }
            selectFirstFilteredAppIfNeeded()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshHistory() async {
        guard let backend else { return }
        isLoadingHistory = true
        defer { isLoadingHistory = false }
        do {
            let payload = try await backend.history()
            historyEntries = (payload.sessions ?? []) + (payload.deletions ?? [])
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshPermissionStatus() async {
        guard let backend else { return }
        isLoadingPermissions = true
        defer { isLoadingPermissions = false }
        permissionStatus = await backend.permissionStatus()
    }

    func openFullDiskAccessSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_FullDiskAccess"
        ]
        for rawURL in urls {
            if let url = URL(string: rawURL), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    func toggleCleanCategory(_ category: CleanCategory) {
        guard let index = cleanCategories.firstIndex(where: { $0.id == category.id }) else { return }
        cleanCategories[index].selected.toggle()
    }

    func isCleanPathSelected(_ item: CleanCategoryDetail) -> Bool {
        selectedCleanPathIDs.contains(item.id)
    }

    func toggleCleanPath(_ item: CleanCategoryDetail) {
        if selectedCleanPathIDs.contains(item.id) {
            selectedCleanPathIDs.remove(item.id)
        } else {
            selectedCleanPathIDs.insert(item.id)
        }
    }

    func selectedCleanItems(in category: CleanCategory) -> [CleanCategoryDetail] {
        category.detailItems.filter { selectedCleanPathIDs.contains($0.id) }
    }

    func selectedCleanSize(in category: CleanCategory) -> Int64 {
        selectedCleanItems(in: category).map(\.sizeBytes).reduce(0, +)
    }

    func selectAllCleanPaths(in category: CleanCategory) {
        selectedCleanPathIDs.formUnion(category.detailItems.map(\.id))
    }

    func deselectAllCleanPaths(in category: CleanCategory) {
        selectedCleanPathIDs.subtract(category.detailItems.map(\.id))
    }

    func runCleanDryRunPreview() async {
        guard let backend, !isRunningCommand else { return }
        isRunningCommand = true
        isLoadingCleanPreview = true
        defer {
            isRunningCommand = false
            isLoadingCleanPreview = false
        }
        errorMessage = nil
        do {
            await refreshCleanCategorySizes()
            let output = try await backend.cleanDryRunPreview()
            cleanPreviewItems = parseCleanPreviewItems(output)
        } catch {
            errorMessage = message(for: error)
        }
    }

    func clearCleanPreview() {
        cleanPreviewItems = []
    }

    func requestCleanNow() {
        guard hasScannedCleanCategories else {
            errorMessage = text("scanBeforeCleanup")
            return
        }
        pendingCleanCategoryID = nil
        pendingCleanPaths = nil
        pendingCleanDisplayName = nil
        isCleanConfirmationPresented = true
    }

    func requestCleanSelectedPathsNow() {
        guard hasScannedCleanCategories else {
            errorMessage = text("scanBeforeCleanup")
            return
        }
        let paths = cleanCategories
            .flatMap(\.detailItems)
            .filter { selectedCleanPathIDs.contains($0.id) }
            .map(\.path)
        guard !paths.isEmpty else {
            errorMessage = text("selectCleanItemsFirst")
            return
        }
        pendingCleanCategoryID = nil
        pendingCleanPaths = paths
        pendingCleanDisplayName = text("selectedItems")
        isCleanConfirmationPresented = true
    }

    func requestCleanCategoryNow(_ category: CleanCategory) {
        guard hasScannedCleanCategories else {
            errorMessage = text("scanBeforeCleanup")
            return
        }
        let selectedItems = selectedCleanItems(in: category)
        guard !selectedItems.isEmpty else {
            errorMessage = text("selectCleanItemsFirst")
            return
        }
        pendingCleanCategoryID = nil
        pendingCleanPaths = selectedItems.map(\.path)
        pendingCleanDisplayName = text(category.nameKey)
        isCleanConfirmationPresented = true
    }

    func cancelPendingClean() {
        pendingCleanCategoryID = nil
        pendingCleanPaths = nil
        pendingCleanDisplayName = nil
        isCleanConfirmationPresented = false
    }

    func confirmCleanNow() async {
        guard let backend, !isRunningCommand else { return }
        isCleanConfirmationPresented = false
        isRunningCommand = true
        defer { isRunningCommand = false }
        errorMessage = nil
        do {
            let output: String
            if let pendingCleanPaths, let pendingCleanDisplayName {
                output = try await backend.cleanCategory(
                    displayName: pendingCleanDisplayName,
                    paths: pendingCleanPaths
                )
            } else if let category = pendingCleanCategory {
                output = try await backend.cleanCategory(
                    displayName: text(category.nameKey),
                    paths: category.detailItems.map(\.path)
                )
            } else {
                output = try await backend.cleanNow()
            }
            commandOutputTitle = text("cleanCompleteTitle")
            commandOutput = output.isEmpty ? text("emptyOutput") : output
            pendingCleanCategoryID = nil
            pendingCleanPaths = nil
            pendingCleanDisplayName = nil
            await refreshStatus()
            await refreshHistory()
            await refreshCleanCategorySizes()
        } catch {
            errorMessage = message(for: error)
            pendingCleanCategoryID = nil
            pendingCleanPaths = nil
            pendingCleanDisplayName = nil
        }
    }

    func runMoleCommand(title: String, arguments: [String], timeoutSeconds: UInt64 = 90, standardInput: String? = nil) async {
        guard let backend, !isRunningCommand else { return }
        isRunningCommand = true
        defer { isRunningCommand = false }
        errorMessage = nil
        do {
            let output = try await backend.runMoleCommand(
                arguments: arguments,
                timeoutSeconds: TimeInterval(timeoutSeconds),
                standardInput: standardInput
            )
            commandOutputTitle = title
            commandOutput = output.isEmpty ? text("emptyOutput") : output
            if arguments.first == "history" {
                await refreshHistory()
            }
            if arguments.first == "status" || arguments.first == "optimize" || arguments.first == "clean" || arguments.first == "purge" || arguments.first == "installer" || arguments.first == "update" {
                await refreshStatus()
                await refreshHistory()
                await refreshCleanCategorySizes()
            }
        } catch {
            errorMessage = message(for: error)
        }
    }

    func runOptimizePreview() async {
        guard let backend, !isRunningCommand else { return }
        isRunningCommand = true
        defer { isRunningCommand = false }
        errorMessage = nil
        do {
            let output = try await backend.optimizePreview()
            commandOutputTitle = text("optimizePreview")
            commandOutput = output.isEmpty ? text("emptyOutput") : output
            await refreshPermissionStatus()
        } catch {
            errorMessage = message(for: error)
        }
    }

    func runOptimizeWithAuthorization() async {
        guard let backend, !isRunningCommand else { return }
        isRunningCommand = true
        defer { isRunningCommand = false }
        errorMessage = nil
        do {
            let output = try await backend.optimizeWithAdministratorPrivileges()
            commandOutputTitle = text("optimizeRun")
            commandOutput = output.isEmpty ? text("emptyOutput") : output
            await refreshStatus()
            await refreshHistory()
            await refreshPermissionStatus()
        } catch {
            errorMessage = message(for: error)
        }
    }

    func runUninstallDryRunPreview(app explicitApp: InstalledApp? = nil) async {
        guard let backend, !isRunningCommand else { return }
        guard let app = explicitApp ?? selectedApp else {
            errorMessage = text("noAppSelected")
            return
        }
        isRunningCommand = true
        defer { isRunningCommand = false }
        errorMessage = nil
        let uninstallName = app.uninstallName
        do {
            let output = try await backend.uninstallDryRunPreview(appName: uninstallName, autoConfirm: true)
            uninstallPreviews[app.id] = parseUninstallPreview(output: output, app: app)
            selectFirstFilteredAppIfNeeded()
        } catch {
            errorMessage = message(for: error)
        }
    }

    func requestUninstallSelectedApp(_ explicitApp: InstalledApp? = nil) {
        guard let app = explicitApp ?? selectedApp else {
            errorMessage = text("noAppSelected")
            return
        }
        guard uninstallPreviews[app.id] != nil else {
            errorMessage = text("scanBeforeUninstall")
            return
        }
        appPendingUninstall = app
    }

    func cancelPendingUninstall() {
        appPendingUninstall = nil
    }

    func confirmPendingUninstall() async {
        guard let backend, !isRunningCommand else { return }
        guard let app = appPendingUninstall else {
            errorMessage = text("noAppSelected")
            return
        }

        appPendingUninstall = nil
        isRunningCommand = true
        defer { isRunningCommand = false }
        errorMessage = nil

        let uninstallName = app.uninstallName
        let displayName = app.name
        do {
            let output = try await backend.uninstallApp(appName: uninstallName)
            let appWasRemoved = !FileManager.default.fileExists(atPath: app.path)
            if appWasRemoved {
                commandOutputTitle = "\(text("uninstallCompleteTitle")): \(displayName)"
                apps.removeAll { $0.id == app.id || $0.path == app.path }
                uninstallPreviews[app.id] = nil
                lastAppsRefreshAt = Date()
                selectedAppID = apps.first?.id
                commandOutput = appendStatusLine(to: output, status: text("uninstallRemovedFromList"))
            } else {
                commandOutputTitle = "\(text("uninstallIncompleteTitle")): \(displayName)"
                commandOutput = appendStatusLine(to: output, status: text("uninstallStillPresent"))
                errorMessage = text("uninstallStillPresent")
            }
        } catch {
            errorMessage = message(for: error)
        }
    }

    func scanSelectedAppLeftovers(app explicitApp: InstalledApp? = nil) async {
        guard let backend, !isScanningLeftovers else { return }
        guard let app = explicitApp ?? selectedApp else {
            errorMessage = text("noAppSelected")
            return
        }
        isScanningLeftovers = true
        defer { isScanningLeftovers = false }
        errorMessage = nil
        let uninstallName = app.uninstallName
        do {
            let output = try await backend.uninstallDryRunPreview(appName: uninstallName, autoConfirm: true)
            uninstallPreviews[app.id] = parseUninstallPreview(output: output, app: app)
            selectFirstFilteredAppIfNeeded()
        } catch {
            errorMessage = message(for: error)
        }
    }

    func dismissCommandOutput() {
        commandOutputTitle = nil
        commandOutput = nil
    }

    func uninstallPreview(for app: InstalledApp) -> UninstallPreview? {
        uninstallPreviews[app.id]
    }

    func revealInFinder(_ path: String) {
        guard !path.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func openAnalyzeEntry(_ entry: AnalyzeEntry) {
        if entry.isDir {
            Task { await navigateAnalyze(to: entry.path) }
        } else {
            revealInFinder(entry.path)
        }
    }

    func formattedCleanSize(for category: CleanCategory) -> String {
        guard let sizeBytes = category.sizeBytes else { return text("notScanned") }
        return sizeBytes.formattedBytes
    }

    private func appendLoadSample() {
        let usage = min(max((status?.cpu?.usage ?? 0) / 100, 0.03), 1)
        loadSamples.append(usage)
        if loadSamples.count > 12 {
            loadSamples.removeFirst(loadSamples.count - 12)
        }
    }

    private func removeAnalyzeEntryLocally(_ entry: AnalyzeEntry) {
        guard var output = analyzeOutput else { return }
        output.entries.removeAll { $0.path == entry.path }
        output.largeFiles?.removeAll { $0.path == entry.path }
        output.totalSize = max(0, output.totalSize - entry.size)
        if let totalFiles = output.totalFiles {
            output.totalFiles = max(0, totalFiles - 1)
        }
        analyzeOutput = output
    }

    private func message(for error: Error) -> String {
        if case let CLIError.commandTimedOut(command) = error {
            return "\(text("commandTimedOutTitle"))\n\(command)\n\n\(text("commandTimedOutDetail"))"
        }
        return error.localizedDescription
    }

    private func appendStatusLine(to output: String, status: String) -> String {
        let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedOutput.isEmpty {
            return status
        }
        return "\(trimmedOutput)\n\n\(status)"
    }

    private func parseCleanPreviewItems(_ output: String) -> [CleanPreviewItem] {
        stripANSI(output)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { line in
                let lowercased = line.lowercased()
                let isPath = line.hasPrefix("/") ||
                    line.hasPrefix("~/") ||
                    lowercased.contains("/library/") ||
                    lowercased.contains("/caches/") ||
                    lowercased.contains("/applications/")
                return CleanPreviewItem(text: line, isPath: isPath)
            }
    }

    private func parseUninstallPreview(output: String, app: InstalledApp) -> UninstallPreview {
        let cleanOutput = stripANSI(output)
        var appBundlePath: String?
        var relatedFiles: [String] = []
        var systemFiles: [String] = []
        var reviewOnlyFiles: [String] = []
        var totalSize: String?
        var itemCount = 0
        var inFileList = false

        for rawLine in cleanOutput.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if line.contains("Files to be removed") {
                inFileList = true
                continue
            }

            if line.hasPrefix("➤") || line.hasPrefix("Uninstall dry run complete") {
                inFileList = false
            }

            if line.contains("Would remove") || line.contains("Removed") {
                if let countRange = line.range(of: #"remove\s+(\d+)"#, options: .regularExpression) {
                    let match = String(line[countRange])
                    itemCount = Int(match.components(separatedBy: .whitespaces).last ?? "") ?? itemCount
                }
                if let sizeRange = line.range(of: #"\b\d+(?:\.\d+)?\s*(?:KB|MB|GB|TB)\b"#, options: .regularExpression) {
                    totalSize = String(line[sizeRange])
                }
            }

            guard inFileList else { continue }

            let normalized = line
                .replacingOccurrences(of: "✓", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if normalized.hasPrefix("/") || normalized.hasPrefix("~") {
                let path = expandHome(normalized)
                if path == app.path {
                    appBundlePath = path
                } else {
                    relatedFiles.append(path)
                }
            } else if normalized.hasPrefix("System:") {
                systemFiles.append(String(normalized.dropFirst("System:".count)).trimmingCharacters(in: .whitespaces))
            } else if normalized.hasPrefix("Review only:") {
                reviewOnlyFiles.append(String(normalized.dropFirst("Review only:".count)).trimmingCharacters(in: .whitespaces))
            }
        }

        if appBundlePath == nil {
            appBundlePath = app.path
        }
        if itemCount == 0 {
            itemCount = (appBundlePath == nil ? 0 : 1) + relatedFiles.count + systemFiles.count
        }

        return UninstallPreview(
            appName: app.name,
            appBundlePath: appBundlePath,
            relatedFiles: Array(Set(relatedFiles)).sorted(),
            systemFiles: Array(Set(systemFiles)).sorted(),
            reviewOnlyFiles: Array(Set(reviewOnlyFiles)).sorted(),
            totalSize: totalSize,
            itemCount: itemCount,
            rawOutput: output
        )
    }

    private func stripANSI(_ string: String) -> String {
        string.replacingOccurrences(of: "\u{001B}\\[[0-?]*[ -/]*[@-~]", with: "", options: .regularExpression)
    }

    private func expandHome(_ path: String) -> String {
        if path == "~" {
            return FileManager.default.homeDirectoryForCurrentUser.path
        }
        if path.hasPrefix("~/") {
            return FileManager.default.homeDirectoryForCurrentUser.appending(path: String(path.dropFirst(2))).path
        }
        return path
    }
}

enum Localizer {
    static func text(_ key: String, language: AppLanguage) -> String {
        dictionaries[language]?[key] ?? dictionaries[.simplifiedChinese]?[key] ?? key
    }

    private static let dictionaries: [AppLanguage: [String: String]] = [
        .simplifiedChinese: [
            "dashboard": "总览",
            "smartCare": "智能看护",
            "cleanup": "清理",
            "protection": "保护",
            "performance": "性能",
            "toReview": "待预览",
            "tasksReady": "个任务可执行",
            "dashboardScanTitle": "准备好了解你的 Mac",
            "dashboardScanSubtitle": "先扫描，再决定清理、卸载或优化。",
            "quickActions": "快捷操作",
            "clean": "清理预览",
            "analyze": "磁盘分析",
            "uninstall": "应用卸载",
            "optimize": "系统优化",
            "commandCenter": "命令中心",
            "status": "系统状态",
            "history": "操作历史",
            "settings": "设置",
            "subtitle": "可视化清理、卸载、分析与状态监控工作台",
            "dashboardHeroTitle": "更懂你的 Mac。\n清理更安心。",
            "dashboardHeroSubtitle": "扫描空间占用、应用残留和系统状态。先预览，再确认，把每一步都交代清楚。",
            "previewFirst": "先预览",
            "trashProtected": "废纸篓保护",
            "localOnly": "本地执行",
            "largeFileFeature": "大文件",
            "largeFileFeatureDetail": "找出超过 50MB 的文件和占用空间。",
            "duplicateFileFeature": "重复文件",
            "duplicateFileFeatureDetail": "检索可能重复的文件，减少无效占用。",
            "similarPhotosFeature": "相似照片",
            "similarPhotosFeatureDetail": "查找可对比的相似图片与媒体文件。",
            "appUninstallFeature": "应用卸载",
            "appUninstallFeatureDetail": "移除应用本体，并预览相关文件。",
            "privacyCleanFeature": "隐私清理",
            "privacyCleanFeatureDetail": "清理浏览器痕迹、日志和本地缓存。",
            "startupItemsFeature": "启动项",
            "startupItemsFeatureDetail": "查看可能随系统启动的服务和工具。",
            "diskAnalyzerFeature": "磁盘分析",
            "diskAnalyzerFeatureDetail": "深入查看目录、隐藏空间和大文件。",
            "moleLabFeature": "Mole Lab",
            "moleLabFeatureDetail": "查看历史记录和更多实验功能。",
            "optimizeStorage": "空间优化",
            "optimizeStorageDetail": "结合清理预览、磁盘分析和安全规则，维护可释放空间。",
            "optimizeStartup": "启动与服务",
            "optimizeStartupDetail": "检查可能影响启动速度的应用、后台服务和工具。",
            "optimizeProtection": "保护规则",
            "optimizeProtectionDetail": "继续使用 Mole 的废纸篓、白名单、认证与会话保护策略。",
            "operationHistory": "操作记录",
            "optimizePreview": "预览优化",
            "optimizePreviewDetail": "读取系统状态并展示将执行的维护项目。",
            "optimizeRun": "执行优化",
            "optimizeRunDetail": "运行 Mole 的系统维护任务。",
            "optimizeWhitelist": "优化白名单",
            "optimizeWhitelistDetail": "查看或管理优化保护规则。",
            "touchIDStatus": "Touch ID 状态",
            "touchIDStatusDetail": "检查 sudo 是否已启用 Touch ID。",
            "moleCommandCenter": "Mole 命令中心",
            "allMoleCommands": "覆盖命令行能力",
            "cleanPreviewCommand": "预览清理",
            "cleanPreviewCommandDetail": "扫描可清理项目，不删除。",
            "cleanRunCommand": "执行清理",
            "cleanRunCommandDetail": "按 Mole 规则清理并移动到废纸篓。",
            "cleanWhitelistCommand": "清理白名单",
            "cleanWhitelistCommandDetail": "管理受保护的缓存和路径。",
            "installerPreviewCommand": "预览安装包清理",
            "installerPreviewCommandDetail": "查找可清理安装包。",
            "installerRunCommand": "清理安装包",
            "installerRunCommandDetail": "执行安装包清理流程。",
            "purgePreviewCommand": "预览项目清理",
            "purgePreviewCommandDetail": "扫描项目产物，不删除。",
            "purgeRunCommand": "清理项目产物",
            "purgeRunCommandDetail": "清理旧构建缓存和项目临时产物。",
            "purgeIncludeEmptyCommand": "包含空目录",
            "purgeIncludeEmptyCommandDetail": "连同零大小项目目录一起预览。",
            "purgePathsCommand": "项目扫描路径",
            "purgePathsCommandDetail": "查看项目清理扫描目录配置。",
            "historyCommand": "查看历史",
            "historyCommandDetail": "显示近期操作记录。",
            "historyJSONCommand": "导出历史 JSON",
            "historyJSONCommandDetail": "输出机器可读历史数据。",
            "completionPreviewCommand": "预览补全安装",
            "completionPreviewCommandDetail": "检查 shell 补全将修改的配置。",
            "completionBashCommand": "生成 Bash 补全",
            "completionBashCommandDetail": "输出 Bash completion 脚本。",
            "completionZshCommand": "生成 Zsh 补全",
            "completionZshCommandDetail": "输出 Zsh completion 脚本。",
            "completionFishCommand": "生成 Fish 补全",
            "completionFishCommandDetail": "输出 Fish completion 脚本。",
            "touchIDPreviewCommand": "预览 Touch ID",
            "touchIDPreviewCommandDetail": "查看启用 Touch ID 会修改什么。",
            "touchIDEnableCommand": "启用 Touch ID",
            "touchIDEnableCommandDetail": "为 sudo 配置 Touch ID。",
            "touchIDDisablePreviewCommand": "预览关闭 Touch ID",
            "touchIDDisablePreviewCommandDetail": "查看关闭 Touch ID 会修改什么。",
            "statusCommand": "查看状态",
            "statusCommandDetail": "运行 Mole 系统状态监控。",
            "updateForceCommand": "强制更新稳定版",
            "updateForceCommandDetail": "重新安装最新稳定版，需要网络与权限。",
            "updateNightlyCommand": "更新到夜间版",
            "updateNightlyCommandDetail": "安装 main 分支构建，适合测试新功能。",
            "versionCommand": "版本信息",
            "versionCommandDetail": "显示 Mole 版本与环境。",
            "helpCommand": "帮助信息",
            "helpCommandDetail": "显示 Mole 命令帮助。",
            "removePreviewCommand": "预览移除 Mole",
            "removePreviewCommandDetail": "仅预览，不会移除 Mole。",
            "searchPlaceholder": "搜索应用、路径或历史",
            "refresh": "刷新",
            "scan": "扫描",
            "scanning": "扫描中",
            "startScan": "开始扫描",
            "safeMode": "安全模式开启",
            "safeModeDetail": "默认先预览，不会直接删除。执行清理时继续使用 Mole 的 Trash 与保护规则。",
            "moleModules": "Mole 功能",
            "authorization": "授权",
            "permissionStatus": "权限状态",
            "fullDiskAccess": "完全磁盘访问",
            "adminAuthorization": "管理员授权",
            "openFullDiskAccess": "打开权限设置",
            "checkAgain": "重新检测",
            "granted": "已授权",
            "notGranted": "未授权",
            "available": "已可用",
            "requiresAuthorization": "执行时需要授权",
            "unknown": "未知",
            "healthScore": "健康分",
            "reclaimable": "可释放空间",
            "diskUsage": "磁盘使用",
            "activeAlerts": "活跃提醒",
            "statusHealthy": "状态良好",
            "fromCaches": "来自缓存、构建产物、安装包",
            "scanWorkflow": "扫描工作流",
            "readOnlyPreview": "只读预览，不执行删除",
            "systemStatus": "系统状态",
            "health": "健康",
            "memory": "内存",
            "disk": "磁盘",
            "cpuAndGpu": "CPU 与 GPU",
            "networkAndPower": "网络与电源",
            "storage": "存储",
            "topProcesses": "高负载进程",
            "loadAverage": "负载均值",
            "cpuCores": "核心",
            "temperature": "温度",
            "download": "下载",
            "upload": "上传",
            "battery": "电池",
            "batteryHealth": "电池健康度",
            "chargingStatus": "充电状态",
            "remainingTime": "剩余时间",
            "cycleCount": "循环次数",
            "charging": "充电中",
            "discharging": "使用电池",
            "charged": "已充满",
            "proxy": "代理",
            "uptime": "运行",
            "logicalCPU": "逻辑核心",
            "network": "网络",
            "notAvailable": "不可用",
            "off": "关闭",
            "read": "读",
            "write": "写",
            "cleanupSuggestions": "清理建议",
            "projectArtifacts": "项目产物",
            "deleteProtection": "删除保护",
            "enabled": "开启",
            "liveLoad": "实时负载",
            "nextStep": "下一步",
            "recommended": "推荐",
            "readOnly": "只读",
            "confirm": "需确认",
            "readyToScan": "准备扫描",
            "readingStatus": "读取系统状态",
            "loadingApps": "扫描应用列表",
            "analyzingDisk": "分析磁盘空间",
            "readingHistory": "读取操作历史",
            "buildingPreview": "生成清理预览",
            "scanComplete": "扫描完成",
            "browserCache": "浏览器缓存",
            "browserCacheDetail": "Chrome, Safari, Firefox cache",
            "developerCache": "开发工具缓存",
            "developerCacheDetail": "Xcode DerivedData, npm, Go build cache",
            "systemLogs": "系统日志",
            "systemLogsDetail": "~/Library/Logs, DiagnosticReports",
            "aiToolCache": "AI 工具缓存",
            "aiToolCacheDetail": "保留 auth、session、模型与配置文件",
            "trash": "废纸篓",
            "trashDetail": "需要单独确认",
            "lowRisk": "低",
            "mediumRisk": "中",
            "highRisk": "高",
            "selectedReclaimable": "本次选择可释放",
            "scanSummary": "扫描摘要",
            "scanRedundantFiles": "扫描冗余文件",
            "scanRedundantFilesDetail": "使用 Mole dry-run 扫描可清理项目，不删除文件。",
            "waitingForScan": "等待扫描",
            "cleanScanReadyTitle": "点击扫描后查看清理分类",
            "cleanScanReadyDetail": "进入页面不会自动扫描。点击上方扫描按钮后，将按浏览器缓存、开发工具缓存、系统日志等分类展示结果。",
            "cleanScanHint": "扫描只会统计分类和路径，不会删除文件。",
            "viewMolePreview": "预览将清理内容",
            "previewCleanupList": "预览清单",
            "previewCleanupListDetail": "这里展示 Mole 预演清理流程得到的清单，只用于确认范围，不会删除文件。",
            "clearPreview": "清空预览",
            "loading": "加载中",
            "categoryDetails": "分类详情",
            "categoryAlreadyClean": "这个分类暂时没有发现明显可清理内容。",
            "scanBeforeDetails": "请先点击上方扫描按钮，再查看每个分类包含的路径。",
            "includedPaths": "包含路径",
            "scanBeforeCleanup": "请先扫描冗余文件，再确认清理。",
            "noneSelected": "未选择",
            "selectedItems": "已选项目",
            "selectAll": "全选",
            "deselectAll": "取消全选",
            "selectCleanItemsFirst": "请先勾选要清理的项目。",
            "cleanAllScannedItems": "清理全部扫描项目",
            "cleanSelectedCategory": "只清理当前分类",
            "cleanSelectedPaths": "清理已选项目",
            "cleanAllScopeHint": "全部清理会调用 Mole clean，按 Mole 规则统一处理扫描到的清理项目。",
            "cleanScopeNote": "上方显示当前已勾选项目的预计大小。全部清理仍会按 Mole 规则处理完整扫描范围。",
            "selectedCardDetailOnly": "勾选要清理的路径，执行时会先移动到废纸篓。",
            "estimatedByLocalPaths": "上方大小为本地路径估算，完整清单以 Mole 预览结果为准。",
            "moleCleanRules": "Mole 清理规则",
            "cleanConfirmationTitle": "确认执行清理？",
            "cleanConfirmationMessage": "这将按 Mole 规则清理全部扫描项目，不是只清理当前选中的卡片。Mole 会继续使用废纸篓、白名单和保护规则。",
            "cleanCategoryConfirmationMessage": "将只清理「%@」分类中列出的路径，并先移动到废纸篓。其他分类不会处理。",
            "cleanSelectedPathsConfirmationMessage": "将只清理「%@」中已勾选的 %d 个项目，并先移动到废纸篓。未勾选项目不会处理。",
            "cleanCompleteTitle": "Mole 清理完成",
            "exportList": "导出路径清单",
            "confirmCleanup": "确认清理",
            "diskMap": "磁盘空间图",
            "largeFiles": "大文件与隐藏空间",
            "startDiskAnalyze": "开始分析",
            "analyzeIntroTitle": "分析磁盘空间占用",
            "analyzeIntroDetail": "点击后读取 Mole 的磁盘分析结果，按目录和大文件展示占用情况。点击方块可进入目录，删除操作会先移动到废纸篓并要求确认。",
            "analyzeEmptyDetail": "选择一个范围开始分析。结果会显示当前路径下占用最大的目录和文件。",
            "homeFolder": "主目录",
            "rootDisk": "根磁盘",
            "applicationsFolder": "应用目录",
            "downloadsFolder": "下载目录",
            "analyzedPath": "分析路径",
            "currentAnalyzePath": "当前位置",
            "backToPreviousFolder": "返回上一级",
            "totalSize": "总占用",
            "fileCount": "文件数量",
            "noLargeFilesFound": "暂未发现明显的大文件。",
            "moreItems": "更多项目",
            "showMoreItems": "显示更多 %@ 项",
            "collapse": "收起",
            "openFolder": "打开",
            "clickToOpenFolder": "点击或双击进入目录",
            "revealInFinder": "在 Finder 中显示",
            "analyzeDeleteConfirmationTitle": "确认移到废纸篓？",
            "analyzeDeleteConfirmationMessage": "将把「%@」移到废纸篓，预计占用 %@。\n\n路径：%@\n\n请确认这不是系统、工作资料或仍在使用的文件夹。移到废纸篓后通常可以恢复，但清空废纸篓后将无法恢复。",
            "analyzeDeleteCompleteTitle": "已移到废纸篓",
            "analyzeMovedToTrashInline": "已将「%@」移到废纸篓，正在刷新空间图。",
            "appInventory": "应用清单",
            "scanLeftovers": "扫描残留",
            "installed": "已安装",
            "leftovers": "残留",
            "extensions": "扩展",
            "appBundle": "应用本体",
            "relatedFiles": "相关文件",
            "leftoverFiles": "残留文件",
            "supportFiles": "应用支持文件",
            "cacheFiles": "缓存文件",
            "preferenceFiles": "偏好设置",
            "logFiles": "日志文件",
            "systemFiles": "系统相关文件",
            "reviewOnlyFiles": "需人工确认",
            "otherFiles": "其他文件",
            "readingRelatedFiles": "正在读取残留文件",
            "files": "文件项",
            "defaultDeleteMode": "默认删除模式",
            "moveToTrashNote": "卸载会先移动到废纸篓。系统应用、白名单路径、认证与会话数据默认跳过。",
            "showFiles": "显示文件",
            "uninstallSelected": "卸载所选",
            "operation": "操作",
            "result": "结果",
            "path": "路径",
            "time": "时间",
            "safetyExecution": "安全与执行",
            "alwaysDryRun": "执行前始终先预览",
            "moveToTrash": "移动到废纸篓",
            "movingToTrash": "正在移到废纸篓",
            "allowAdmin": "允许管理员任务",
            "whitelist": "白名单",
            "repository": "仓库路径",
            "language": "语言",
            "dryRunOutput": "预览结果",
            "backendPreview": "来自 Mole 本地 CLI 后端，仅预览，不执行删除",
            "previewOnlyTitle": "这是安全预览",
            "previewOnlyDescription": "仅展示将要处理的项目，不会删除或修改文件。",
            "previewOnlyMessage": "你可以先确认应用本体、相关文件和风险提示；只有点击确认卸载或确认清理后，Mole 才会把可处理项目移动到废纸篓。",
            "operationCompleteTitle": "处理完成",
            "operationCompleteSubtitle": "已按 Mole 的安全规则完成操作。",
            "operationCompleteMessage": "应用本体已从原路径移除，相关结果已同步到应用清单。你可以在下方查看技术详情，或点击知道了返回继续操作。",
            "operationNeedsReviewTitle": "需要确认结果",
            "operationNeedsReviewSubtitle": "操作已结束，但仍有项目需要你查看。",
            "operationNeedsReviewMessage": "部分文件可能因为权限、保护规则或仍在使用而未处理。请查看下方技术详情，再决定是否手动处理。",
            "technicalDetails": "技术详情",
            "copyOutput": "复制输出",
            "lines": "行",
            "cleanDryRunTitle": "Mole 清理预览",
            "uninstallDryRunTitle": "Mole 卸载预览",
            "previewWithMole": "用 Mole 预览",
            "running": "运行中",
            "close": "关闭",
            "done": "知道了",
            "emptyOutput": "命令没有输出。",
            "noAppSelected": "请先选择一个应用。",
            "notScanned": "未扫描",
            "noActiveAlerts": "暂无提醒",
            "memoryUsage": "内存使用",
            "dryRunOnly": "预览后显示",
            "runDryRunForRelatedFiles": "点击扫描残留，会读取真实相关文件；预览阶段不会删除。",
            "scanBeforeUninstall": "请先点击“扫描残留”，确认将处理的应用本体和相关文件后再卸载。",
            "scanBeforeUninstallShort": "先扫描再卸载",
            "noneFound": "未发现",
            "noRelatedFilesFound": "未发现额外相关文件。",
            "scanningLeftovers": "扫描中",
            "leftoverScanTitle": "残留扫描",
            "confirmUninstallTitle": "确认卸载应用？",
            "confirmUninstallMessage": "Mole 会把所选应用和可处理的相关文件移动到废纸篓。这一步会真正执行，不再只是预览。",
            "uninstallCompleteTitle": "卸载完成",
            "uninstallIncompleteTitle": "卸载未完成",
            "uninstallRemovedFromList": "已确认应用本体不在原路径，并已从应用清单移除。",
            "uninstallStillPresent": "卸载命令已结束，但应用本体仍在原路径。可能被系统权限、运行中的进程或官方卸载器要求拦截，请查看上方输出。",
            "commandTimedOutTitle": "这个操作执行时间过长，已自动停止。",
            "commandTimedOutDetail": "可能是正在扫描大量应用、磁盘路径或等待系统权限。你可以稍后重试，或先运行预览确认范围。",
            "cancel": "取消"
        ],
        .traditionalChinese: [
            "dashboard": "總覽",
            "smartCare": "智慧看護",
            "cleanup": "清理",
            "protection": "保護",
            "performance": "效能",
            "toReview": "待預覽",
            "tasksReady": "個任務可執行",
            "dashboardScanTitle": "準備好了解你的 Mac",
            "dashboardScanSubtitle": "先掃描，再決定清理、卸載或最佳化。",
            "quickActions": "快捷操作",
            "clean": "清理預覽",
            "analyze": "磁碟分析",
            "uninstall": "應用程式卸載",
            "optimize": "系統最佳化",
            "commandCenter": "命令中心",
            "status": "系統狀態",
            "history": "操作記錄",
            "settings": "設定",
            "subtitle": "視覺化清理、卸載、分析與狀態監控工作台",
            "dashboardHeroTitle": "更懂你的 Mac。\n清理更安心。",
            "dashboardHeroSubtitle": "掃描空間佔用、應用程式殘留和系統狀態。先預覽，再確認，把每一步都交代清楚。",
            "previewFirst": "先預覽",
            "trashProtected": "廢紙簍保護",
            "localOnly": "本機執行",
            "largeFileFeature": "大型檔案",
            "largeFileFeatureDetail": "找出超過 50MB 的檔案和佔用空間。",
            "duplicateFileFeature": "重複檔案",
            "duplicateFileFeatureDetail": "檢索可能重複的檔案，減少無效佔用。",
            "similarPhotosFeature": "相似照片",
            "similarPhotosFeatureDetail": "查找可對比的相似圖片與媒體檔案。",
            "appUninstallFeature": "應用程式卸載",
            "appUninstallFeatureDetail": "移除應用程式本體，並預覽相關檔案。",
            "privacyCleanFeature": "隱私清理",
            "privacyCleanFeatureDetail": "清理瀏覽器痕跡、日誌和本機快取。",
            "startupItemsFeature": "啟動項目",
            "startupItemsFeatureDetail": "查看可能隨系統啟動的服務和工具。",
            "diskAnalyzerFeature": "磁碟分析",
            "diskAnalyzerFeatureDetail": "深入查看目錄、隱藏空間和大型檔案。",
            "moleLabFeature": "Mole Lab",
            "moleLabFeatureDetail": "查看操作記錄和更多實驗功能。",
            "optimizeStorage": "空間最佳化",
            "optimizeStorageDetail": "結合清理預覽、磁碟分析和安全規則，維護可釋放空間。",
            "optimizeStartup": "啟動與服務",
            "optimizeStartupDetail": "檢查可能影響啟動速度的應用程式、背景服務和工具。",
            "optimizeProtection": "保護規則",
            "optimizeProtectionDetail": "繼續使用 Mole 的廢紙簍、白名單、認證與工作階段保護策略。",
            "operationHistory": "操作記錄",
            "optimizePreview": "預覽最佳化",
            "optimizePreviewDetail": "讀取系統狀態並展示將執行的維護項目。",
            "optimizeRun": "執行最佳化",
            "optimizeRunDetail": "執行 Mole 的系統維護任務。",
            "optimizeWhitelist": "最佳化白名單",
            "optimizeWhitelistDetail": "查看或管理最佳化保護規則。",
            "touchIDStatus": "Touch ID 狀態",
            "touchIDStatusDetail": "檢查 sudo 是否已啟用 Touch ID。",
            "moleCommandCenter": "Mole 命令中心",
            "allMoleCommands": "覆蓋命令列能力",
            "cleanPreviewCommand": "預覽清理",
            "cleanPreviewCommandDetail": "掃描可清理項目，不刪除。",
            "cleanRunCommand": "執行清理",
            "cleanRunCommandDetail": "依 Mole 規則清理並移到廢紙簍。",
            "cleanWhitelistCommand": "清理白名單",
            "cleanWhitelistCommandDetail": "管理受保護的快取和路徑。",
            "installerPreviewCommand": "預覽安裝包清理",
            "installerPreviewCommandDetail": "查找可清理安裝包。",
            "installerRunCommand": "清理安裝包",
            "installerRunCommandDetail": "執行安裝包清理流程。",
            "purgePreviewCommand": "預覽專案清理",
            "purgePreviewCommandDetail": "掃描專案產物，不刪除。",
            "purgeRunCommand": "清理專案產物",
            "purgeRunCommandDetail": "清理舊建置快取和專案暫存產物。",
            "purgeIncludeEmptyCommand": "包含空目錄",
            "purgeIncludeEmptyCommandDetail": "連同零大小專案目錄一起預覽。",
            "purgePathsCommand": "專案掃描路徑",
            "purgePathsCommandDetail": "查看專案清理掃描目錄設定。",
            "historyCommand": "查看記錄",
            "historyCommandDetail": "顯示近期操作記錄。",
            "historyJSONCommand": "匯出記錄 JSON",
            "historyJSONCommandDetail": "輸出機器可讀記錄資料。",
            "completionPreviewCommand": "預覽補全安裝",
            "completionPreviewCommandDetail": "檢查 shell 補全將修改的設定。",
            "completionBashCommand": "產生 Bash 補全",
            "completionBashCommandDetail": "輸出 Bash completion 腳本。",
            "completionZshCommand": "產生 Zsh 補全",
            "completionZshCommandDetail": "輸出 Zsh completion 腳本。",
            "completionFishCommand": "產生 Fish 補全",
            "completionFishCommandDetail": "輸出 Fish completion 腳本。",
            "touchIDPreviewCommand": "預覽 Touch ID",
            "touchIDPreviewCommandDetail": "查看啟用 Touch ID 會修改什麼。",
            "touchIDEnableCommand": "啟用 Touch ID",
            "touchIDEnableCommandDetail": "為 sudo 設定 Touch ID。",
            "touchIDDisablePreviewCommand": "預覽關閉 Touch ID",
            "touchIDDisablePreviewCommandDetail": "查看關閉 Touch ID 會修改什麼。",
            "statusCommand": "查看狀態",
            "statusCommandDetail": "執行 Mole 系統狀態監控。",
            "updateForceCommand": "強制更新穩定版",
            "updateForceCommandDetail": "重新安裝最新穩定版，需要網路與權限。",
            "updateNightlyCommand": "更新到夜間版",
            "updateNightlyCommandDetail": "安裝 main 分支建置，適合測試新功能。",
            "versionCommand": "版本資訊",
            "versionCommandDetail": "顯示 Mole 版本與環境。",
            "helpCommand": "說明資訊",
            "helpCommandDetail": "顯示 Mole 命令說明。",
            "removePreviewCommand": "預覽移除 Mole",
            "removePreviewCommandDetail": "僅預覽，不會移除 Mole。",
            "searchPlaceholder": "搜尋應用程式、路徑或記錄",
            "refresh": "重新整理",
            "scan": "掃描",
            "scanning": "掃描中",
            "startScan": "開始掃描",
            "safeMode": "安全模式開啟",
            "safeModeDetail": "預設先預覽，不會直接刪除。執行清理時會繼續使用 Mole 的 Trash 與保護規則。",
            "moleModules": "Mole 功能",
            "authorization": "授權",
            "permissionStatus": "權限狀態",
            "fullDiskAccess": "完整磁碟取用",
            "adminAuthorization": "管理員授權",
            "openFullDiskAccess": "開啟權限設定",
            "checkAgain": "重新偵測",
            "granted": "已授權",
            "notGranted": "未授權",
            "available": "已可用",
            "requiresAuthorization": "執行時需要授權",
            "unknown": "未知",
            "healthScore": "健康分",
            "reclaimable": "可釋放空間",
            "diskUsage": "磁碟使用",
            "activeAlerts": "活躍提醒",
            "statusHealthy": "狀態良好",
            "fromCaches": "來自快取、建置產物、安裝包",
            "scanWorkflow": "掃描工作流程",
            "readOnlyPreview": "唯讀預覽，不執行刪除",
            "systemStatus": "系統狀態",
            "health": "健康",
            "memory": "記憶體",
            "disk": "磁碟",
            "cpuAndGpu": "CPU 與 GPU",
            "networkAndPower": "網路與電源",
            "storage": "儲存空間",
            "topProcesses": "高負載行程",
            "loadAverage": "負載平均",
            "cpuCores": "核心",
            "temperature": "溫度",
            "download": "下載",
            "upload": "上傳",
            "battery": "電池",
            "batteryHealth": "電池健康度",
            "chargingStatus": "充電狀態",
            "remainingTime": "剩餘時間",
            "cycleCount": "循環次數",
            "charging": "充電中",
            "discharging": "使用電池",
            "charged": "已充滿",
            "proxy": "代理",
            "uptime": "運行",
            "logicalCPU": "邏輯核心",
            "network": "網路",
            "notAvailable": "不可用",
            "off": "關閉",
            "read": "讀",
            "write": "寫",
            "cleanupSuggestions": "清理建議",
            "projectArtifacts": "專案產物",
            "deleteProtection": "刪除保護",
            "enabled": "開啟",
            "liveLoad": "即時負載",
            "nextStep": "下一步",
            "recommended": "推薦",
            "readOnly": "唯讀",
            "confirm": "需確認",
            "readyToScan": "準備掃描",
            "readingStatus": "讀取系統狀態",
            "loadingApps": "掃描應用程式列表",
            "analyzingDisk": "分析磁碟空間",
            "readingHistory": "讀取操作記錄",
            "buildingPreview": "產生清理預覽",
            "scanComplete": "掃描完成",
            "browserCache": "瀏覽器快取",
            "browserCacheDetail": "Chrome, Safari, Firefox cache",
            "developerCache": "開發工具快取",
            "developerCacheDetail": "Xcode DerivedData, npm, Go build cache",
            "systemLogs": "系統日誌",
            "systemLogsDetail": "~/Library/Logs, DiagnosticReports",
            "aiToolCache": "AI 工具快取",
            "aiToolCacheDetail": "保留 auth、session、模型與設定檔",
            "trash": "廢紙簍",
            "trashDetail": "需要單獨確認",
            "lowRisk": "低",
            "mediumRisk": "中",
            "highRisk": "高",
            "selectedReclaimable": "本次選擇可釋放",
            "scanSummary": "掃描摘要",
            "scanRedundantFiles": "掃描冗餘檔案",
            "scanRedundantFilesDetail": "使用 Mole dry-run 掃描可清理項目，不刪除檔案。",
            "waitingForScan": "等待掃描",
            "cleanScanReadyTitle": "點擊掃描後查看清理分類",
            "cleanScanReadyDetail": "進入頁面不會自動掃描。點擊上方掃描按鈕後，會依瀏覽器快取、開發工具快取、系統日誌等分類展示結果。",
            "cleanScanHint": "掃描只會統計分類和路徑，不會刪除檔案。",
            "viewMolePreview": "預覽將清理內容",
            "previewCleanupList": "預覽清單",
            "previewCleanupListDetail": "這裡展示 Mole 預演清理流程得到的清單，只用於確認範圍，不會刪除檔案。",
            "clearPreview": "清空預覽",
            "loading": "載入中",
            "categoryDetails": "分類詳情",
            "categoryAlreadyClean": "這個分類暫時沒有發現明顯可清理內容。",
            "scanBeforeDetails": "請先點擊上方掃描按鈕，再查看每個分類包含的路徑。",
            "includedPaths": "包含路徑",
            "scanBeforeCleanup": "請先掃描冗餘檔案，再確認清理。",
            "noneSelected": "未選擇",
            "selectedItems": "已選項目",
            "selectAll": "全選",
            "deselectAll": "取消全選",
            "selectCleanItemsFirst": "請先勾選要清理的項目。",
            "cleanAllScannedItems": "清理全部掃描項目",
            "cleanSelectedCategory": "只清理目前分類",
            "cleanSelectedPaths": "清理已選項目",
            "cleanAllScopeHint": "全部清理會呼叫 Mole clean，依 Mole 規則統一處理掃描到的清理項目。",
            "cleanScopeNote": "上方顯示目前已勾選項目的預估大小。全部清理仍會依 Mole 規則處理完整掃描範圍。",
            "selectedCardDetailOnly": "勾選要清理的路徑，執行時會先移到廢紙簍。",
            "estimatedByLocalPaths": "上方大小為本機路徑估算，完整清單以 Mole 預覽結果為準。",
            "moleCleanRules": "Mole 清理規則",
            "cleanConfirmationTitle": "確認執行清理？",
            "cleanConfirmationMessage": "這會依 Mole 規則清理全部掃描項目，不是只清理目前選中的卡片。Mole 會繼續使用廢紙簍、白名單和保護規則。",
            "cleanCategoryConfirmationMessage": "將只清理「%@」分類中列出的路徑，並先移到廢紙簍。其他分類不會處理。",
            "cleanSelectedPathsConfirmationMessage": "將只清理「%@」中已勾選的 %d 個項目，並先移到廢紙簍。未勾選項目不會處理。",
            "cleanCompleteTitle": "Mole 清理完成",
            "exportList": "匯出路徑清單",
            "confirmCleanup": "確認清理",
            "diskMap": "磁碟空間圖",
            "largeFiles": "大型檔案與隱藏空間",
            "startDiskAnalyze": "開始分析",
            "analyzeIntroTitle": "分析磁碟空間占用",
            "analyzeIntroDetail": "點擊後讀取 Mole 的磁碟分析結果，依目錄和大型檔案展示占用情況。點擊方塊可進入目錄，刪除操作會先移到垃圾桶並要求確認。",
            "analyzeEmptyDetail": "選擇一個範圍開始分析。結果會顯示目前路徑下占用最大的目錄和檔案。",
            "homeFolder": "主目錄",
            "rootDisk": "根磁碟",
            "applicationsFolder": "應用程式目錄",
            "downloadsFolder": "下載目錄",
            "analyzedPath": "分析路徑",
            "currentAnalyzePath": "目前位置",
            "backToPreviousFolder": "返回上一層",
            "totalSize": "總占用",
            "fileCount": "檔案數量",
            "noLargeFilesFound": "暫未發現明顯的大型檔案。",
            "moreItems": "更多項目",
            "showMoreItems": "顯示更多 %@ 項",
            "collapse": "收起",
            "openFolder": "打開",
            "clickToOpenFolder": "點擊或雙擊進入資料夾",
            "revealInFinder": "在 Finder 中顯示",
            "analyzeDeleteConfirmationTitle": "確認移到垃圾桶？",
            "analyzeDeleteConfirmationMessage": "將把「%@」移到垃圾桶，預計占用 %@。\n\n路徑：%@\n\n請確認這不是系統、工作資料或仍在使用的資料夾。移到垃圾桶後通常可以恢復，但清空垃圾桶後將無法恢復。",
            "analyzeDeleteCompleteTitle": "已移到垃圾桶",
            "analyzeMovedToTrashInline": "已將「%@」移到垃圾桶，正在重新整理空間圖。",
            "appInventory": "應用程式清單",
            "scanLeftovers": "掃描殘留",
            "installed": "已安裝",
            "leftovers": "殘留",
            "extensions": "擴充",
            "appBundle": "應用程式本體",
            "relatedFiles": "相關檔案",
            "leftoverFiles": "殘留檔案",
            "supportFiles": "應用程式支援檔案",
            "cacheFiles": "快取檔案",
            "preferenceFiles": "偏好設定",
            "logFiles": "日誌檔案",
            "systemFiles": "系統相關檔案",
            "reviewOnlyFiles": "需人工確認",
            "otherFiles": "其他檔案",
            "readingRelatedFiles": "正在讀取殘留檔案",
            "files": "檔案項目",
            "defaultDeleteMode": "預設刪除模式",
            "moveToTrashNote": "卸載會先移到廢紙簍。系統應用程式、白名單路徑、認證與工作階段資料預設跳過。",
            "showFiles": "顯示檔案",
            "uninstallSelected": "卸載所選",
            "operation": "操作",
            "result": "結果",
            "path": "路徑",
            "time": "時間",
            "safetyExecution": "安全與執行",
            "alwaysDryRun": "執行前永遠先預覽",
            "moveToTrash": "移到廢紙簍",
            "movingToTrash": "正在移到廢紙簍",
            "allowAdmin": "允許管理員任務",
            "whitelist": "白名單",
            "repository": "倉庫路徑",
            "language": "語言",
            "dryRunOutput": "預覽結果",
            "backendPreview": "來自 Mole 本地 CLI 後端，僅預覽，不執行刪除",
            "previewOnlyTitle": "這是安全預覽",
            "previewOnlyDescription": "僅展示將要處理的項目，不會刪除或修改檔案。",
            "previewOnlyMessage": "你可以先確認應用程式本體、相關檔案和風險提示；只有點擊確認卸載或確認清理後，Mole 才會把可處理項目移到廢紙簍。",
            "operationCompleteTitle": "處理完成",
            "operationCompleteSubtitle": "已依照 Mole 的安全規則完成操作。",
            "operationCompleteMessage": "應用程式本體已從原路徑移除，相關結果已同步到應用程式清單。你可以在下方查看技術詳情，或點擊知道了返回繼續操作。",
            "operationNeedsReviewTitle": "需要確認結果",
            "operationNeedsReviewSubtitle": "操作已結束，但仍有項目需要你查看。",
            "operationNeedsReviewMessage": "部分檔案可能因為權限、保護規則或仍在使用而未處理。請查看下方技術詳情，再決定是否手動處理。",
            "technicalDetails": "技術詳情",
            "copyOutput": "複製輸出",
            "lines": "行",
            "cleanDryRunTitle": "Mole 清理預覽",
            "uninstallDryRunTitle": "Mole 卸載預覽",
            "previewWithMole": "用 Mole 預覽",
            "running": "執行中",
            "close": "關閉",
            "done": "知道了",
            "emptyOutput": "命令沒有輸出。",
            "noAppSelected": "請先選擇一個應用程式。",
            "notScanned": "未掃描",
            "noActiveAlerts": "暫無提醒",
            "memoryUsage": "記憶體使用",
            "dryRunOnly": "預覽後顯示",
            "runDryRunForRelatedFiles": "點擊掃描殘留，會讀取真實相關檔案；預覽階段不會刪除。",
            "scanBeforeUninstall": "請先點擊「掃描殘留」，確認將處理的應用程式本體和相關檔案後再卸載。",
            "scanBeforeUninstallShort": "先掃描再卸載",
            "noneFound": "未發現",
            "noRelatedFilesFound": "未發現額外相關檔案。",
            "scanningLeftovers": "掃描中",
            "leftoverScanTitle": "殘留掃描",
            "confirmUninstallTitle": "確認卸載應用程式？",
            "confirmUninstallMessage": "Mole 會把所選應用程式和可處理的相關檔案移到廢紙簍。這一步會真正執行，不再只是預覽。",
            "uninstallCompleteTitle": "卸載完成",
            "uninstallIncompleteTitle": "卸載未完成",
            "uninstallRemovedFromList": "已確認應用程式本體不在原路徑，並已從應用程式清單移除。",
            "uninstallStillPresent": "卸載命令已結束，但應用程式本體仍在原路徑。可能被系統權限、執行中的行程或官方卸載器要求攔截，請查看上方輸出。",
            "commandTimedOutTitle": "這個操作執行時間過長，已自動停止。",
            "commandTimedOutDetail": "可能是正在掃描大量應用程式、磁碟路徑或等待系統權限。你可以稍後重試，或先執行預覽確認範圍。",
            "cancel": "取消"
        ],
        .english: [
            "dashboard": "Dashboard",
            "smartCare": "Smart Care",
            "cleanup": "Cleanup",
            "protection": "Protection",
            "performance": "Performance",
            "toReview": "to review",
            "tasksReady": "tasks ready",
            "dashboardScanTitle": "Ready to read your Mac",
            "dashboardScanSubtitle": "Scan first, then choose cleanup, uninstall, or optimize.",
            "quickActions": "Quick Actions",
            "clean": "Clean Preview",
            "analyze": "Disk Analyze",
            "uninstall": "Uninstaller",
            "optimize": "Optimize",
            "commandCenter": "Command Center",
            "status": "Status",
            "history": "History",
            "settings": "Settings",
            "subtitle": "A visual workspace for cleanup, uninstall, analysis, and system status.",
            "dashboardHeroTitle": "Know your Mac better.\nClean with confidence.",
            "dashboardHeroSubtitle": "Scan space usage, app leftovers, and system status. Preview first, confirm later, and keep every step understandable.",
            "previewFirst": "Preview first",
            "trashProtected": "Trash protected",
            "localOnly": "Local only",
            "largeFileFeature": "Large File",
            "largeFileFeatureDetail": "Find files larger than 50MB and heavy folders.",
            "duplicateFileFeature": "Duplicate File",
            "duplicateFileFeatureDetail": "Check likely duplicate files and reclaim wasted space.",
            "similarPhotosFeature": "Similar Photos",
            "similarPhotosFeatureDetail": "Find comparable images and media files.",
            "appUninstallFeature": "App Uninstall",
            "appUninstallFeatureDetail": "Remove apps and preview associated files.",
            "privacyCleanFeature": "Privacy Clean",
            "privacyCleanFeatureDetail": "Clean browser traces, logs, and local caches.",
            "startupItemsFeature": "Startup Items",
            "startupItemsFeatureDetail": "Review services and tools running at startup.",
            "diskAnalyzerFeature": "Disk Analyzer",
            "diskAnalyzerFeatureDetail": "Inspect folders, hidden space, and large files.",
            "moleLabFeature": "Mole Lab",
            "moleLabFeatureDetail": "Review history and experimental tools.",
            "optimizeStorage": "Storage Optimization",
            "optimizeStorageDetail": "Combine cleanup preview, disk analysis, and safety rules to maintain reclaimable space.",
            "optimizeStartup": "Startup & Services",
            "optimizeStartupDetail": "Check apps, background services, and tools that may affect startup speed.",
            "optimizeProtection": "Protection Rules",
            "optimizeProtectionDetail": "Keep using Mole's Trash routing, whitelist, credential, and session protection rules.",
            "operationHistory": "Operation History",
            "optimizePreview": "Preview Optimize",
            "optimizePreviewDetail": "Read system state and show maintenance tasks.",
            "optimizeRun": "Run Optimize",
            "optimizeRunDetail": "Run Mole system maintenance tasks.",
            "optimizeWhitelist": "Optimize Whitelist",
            "optimizeWhitelistDetail": "View or manage protected optimization rules.",
            "touchIDStatus": "Touch ID Status",
            "touchIDStatusDetail": "Check whether sudo Touch ID is enabled.",
            "moleCommandCenter": "Mole Command Center",
            "allMoleCommands": "CLI coverage",
            "cleanPreviewCommand": "Preview Cleanup",
            "cleanPreviewCommandDetail": "Scan cleanable items without deleting.",
            "cleanRunCommand": "Run Cleanup",
            "cleanRunCommandDetail": "Clean using Mole rules and Trash routing.",
            "cleanWhitelistCommand": "Cleanup Whitelist",
            "cleanWhitelistCommandDetail": "Manage protected caches and paths.",
            "installerPreviewCommand": "Preview Installers",
            "installerPreviewCommandDetail": "Find removable installer packages.",
            "installerRunCommand": "Clean Installers",
            "installerRunCommandDetail": "Run installer cleanup.",
            "purgePreviewCommand": "Preview Project Purge",
            "purgePreviewCommandDetail": "Scan project artifacts without deleting.",
            "purgeRunCommand": "Clean Project Artifacts",
            "purgeRunCommandDetail": "Remove old build caches and temporary project artifacts.",
            "purgeIncludeEmptyCommand": "Include Empty Dirs",
            "purgeIncludeEmptyCommandDetail": "Preview zero-size project artifact folders too.",
            "purgePathsCommand": "Project Scan Paths",
            "purgePathsCommandDetail": "View project purge scan path settings.",
            "historyCommand": "Show History",
            "historyCommandDetail": "Show recent operation history.",
            "historyJSONCommand": "Export History JSON",
            "historyJSONCommandDetail": "Output machine-readable history.",
            "completionPreviewCommand": "Preview Completion",
            "completionPreviewCommandDetail": "Check shell config edits before writing.",
            "completionBashCommand": "Generate Bash Completion",
            "completionBashCommandDetail": "Output Bash completion script.",
            "completionZshCommand": "Generate Zsh Completion",
            "completionZshCommandDetail": "Output Zsh completion script.",
            "completionFishCommand": "Generate Fish Completion",
            "completionFishCommandDetail": "Output Fish completion script.",
            "touchIDPreviewCommand": "Preview Touch ID",
            "touchIDPreviewCommandDetail": "See what enabling Touch ID would change.",
            "touchIDEnableCommand": "Enable Touch ID",
            "touchIDEnableCommandDetail": "Configure Touch ID for sudo.",
            "touchIDDisablePreviewCommand": "Preview Disable Touch ID",
            "touchIDDisablePreviewCommandDetail": "See what disabling Touch ID would change.",
            "statusCommand": "Show Status",
            "statusCommandDetail": "Run Mole system status.",
            "updateForceCommand": "Force Stable Update",
            "updateForceCommandDetail": "Reinstall the latest stable release; network and permission may be required.",
            "updateNightlyCommand": "Update to Nightly",
            "updateNightlyCommandDetail": "Install the main-branch build for testing new features.",
            "versionCommand": "Version Info",
            "versionCommandDetail": "Show Mole version and environment.",
            "helpCommand": "Help",
            "helpCommandDetail": "Show Mole command help.",
            "removePreviewCommand": "Preview Remove Mole",
            "removePreviewCommandDetail": "Preview only; Mole will not be removed.",
            "searchPlaceholder": "Search apps, paths, or history",
            "refresh": "Refresh",
            "scan": "Scan",
            "scanning": "Scanning",
            "startScan": "Start Scan",
            "safeMode": "Safe Mode On",
            "safeModeDetail": "Preview first by default. Cleanup continues to use Mole's Trash routing and protection rules.",
            "moleModules": "Mole Modules",
            "authorization": "Authorization",
            "permissionStatus": "Permission Status",
            "fullDiskAccess": "Full Disk Access",
            "adminAuthorization": "Admin Authorization",
            "openFullDiskAccess": "Open Privacy Settings",
            "checkAgain": "Check Again",
            "granted": "Granted",
            "notGranted": "Not Granted",
            "available": "Available",
            "requiresAuthorization": "Requires Authorization",
            "unknown": "Unknown",
            "healthScore": "Health Score",
            "reclaimable": "Reclaimable",
            "diskUsage": "Disk Usage",
            "activeAlerts": "Active Alerts",
            "statusHealthy": "Healthy",
            "fromCaches": "From caches, build artifacts, installers",
            "scanWorkflow": "Scan Workflow",
            "readOnlyPreview": "Read-only preview, no deletion",
            "systemStatus": "System Status",
            "health": "Health",
            "memory": "Memory",
            "disk": "Disk",
            "cpuAndGpu": "CPU & GPU",
            "networkAndPower": "Network & Power",
            "storage": "Storage",
            "topProcesses": "Top Processes",
            "loadAverage": "Load Average",
            "cpuCores": "CPU Cores",
            "temperature": "Temperature",
            "download": "Download",
            "upload": "Upload",
            "battery": "Battery",
            "batteryHealth": "Battery Health",
            "chargingStatus": "Charging Status",
            "remainingTime": "Time Remaining",
            "cycleCount": "Cycle Count",
            "charging": "Charging",
            "discharging": "On Battery",
            "charged": "Charged",
            "proxy": "Proxy",
            "uptime": "Uptime",
            "logicalCPU": "logical CPU",
            "network": "Network",
            "notAvailable": "Not available",
            "off": "Off",
            "read": "Read",
            "write": "Write",
            "cleanupSuggestions": "Cleanup Suggestions",
            "projectArtifacts": "Project Artifacts",
            "deleteProtection": "Deletion Protection",
            "enabled": "On",
            "liveLoad": "Live Load",
            "nextStep": "Next Step",
            "recommended": "Recommended",
            "readOnly": "Read-only",
            "confirm": "Confirm",
            "readyToScan": "Ready to scan",
            "readingStatus": "Reading system status",
            "loadingApps": "Loading app inventory",
            "analyzingDisk": "Analyzing disk space",
            "readingHistory": "Reading history",
            "buildingPreview": "Building cleanup preview",
            "scanComplete": "Scan complete",
            "browserCache": "Browser Cache",
            "browserCacheDetail": "Chrome, Safari, Firefox cache",
            "developerCache": "Developer Cache",
            "developerCacheDetail": "Xcode DerivedData, npm, Go build cache",
            "systemLogs": "System Logs",
            "systemLogsDetail": "~/Library/Logs, DiagnosticReports",
            "aiToolCache": "AI Tool Cache",
            "aiToolCacheDetail": "Keep auth, sessions, models, and config",
            "trash": "Trash",
            "trashDetail": "Requires separate confirmation",
            "lowRisk": "Low",
            "mediumRisk": "Medium",
            "highRisk": "High",
            "selectedReclaimable": "Selected Reclaimable",
            "scanSummary": "Scan Summary",
            "scanRedundantFiles": "Scan Redundant Files",
            "scanRedundantFilesDetail": "Use Mole dry-run to scan cleanable items without deleting files.",
            "waitingForScan": "Waiting for scan",
            "cleanScanReadyTitle": "Scan to view cleanup categories",
            "cleanScanReadyDetail": "This page does not scan automatically. Click the scan button above to show browser cache, developer cache, system logs, and other categories.",
            "cleanScanHint": "Scanning only measures categories and paths. It does not delete files.",
            "viewMolePreview": "Preview Cleanup List",
            "previewCleanupList": "Preview List",
            "previewCleanupListDetail": "This list comes from a Mole dry-run. It helps confirm scope and does not delete files.",
            "clearPreview": "Clear Preview",
            "loading": "Loading",
            "categoryDetails": "Category Details",
            "categoryAlreadyClean": "No obvious cleanable content was found in this category.",
            "scanBeforeDetails": "Click the scan button above first, then review the paths included in each category.",
            "includedPaths": "Included Paths",
            "scanBeforeCleanup": "Scan redundant files before confirming cleanup.",
            "noneSelected": "None selected",
            "selectedItems": "Selected items",
            "selectAll": "Select All",
            "deselectAll": "Deselect All",
            "selectCleanItemsFirst": "Select items to clean first.",
            "cleanAllScannedItems": "Clean All Scanned Items",
            "cleanSelectedCategory": "Clean Current Category Only",
            "cleanSelectedPaths": "Clean Selected Items",
            "cleanAllScopeHint": "Clean all runs Mole clean and lets Mole process scanned cleanup items with its own rules.",
            "cleanScopeNote": "The size above is the current selected-item estimate. Clean all still lets Mole process the full scanned scope.",
            "selectedCardDetailOnly": "Select paths to clean. They are moved to Trash first.",
            "estimatedByLocalPaths": "Sizes above are local path estimates. Mole preview remains the source of truth.",
            "moleCleanRules": "Mole Cleanup Rules",
            "cleanConfirmationTitle": "Run cleanup now?",
            "cleanConfirmationMessage": "This will clean all scanned items using Mole rules, not only the currently selected card. Mole will keep Trash routing, whitelist, and protection rules enabled.",
            "cleanCategoryConfirmationMessage": "Only paths listed under \"%@\" will be cleaned and moved to Trash first. Other categories will not be touched.",
            "cleanSelectedPathsConfirmationMessage": "Only the %2$d selected items under \"%1$@\" will be cleaned and moved to Trash first. Unselected items will not be touched.",
            "cleanCompleteTitle": "Mole Cleanup Complete",
            "exportList": "Export Path List",
            "confirmCleanup": "Confirm Cleanup",
            "diskMap": "Disk Map",
            "largeFiles": "Large Files & Hidden Space",
            "startDiskAnalyze": "Start Analyze",
            "analyzeIntroTitle": "Analyze Disk Usage",
            "analyzeIntroDetail": "Read Mole disk analysis results and show the largest folders and files. Click a block to drill into folders. Delete actions move items to Trash and require confirmation.",
            "analyzeEmptyDetail": "Choose a scope to start analyzing. Results will show the largest folders and files under the selected path.",
            "homeFolder": "Home",
            "rootDisk": "Root Disk",
            "applicationsFolder": "Applications",
            "downloadsFolder": "Downloads",
            "analyzedPath": "Analyzed Path",
            "currentAnalyzePath": "Current Location",
            "backToPreviousFolder": "Back",
            "totalSize": "Total Size",
            "fileCount": "File Count",
            "noLargeFilesFound": "No obvious large files found yet.",
            "moreItems": "More Items",
            "showMoreItems": "Show %@ more",
            "collapse": "Collapse",
            "openFolder": "Open",
            "clickToOpenFolder": "Click or double-click to open folder",
            "revealInFinder": "Reveal in Finder",
            "analyzeDeleteConfirmationTitle": "Move to Trash?",
            "analyzeDeleteConfirmationMessage": "This will move \"%@\" to Trash. Estimated size: %@.\n\nPath: %@\n\nMake sure this is not a system folder, work data, or a folder still in use. Items moved to Trash can usually be restored, but not after Trash is emptied.",
            "analyzeDeleteCompleteTitle": "Moved to Trash",
            "analyzeMovedToTrashInline": "\"%@\" was moved to Trash. Refreshing the disk map.",
            "appInventory": "App Inventory",
            "scanLeftovers": "Scan Leftovers",
            "installed": "Installed",
            "leftovers": "Leftovers",
            "extensions": "Extensions",
            "appBundle": "App Bundle",
            "relatedFiles": "Related Files",
            "leftoverFiles": "Leftover Files",
            "supportFiles": "Application Support",
            "cacheFiles": "Cache Files",
            "preferenceFiles": "Preferences",
            "logFiles": "Log Files",
            "systemFiles": "System Related Files",
            "reviewOnlyFiles": "Review Only",
            "otherFiles": "Other Files",
            "readingRelatedFiles": "Reading leftover files",
            "files": "Files",
            "defaultDeleteMode": "Default deletion mode",
            "moveToTrashNote": "Uninstall moves items to Trash first. System apps, whitelist paths, credentials, and session data are skipped by default.",
            "showFiles": "Show Files",
            "uninstallSelected": "Uninstall Selected",
            "operation": "Action",
            "result": "Result",
            "path": "Path",
            "time": "Time",
            "safetyExecution": "Safety & Execution",
            "alwaysDryRun": "Always preview before running",
            "moveToTrash": "Move to Trash",
            "movingToTrash": "Moving to Trash",
            "allowAdmin": "Allow admin tasks",
            "whitelist": "Whitelist",
            "repository": "Repository",
            "language": "Language",
            "dryRunOutput": "Preview Result",
            "backendPreview": "From the local Mole CLI backend. Preview only, no deletion.",
            "previewOnlyTitle": "Safe preview",
            "previewOnlyDescription": "Shows what would be handled without deleting or changing files.",
            "previewOnlyMessage": "Review the app bundle, related files, and safety notes first. Mole only moves supported items to Trash after you confirm uninstall or cleanup.",
            "operationCompleteTitle": "Operation Complete",
            "operationCompleteSubtitle": "The operation finished using Mole's safety rules.",
            "operationCompleteMessage": "The app bundle was removed from its original path and the app list has been updated. You can review the technical details below, or click Got it to continue.",
            "operationNeedsReviewTitle": "Review Needed",
            "operationNeedsReviewSubtitle": "The operation finished, but some items need attention.",
            "operationNeedsReviewMessage": "Some files may have been skipped because of permissions, protection rules, or active use. Review the technical details below before handling them manually.",
            "technicalDetails": "Technical Details",
            "copyOutput": "Copy Output",
            "lines": "lines",
            "cleanDryRunTitle": "Mole Cleanup Preview",
            "uninstallDryRunTitle": "Mole Uninstall Preview",
            "previewWithMole": "Preview with Mole",
            "running": "Running",
            "close": "Close",
            "done": "Got it",
            "emptyOutput": "The command did not print output.",
            "noAppSelected": "Select an app first.",
            "notScanned": "Not scanned",
            "noActiveAlerts": "No active alerts",
            "memoryUsage": "Memory Usage",
            "dryRunOnly": "After preview",
            "runDryRunForRelatedFiles": "Click Scan Leftovers to read real related files. Preview mode will not delete anything.",
            "scanBeforeUninstall": "Scan leftovers first, then review the app bundle and related files before uninstalling.",
            "scanBeforeUninstallShort": "Scan First",
            "noneFound": "None found",
            "noRelatedFilesFound": "No extra related files found.",
            "scanningLeftovers": "Scanning",
            "leftoverScanTitle": "Leftover Scan",
            "confirmUninstallTitle": "Uninstall this app?",
            "confirmUninstallMessage": "Mole will move the selected app and supported related files to Trash. This step will actually run; it is no longer just a preview.",
            "uninstallCompleteTitle": "Uninstall Complete",
            "uninstallIncompleteTitle": "Uninstall Incomplete",
            "uninstallRemovedFromList": "The app bundle is no longer at its original path and was removed from the app list.",
            "uninstallStillPresent": "The uninstall command finished, but the app bundle is still at its original path. System permission, a running process, or an official uninstaller requirement may have blocked removal. Check the output above.",
            "commandTimedOutTitle": "This operation took too long and was stopped.",
            "commandTimedOutDetail": "Mole may be scanning many apps or disk paths, or waiting for system permission. Try again later, or run a preview first to confirm the scope.",
            "cancel": "Cancel"
        ]
    ]
}
