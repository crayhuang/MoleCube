import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        ZStack {
            DashboardGlowField()

            VStack(spacing: 24) {
                Spacer(minLength: 14)

                MoleCubeScannerStage(isScanning: model.isScanning, progress: model.scanProgress)
                    .frame(width: 360, height: 260)

                VStack(spacing: 12) {
                    Text(model.text("dashboardHeroTitle"))
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .lineLimit(3)
                        .minimumScaleFactor(0.72)

                    Text(model.isScanning ? model.text(model.scanStageKey) : model.text("dashboardHeroSubtitle"))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.68))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .frame(maxWidth: 560)
                }

                HStack(spacing: 12) {
                    FeaturePill(title: model.text("clean"), icon: "sparkles")
                    FeaturePill(title: model.text("uninstall"), icon: "app.badge")
                    FeaturePill(title: model.text("analyze"), icon: "internaldrive")
                    FeaturePill(title: model.text("optimize"), icon: "slider.horizontal.3")
                }
                .padding(.top, 4)

                Spacer(minLength: 126)
            }
            .padding(.horizontal, 42)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DashboardGlowField: View {
    var body: some View {
        ZStack {
            RadialGradient(
                colors: [AppTheme.sun.opacity(0.34), .clear],
                center: .top,
                startRadius: 30,
                endRadius: 410
            )

            RadialGradient(
                colors: [AppTheme.mint.opacity(0.36), .clear],
                center: .bottom,
                startRadius: 90,
                endRadius: 500
            )
        }
    }
}

private struct MoleCubeScannerStage: View {
    let isScanning: Bool
    let progress: Double

    var body: some View {
        ZStack {
            Ellipse()
                .fill(AppTheme.green.opacity(0.22))
                .blur(radius: 30)
                .frame(width: 330, height: 96)
                .offset(y: 74)

            VStack(spacing: 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: 42)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.96, green: 0.86, blue: 0.35),
                                    Color(red: 0.58, green: 0.84, blue: 0.42),
                                    Color(red: 0.12, green: 0.45, blue: 0.30)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 250, height: 142)
                        .shadow(color: AppTheme.green.opacity(0.34), radius: 32, x: 0, y: 22)

                    RoundedRectangle(cornerRadius: 32)
                        .stroke(.white.opacity(0.28), lineWidth: 2)
                        .frame(width: 214, height: 104)

                    Hexagon()
                        .stroke(AppTheme.sun.opacity(0.88), lineWidth: 5)
                        .frame(width: 66, height: 66)
                        .rotationEffect(.degrees(isScanning ? 360 : 0))
                        .animation(isScanning ? .linear(duration: 3.0).repeatForever(autoreverses: false) : .default, value: isScanning)

                    ScannerArm()
                        .offset(x: 76, y: -52)
                        .rotationEffect(.degrees(isScanning ? 7 : -4), anchor: .bottomTrailing)
                        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: isScanning)
                }

                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.72), Color.white.opacity(0.34)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 78, height: 62)
                    .overlay(alignment: .center) {
                        Circle()
                            .trim(from: 0, to: isScanning ? max(progress, 0.06) : 0.72)
                            .stroke(AppTheme.green.opacity(0.82), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 24, height: 24)
                    }

                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.56))
                    .frame(width: 156, height: 18)
                    .shadow(color: .black.opacity(0.22), radius: 18, x: 0, y: 10)
            }
        }
    }
}

private struct ScannerArm: View {
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.92), Color.white.opacity(0.50)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 118, height: 18)
                .rotationEffect(.degrees(-28))
                .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 6)

            Capsule()
                .fill(Color.white.opacity(0.72))
                .frame(width: 72, height: 14)
                .rotationEffect(.degrees(70))
                .offset(x: -8, y: 34)

            Circle()
                .fill(Color.white.opacity(0.92))
                .frame(width: 18, height: 18)
                .overlay {
                    Circle().stroke(AppTheme.green.opacity(0.35), lineWidth: 2)
                }
        }
        .frame(width: 132, height: 92)
    }
}

private struct FeaturePill: View {
    let title: String
    let icon: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.bold))
            .foregroundStyle(.white.opacity(0.72))
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(.white.opacity(0.10))
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            }
    }
}

private struct Hexagon: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()

        for index in 0..<6 {
            let angle = CGFloat(index) * .pi / 3 - .pi / 2
            let point = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}
