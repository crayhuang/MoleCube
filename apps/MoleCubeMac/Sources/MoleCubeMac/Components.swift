import AppKit
import SwiftUI

enum AppTheme {
    static let paper = Color(red: 0.98, green: 0.95, blue: 0.88)
    static let panel = Color(red: 1.00, green: 0.985, blue: 0.95)
    static let panelAlt = Color(red: 0.95, green: 0.98, blue: 0.91)
    static let ink = Color(red: 0.10, green: 0.10, blue: 0.08)
    static let muted = Color(red: 0.39, green: 0.38, blue: 0.34)
    static let border = Color(red: 0.18, green: 0.17, blue: 0.14)
    static let green = Color(red: 0.48, green: 0.80, blue: 0.36)
    static let yellow = Color(red: 0.98, green: 0.78, blue: 0.20)
    static let blue = Color(red: 0.45, green: 0.78, blue: 0.92)
    static let red = Color(red: 0.92, green: 0.42, blue: 0.36)
    static let deepBackground = Color(red: 0.018, green: 0.075, blue: 0.070)
    static let sidebarBackground = Color(red: 0.025, green: 0.090, blue: 0.085)
    static let toolbarBackground = Color(red: 0.96, green: 0.98, blue: 0.94)
    static let stageTop = Color(red: 0.98, green: 0.94, blue: 0.76)
    static let stageMid = Color(red: 0.80, green: 0.93, blue: 0.66)
    static let stageBottom = Color(red: 0.30, green: 0.65, blue: 0.43)
    static let forest = Color(red: 0.03, green: 0.18, blue: 0.13)
    static let mint = Color(red: 0.56, green: 0.90, blue: 0.72)
    static let sun = Color(red: 1.00, green: 0.82, blue: 0.28)
    static let violet = Color(red: 0.42, green: 0.72, blue: 0.35)
    static let magenta = Color(red: 0.98, green: 0.72, blue: 0.24)
    static let cyan = Color(red: 0.40, green: 0.84, blue: 0.70)
    static let glass = Color.white.opacity(0.12)
}

struct MetricCard: View {
    let title: String
    let value: String
    let caption: String
    let progress: Double
    var tint: Color = AppTheme.green
    var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.muted)
            if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.18))
                        .frame(width: 72, height: 18)
                }
                ProgressView()
                    .tint(tint)
            } else {
                Text(value)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                ProgressView(value: min(max(progress, 0), 1))
                    .tint(tint)
            }
            Text(caption)
                .font(.caption)
                .foregroundStyle(AppTheme.muted)
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .cardStyle()
    }
}

struct SectionCard<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack {
            Text(title)
                .font(.headline)
                .foregroundStyle(AppTheme.ink)
                Spacer()
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                }
            }
            .padding(14)
            Divider()
            content
        }
        .cardStyle()
    }
}

struct MiniStat: View {
    let title: String
    let value: String
    var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(height: 21, alignment: .leading)
            } else {
                Text(value)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Text(title)
                .font(.caption)
                .foregroundStyle(AppTheme.muted)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(AppTheme.border.opacity(0.22), lineWidth: 1.4)
        }
    }
}

struct LoadingBadge: View {
    let value: String?
    let active: Bool

    var body: some View {
        Group {
            if let value {
                Text(value)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(active ? .white : .secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
            } else {
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 18, height: 16)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
            }
        }
        .background(active ? Color.white.opacity(0.22) : Color.secondary.opacity(0.12))
        .clipShape(Capsule())
    }
}

struct LoadingValue: View {
    let value: String
    var isLoading = false
    var font: Font = .headline.weight(.bold)

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Text(value)
                    .font(font)
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }
}

struct EmptyStateView: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
                .foregroundStyle(AppTheme.ink)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(AppTheme.muted)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 36)
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .top)
    }
}

struct AppIconView: View {
    let app: InstalledApp
    let size: CGFloat

    var body: some View {
        Group {
            if let icon = iconImage {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: size, height: size)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.24)
                        .fill(AppTheme.green.gradient)
                    Text(String(app.name.prefix(1)).uppercased())
                        .font(.system(size: size * 0.42, weight: .bold))
                        .foregroundStyle(AppTheme.ink)
                }
                .frame(width: size, height: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
    }

    private var iconImage: NSImage? {
        guard !app.path.isEmpty,
              FileManager.default.fileExists(atPath: app.path) else {
            return nil
        }
        let image = NSWorkspace.shared.icon(forFile: app.path)
        image.size = NSSize(width: size, height: size)
        return image
    }
}

extension View {
    func cardStyle() -> some View {
        self
            .background(AppTheme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppTheme.border.opacity(0.34), lineWidth: 1.4)
            }
            .shadow(color: AppTheme.ink.opacity(0.05), radius: 0, x: 3, y: 3)
    }
}

struct AppPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(AppTheme.ink)
            .font(.headline.weight(.bold))
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .background(AppTheme.green)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppTheme.ink, lineWidth: 2)
            }
            .shadow(color: AppTheme.ink.opacity(configuration.isPressed ? 0 : 0.9), radius: 0, x: configuration.isPressed ? 1 : 3, y: configuration.isPressed ? 1 : 3)
            .offset(x: configuration.isPressed ? 2 : 0, y: configuration.isPressed ? 2 : 0)
    }
}

struct AppOutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(AppTheme.ink)
            .font(.subheadline.weight(.bold))
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .background(AppTheme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppTheme.border.opacity(0.85), lineWidth: 1.6)
            }
            .offset(x: configuration.isPressed ? 1 : 0, y: configuration.isPressed ? 1 : 0)
    }
}
