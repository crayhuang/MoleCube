import SwiftUI

struct SystemStatusView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                statusHeader

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 14),
                    GridItem(.flexible(), spacing: 14),
                    GridItem(.flexible(), spacing: 14),
                    GridItem(.flexible(), spacing: 14)
                ], spacing: 14) {
                    StatusMetricCard(
                        title: model.text("health"),
                        value: model.status?.healthScore.map(String.init) ?? "--",
                        unit: model.status?.healthScoreMessage ?? model.text("statusHealthy"),
                        systemImage: "heart.text.square",
                        tint: AppTheme.green,
                        progress: Double(model.status?.healthScore ?? 0) / 100,
                        isLoading: model.isLoadingStatus && model.status == nil
                    )

                    StatusMetricCard(
                        title: "CPU",
                        value: percent(model.status?.cpu?.usage),
                        unit: cpuUnit,
                        systemImage: "cpu",
                        tint: AppTheme.cyan,
                        progress: normalizedPercent(model.status?.cpu?.usage),
                        isLoading: model.isLoadingStatus && model.status == nil
                    )

                    StatusMetricCard(
                        title: model.text("memory"),
                        value: percent(model.status?.memory?.usedPercent),
                        unit: memoryUnit,
                        systemImage: "memorychip",
                        tint: AppTheme.sun,
                        progress: normalizedPercent(model.status?.memory?.usedPercent),
                        isLoading: model.isLoadingStatus && model.status == nil
                    )

                    StatusMetricCard(
                        title: "GPU",
                        value: gpuMetricValue,
                        unit: gpuMetricUnit,
                        systemImage: "display",
                        tint: AppTheme.blue,
                        progress: normalizedPercent(model.status?.gpu?.first?.usage),
                        isLoading: model.isLoadingStatus && model.status == nil
                    )
                }

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 14),
                    GridItem(.flexible(), spacing: 14),
                    GridItem(.flexible(), spacing: 14)
                ], spacing: 14) {
                    StatusPanel(title: "CPU", subtitle: model.text("liveLoad")) {
                        VStack(spacing: 14) {
                            MiniBarChart(values: model.status?.cpu?.perCore ?? model.loadSamples.map { $0 * 100 }, tint: AppTheme.cyan)
                                .frame(height: 66)
                            StatusKeyValueGrid(items: [
                                (model.text("loadAverage"), loadAverage),
                                (model.text("cpuCores"), coreSummary),
                                (model.text("temperature"), temperature(model.status?.thermal?.cpuTemp)),
                                (model.text("uptime"), model.status?.uptime ?? "--")
                            ])
                        }
                    }
                    .frame(height: 248)

                    StatusPanel(title: model.text("networkAndPower"), subtitle: networkSubtitle) {
                        VStack(spacing: 14) {
                            MiniLineChart(
                                primary: model.status?.networkHistory?.rxHistory ?? [],
                                secondary: model.status?.networkHistory?.txHistory ?? [],
                                tint: AppTheme.green
                            )
                            .frame(height: 66)
                            StatusKeyValueGrid(items: [
                                (model.text("download"), networkRate(\.rxRateMBs)),
                                (model.text("upload"), networkRate(\.txRateMBs)),
                                (model.text("battery"), batterySummary),
                                (model.text("proxy"), proxySummary)
                            ])
                        }
                    }
                    .frame(height: 248)

                    StatusPanel(title: model.text("battery"), subtitle: batteryPanelSubtitle) {
                        BatteryDetailView(battery: model.status?.batteries?.first, model: model)
                    }
                    .frame(height: 248)
                }

                StatusPanel(title: model.text("topProcesses"), subtitle: "\(model.status?.topProcesses?.count ?? 0)") {
                    ProcessTable(processes: Array((model.status?.topProcesses ?? []).prefix(10)), model: model)
                }
            }
            .padding(.bottom, 24)
        }
        .task {
            await model.startLiveStatusUpdates()
        }
    }

    private var statusHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(model.text("systemStatus"))
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                Text(headerDetail)
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(2)
            }
            Spacer()
            Button {
                Task { await model.refreshStatus() }
            } label: {
                if model.isLoadingStatus {
                    ProgressView()
                        .controlSize(.small)
                    Text(model.text("readingStatus"))
                } else {
                    Label(model.text("refresh"), systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(AppOutlineButtonStyle())
            .disabled(model.isLoadingStatus)
        }
        .padding(16)
        .background(AppTheme.panel.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppTheme.border.opacity(0.16), lineWidth: 1)
        }
    }

    private var headerDetail: String {
        let hardware = model.status?.hardware
        let parts = [
            hardware?.model,
            hardware?.cpuModel,
            hardware?.totalRAM,
            hardware?.osVersion,
            model.status?.uptime.map { "\(model.text("uptime")) \($0)" }
        ].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? "mo status --json" : parts.joined(separator: " · ")
    }

    private var cpuUnit: String {
        let logical = model.status?.cpu?.logicalCPU
        guard let logical, logical > 0 else { return model.text("liveLoad") }
        return "\(logical) \(model.text("logicalCPU"))"
    }

    private var memoryUnit: String {
        guard let memory = model.status?.memory else { return "--" }
        let used = memory.used?.formattedBytes ?? "--"
        let total = memory.total?.formattedBytes ?? "--"
        return "\(used) / \(total)"
    }

    private var diskFree: String {
        guard let free = model.status?.disks?.first?.availableBytes else { return "--" }
        return free.formattedBytes
    }

    private var diskUnit: String {
        guard let disk = model.status?.disks?.first else { return model.text("diskUsage") }
        let used = disk.used?.formattedBytes ?? "--"
        let total = disk.total?.formattedBytes ?? "--"
        return "\(used) / \(total)"
    }

    private var gpuMetricValue: String {
        guard let gpu = model.status?.gpu?.first else { return "--" }
        if let usage = gpu.usage, usage > 0 {
            return percent(usage)
        }
        if let cores = gpu.coreCount, cores > 0 {
            return "\(cores)"
        }
        return "--"
    }

    private var gpuMetricUnit: String {
        guard let gpu = model.status?.gpu?.first else { return "--" }
        if let usage = gpu.usage, usage > 0 {
            return gpu.name ?? "GPU"
        }
        if let cores = gpu.coreCount, cores > 0 {
            return "\(gpu.name ?? "GPU") · \(cores) cores"
        }
        return gpu.name ?? "GPU"
    }

    private var loadAverage: String {
        guard let cpu = model.status?.cpu else { return "--" }
        return [cpu.load1, cpu.load5, cpu.load15]
            .compactMap { $0 }
            .map { String(format: "%.2f", $0) }
            .joined(separator: " · ")
    }

    private var coreSummary: String {
        guard let cpu = model.status?.cpu else { return "--" }
        if let p = cpu.pCoreCount, let e = cpu.eCoreCount, p + e > 0 {
            return "P\(p) / E\(e)"
        }
        return "\(cpu.coreCount ?? cpu.logicalCPU ?? 0)"
    }

    private var gpuSummary: String {
        guard let gpu = model.status?.gpu?.first else { return "--" }
        let name = gpu.name ?? "GPU"
        if let usage = gpu.usage, usage > 0 {
            return "\(name) \(percent(usage))"
        }
        if let cores = gpu.coreCount, cores > 0 {
            return "\(name) · \(cores) cores"
        }
        return name
    }

    private var networkSubtitle: String {
        model.status?.network?.first?.ip ?? model.text("network")
    }

    private var batterySummary: String {
        guard let battery = model.status?.batteries?.first else { return model.text("notAvailable") }
        return [
            battery.percent.map { percent($0) },
            localizedBatteryStatus(battery.status),
            battery.timeLeft
        ].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var batteryPanelSubtitle: String {
        guard let battery = model.status?.batteries?.first else { return model.text("notAvailable") }
        return battery.capacity.map { "\($0)% \(model.text("batteryHealth"))" } ?? localizedBatteryStatus(battery.status)
    }

    private var proxySummary: String {
        guard let proxy = model.status?.proxy else { return "--" }
        guard proxy.enabled == true else { return model.text("off") }
        return [proxy.type, proxy.host].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var diskIOSummary: String {
        let read = model.status?.diskIO?.readRate ?? 0
        let write = model.status?.diskIO?.writeRate ?? 0
        return "\(model.text("read")) \(String(format: "%.1f", read)) MB/s · \(model.text("write")) \(String(format: "%.1f", write)) MB/s"
    }

    private func networkRate(_ keyPath: KeyPath<StatusSnapshot.Network, Double?>) -> String {
        let value = model.status?.network?.reduce(0.0) { partial, item in
            partial + (item[keyPath: keyPath] ?? 0)
        } ?? 0
        return String(format: "%.2f MB/s", value)
    }

    private func percent(_ value: Double?) -> String {
        guard let value else { return "--" }
        return "\(Int(value.rounded()))%"
    }

    private func temperature(_ value: Double?) -> String {
        guard let value, value > 0 else { return "--" }
        return "\(Int(value.rounded()))°C"
    }

    private func normalizedPercent(_ value: Double?) -> Double {
        min(max((value ?? 0) / 100, 0), 1)
    }

    private func localizedBatteryStatus(_ status: String?) -> String {
        guard let status, !status.isEmpty else { return "--" }
        switch status.lowercased() {
        case "charging":
            return model.text("charging")
        case "discharging":
            return model.text("discharging")
        case "charged", "charged;":
            return model.text("charged")
        default:
            return status
        }
    }
}

private struct StatusMetricCard: View {
    let title: String
    let value: String
    let unit: String
    let systemImage: String
    let tint: Color
    let progress: Double
    var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.muted)
                Spacer()
            }

            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(height: 34, alignment: .leading)
            } else {
                Text(value)
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }

            ProgressView(value: min(max(progress, 0), 1))
                .tint(tint)

            Text(unit)
                .font(.caption)
                .foregroundStyle(AppTheme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 142, alignment: .leading)
        .statusCardStyle()
    }
}

private struct StatusPanel<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                Spacer()
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(1)
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
        .statusCardStyle()
    }
}

private struct StatusKeyValueGrid: View {
    let items: [(String, String)]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(items, id: \.0) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.0)
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                    Text(item.1.isEmpty ? "--" : item.1)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(AppTheme.panelAlt.opacity(0.70))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

private struct DiskUsageRow: View {
    let disk: StatusSnapshot.Disk

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(disk.mount ?? disk.mountpoint ?? disk.device ?? "--")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                Spacer()
                Text("\(Int((disk.usedPercent ?? 0).rounded()))%")
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(AppTheme.ink)
            }
            ProgressView(value: min(max((disk.usedPercent ?? 0) / 100, 0), 1))
                .tint(disk.external == true ? AppTheme.blue : AppTheme.green)
                .scaleEffect(x: 1, y: 1.08, anchor: .center)
            HStack {
                Text("\((disk.used ?? 0).formattedBytes) / \((disk.total ?? 0).formattedBytes)")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(1)
                Spacer()
                Text(disk.fstype ?? "--")
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(AppTheme.muted)
            }
        }
        .padding(12)
        .background(AppTheme.panelAlt.opacity(0.70))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct BatteryDetailView: View {
    let battery: StatusSnapshot.Battery?
    let model: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(battery?.percent.map { "\(Int($0.rounded()))" } ?? "--")
                    .font(.system(size: 38, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                Text("%")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AppTheme.muted)
                Spacer()
                Label(localizedStatus, systemImage: batteryIcon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.green)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(AppTheme.green.opacity(0.12))
                    .clipShape(Capsule())
            }

            ProgressView(value: min(max((battery?.percent ?? 0) / 100, 0), 1))
                .tint(AppTheme.green)

            StatusKeyValueGrid(items: [
                (model.text("batteryHealth"), healthValue),
                (model.text("chargingStatus"), localizedStatus),
                (model.text("remainingTime"), battery?.timeLeft ?? "--"),
                (model.text("cycleCount"), battery?.cycleCount.map(String.init) ?? "--")
            ])
        }
        .frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
    }

    private var localizedStatus: String {
        guard let status = battery?.status, !status.isEmpty else { return "--" }
        switch status.lowercased() {
        case "charging":
            return model.text("charging")
        case "discharging":
            return model.text("discharging")
        case "charged", "charged;":
            return model.text("charged")
        default:
            return status
        }
    }

    private var batteryIcon: String {
        switch battery?.status?.lowercased() {
        case "charging":
            return "bolt.fill"
        case "charged", "charged;":
            return "battery.100percent"
        default:
            return "battery.75percent"
        }
    }

    private var healthValue: String {
        let capacity = battery?.capacity.map { "\($0)%" }
        let health = battery?.health
        return [capacity, health].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ").nilIfEmpty ?? "--"
    }
}

private struct ProcessTable: View {
    let processes: [StatusSnapshot.ProcessInfo]
    let model: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("NAME")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("PID")
                    .frame(width: 90, alignment: .trailing)
                Text("CPU")
                    .frame(width: 90, alignment: .trailing)
                Text("MEM")
                    .frame(width: 110, alignment: .trailing)
            }
            .font(.caption2.monospaced().weight(.bold))
            .foregroundStyle(AppTheme.muted)
            .padding(.vertical, 6)

            if processes.isEmpty {
                EmptyStatusLine(text: model.text("notScanned"))
            } else {
                ForEach(processes) { process in
                    ProcessTableRow(process: process)
                    if process.id != processes.last?.id {
                        Divider().overlay(AppTheme.border.opacity(0.12))
                    }
                }
            }
        }
    }
}

private struct ProcessTableRow: View {
    let process: StatusSnapshot.ProcessInfo

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(process.name ?? process.command ?? "--")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                Text(process.command ?? "--")
                    .font(.caption.monospaced())
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(process.pid ?? 0)")
                .font(.caption.monospaced())
                .foregroundStyle(AppTheme.muted)
                .frame(width: 90, alignment: .trailing)

            Text("\(String(format: "%.1f", process.cpu ?? 0))%")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.ink)
                .frame(width: 90, alignment: .trailing)

            Text((process.memoryBytes ?? 0) > 0 ? (process.memoryBytes ?? 0).formattedBytes : "\(String(format: "%.1f", process.memory ?? 0))%")
                .font(.caption)
                .foregroundStyle(AppTheme.muted)
                .frame(width: 110, alignment: .trailing)
        }
        .padding(.vertical, 8)
    }
}

private struct EmptyStatusLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(AppTheme.muted)
            .frame(maxWidth: .infinity, minHeight: 72)
    }
}

private struct MiniBarChart: View {
    let values: [Double]
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(values.suffix(16).enumerated()), id: \.offset) { _, value in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(tint.opacity(0.82))
                        .frame(height: max(4, proxy.size.height * min(max(value / 100, 0.04), 1)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .padding(10)
        .background(AppTheme.panelAlt.opacity(0.70))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct MiniLineChart: View {
    let primary: [Double]
    let secondary: [Double]
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                line(values: primary, in: proxy.size)
                    .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                line(values: secondary, in: proxy.size)
                    .stroke(AppTheme.sun, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            .padding(8)
        }
        .background(AppTheme.panelAlt.opacity(0.70))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func line(values: [Double], in size: CGSize) -> Path {
        let samples = values.suffix(48)
        guard samples.count > 1 else { return Path() }
        let maxValue = max(samples.max() ?? 0.1, 0.1)
        var path = Path()
        for (index, value) in samples.enumerated() {
            let x = size.width * CGFloat(index) / CGFloat(samples.count - 1)
            let y = size.height - (size.height * CGFloat(value / maxValue))
            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        return path
    }
}

private extension View {
    func statusCardStyle() -> some View {
        self
            .background(AppTheme.panel.opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(AppTheme.border.opacity(0.16), lineWidth: 1)
            }
            .shadow(color: AppTheme.forest.opacity(0.08), radius: 12, x: 0, y: 6)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
