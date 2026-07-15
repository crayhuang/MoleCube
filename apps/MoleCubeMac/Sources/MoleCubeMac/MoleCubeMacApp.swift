import SwiftUI

@main
struct MoleCubeMacApp: App {
    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .frame(minWidth: 1120, minHeight: 720)
                .preferredColorScheme(.light)
                .task {
                    await viewModel.startInitialLoad()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: 240)
                .frame(maxHeight: .infinity)

            ZStack {
                StageBackground()

                VStack(spacing: 0) {
                    ToolbarView()
                    contentArea
                }
            }
        }
        .frame(minWidth: 1120, minHeight: 720)
        .alert("MoleCube", isPresented: Binding(
            get: { model.errorMessage != nil && !model.isMoleInstallerPresented },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .alert(model.text("confirmUninstallTitle"), isPresented: Binding(
            get: { model.appPendingUninstall != nil },
            set: { _ in }
        )) {
            Button(model.text("cancel"), role: .cancel) {
                model.cancelPendingUninstall()
            }
            Button(model.text("uninstallSelected"), role: .destructive) {
                Task { await model.confirmPendingUninstall() }
            }
        } message: {
            Text(model.text("confirmUninstallMessage"))
        }
        .alert(model.text("cleanConfirmationTitle"), isPresented: $model.isCleanConfirmationPresented) {
            Button(model.text("cancel"), role: .cancel) {
                model.cancelPendingClean()
            }
            Button(model.cleanConfirmationButtonText, role: .destructive) {
                Task { await model.confirmCleanNow() }
            }
        } message: {
            Text(model.cleanConfirmationMessage)
        }
        .alert(model.text("analyzeDeleteConfirmationTitle"), isPresented: Binding(
            get: { model.pendingAnalyzeDeleteEntry != nil },
            set: { if !$0 { model.cancelPendingAnalyzeDelete() } }
        )) {
            Button(model.text("cancel"), role: .cancel) {
                model.cancelPendingAnalyzeDelete()
            }
            Button(model.text("moveToTrash"), role: .destructive) {
                Task { await model.confirmPendingAnalyzeDelete() }
            }
        } message: {
            Text(model.analyzeDeleteConfirmationMessage)
        }
        .sheet(isPresented: Binding(
            get: { model.commandOutput != nil },
            set: { if !$0 { model.dismissCommandOutput() } }
        )) {
            CommandOutputSheet(
                title: model.commandOutputTitle ?? model.text("dryRunOutput"),
                output: model.commandOutput ?? ""
            )
            .environmentObject(model)
        }
        .sheet(isPresented: $model.isMoleInstallerPresented, onDismiss: {
            if model.errorMessage == model.text("moleNotInstalled") {
                model.errorMessage = nil
            }
        }) {
            MoleInstallerSheet()
                .environmentObject(model)
        }
    }

    @ViewBuilder
    private var contentArea: some View {
        if model.selectedSection == .uninstall {
            VStack(alignment: .leading, spacing: 12) {
                moleDependencyCard
                sectionView
            }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    moleDependencyCard
                    sectionView
                }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private var moleDependencyCard: some View {
        if model.installedMolePath == nil && model.selectedSection != .status && model.selectedSection != .settings {
            SectionCard(
                title: model.text(model.installedMolePath == nil ? "moleInstallRequiredTitle" : "moleCLIManagementTitle"),
                subtitle: model.text(model.installedMolePath == nil ? "moleInstallRequiredSubtitle" : "moleCLIManagementSubtitle")
            ) {
                MoleInstallPrompt()
                    .padding(14)
            }
        }
    }

    @ViewBuilder
    private var sectionView: some View {
        switch model.selectedSection {
        case .clean:
            CleanPreviewView()
        case .uninstall:
            UninstallView()
        case .optimize:
            OptimizeView()
                .frame(maxWidth: .infinity, alignment: .topLeading)
        case .analyze:
            AnalyzeView()
        case .status:
            SystemStatusView()
        case .settings:
            SettingsView()
        }
    }
}

private struct MoleInstallerSheet: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                LinearGradient(
                    colors: [AppTheme.sun.opacity(0.42), AppTheme.mint.opacity(0.34)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                VStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18)
                            .fill(AppTheme.green)
                            .frame(width: 76, height: 76)
                            .shadow(color: AppTheme.green.opacity(0.28), radius: 18, y: 8)
                        Image(systemName: "terminal.fill")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(.white)
                    }

                    Text(model.text("moleInstallerSheetTitle"))
                        .font(.system(size: 25, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.ink)

                    Text(model.text("moleInstallerSheetSubtitle"))
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.muted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 430)
                }
                .padding(.vertical, 30)
            }

            VStack(alignment: .leading, spacing: 18) {
                installerBenefit(
                    icon: "hand.raised.fill",
                    title: model.text("moleInstallerSafetyTitle"),
                    detail: model.text("moleInstallerSafetyDetail")
                )
                installerBenefit(
                    icon: "folder.badge.plus",
                    title: model.text("moleInstallerLocationTitle"),
                    detail: model.text("moleInstallerLocationDetail")
                )
                installerBenefit(
                    icon: "arrow.triangle.2.circlepath",
                    title: model.text("moleInstallerUpdateTitle"),
                    detail: model.text("moleInstallerUpdateDetail")
                )

                if let errorMessage = model.errorMessage,
                   errorMessage != model.text("moleNotInstalled") {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                HStack(spacing: 10) {
                    Button(model.text("notNow")) {
                        model.isMoleInstallerPresented = false
                    }
                    .buttonStyle(AppOutlineButtonStyle())
                    .disabled(model.isInstallingMole)

                    Button {
                        model.errorMessage = nil
                        Task { await model.installMoleIfNeeded() }
                    } label: {
                        if model.isInstallingMole {
                            ProgressView()
                                .controlSize(.small)
                            Text(model.text("installingMole"))
                        } else {
                            Label(model.text("installMoleNow"), systemImage: "arrow.down.circle.fill")
                        }
                    }
                    .buttonStyle(AppPrimaryButtonStyle())
                    .disabled(model.isInstallingMole)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 4)
            }
            .padding(24)
            .background(AppTheme.panel)
        }
        .frame(width: 560)
        .fixedSize(horizontal: true, vertical: true)
    }

    private func installerBenefit(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(AppTheme.green)
                .frame(width: 34, height: 34)
                .background(AppTheme.green.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct StageBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [AppTheme.stageTop, AppTheme.stageMid, AppTheme.stageBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [AppTheme.sun.opacity(0.38), .clear],
                center: .topTrailing,
                startRadius: 70,
                endRadius: 620
            )

            RadialGradient(
                colors: [AppTheme.mint.opacity(0.38), .clear],
                center: .bottomLeading,
                startRadius: 60,
                endRadius: 540
            )

            LinearGradient(
                colors: [.white.opacity(0.18), AppTheme.forest.opacity(0.16)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

struct SidebarView: View {
    @EnvironmentObject private var model: AppViewModel
    private let trafficLightSafeTopPadding: CGFloat = 50

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.31, blue: 0.22).opacity(0.98),
                    Color(red: 0.04, green: 0.20, blue: 0.15).opacity(0.98),
                    Color(red: 0.02, green: 0.11, blue: 0.09).opacity(0.99)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [AppTheme.sun.opacity(0.16), .clear],
                center: .top,
                startRadius: 20,
                endRadius: 260
            )

            VStack(alignment: .leading, spacing: 22) {
                brandHeader
                    .padding(.top, trafficLightSafeTopPadding)

                VStack(alignment: .leading, spacing: 8) {
                    Text(model.text("moleModules"))
                        .font(.caption2.weight(.black))
                        .foregroundStyle(.white.opacity(0.38))
                        .textCase(.uppercase)
                        .padding(.horizontal, 10)

                    VStack(spacing: 8) {
                        ForEach(AppSection.allCases) { section in
                            sidebarButton(for: section)
                        }
                    }
                }

                Spacer()

                let settingsSelected = model.selectedSection == .settings
                Button {
                    model.selectedSection = .settings
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(settingsSelected ? AppTheme.forest : AppTheme.green)
                            .frame(width: 36, height: 36)
                            .background(settingsSelected ? AppTheme.sun : .white.opacity(0.12))
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 3) {
                            Text(model.text("settings"))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white.opacity(0.90))
                            Text(model.text("settingsShortcutDetail"))
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.60))
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(settingsSelected ? .white.opacity(0.16) : .white.opacity(0.075))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(settingsSelected ? .white.opacity(0.25) : .white.opacity(0.08), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .accessibilityLabel(model.text("settings"))
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 18)
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(width: 1)
        }
    }

    private var brandHeader: some View {
        HStack(spacing: 12) {
            SidebarAppIcon()

            VStack(alignment: .leading, spacing: 3) {
                Text("MoleCube")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Text(model.text("subtitle"))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.56))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background(.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
    }

    private struct SidebarAppIcon: View {
        var body: some View {
            ZStack {
                RoundedRectangle(cornerRadius: 15)
                    .fill(.white.opacity(0.16))
                    .shadow(color: AppTheme.green.opacity(0.24), radius: 18, x: 0, y: 10)

                if let image = NSImage(named: "AppIcon") {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 40, height: 40)
                } else {
                    RoundedRectangle(cornerRadius: 13)
                        .fill(LinearGradient(colors: [AppTheme.green, AppTheme.cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "cube.transparent")
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 44, height: 44)
            .accessibilityLabel("MoleCube")
        }
    }

    private func sidebarButton(for section: AppSection) -> some View {
        let selected = model.selectedSection == section

        return Button {
            model.selectedSection = section
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(selected ? .white.opacity(0.22) : .white.opacity(0.10))
                    Image(systemName: symbol(for: section))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(selected ? .white : .white.opacity(0.72))
                }
                .frame(width: 36, height: 36)
                .layoutPriority(0)

                Text(title(for: section))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(selected ? .white : .white.opacity(0.66))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .allowsTightening(true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)

                badge(for: section, selected: selected)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 16))
            .background(selected ? .white.opacity(0.16) : .white.opacity(0.045))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(selected ? .white.opacity(0.25) : .white.opacity(0.055), lineWidth: 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .buttonStyle(.plain)
        .focusEffectDisabled()
    }

    @ViewBuilder
    private func badge(for section: AppSection, selected: Bool) -> some View {
        switch section {
        case .clean:
            SidebarCountBadge(value: model.isLoadingCleanCategories ? nil : "\(model.cleanCategories.count)", selected: selected)
        case .uninstall:
            SidebarCountBadge(value: model.isLoadingApps ? nil : "\(model.apps.count)", selected: selected)
        case .status:
            SidebarCountBadge(value: model.status?.healthScore.map(String.init), selected: selected)
        case .optimize, .analyze, .settings:
            EmptyView()
        }
    }

    private func symbol(for section: AppSection) -> String {
        switch section {
        case .clean: "sparkles"
        case .uninstall: "app.badge"
        case .optimize: "terminal"
        case .analyze: "internaldrive"
        case .status: "gauge.with.dots.needle.67percent"
        case .settings: "gearshape"
        }
    }

    private func title(for section: AppSection) -> String {
        switch section {
        case .clean: model.text("clean")
        case .uninstall: model.text("uninstall")
        case .optimize: model.text("commandCenter")
        case .analyze: model.text("analyze")
        case .status: model.text("status")
        case .settings: model.text("settings")
        }
    }
}

private struct SidebarCountBadge: View {
    let value: String?
    let selected: Bool

    var body: some View {
        Group {
            if let value {
                Text(value)
                    .font(.caption2.weight(.black))
                    .monospacedDigit()
                    .foregroundStyle(selected ? AppTheme.forest : AppTheme.ink)
                    .padding(.horizontal, 7)
                    .frame(minWidth: 28, minHeight: 20)
            } else {
                ProgressView()
                    .controlSize(.mini)
                    .tint(AppTheme.forest)
                    .frame(width: 28, height: 20)
            }
        }
        .background(selected ? AppTheme.sun.opacity(0.95) : Color.white.opacity(0.90))
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(selected ? AppTheme.forest.opacity(0.16) : Color.white.opacity(0.32), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.10), radius: 4, x: 0, y: 2)
        .layoutPriority(2)
        .accessibilityLabel(value ?? "Loading")
    }
}

struct ToolbarView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: symbol(for: model.selectedSection))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(AppTheme.green.opacity(0.24))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.white.opacity(0.14), lineWidth: 1)
                    }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title(for: model.selectedSection))
                        .font(.headline.weight(.bold))
                        .foregroundStyle(AppTheme.forest)
                    Text(model.text("subtitle"))
                        .font(.caption)
                        .foregroundStyle(AppTheme.forest.opacity(0.66))
                        .lineLimit(1)
                }
            }
            .frame(minWidth: 220, alignment: .leading)

            Spacer()

            Button {
                Task { await model.refreshStatus() }
            } label: {
                if model.isLoadingStatus {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 34, height: 34)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 34, height: 34)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.forest)
            .background(AppTheme.panel.opacity(0.78))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(AppTheme.forest.opacity(0.12), lineWidth: 1)
            }
            .help(model.text("refresh"))
            .disabled(model.isLoadingStatus)
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 12)
    }

    private func symbol(for section: AppSection) -> String {
        switch section {
        case .clean: "sparkles"
        case .uninstall: "app.badge"
        case .optimize: "terminal"
        case .analyze: "internaldrive"
        case .status: "gauge.with.dots.needle.67percent"
        case .settings: "gearshape"
        }
    }

    private func title(for section: AppSection) -> String {
        switch section {
        case .clean: model.text("clean")
        case .uninstall: model.text("uninstall")
        case .optimize: model.text("commandCenter")
        case .analyze: model.text("analyze")
        case .status: model.text("status")
        case .settings: model.text("settings")
        }
    }
}

struct GlobalScanButton: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        Button {
            Task { await model.runScan() }
        } label: {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.green, AppTheme.mint, AppTheme.sun.opacity(0.92)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 96, height: 96)
                    .shadow(color: AppTheme.green.opacity(0.36), radius: 28, x: 0, y: 16)
                    .shadow(color: AppTheme.sun.opacity(0.22), radius: 18, x: 0, y: 0)

                Circle()
                    .stroke(.white.opacity(0.72), lineWidth: 2)
                    .frame(width: 96, height: 96)

                VStack(spacing: 4) {
                    if model.isScanning {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                        Text("\(Int((model.scanProgress * 100).rounded()))%")
                            .font(.caption2.weight(.black))
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: 18, weight: .black))
                        Text(model.text("startScan"))
                            .font(.caption.weight(.black))
                    }
                }
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            }
        }
        .buttonStyle(.plain)
        .disabled(model.isScanning)
        .help(model.isScanning ? model.text("running") : model.text("startScan"))
    }
}

struct CommandOutputSheet: View {
    @EnvironmentObject private var model: AppViewModel
    let title: String
    let output: String

    var body: some View {
        let displayOutput = output.isEmpty ? model.text("emptyOutput") : output
        let lineCount = max(displayOutput.split(separator: "\n", omittingEmptySubsequences: false).count, 1)
        let presentation = outputPresentation

        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                Text(presentation.subtitle)
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: presentation.systemImage)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(presentation.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text(presentation.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                    Text(presentation.message)
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(presentation.tint.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(presentation.tint.opacity(0.22), lineWidth: 1)
            }

            HStack {
                Text(model.text("technicalDetails"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("· \(lineCount) \(model.text("lines"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(displayOutput, forType: .string)
                } label: {
                    Label(model.text("copyOutput"), systemImage: "doc.on.doc")
                }
                .buttonStyle(AppOutlineButtonStyle())
            }

            ScrollView([.vertical, .horizontal]) {
                Text(displayOutput)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: true)
                    .frame(minWidth: 820, alignment: .topLeading)
                    .padding(12)
            }
            .frame(minWidth: 820, minHeight: 340, maxHeight: 390)
            .background(AppTheme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppTheme.border.opacity(0.22))
            }

            HStack {
                Spacer()
                Button {
                    model.dismissCommandOutput()
                } label: {
                    Label(model.text("done"), systemImage: "checkmark")
                        .frame(minWidth: 128)
                }
                .buttonStyle(AppPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                Spacer()
            }
        }
        .padding(18)
        .frame(width: 900, height: 650)
    }

    private var outputPresentation: CommandOutputPresentation {
        let lowerTitle = title.lowercased()
        let lowerOutput = output.lowercased()
        if lowerTitle.contains(model.text("uninstallCompleteTitle").lowercased()) ||
            lowerOutput.contains("uninstall complete") ||
            lowerOutput.contains("removed 1 app") {
            return CommandOutputPresentation(
                title: model.text("operationCompleteTitle"),
                subtitle: model.text("operationCompleteSubtitle"),
                message: model.text("operationCompleteMessage"),
                systemImage: "checkmark.circle.fill",
                tint: AppTheme.green
            )
        }
        if lowerTitle.contains(model.text("uninstallIncompleteTitle").lowercased()) ||
            lowerOutput.contains("failed") {
            return CommandOutputPresentation(
                title: model.text("operationNeedsReviewTitle"),
                subtitle: model.text("operationNeedsReviewSubtitle"),
                message: model.text("operationNeedsReviewMessage"),
                systemImage: "exclamationmark.triangle.fill",
                tint: AppTheme.yellow
            )
        }
        return CommandOutputPresentation(
            title: model.text("previewOnlyTitle"),
            subtitle: model.text("previewOnlyDescription"),
            message: model.text("previewOnlyMessage"),
            systemImage: "checkmark.shield.fill",
            tint: AppTheme.green
        )
    }
}

private struct CommandOutputPresentation {
    let title: String
    let subtitle: String
    let message: String
    let systemImage: String
    let tint: Color
}
