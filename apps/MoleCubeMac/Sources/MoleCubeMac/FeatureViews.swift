import SwiftUI
#if os(macOS)
import AppKit
#endif

struct CleanPreviewView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.hasScannedCleanCategories ? model.text("scanComplete") : model.text("waitingForScan"))
                        .font(.headline.weight(.bold))
                        .foregroundStyle(AppTheme.ink)
                    Text(model.text("cleanScanHint"))
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                }

                Spacer()

                Button {
                    Task { await model.scanCleanCategories() }
                } label: {
                    if model.isLoadingCleanCategories {
                        ProgressView()
                            .controlSize(.small)
                        Text(model.text("scanning"))
                    } else {
                        Label(model.text("scan"), systemImage: "sparkle.magnifyingglass")
                    }
                }
                .buttonStyle(AppPrimaryButtonStyle())
                .disabled(model.isLoadingCleanCategories || model.isRunningCommand)
            }

            HStack(alignment: .top, spacing: 16) {
                SectionCard(title: model.text("clean"), subtitle: model.hasScannedCleanCategories ? model.text("scanComplete") : model.text("waitingForScan")) {
                    if !model.hasScannedCleanCategories && !model.isLoadingCleanCategories {
                        EmptyStateView(
                            title: model.text("cleanScanReadyTitle"),
                            message: model.text("cleanScanReadyDetail"),
                            systemImage: "sparkle.magnifyingglass"
                        )
                        .frame(maxWidth: .infinity, minHeight: 280)
                    } else {
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12)
                        ], spacing: 12) {
                            ForEach(model.cleanCategories) { category in
                                CleanCategoryCard(
                                    category: category,
                                    isSelected: model.selectedCleanCategory?.id == category.id,
                                    isLoading: model.isLoadingCleanCategories,
                                    title: model.text(category.nameKey),
                                    detail: model.text(category.detailKey),
                                    risk: model.text(category.riskKey),
                                    icon: icon(for: category.nameKey),
                                    riskColor: riskColor(category.riskKey)
                                ) {
                                    model.selectCleanCategory(category)
                                }
                            }
                        }
                        .padding(14)
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    SectionCard(title: model.text("scanSummary"), subtitle: model.text("readOnly")) {
                        VStack(alignment: .leading, spacing: 14) {
                            LoadingValue(
                                value: model.selectedCleanPathTotal,
                                isLoading: model.isLoadingCleanCategories && model.cleanCategories.contains(where: { $0.sizeBytes == nil }),
                                font: .largeTitle.weight(.bold)
                            )

                            ProgressView(value: cleanProgress)
                                .tint(AppTheme.green)

                            Text(model.text("estimatedByLocalPaths"))
                                .font(.caption)
                                .foregroundStyle(AppTheme.muted)

                            Text(model.text("safeModeDetail"))
                                .font(.caption)
                                .foregroundStyle(AppTheme.muted)

                            Text(model.text("cleanScopeNote"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.ink)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(AppTheme.sun.opacity(0.16))
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                            Text("\(model.text("selectedItems")): \(model.selectedCleanPathCount)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.muted)

                            Button {
                                Task { await model.runCleanDryRunPreview() }
                            } label: {
                                Label(model.text("viewMolePreview"), systemImage: "terminal")
                            }
                            .buttonStyle(AppOutlineButtonStyle())
                            .disabled(model.isRunningCommand || model.isLoadingCleanCategories)

                            Button(role: .destructive) {
                                model.requestCleanSelectedPathsNow()
                            } label: {
                                Label(model.text("cleanSelectedPaths"), systemImage: "trash")
                            }
                            .buttonStyle(AppPrimaryButtonStyle())
                            .disabled(model.isRunningCommand || model.isLoadingCleanCategories || model.selectedCleanPathCount == 0)

                            Button(role: .destructive) {
                                model.requestCleanNow()
                            } label: {
                                Label(model.text("cleanAllScannedItems"), systemImage: "exclamationmark.triangle.fill")
                            }
                            .buttonStyle(AppOutlineButtonStyle())
                            .disabled(model.isRunningCommand || model.isLoadingCleanCategories || !model.hasScannedCleanCategories)

                            Text(model.text("cleanAllScopeHint"))
                                .font(.caption2)
                                .foregroundStyle(AppTheme.muted)
                        }
                        .padding(16)
                    }

                    SectionCard(title: model.text("categoryDetails"), subtitle: model.hasScannedCleanCategories ? model.selectedCleanCategory.map { model.text($0.nameKey) } : nil) {
                        if let category = model.selectedCleanCategory, model.hasScannedCleanCategories {
                            VStack(alignment: .leading, spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(model.text(category.nameKey))
                                            .font(.headline.weight(.bold))
                                            .foregroundStyle(AppTheme.ink)
                                        Spacer()
                                        Text(model.selectedCleanSize(in: category).formattedBytes)
                                            .font(.subheadline.weight(.black))
                                            .foregroundStyle(AppTheme.ink)
                                    }

                                    Text(model.text("selectedCardDetailOnly"))
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.muted)
                                }

                                HStack(spacing: 8) {
                                    Button {
                                        model.selectAllCleanPaths(in: category)
                                    } label: {
                                        Label(model.text("selectAll"), systemImage: "checkmark.square")
                                    }
                                    .buttonStyle(AppOutlineButtonStyle())
                                    .disabled(category.detailItems.isEmpty)

                                    Button {
                                        model.deselectAllCleanPaths(in: category)
                                    } label: {
                                        Label(model.text("deselectAll"), systemImage: "square")
                                    }
                                    .buttonStyle(AppOutlineButtonStyle())
                                    .disabled(category.detailItems.isEmpty)
                                }

                                Button(role: .destructive) {
                                    model.requestCleanCategoryNow(category)
                                } label: {
                                    Label(model.text("cleanSelectedPaths"), systemImage: "trash")
                                }
                                .buttonStyle(AppPrimaryButtonStyle())
                                .disabled(model.isRunningCommand || model.isLoadingCleanCategories || model.selectedCleanItems(in: category).isEmpty)

                                if category.detailItems.isEmpty {
                                    Text(model.text("categoryAlreadyClean"))
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.muted)
                                        .frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
                                } else {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Text(model.text("includedPaths"))
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(AppTheme.muted)
                                            Spacer()
                                            Text("\(model.selectedCleanItems(in: category).count) / \(category.detailItems.count)")
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(AppTheme.muted)
                                        }

                                        VStack(spacing: 0) {
                                            ForEach(category.detailItems) { item in
                                                Button {
                                                    model.toggleCleanPath(item)
                                                } label: {
                                                    HStack(spacing: 8) {
                                                        Image(systemName: model.isCleanPathSelected(item) ? "checkmark.square.fill" : "square")
                                                            .font(.system(size: 14, weight: .bold))
                                                            .foregroundStyle(model.isCleanPathSelected(item) ? AppTheme.green : AppTheme.muted)
                                                        Image(systemName: "folder")
                                                            .foregroundStyle(AppTheme.green)
                                                        Text(shortPath(item.path))
                                                            .font(.caption.monospaced())
                                                            .foregroundStyle(AppTheme.ink)
                                                            .lineLimit(1)
                                                        Spacer()
                                                        Text(item.sizeBytes.formattedBytes)
                                                            .font(.caption.weight(.bold))
                                                            .foregroundStyle(AppTheme.muted)
                                                    }
                                                    .contentShape(Rectangle())
                                                }
                                                .buttonStyle(.plain)
                                                .padding(.vertical, 8)

                                                if item.id != category.detailItems.last?.id {
                                                    Divider()
                                                        .overlay(AppTheme.border.opacity(0.16))
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(16)
                        } else {
                            EmptyStateView(
                                title: model.text("categoryDetails"),
                                message: model.text("scanBeforeDetails"),
                                systemImage: "rectangle.grid.2x2"
                            )
                            .frame(maxWidth: .infinity, minHeight: 170)
                        }
                    }
                }
                .frame(width: 320)
            }

            if model.isLoadingCleanPreview || !model.cleanPreviewItems.isEmpty {
                SectionCard(
                    title: model.text("previewCleanupList"),
                    subtitle: model.isLoadingCleanPreview ? model.text("loading") : "\(model.cleanPreviewItems.count) \(model.text("lines"))"
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .center) {
                            Text(model.text("previewCleanupListDetail"))
                                .font(.caption)
                                .foregroundStyle(AppTheme.muted)
                            Spacer()
                            if !model.cleanPreviewItems.isEmpty {
                                Button {
                                    model.clearCleanPreview()
                                } label: {
                                    Label(model.text("clearPreview"), systemImage: "xmark")
                                }
                                .buttonStyle(AppOutlineButtonStyle())
                            }
                        }

                        if model.isLoadingCleanPreview {
                            HStack(spacing: 10) {
                                ProgressView()
                                    .controlSize(.small)
                                Text(model.text("buildingPreview"))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AppTheme.muted)
                            }
                            .frame(maxWidth: .infinity, minHeight: 160, alignment: .center)
                        } else {
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 0) {
                                    ForEach(model.cleanPreviewItems) { item in
                                        HStack(alignment: .top, spacing: 10) {
                                            Image(systemName: item.isPath ? "folder" : "text.alignleft")
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(item.isPath ? AppTheme.green : AppTheme.muted)
                                                .frame(width: 18)
                                            Text(item.text)
                                                .font(item.isPath ? .caption.monospaced() : .caption)
                                                .foregroundStyle(item.isPath ? AppTheme.ink : AppTheme.muted)
                                                .textSelection(.enabled)
                                                .lineLimit(2)
                                            Spacer(minLength: 0)
                                        }
                                        .padding(.vertical, 8)

                                        if item.id != model.cleanPreviewItems.last?.id {
                                            Divider()
                                                .overlay(AppTheme.border.opacity(0.12))
                                        }
                                    }
                                }
                            }
                            .frame(maxHeight: 240)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var cleanProgress: Double {
        let total = model.selectedCleanPathBytes
        guard total > 0 else { return 0.04 }
        return min(max(Double(total) / Double(8 * 1024 * 1024 * 1024), 0.08), 1)
    }

    private func riskColor(_ key: String) -> Color {
        switch key {
        case "lowRisk": .green
        case "mediumRisk": .orange
        default: .red
        }
    }

    private func icon(for key: String) -> String {
        switch key {
        case "browserCache": "safari"
        case "developerCache": "hammer"
        case "systemLogs": "doc.text.magnifyingglass"
        case "aiToolCache": "sparkles"
        case "trash": "trash"
        default: "folder"
        }
    }

    private func shortPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + String(path.dropFirst(home.count))
        }
        return path
    }
}

private struct CleanCategoryCard: View {
    let category: CleanCategory
    let isSelected: Bool
    let isLoading: Bool
    let title: String
    let detail: String
    let risk: String
    let icon: String
    let riskColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(riskColor.opacity(0.15))
                        Image(systemName: icon)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(riskColor)
                    }
                    .frame(width: 42, height: 42)

                    Spacer()

                    Text(risk)
                        .font(.caption.weight(.black))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(riskColor.opacity(0.14))
                        .foregroundStyle(riskColor)
                        .clipShape(Capsule())
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(AppTheme.ink)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                HStack {
                    LoadingValue(
                        value: category.sizeBytes.map { $0.formattedBytes } ?? "--",
                        isLoading: isLoading && category.sizeBytes == nil,
                        font: .title3.weight(.black)
                    )
                    Spacer()
                    Text("\(category.detailItems.count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.muted)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 176, alignment: .topLeading)
            .background(AppTheme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? AppTheme.forest : AppTheme.border.opacity(0.25), lineWidth: isSelected ? 2 : 1.2)
            }
            .shadow(color: .black.opacity(isSelected ? 0.12 : 0.06), radius: isSelected ? 14 : 8, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }
}

struct AnalyzeView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionCard(title: model.text("diskAnalyzerFeature"), subtitle: "mo analyze --json") {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 14) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(model.text("analyzeIntroTitle"))
                                .font(.title2.weight(.bold))
                                .foregroundStyle(AppTheme.ink)
                            Text(model.text("analyzeIntroDetail"))
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 16)

                        Button {
                            Task { await model.startAnalyzeScope() }
                        } label: {
                            if model.isLoadingAnalyze {
                                ProgressView()
                                    .controlSize(.small)
                                Text(model.text("analyzingDisk"))
                            } else {
                                Label(model.text("startDiskAnalyze"), systemImage: "play.fill")
                            }
                        }
                        .buttonStyle(AppPrimaryButtonStyle())
                        .disabled(model.isLoadingAnalyze)
                    }

                    HStack(spacing: 10) {
                        AnalyzePathButton(title: model.text("homeFolder"), systemImage: "house", path: nil)
                        AnalyzePathButton(title: model.text("rootDisk"), systemImage: "internaldrive", path: "/")
                        AnalyzePathButton(title: model.text("applicationsFolder"), systemImage: "app", path: "/Applications")
                        AnalyzePathButton(title: model.text("downloadsFolder"), systemImage: "arrow.down.doc", path: "\(NSHomeDirectory())/Downloads")
                    }
                }
                .padding(14)
            }

            if model.isLoadingAnalyze && model.analyzeOutput == nil {
                SectionCard(title: model.text("diskMap"), subtitle: model.text("scanning")) {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text(model.text("analyzingDisk"))
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)
                    }
                    .frame(maxWidth: .infinity, minHeight: 240)
                }
            } else if let output = model.analyzeOutput {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 14),
                    GridItem(.flexible(), spacing: 14),
                    GridItem(.flexible(), spacing: 14)
                ], spacing: 14) {
                    AnalyzeMetricCard(title: model.text("analyzedPath"), value: output.path, systemImage: "folder")
                    AnalyzeMetricCard(title: model.text("totalSize"), value: output.totalSize.formattedBytes, systemImage: "externaldrive")
                    AnalyzeMetricCard(title: model.text("fileCount"), value: "\(output.totalFiles ?? Int64(output.entries.count))", systemImage: "doc.on.doc")
                }

                SectionCard(title: model.text("diskMap"), subtitle: nil) {
                    VStack(alignment: .leading, spacing: 12) {
                        AnalyzePathBar(path: output.path)
                        if let message = model.analyzeStatusMessage {
                            AnalyzeInlineStatus(message: message, isLoading: model.deletingAnalyzePath != nil)
                        }

                        AnalyzeTreemap(
                            entries: output.entries.sorted { $0.size > $1.size },
                            totalSize: output.totalSize,
                            deletingPath: model.deletingAnalyzePath,
                            onOpen: model.openAnalyzeEntry,
                            onDelete: model.requestAnalyzeDelete
                        )
                    }
                    .padding(12)
                }

                SectionCard(title: model.text("largeFiles"), subtitle: "mo analyze --json") {
                    if let files = output.largeFiles, !files.isEmpty {
                        AnalyzeFileList(
                            files: Array(files.sorted { $0.size > $1.size }.prefix(12)),
                            deletingPath: model.deletingAnalyzePath,
                            onOpen: { model.revealInFinder($0.path) },
                            onDelete: { file in
                                model.requestAnalyzeDelete(
                                    AnalyzeEntry(
                                        name: file.name,
                                        path: file.path,
                                        size: file.size,
                                        isDir: false,
                                        insight: nil,
                                        cleanable: nil
                                    )
                                )
                            }
                        )
                    } else {
                        EmptyStateView(title: model.text("largeFiles"), message: model.text("noLargeFilesFound"), systemImage: "doc.text.magnifyingglass")
                    }
                }
            } else {
                SectionCard(title: model.text("diskMap"), subtitle: model.text("readOnlyPreview")) {
                    EmptyStateView(title: model.text("analyze"), message: model.text("analyzeEmptyDetail"), systemImage: "chart.pie")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct AnalyzeInlineStatus: View {
    let message: String
    let isLoading: Bool

    var body: some View {
        HStack(spacing: 8) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppTheme.green)
            }
            Text(message)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(AppTheme.green.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(AppTheme.green.opacity(0.26), lineWidth: 1)
        }
    }
}

private struct AnalyzePathButton: View {
    @EnvironmentObject private var model: AppViewModel
    let title: String
    let systemImage: String
    let path: String?

    var body: some View {
        Button {
            Task { await model.startAnalyzeScope(path: path) }
        } label: {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(AppOutlineButtonStyle())
        .disabled(model.isLoadingAnalyze)
    }
}

private struct AnalyzePathBar: View {
    @EnvironmentObject private var model: AppViewModel
    let path: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder")
                .font(.headline)
                .foregroundStyle(AppTheme.forest)
                .frame(width: 34, height: 34)
                .background(AppTheme.green.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(model.text("currentAnalyzePath"))
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
                Text(path)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 12)

            if let previousPath = model.analyzePathStack.last {
                Text(previousPath)
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 260, alignment: .trailing)

                Button {
                    Task { await model.goBackAnalyzePath() }
                } label: {
                    Label(model.text("backToPreviousFolder"), systemImage: "chevron.left")
                }
                .buttonStyle(AppOutlineButtonStyle())
                .disabled(model.isLoadingAnalyze)
            }
        }
        .padding(12)
        .background(AppTheme.panelAlt.opacity(0.66))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppTheme.border.opacity(0.16), lineWidth: 1)
        }
    }
}

private struct AnalyzeMetricCard: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(AppTheme.forest)
                .frame(width: 34, height: 34)
                .background(AppTheme.green.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
                Text(value)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .background(AppTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppTheme.border.opacity(0.22), lineWidth: 1.4)
        }
    }
}

private struct AnalyzeTreemap: View {
    @EnvironmentObject private var model: AppViewModel
    let entries: [AnalyzeEntry]
    let totalSize: Int64
    let deletingPath: String?
    let onOpen: (AnalyzeEntry) -> Void
    let onDelete: (AnalyzeEntry) -> Void
    @State private var visibleLimit = 12

    var body: some View {
        let visibleEntries = Array(sortedUsableEntries.prefix(visibleLimit))
        let mapEntries = Array(visibleEntries.prefix(8))
        let listEntries = Array(visibleEntries.dropFirst(mapEntries.count))
        let remainingCount = max(sortedUsableEntries.count - visibleEntries.count, 0)

        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { proxy in
                let items = treemapItems(entries: mapEntries, in: proxy.size)

                ZStack(alignment: .topLeading) {
                    ForEach(items) { item in
                        AnalyzeTreemapTile(
                            item: item,
                            isDeleting: deletingPath == item.entry.path,
                            onOpen: onOpen,
                            onDelete: onDelete
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 430, maxHeight: 430)

            if !listEntries.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text(model.text("moreItems"))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.muted)
                        .padding(.horizontal, 12)
                        .padding(.top, 4)
                        .padding(.bottom, 6)

                    ForEach(listEntries) { entry in
                        AnalyzeRow(
                            title: entry.name,
                            subtitle: entry.path,
                            value: entry.size.formattedBytes,
                            systemImage: entry.isDir ? "folder.fill" : "doc.fill",
                            tint: entry.isDir ? AppTheme.green : AppTheme.muted,
                            isFolder: entry.isDir,
                            isDeleting: deletingPath == entry.path,
                            onOpen: { onOpen(entry) },
                            onDelete: { onDelete(entry) }
                        )
                        Divider().overlay(AppTheme.border.opacity(0.14))
                    }
                }
                .background(AppTheme.panelAlt.opacity(0.58))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(AppTheme.border.opacity(0.16), lineWidth: 1)
                }
            }

            if remainingCount > 0 || visibleLimit > 12 {
                HStack {
                    if remainingCount > 0 {
                        Button {
                            visibleLimit = min(visibleLimit + 20, sortedUsableEntries.count)
                        } label: {
                            Label(
                                String(format: model.text("showMoreItems"), "\(min(20, remainingCount))"),
                                systemImage: "chevron.down.circle"
                            )
                        }
                        .buttonStyle(AppOutlineButtonStyle())
                    }

                    Spacer()

                    if visibleLimit > 12 {
                        Button {
                            visibleLimit = 12
                        } label: {
                            Label(model.text("collapse"), systemImage: "chevron.up.circle")
                        }
                        .buttonStyle(AppOutlineButtonStyle())
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(12)
        .background(AppTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppTheme.border.opacity(0.18), lineWidth: 1.2)
        }
        .onChange(of: entries.map(\.id)) { _, _ in
            visibleLimit = 12
        }
    }

    private var sortedUsableEntries: [AnalyzeEntry] {
        entries
            .filter { $0.size > 0 }
            .sorted { $0.size > $1.size }
    }

    private func treemapItems(entries: [AnalyzeEntry], in size: CGSize) -> [AnalyzeTreemapItem] {
        let rect = CGRect(origin: .zero, size: size)
        let denominator = Double(entries.map(\.size).reduce(0, +))
        return layoutTreemap(
            entries: entries,
            in: rect,
            total: denominator,
            colorIndex: 0
        )
    }

    private func layoutTreemap(
        entries: [AnalyzeEntry],
        in rect: CGRect,
        total: Double,
        colorIndex: Int
    ) -> [AnalyzeTreemapItem] {
        guard let first = entries.first, rect.width > 4, rect.height > 4, total > 0 else {
            return []
        }

        let colors = treemapColors
        let clampedFraction = min(max(Double(first.size) / total, 0.08), entries.count == 1 ? 1 : 0.82)
        let spacing: CGFloat = 3
        let firstRect: CGRect
        let remainingRect: CGRect

        if rect.width >= rect.height {
            let width = max(24, rect.width * clampedFraction)
            firstRect = CGRect(x: rect.minX, y: rect.minY, width: width - spacing, height: rect.height)
            remainingRect = CGRect(x: rect.minX + width, y: rect.minY, width: max(0, rect.width - width), height: rect.height)
        } else {
            let height = max(24, rect.height * clampedFraction)
            firstRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: height - spacing)
            remainingRect = CGRect(x: rect.minX, y: rect.minY + height, width: rect.width, height: max(0, rect.height - height))
        }

        let current = AnalyzeTreemapItem(
            entry: first,
            rect: firstRect.insetBy(dx: 1, dy: 1),
            color: colors[colorIndex % colors.count]
        )
        let remaining = Array(entries.dropFirst())
        let remainingTotal = max(total - Double(first.size), 0)
        return [current] + layoutTreemap(
            entries: remaining,
            in: remainingRect,
            total: remainingTotal,
            colorIndex: colorIndex + 1
        )
    }

    private var treemapColors: [Color] {
        [
            Color(red: 0.78, green: 0.50, blue: 0.26),
            Color(red: 0.25, green: 0.56, blue: 0.82),
            Color(red: 0.80, green: 0.34, blue: 0.25),
            Color(red: 0.35, green: 0.50, blue: 0.75),
            Color(red: 0.48, green: 0.74, blue: 0.42),
            Color(red: 0.86, green: 0.66, blue: 0.28),
            Color(red: 0.42, green: 0.72, blue: 0.68)
        ]
    }
}

private struct AnalyzeTreemapItem: Identifiable {
    var id: String { entry.id }
    let entry: AnalyzeEntry
    let rect: CGRect
    let color: Color
}

private struct AnalyzeTreemapTile: View {
    @EnvironmentObject private var model: AppViewModel
    let item: AnalyzeTreemapItem
    let isDeleting: Bool
    let onOpen: (AnalyzeEntry) -> Void
    let onDelete: (AnalyzeEntry) -> Void
    @State private var isHovered = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 8)
                .fill(item.color.gradient)
                .overlay {
                    if isFolderHoverable && isHovered {
                        Color.white.opacity(0.10)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .overlay(alignment: .center) {
                    if isDeleting {
                        VStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                            Text(model.text("movingToTrash"))
                                .font(.caption.weight(.bold))
                        }
                        .foregroundStyle(.white)
                        .padding(8)
                    } else {
                        tileLabel
                            .padding(8)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if isFolderHoverable && isHovered {
                        folderHoverAffordance
                            .padding(10)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            isFolderHoverable && isHovered ? Color.white.opacity(0.92) : Color.white.opacity(0.0),
                            lineWidth: isFolderHoverable && isHovered ? 2.2 : 0
                        )
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if !isDeleting {
                        onOpen(item.entry)
                    }
                }

            Button {
                onDelete(item.entry)
            } label: {
                if isDeleting {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(.white)
                        .padding(6)
                        .background(Color.black.opacity(0.22))
                        .clipShape(Circle())
                } else {
                    Image(systemName: "trash")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(Color.black.opacity(0.22))
                        .clipShape(Circle())
                }
            }
            .buttonStyle(.plain)
            .disabled(isDeleting)
            .padding(6)
            .opacity(item.rect.width >= 86 && item.rect.height >= 58 ? 1 : 0)
        }
        .opacity(isDeleting ? 0.72 : 1)
        .scaleEffect(isFolderHoverable && isHovered ? 1.012 : 1)
        .shadow(
            color: isFolderHoverable && isHovered ? Color.black.opacity(0.24) : Color.clear,
            radius: isFolderHoverable && isHovered ? 10 : 0,
            x: 0,
            y: isFolderHoverable && isHovered ? 5 : 0
        )
        .frame(width: item.rect.width, height: item.rect.height)
        .position(x: item.rect.midX, y: item.rect.midY)
        .onHover { hovering in
            isHovered = hovering
            updateCursor(isHovering: hovering)
        }
        .animation(.easeOut(duration: 0.16), value: isHovered)
        .contextMenu {
            Button {
                onOpen(item.entry)
            } label: {
                Label(item.entry.isDir ? model.text("openFolder") : model.text("revealInFinder"), systemImage: item.entry.isDir ? "arrow.right.circle" : "magnifyingglass")
            }
            Button(role: .destructive) {
                onDelete(item.entry)
            } label: {
                Label(model.text("moveToTrash"), systemImage: "trash")
            }
            .disabled(isDeleting)
        }
        .help(helpText)
    }

    private var isFolderHoverable: Bool {
        item.entry.isDir && !isDeleting
    }

    @ViewBuilder
    private var folderHoverAffordance: some View {
        if item.rect.width >= 150 && item.rect.height >= 82 {
            Label(model.text("clickToOpenFolder"), systemImage: "arrow.right.circle.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.black.opacity(0.38))
                .clipShape(Capsule())
                .overlay {
                    Capsule()
                        .stroke(.white.opacity(0.28), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        } else {
            Image(systemName: "arrow.right.circle.fill")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .padding(7)
                .background(.black.opacity(0.34))
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        }
    }

    private var helpText: String {
        if item.entry.isDir {
            return "\(model.text("clickToOpenFolder"))\n\(item.entry.path)\n\(item.entry.size.formattedBytes)"
        }
        return "\(item.entry.path)\n\(item.entry.size.formattedBytes)"
    }

    private func updateCursor(isHovering: Bool) {
        #if os(macOS)
        guard isFolderHoverable else { return }
        if isHovering {
            NSCursor.pointingHand.push()
        } else {
            NSCursor.pop()
        }
        #endif
    }

    private var tileLabel: some View {
        VStack(spacing: 4) {
            Image(systemName: item.entry.isDir ? "folder.fill" : "doc.fill")
                .font(.caption.weight(.bold))
            Text(item.entry.name)
                .font(.caption.weight(.bold))
                .lineLimit(item.rect.width > 140 ? 2 : 1)
                .multilineTextAlignment(.center)
            Text(item.entry.size.formattedBytes)
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
    }
}

private struct AnalyzeEntryList: View {
    let entries: [AnalyzeEntry]
    let deletingPath: String?
    let onOpen: (AnalyzeEntry) -> Void
    let onDelete: (AnalyzeEntry) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(entries) { entry in
                AnalyzeRow(
                    title: entry.name,
                    subtitle: entry.path,
                    value: entry.size.formattedBytes,
                    systemImage: entry.isDir ? "folder.fill" : "doc.fill",
                    tint: entry.isDir ? AppTheme.green : AppTheme.muted,
                    isFolder: entry.isDir,
                    isDeleting: deletingPath == entry.path,
                    onOpen: { onOpen(entry) },
                    onDelete: { onDelete(entry) }
                )
                Divider().overlay(AppTheme.border.opacity(0.14))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppTheme.border.opacity(0.16), lineWidth: 1)
        }
    }
}

private struct AnalyzeFileList: View {
    let files: [AnalyzeFile]
    let deletingPath: String?
    let onOpen: (AnalyzeFile) -> Void
    let onDelete: (AnalyzeFile) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(files) { file in
                AnalyzeRow(
                    title: file.name,
                    subtitle: file.path,
                    value: file.size.formattedBytes,
                    systemImage: "doc.fill",
                    tint: AppTheme.sun,
                    isDeleting: deletingPath == file.path,
                    onOpen: { onOpen(file) },
                    onDelete: { onDelete(file) }
                )
                Divider().overlay(AppTheme.border.opacity(0.14))
            }
        }
    }
}

private struct AnalyzeRow: View {
    @EnvironmentObject private var model: AppViewModel
    let title: String
    let subtitle: String
    let value: String
    let systemImage: String
    let tint: Color
    var isFolder = false
    var isDeleting = false
    let onOpen: () -> Void
    let onDelete: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 12)

            if isFolder && isHovered && !isDeleting {
                Label(model.text("clickToOpenFolder"), systemImage: "arrow.right.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.green)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(AppTheme.green.opacity(0.12))
                    .clipShape(Capsule())
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }

            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
                .monospacedDigit()

            Button(action: onDelete) {
                if isDeleting {
                    ProgressView()
                        .controlSize(.mini)
                        .frame(width: 24, height: 24)
                        .background(AppTheme.red.opacity(0.10))
                        .clipShape(Circle())
                } else {
                    Image(systemName: "trash")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.red)
                        .frame(width: 24, height: 24)
                        .background(AppTheme.red.opacity(0.10))
                        .clipShape(Circle())
                }
            }
            .buttonStyle(.plain)
            .disabled(isDeleting)
        }
        .opacity(isDeleting ? 0.62 : 1)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            if isFolder && isHovered && !isDeleting {
                RoundedRectangle(cornerRadius: 8)
                    .fill(AppTheme.green.opacity(0.10))
            }
        }
        .overlay {
            if isFolder && isHovered && !isDeleting {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppTheme.green.opacity(0.28), lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !isDeleting {
                onOpen()
            }
        }
        .onHover { hovering in
            isHovered = hovering
            updateCursor(isHovering: hovering)
        }
        .animation(.easeOut(duration: 0.14), value: isHovered)
        .contextMenu {
            Button(action: onOpen) {
                Label(model.text("openFolder"), systemImage: "arrow.right.circle")
            }
            .disabled(isDeleting)
            Button(role: .destructive, action: onDelete) {
                Label(model.text("moveToTrash"), systemImage: "trash")
            }
            .disabled(isDeleting)
        }
        .help(isFolder ? "\(model.text("clickToOpenFolder"))\n\(subtitle)" : subtitle)
    }

    private func updateCursor(isHovering: Bool) {
        #if os(macOS)
        guard isFolder && !isDeleting else { return }
        if isHovering {
            NSCursor.pointingHand.push()
        } else {
            NSCursor.pop()
        }
        #endif
    }
}

struct UninstallView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            SectionCard(title: model.text("appInventory"), subtitle: model.isLoadingApps && model.apps.isEmpty ? nil : "\(model.filteredApps.count) / \(model.apps.count)") {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Picker("", selection: $model.uninstallFilter) {
                            Text(model.text("installed")).tag(UninstallFilter.installed)
                            Text(model.text("extensions")).tag(UninstallFilter.extensions)
                        }
                        .pickerStyle(.segmented)

                        Button {
                            Task { await model.refreshApps(force: true) }
                        } label: {
                            if model.isLoadingApps {
                                ProgressView()
                                    .controlSize(.small)
                                    .frame(width: 28, height: 28)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 13, weight: .bold))
                                    .frame(width: 28, height: 28)
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(AppTheme.forest)
                        .background(AppTheme.panelAlt)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(AppTheme.border.opacity(0.18), lineWidth: 1)
                        }
                        .disabled(model.isLoadingApps)
                    }
                    .padding([.horizontal, .top], 12)

                    Group {
                        if model.isLoadingApps && model.apps.isEmpty {
                            VStack(spacing: 10) {
                                ProgressView()
                                Text(model.text("loadingApps"))
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.muted)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if model.filteredApps.isEmpty {
                            EmptyStateView(
                                title: model.text("noneFound"),
                                message: model.text("noRelatedFilesFound"),
                                systemImage: "tray"
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ScrollView {
                                LazyVStack(spacing: 8) {
                                    ForEach(model.filteredApps) { app in
                                        Button {
                                            model.selectApp(app)
                                        } label: {
                                            AppRowView(app: app, selected: app.id == model.selectedAppID)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(12)
                            }
                            .frame(maxHeight: .infinity)
                        }
                    }

                    HStack {
                        MiniStat(
                            title: model.text("installed"),
                            value: "\(model.apps.count)",
                            isLoading: model.isLoadingApps && model.apps.isEmpty
                        )
                        MiniStat(title: model.text("leftovers"), value: "\(model.uninstallPreviews.count)")
                        MiniStat(title: model.text("extensions"), value: "\(extensionAppCount)")
                    }
                    .padding(12)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(width: 360)
            .frame(maxHeight: .infinity)

            AppDetailView(app: model.selectedApp)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task {
            await model.loadAppsIfNeeded()
            if let app = model.selectedApp, model.uninstallPreview(for: app) == nil {
                await model.scanSelectedAppLeftovers(app: app)
            }
        }
        .onChange(of: model.uninstallFilter) { _, _ in
            model.selectFirstFilteredAppIfNeeded()
        }
    }

    private var extensionAppCount: Int {
        model.apps.filter { app in
            let searchable = "\(app.name) \(app.bundleID) \(app.path) \(app.source)".lowercased()
            return searchable.contains("extension") || searchable.contains(".appex") || searchable.contains("plugin")
        }.count
    }
}

struct AppRowView: View {
    let app: InstalledApp
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            AppIconView(app: app, size: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(app.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                Text(app.bundleID)
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(1)
            }
            Spacer()
            Text(app.size)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
        }
        .padding(10)
        .background(selected ? AppTheme.green.opacity(0.22) : AppTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(selected ? AppTheme.ink : AppTheme.border.opacity(0.18), lineWidth: selected ? 1.6 : 1)
        }
    }
}

struct AppDetailView: View {
    @EnvironmentObject private var model: AppViewModel
    let app: InstalledApp?
    @State private var includeAppBundle = true

    var body: some View {
        SectionCard(title: app?.name ?? model.text("uninstall"), subtitle: app?.source) {
            if model.isLoadingApps && app == nil {
                VStack(spacing: 10) {
                    ProgressView()
                    Text(model.text("loadingApps"))
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let app {
                let preview = model.uninstallPreview(for: app)
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 16) {
                            HStack(alignment: .center, spacing: 16) {
                                AppIconView(app: app, size: 76)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(app.name)
                                        .font(.title2.weight(.bold))
                                        .foregroundStyle(AppTheme.ink)
                                    Text(app.bundleID)
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.muted)
                                    Text(app.path)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(AppTheme.muted)
                                        .lineLimit(1)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(app.size)
                                        .font(.largeTitle.weight(.bold))
                                        .foregroundStyle(AppTheme.ink)
                                    Text(model.text("appBundle"))
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.muted)
                                }
                            }

                            HStack(spacing: 10) {
                                MiniStat(title: model.text("appBundle"), value: app.size)
                                MiniStat(title: model.text("relatedFiles"), value: preview.map { "\($0.relatedItemCount)" } ?? model.text("notScanned"))
                                MiniStat(title: model.text("files"), value: preview.map { "\($0.itemCount)" } ?? model.text("notScanned"))
                                MiniStat(title: model.text("defaultDeleteMode"), value: "Trash")
                            }

                            Text(model.text("moveToTrashNote"))
                                .font(.caption)
                                .foregroundStyle(AppTheme.ink)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(AppTheme.yellow.opacity(0.18))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(AppTheme.border.opacity(0.22), lineWidth: 1)
                                }

                            VStack(spacing: 10) {
                                FileGroupView(
                                    title: model.text("appBundle"),
                                    size: app.size,
                                    rows: [preview?.appBundlePath ?? app.path],
                                    isSelected: $includeAppBundle
                                )
                                if model.isScanningLeftovers && preview == nil {
                                    HStack(spacing: 10) {
                                        ProgressView()
                                            .controlSize(.small)
                                        Text(model.text("readingRelatedFiles"))
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(AppTheme.muted)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 92)
                                    .background(AppTheme.panel)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(AppTheme.border.opacity(0.22), lineWidth: 1)
                                    }
                                } else if let preview {
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text(model.text("leftoverFiles"))
                                            .font(.headline)
                                            .foregroundStyle(AppTheme.ink)
                                        LeftoverGroupView(title: model.text("supportFiles"), rows: preview.supportFiles)
                                        LeftoverGroupView(title: model.text("cacheFiles"), rows: preview.cacheFiles)
                                        LeftoverGroupView(title: model.text("preferenceFiles"), rows: preview.preferenceFiles)
                                        LeftoverGroupView(title: model.text("logFiles"), rows: preview.logFiles)
                                        LeftoverGroupView(title: model.text("systemFiles"), rows: preview.systemFiles)
                                        LeftoverGroupView(title: model.text("reviewOnlyFiles"), rows: preview.reviewOnlyFiles)
                                        LeftoverGroupView(title: model.text("otherFiles"), rows: preview.otherFiles)
                                    }
                                    .padding(12)
                                    .background(AppTheme.panel)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(AppTheme.border.opacity(0.22), lineWidth: 1)
                                    }
                                } else {
                                    Text(model.text("readingRelatedFiles"))
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.muted)
                                        .frame(maxWidth: .infinity, minHeight: 72)
                                        .background(AppTheme.panel)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }
                        .padding(16)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    HStack {
                        Button {
                            model.revealInFinder(app.path)
                        } label: {
                            Label(model.text("showFiles"), systemImage: "finder")
                        }
                        .buttonStyle(AppOutlineButtonStyle())
                        Spacer()
                        Button(role: .destructive) {
                            model.selectApp(app)
                            model.requestUninstallSelectedApp(app)
                        } label: {
                            if model.isRunningCommand {
                                ProgressView()
                                    .controlSize(.small)
                                Text(model.text("running"))
                            } else {
                                Label(preview == nil ? model.text("loading") : model.text("uninstallSelected"), systemImage: "exclamationmark.triangle.fill")
                            }
                        }
                        .buttonStyle(AppPrimaryButtonStyle())
                        .disabled(model.isRunningCommand || model.isScanningLeftovers || !includeAppBundle || preview == nil)
                    }
                    .padding(16)
                    .background(AppTheme.panel)
                    .overlay(alignment: .top) {
                        Divider()
                            .overlay(AppTheme.border.opacity(0.16))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                EmptyStateView(title: model.text("uninstall"), message: model.text("scanLeftovers"), systemImage: "trash")
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(maxHeight: .infinity)
        .onChange(of: app?.id) { _, _ in
            includeAppBundle = true
            if let app, model.uninstallPreview(for: app) == nil {
                Task { await model.scanSelectedAppLeftovers(app: app) }
            }
        }
    }
}

struct LeftoverGroupView: View {
    @EnvironmentObject private var model: AppViewModel
    let title: String
    let rows: [String]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: rows.isEmpty ? "checkmark.circle" : "folder")
                    .foregroundStyle(rows.isEmpty ? AppTheme.green : AppTheme.muted)
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                Spacer()
                Text(rows.isEmpty ? model.text("noneFound") : "\(rows.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.muted)
            }
            .padding(.vertical, 7)

            ForEach(rows.prefix(5), id: \.self) { row in
                HStack(spacing: 8) {
                    Image(systemName: "doc")
                        .foregroundStyle(AppTheme.muted)
                    Text(row)
                        .font(.caption.monospaced())
                        .foregroundStyle(AppTheme.muted)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 5)
            }

            if rows.count > 5 {
                Text("+ \(rows.count - 5)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(AppTheme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            }
        }
    }
}

struct FileGroupView: View {
    let title: String
    let size: String
    let rows: [String]
    @Binding var isSelected: Bool
    var allowsSelection = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if allowsSelection {
                    Toggle("", isOn: $isSelected)
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                Spacer()
                Text(size)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
            }
            .padding(10)
            Divider()
                .overlay(AppTheme.border.opacity(0.14))
            ForEach(rows, id: \.self) { row in
                HStack {
                    if allowsSelection {
                        Toggle("", isOn: $isSelected)
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                    }
                    Text(row)
                        .font(.caption.monospaced())
                        .foregroundStyle(AppTheme.muted)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(10)
                Divider()
                    .overlay(AppTheme.border.opacity(0.14))
            }
        }
        .background(AppTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.border.opacity(0.20))
        }
    }
}

struct OptimizeView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 14) {
                SectionCard(title: model.text("optimize"), subtitle: "mo optimize") {
                    VStack(alignment: .leading, spacing: 12) {
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12)
                        ], spacing: 12) {
                            MoleCommandCard(
                                title: model.text("optimizePreview"),
                                detail: model.text("optimizePreviewDetail"),
                                command: "mo optimize --dry-run",
                                systemImage: "wand.and.stars"
                            ) {
                                Task {
                                    await model.runOptimizePreview()
                                }
                            }

                            MoleCommandCard(
                                title: model.text("optimizeRun"),
                                detail: model.text("optimizeRunDetail"),
                                command: "mo optimize",
                                systemImage: "slider.horizontal.3"
                            ) {
                                Task {
                                    await model.runOptimizeWithAuthorization()
                                }
                            }

                            MoleCommandCard(
                                title: model.text("optimizeWhitelist"),
                                detail: model.text("optimizeWhitelistDetail"),
                                command: "mo optimize --whitelist",
                                systemImage: "lock.shield"
                            ) {
                                Task {
                                    await model.runMoleCommand(
                                        title: model.text("optimizeWhitelist"),
                                        arguments: ["optimize", "--whitelist"],
                                        timeoutSeconds: 60,
                                        standardInput: "q\n"
                                    )
                                }
                            }

                            MoleCommandCard(
                                title: model.text("touchIDStatus"),
                                detail: model.text("touchIDStatusDetail"),
                                command: "mo touchid status",
                                systemImage: "touchid"
                            ) {
                                Task {
                                    await model.runMoleCommand(
                                        title: model.text("touchIDStatus"),
                                        arguments: ["touchid", "status"],
                                        timeoutSeconds: 30
                                    )
                                }
                            }
                        }
                    }
                    .padding(14)
                }

                SectionCard(title: model.text("moleCommandCenter"), subtitle: model.text("allMoleCommands")) {
                    LazyVGrid(columns: commandGridColumns, spacing: 12) {
                        ForEach(moleCommandActions) { action in
                            MoleCommandCard(
                                title: model.text(action.titleKey),
                                detail: model.text(action.detailKey),
                                command: action.command,
                                systemImage: action.systemImage
                            ) {
                                Task {
                                    await model.runMoleCommand(
                                        title: model.text(action.titleKey),
                                        arguments: action.arguments,
                                        timeoutSeconds: action.timeoutSeconds,
                                        standardInput: action.standardInput
                                    )
                                }
                            }
                        }
                    }
                    .padding(14)
                }

                SectionCard(title: model.text("operationHistory"), subtitle: "mo history") {
                    if model.isLoadingHistory && model.historyEntries.isEmpty {
                        VStack(spacing: 10) {
                            ProgressView()
                            Text(model.text("readingHistory"))
                                .font(.caption)
                                .foregroundStyle(AppTheme.muted)
                        }
                        .frame(maxWidth: .infinity, minHeight: 160)
                    } else if model.historyEntries.isEmpty {
                        EmptyStateView(title: model.text("operationHistory"), message: model.text("readOnlyPreview"), systemImage: "clock")
                    } else {
                        VStack(spacing: 0) {
                            ForEach(model.historyEntries.prefix(8)) { entry in
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(entry.command ?? entry.action ?? model.text("operation"))
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(AppTheme.ink)
                                        Text(entry.path ?? "")
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.muted)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Text(entry.status ?? "")
                                        .font(.caption)
                                    Text(entry.timestamp ?? "")
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.muted)
                                }
                                .padding(12)
                                Divider()
                                    .overlay(AppTheme.border.opacity(0.14))
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            VStack(alignment: .leading, spacing: 14) {
                SectionCard(title: model.text("authorization"), subtitle: model.text("permissionStatus")) {
                    VStack(alignment: .leading, spacing: 12) {
                        PermissionRow(
                            title: model.text("fullDiskAccess"),
                            value: fullDiskAccessLabel,
                            systemImage: "externaldrive.badge.checkmark",
                            isGranted: model.permissionStatus.fullDiskAccessGranted == true,
                            isLoading: model.isLoadingPermissions
                        )
                        PermissionRow(
                            title: model.text("adminAuthorization"),
                            value: sudoStatusLabel,
                            systemImage: "lock.shield",
                            isGranted: model.permissionStatus.sudoSessionAvailable == true,
                            isLoading: model.isLoadingPermissions
                        )

                        HStack(spacing: 8) {
                            Button {
                                model.openFullDiskAccessSettings()
                            } label: {
                                Label(model.text("openFullDiskAccess"), systemImage: "gearshape")
                            }
                            .buttonStyle(AppOutlineButtonStyle())

                            Button {
                                Task { await model.refreshPermissionStatus() }
                            } label: {
                                Label(model.text("checkAgain"), systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(AppOutlineButtonStyle())
                        }
                    }
                    .padding(14)
                }

                SectionCard(title: model.text("systemStatus"), subtitle: "mo status") {
                    VStack(alignment: .leading, spacing: 12) {
                        MiniStat(
                            title: model.text("healthScore"),
                            value: model.status?.healthScore.map(String.init) ?? "--",
                            isLoading: model.isLoadingStatus && model.status == nil
                        )
                        MiniStat(
                            title: model.text("diskUsage"),
                            value: optimizeDiskUsage,
                            isLoading: model.isLoadingStatus && model.status?.disks?.first == nil
                        )
                        MiniStat(
                            title: model.text("activeAlerts"),
                            value: "\(model.activeAlertCount)",
                            isLoading: model.isLoadingStatus && model.status == nil
                        )
                    }
                    .padding(14)
                }
            }
            .frame(width: 320, alignment: .top)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .task {
            if model.historyEntries.isEmpty {
                await model.refreshHistory()
            }
            if model.status == nil {
                await model.refreshStatus()
            }
            await model.refreshPermissionStatus()
        }
    }

    private var commandGridColumns: [GridItem] {
        [
            GridItem(.adaptive(minimum: 260, maximum: 360), spacing: 12, alignment: .top)
        ]
    }

    private var moleCommandActions: [MoleCommandAction] {
        [
            MoleCommandAction(titleKey: "cleanPreviewCommand", detailKey: "cleanPreviewCommandDetail", command: "mo clean --dry-run", arguments: ["clean", "--dry-run"], systemImage: "sparkle.magnifyingglass", timeoutSeconds: 90),
            MoleCommandAction(titleKey: "cleanRunCommand", detailKey: "cleanRunCommandDetail", command: "mo clean", arguments: ["clean"], systemImage: "trash.slash", timeoutSeconds: 180, standardInput: "\n"),
            MoleCommandAction(titleKey: "cleanWhitelistCommand", detailKey: "cleanWhitelistCommandDetail", command: "mo clean --whitelist", arguments: ["clean", "--whitelist"], systemImage: "checklist.checked", timeoutSeconds: 60, standardInput: "q\n"),
            MoleCommandAction(titleKey: "installerPreviewCommand", detailKey: "installerPreviewCommandDetail", command: "mo installer --dry-run", arguments: ["installer", "--dry-run"], systemImage: "shippingbox", timeoutSeconds: 90),
            MoleCommandAction(titleKey: "installerRunCommand", detailKey: "installerRunCommandDetail", command: "mo installer", arguments: ["installer"], systemImage: "shippingbox.fill", timeoutSeconds: 180, standardInput: "q\n"),
            MoleCommandAction(titleKey: "purgePreviewCommand", detailKey: "purgePreviewCommandDetail", command: "mo purge --dry-run", arguments: ["purge", "--dry-run"], systemImage: "folder.badge.minus", timeoutSeconds: 90),
            MoleCommandAction(titleKey: "purgeRunCommand", detailKey: "purgeRunCommandDetail", command: "mo purge", arguments: ["purge"], systemImage: "folder.badge.minus.fill", timeoutSeconds: 180),
            MoleCommandAction(titleKey: "purgeIncludeEmptyCommand", detailKey: "purgeIncludeEmptyCommandDetail", command: "mo purge --dry-run --include-empty", arguments: ["purge", "--dry-run", "--include-empty"], systemImage: "folder", timeoutSeconds: 90),
            MoleCommandAction(titleKey: "purgePathsCommand", detailKey: "purgePathsCommandDetail", command: "mo purge --paths", arguments: ["purge", "--paths"], systemImage: "folder.badge.gearshape", timeoutSeconds: 60, standardInput: "q\n"),
            MoleCommandAction(titleKey: "historyCommand", detailKey: "historyCommandDetail", command: "mo history", arguments: ["history"], systemImage: "clock.arrow.circlepath", timeoutSeconds: 30),
            MoleCommandAction(titleKey: "historyJSONCommand", detailKey: "historyJSONCommandDetail", command: "mo history --json", arguments: ["history", "--json"], systemImage: "curlybraces", timeoutSeconds: 30),
            MoleCommandAction(titleKey: "completionPreviewCommand", detailKey: "completionPreviewCommandDetail", command: "mo completion --dry-run", arguments: ["completion", "--dry-run"], systemImage: "terminal", timeoutSeconds: 45),
            MoleCommandAction(titleKey: "completionBashCommand", detailKey: "completionBashCommandDetail", command: "mo completion bash", arguments: ["completion", "bash"], systemImage: "terminal.fill", timeoutSeconds: 30),
            MoleCommandAction(titleKey: "completionZshCommand", detailKey: "completionZshCommandDetail", command: "mo completion zsh", arguments: ["completion", "zsh"], systemImage: "terminal.fill", timeoutSeconds: 30),
            MoleCommandAction(titleKey: "completionFishCommand", detailKey: "completionFishCommandDetail", command: "mo completion fish", arguments: ["completion", "fish"], systemImage: "terminal.fill", timeoutSeconds: 30),
            MoleCommandAction(titleKey: "touchIDPreviewCommand", detailKey: "touchIDPreviewCommandDetail", command: "mo touchid enable --dry-run", arguments: ["touchid", "enable", "--dry-run"], systemImage: "touchid", timeoutSeconds: 30),
            MoleCommandAction(titleKey: "touchIDEnableCommand", detailKey: "touchIDEnableCommandDetail", command: "mo touchid enable", arguments: ["touchid", "enable"], systemImage: "touchid", timeoutSeconds: 90),
            MoleCommandAction(titleKey: "touchIDDisablePreviewCommand", detailKey: "touchIDDisablePreviewCommandDetail", command: "mo touchid disable --dry-run", arguments: ["touchid", "disable", "--dry-run"], systemImage: "touchid", timeoutSeconds: 30),
            MoleCommandAction(titleKey: "statusCommand", detailKey: "statusCommandDetail", command: "mo status", arguments: ["status"], systemImage: "waveform.path.ecg", timeoutSeconds: 30),
            MoleCommandAction(titleKey: "updateForceCommand", detailKey: "updateForceCommandDetail", command: "mo update --force", arguments: ["update", "--force"], systemImage: "arrow.down.circle", timeoutSeconds: 300),
            MoleCommandAction(titleKey: "updateNightlyCommand", detailKey: "updateNightlyCommandDetail", command: "mo update --nightly", arguments: ["update", "--nightly"], systemImage: "moon.stars", timeoutSeconds: 300),
            MoleCommandAction(titleKey: "versionCommand", detailKey: "versionCommandDetail", command: "mo --version", arguments: ["--version"], systemImage: "number", timeoutSeconds: 30),
            MoleCommandAction(titleKey: "helpCommand", detailKey: "helpCommandDetail", command: "mo --help", arguments: ["--help"], systemImage: "questionmark.circle", timeoutSeconds: 30),
            MoleCommandAction(titleKey: "removePreviewCommand", detailKey: "removePreviewCommandDetail", command: "mo remove --dry-run", arguments: ["remove", "--dry-run"], systemImage: "xmark.bin", timeoutSeconds: 60)
        ]
    }

    private var optimizeDiskUsage: String {
        guard let percent = model.status?.disks?.first?.usedPercent else {
            return "--"
        }
        return "\(Int(percent.rounded()))%"
    }

    private var fullDiskAccessLabel: String {
        switch model.permissionStatus.fullDiskAccessGranted {
        case true: model.text("granted")
        case false: model.text("notGranted")
        case nil: model.text("unknown")
        }
    }

    private var sudoStatusLabel: String {
        switch model.permissionStatus.sudoSessionAvailable {
        case true: model.text("available")
        case false: model.text("requiresAuthorization")
        case nil: model.text("unknown")
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let value: String
    let systemImage: String
    let isGranted: Bool
    let isLoading: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(isGranted ? AppTheme.green : AppTheme.sun)
                .frame(width: 32, height: 32)
                .background((isGranted ? AppTheme.green : AppTheme.sun).opacity(0.16))
                .clipShape(RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.muted)
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(value)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppTheme.ink)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(AppTheme.panel.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.border.opacity(0.20), lineWidth: 1)
        }
    }
}

struct MoleCommandAction: Identifiable {
    let id = UUID()
    let titleKey: String
    let detailKey: String
    let command: String
    let arguments: [String]
    let systemImage: String
    let timeoutSeconds: UInt64
    var standardInput: String?
}

struct MoleCommandCard: View {
    let title: String
    let detail: String
    let command: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
                    .frame(width: 34, height: 34)
                    .background(AppTheme.green.opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(AppTheme.border.opacity(0.4), lineWidth: 1.2)
                    }

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(1)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(command)
                        .font(.caption2.monospaced().weight(.semibold))
                        .foregroundStyle(AppTheme.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 106, maxHeight: 106, alignment: .topLeading)
            .background(AppTheme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppTheme.border.opacity(0.25), lineWidth: 1.2)
            }
        }
        .buttonStyle(.plain)
    }
}

struct HistoryView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        SectionCard(title: model.text("history"), subtitle: "mo history --json") {
            if model.isLoadingHistory && model.historyEntries.isEmpty {
                VStack(spacing: 10) {
                    ProgressView()
                    Text(model.text("readingHistory"))
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                }
                .frame(maxWidth: .infinity, minHeight: 220)
            } else if model.historyEntries.isEmpty {
                EmptyStateView(title: model.text("history"), message: model.text("readOnlyPreview"), systemImage: "clock")
            } else {
                VStack(spacing: 0) {
                    ForEach(model.historyEntries.prefix(30)) { entry in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.command ?? entry.action ?? model.text("operation"))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.ink)
                                Text(entry.path ?? "")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.muted)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(entry.status ?? "")
                                .font(.caption)
                            Text(entry.timestamp ?? "")
                                .font(.caption)
                                .foregroundStyle(AppTheme.muted)
                        }
                        .padding(12)
                        Divider()
                            .overlay(AppTheme.border.opacity(0.14))
                    }
                }
            }
        }
        .task {
            if model.historyEntries.isEmpty {
                await model.refreshHistory()
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            SectionCard(title: model.text("safetyExecution"), subtitle: model.text("settings")) {
                VStack(spacing: 0) {
                    Toggle(model.text("alwaysDryRun"), isOn: .constant(true))
                    Divider()
                        .overlay(AppTheme.border.opacity(0.14))
                    Toggle(model.text("moveToTrash"), isOn: .constant(true))
                    Divider()
                        .overlay(AppTheme.border.opacity(0.14))
                    Toggle(model.text("allowAdmin"), isOn: .constant(false))
                }
                .padding(14)
            }

            SectionCard(title: model.text("whitelist"), subtitle: model.text("repository")) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(model.repositoryPath)
                        .font(.caption.monospaced())
                        .foregroundStyle(AppTheme.muted)
                        .textSelection(.enabled)
                    Picker(model.text("language"), selection: $model.language) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(14)
            }
        }
    }
}
