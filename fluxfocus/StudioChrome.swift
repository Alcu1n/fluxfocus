// [IN]: SwiftUI and WheelPickerKit visual primitives / SwiftUI 与 WheelPickerKit 视觉原语
// [OUT]: Shared studio theme, surfaces, buttons, chips, countdown ring, and text-entry styling / 共享 studio 主题、卡片、按钮、胶囊、倒计时圆环与输入样式
// [POS]: Reusable visual language for the full-app studio experience and countdown system / 完整 App studio 体验与倒计时系统的可复用视觉语言
// Protocol: When updating me, sync this header + parent folder's .folder.md
// 协议:更新本文件时,同步更新此头注释及所属文件夹的 .folder.md

import SwiftUI
import WheelPickerKit

enum StudioTheme {
    static let deepInk = Color(red: 0.08, green: 0.12, blue: 0.19)
    static let deepForest = Color(red: 0.10, green: 0.21, blue: 0.18)
    static let panel = Color.white.opacity(0.055)
    static let panelStrong = Color.white.opacity(0.075)
    static let outline = Color.white.opacity(0.10)
    static let accent = Color(hue: 0.36, saturation: 0.58, brightness: 0.88)
    static let accentSoft = accent.opacity(0.18)
    static let cool = Color(red: 0.47, green: 0.78, blue: 0.96)
    static let danger = Color(red: 0.45, green: 0.17, blue: 0.18)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.68)
    static let textTertiary = Color.white.opacity(0.50)

    static let wheelStyle = TimerWheelPickerStyle(
        colors: .init(
            activeTint: .white,
            inactiveTint: Color.white.opacity(0.12),
            ringBackground: accent,
            tickGradient: Gradient(colors: [
                Color(hue: 0.57, saturation: 0.46, brightness: 0.86),
                Color(hue: 0.66, saturation: 0.82, brightness: 0.94)
            ]),
            valueGradient: Gradient(colors: [
                Color(hue: 0.48, saturation: 0.45, brightness: 0.88),
                Color(hue: 0.51, saturation: 0.62, brightness: 0.97)
            ])
        ),
        layout: .init(
            dialHeight: 214,
            dialScale: 0.9,
            ringThickness: 44,
            ringBackgroundExtraWidth: 10,
            indicatorHeight: 28,
            indicatorWidth: 5,
            indicatorDotSize: 10,
            tickWidth: 3.3,
            tickSlotWidth: 5.2,
            gapBetweenTicks: -2.6,
            largeTickFrequency: 3,
            largeTickRatio: 0.68,
            smallTickRatio: 0.32
        ),
        typography: .init(
            valueFontSize: 52,
            unitFontSize: 12,
            unitLabel: "MIN"
        )
    )
}

enum StudioButtonTone {
    case primary
    case secondary
    case danger
}

enum StudioCapsuleTone {
    case neutral
    case accent
    case danger
}

struct StudioBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    StudioTheme.deepInk,
                    Color(red: 0.11, green: 0.18, blue: 0.24),
                    StudioTheme.deepForest
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [
                    StudioTheme.accent.opacity(0.28),
                    .clear
                ],
                center: .center,
                startRadius: 24,
                endRadius: 360
            )
            .blur(radius: 28)
        }
        .ignoresSafeArea()
    }
}

struct StudioCard<Content: View>: View {
    var emphasis = false
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(
            emphasis ? StudioTheme.panelStrong : StudioTheme.panel,
            in: RoundedRectangle(cornerRadius: 30, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(StudioTheme.outline, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 24, y: 16)
    }
}

struct StudioInsetPanel<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(StudioTheme.panelStrong.opacity(0.96), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }
}

struct StudioSectionLabel: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .tracking(2.2)
            .foregroundStyle(StudioTheme.textTertiary)
    }
}

struct StudioActionButton: View {
    let title: String
    let subtitle: String
    var tone: StudioButtonTone = .primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(foreground.opacity(0.76))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(foreground)
    }

    private var background: Color {
        switch tone {
        case .primary:
            StudioTheme.accent
        case .secondary:
            Color.white.opacity(0.08)
        case .danger:
            StudioTheme.danger
        }
    }

    private var foreground: Color {
        switch tone {
        case .primary:
            StudioTheme.deepInk
        case .secondary, .danger:
            .white
        }
    }

    private var borderColor: Color {
        switch tone {
        case .primary:
            .clear
        case .secondary, .danger:
            Color.white.opacity(0.08)
        }
    }
}

struct StudioCapsuleLabel: View {
    let title: String
    var tone: StudioCapsuleTone = .neutral

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(background, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(borderColor, lineWidth: 1)
            }
    }

    private var foreground: Color {
        switch tone {
        case .neutral, .danger:
            .white.opacity(0.88)
        case .accent:
            StudioTheme.deepInk
        }
    }

    private var background: Color {
        switch tone {
        case .neutral:
            .white.opacity(0.07)
        case .accent:
            StudioTheme.accent
        case .danger:
            StudioTheme.danger
        }
    }

    private var borderColor: Color {
        tone == .accent ? .clear : Color.white.opacity(0.08)
    }
}

struct StudioMetricTile: View {
    let title: String
    let value: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(StudioTheme.textTertiary)
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(StudioTheme.textPrimary)
                .monospacedDigit()
            Text(subtitle)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(StudioTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }
}

struct StudioCountdownRing: View {
    let progress: Double
    let remainingText: String
    let detail: String

    @ScaledMetric private var ringSize = 246.0
    @ScaledMetric private var ringLineWidth = 24.0
    @ScaledMetric private var innerSpacing = 8.0

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: ringLineWidth))

                Circle()
                    .trim(from: 0, to: clampedProgress)
                    .stroke(
                        LinearGradient(
                            colors: [
                                StudioTheme.accent,
                                StudioTheme.cool,
                                StudioTheme.accent.opacity(0.85)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: ringLineWidth, lineCap: .round, lineJoin: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: StudioTheme.accent.opacity(0.25), radius: 16, y: 6)
                    .animation(Animation.linear(duration: 0.9), value: clampedProgress)

                Circle()
                    .fill(Color.white.opacity(0.06))
                    .padding(ringLineWidth + 12)

                VStack(spacing: innerSpacing) {
                    Text("剩余时间")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .tracking(1.6)
                        .foregroundStyle(StudioTheme.textTertiary)

                    Text(remainingText)
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(StudioTheme.textPrimary)
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, 22)
            }
            .frame(width: ringSize, height: ringSize)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("会话倒计时")
            .accessibilityValue("\(remainingText)，剩余进度 \(Int(clampedProgress * 100))%")

            Text(detail)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(StudioTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }
}

struct StudioEmptyState: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(StudioTheme.textPrimary)
            Text(message)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(StudioTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }
}

struct StudioTokenChip<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.08), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }
    }
}

private struct StudioTextEntryModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }
    }
}

extension View {
    func studioTextEntry() -> some View {
        modifier(StudioTextEntryModifier())
    }

    func studioNavigationBar() -> some View {
        toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

#Preview("Studio Countdown Ring") {
    ZStack {
        StudioBackground()
        StudioCountdownRing(
            progress: 0.68,
            remainingText: "16:52",
            detail: "圆环会随着倒计时推进而缩短，中心数字负责即时读数。"
        )
        .padding(24)
    }
}
