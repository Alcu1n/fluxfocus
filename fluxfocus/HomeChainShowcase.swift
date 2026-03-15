// [IN]: SwiftUI, StudioChrome surfaces, and derived HomeChainSnapshot data / SwiftUI、StudioChrome 视觉表面与派生 HomeChainSnapshot 数据
// [OUT]: Visual-first home chain showcase card and supporting chain/pulse subviews / 视觉优先的首页链条展示卡片及其链条/脉冲子视图
// [POS]: Premium homepage visualization layer that turns completed focus work into an immediately legible chain / 将已完成专注转化为即时可感知链条的高级首页可视化层
// Protocol: When updating me, sync this header + parent folder's .folder.md
// 协议:更新本文件时,同步更新此头注释及所属文件夹的 .folder.md

import SwiftUI

struct HomeChainShowcase: View {
    let snapshot: HomeChainSnapshot

    var body: some View {
        StudioCard(emphasis: true) {
            ZStack(alignment: .topTrailing) {
                decorativeGlow

                VStack(alignment: .leading, spacing: 22) {
                    header

                    ViewThatFits {
                        HStack(alignment: .top, spacing: 16) {
                            chainCore
                            pulsePanel
                        }

                        VStack(spacing: 16) {
                            chainCore
                            pulsePanel
                        }
                    }

                    HomeChainLinkStrip(
                        nodes: snapshot.recentNodes,
                        overflowCount: snapshot.archivedLength
                    )

                    summaryStrip
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                StudioSectionLabel(title: "Chain Field")

                Text("把已经完成的专注，铸成一条正在发光的链")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(StudioTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(headerCopy)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(StudioTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 8) {
                StudioCapsuleLabel(
                    title: momentumTitle,
                    tone: snapshot.currentLength == 0 ? .neutral : .accent
                )
                StudioCapsuleLabel(title: "累计 \(snapshot.totalCompletedSessions) 次")
            }
        }
    }

    private var chainCore: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.white.opacity(0.045))

            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("当前主链")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .tracking(1.6)
                            .foregroundStyle(StudioTheme.textTertiary)
                        Text(todayDeltaText)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(StudioTheme.textSecondary)
                    }

                    Spacer()

                    Text(snapshot.latestCompletionAt?.formatted(date: .abbreviated, time: .omitted) ?? "等待下一节")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(StudioTheme.textTertiary)
                }

                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    StudioTheme.accent.opacity(0.30),
                                    StudioTheme.cool.opacity(0.18),
                                    .clear
                                ],
                                center: .center,
                                startRadius: 12,
                                endRadius: 92
                            )
                        )
                        .frame(width: 150, height: 150)

                    Circle()
                        .stroke(.white.opacity(0.10), lineWidth: 1)
                        .frame(width: 136, height: 136)

                    Circle()
                        .trim(from: 0, to: ringProgress)
                        .stroke(
                            AngularGradient(
                                colors: [
                                    StudioTheme.cool.opacity(0.55),
                                    StudioTheme.accent,
                                    StudioTheme.cool,
                                    StudioTheme.accent.opacity(0.78)
                                ],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 12, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 136, height: 136)
                        .shadow(color: StudioTheme.accent.opacity(0.22), radius: 10, y: 4)
                        .animation(.spring(response: 0.7, dampingFraction: 0.86), value: snapshot.currentLength)

                    VStack(spacing: 6) {
                        Text(snapshot.currentLength.formatted())
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundStyle(StudioTheme.textPrimary)
                            .monospacedDigit()
                        Text(snapshot.currentLength == 1 ? "节专注" : "节连续专注")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .tracking(1.4)
                            .foregroundStyle(StudioTheme.textTertiary)
                    }
                }
                .frame(maxWidth: .infinity)

                Text(snapshot.latestSummary)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(StudioTheme.textPrimary)
                    .lineLimit(2)

                Text(snapshot.currentLength == 0 ? "断链并不抹掉历史，它只是在等下一次点亮。" : "每一节都代表一次真的完成，不是空洞打卡。")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(StudioTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity, minHeight: 286, alignment: .top)
    }

    private var pulsePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("最近 12 天脉冲")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .tracking(1.6)
                        .foregroundStyle(StudioTheme.textTertiary)
                    Text("不是抽象统计，而是最近专注动量的实体波形。")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(StudioTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    Text(totalFocusLabel)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(StudioTheme.textPrimary)
                        .monospacedDigit()
                    Text("累计守住时长")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(StudioTheme.textTertiary)
                }
            }

            GeometryReader { proxy in
                let availableWidth = max(proxy.size.width, 1)
                let barWidth = max((availableWidth - 11 * 8) / 12, 14)

                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(snapshot.dailyPulses) { pulse in
                        HomeChainPulseBar(
                            pulse: pulse,
                            width: barWidth,
                            maxFocusSeconds: maxPulseSeconds
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
            .frame(height: 152)

            HStack(spacing: 10) {
                highlightPill(title: "今日", value: shortFocusLabel(snapshot.focusSecondsToday), emphasized: true)
                highlightPill(title: "Shield", value: "\(snapshot.shieldedSessionCount) 次", emphasized: false)
                highlightPill(title: "主链新增", value: "\(snapshot.todayContributionCount) 节", emphasized: false)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 286, alignment: .topLeading)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
    }

    private var summaryStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                HomeChainMetricBadge(title: "当前主链", value: "\(snapshot.currentLength)")
                HomeChainMetricBadge(title: "累计完成", value: "\(snapshot.totalCompletedSessions)")
                HomeChainMetricBadge(title: "累计时长", value: totalFocusLabel)
                HomeChainMetricBadge(title: "今日新增", value: "\(snapshot.todayContributionCount)")
            }
            .padding(.vertical, 2)
        }
    }

    private var decorativeGlow: some View {
        ZStack {
            Circle()
                .fill(StudioTheme.cool.opacity(0.14))
                .frame(width: 160, height: 160)
                .blur(radius: 18)
                .offset(x: 28, y: -34)

            Circle()
                .fill(StudioTheme.accent.opacity(0.20))
                .frame(width: 108, height: 108)
                .blur(radius: 12)
                .offset(x: 10, y: 36)
        }
        .allowsHitTesting(false)
    }

    private var momentumTitle: String {
        switch snapshot.currentLength {
        case 0:
            "等待重铸"
        case 1...2:
            "链条点亮"
        case 3...5:
            "惯性已成"
        case 6...11:
            "进入深水区"
        default:
            "锁定高势能"
        }
    }

    private var headerCopy: String {
        if snapshot.currentLength == 0 {
            return "链条不是签到数字，而是完成证明。现在首页保留这片场域，等你把下一次真正完成重新点亮。"
        }
        return "每完成一次高质量专注，就在这里留下实体链节。你看到的不是统计，而是自己最近持续守住的承诺。"
    }

    private var todayDeltaText: String {
        snapshot.todayContributionCount == 0 ? "今天还没新增链节" : "今天已新铸 \(snapshot.todayContributionCount) 节"
    }

    private var ringProgress: Double {
        min(Double(max(snapshot.currentLength, 0)) / 12.0, 1.0)
    }

    private var totalFocusLabel: String {
        shortFocusLabel(snapshot.totalFocusSeconds)
    }

    private var maxPulseSeconds: Int {
        max(snapshot.dailyPulses.map(\.totalFocusSeconds).max() ?? 0, 1)
    }

    private func highlightPill(title: String, value: String, emphasized: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(StudioTheme.textTertiary)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(emphasized ? StudioTheme.textPrimary : StudioTheme.textSecondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background((emphasized ? StudioTheme.accentSoft : .white.opacity(0.04)), in: Capsule())
        .overlay {
            Capsule()
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
    }

    private func shortFocusLabel(_ seconds: Int) -> String {
        guard seconds > 0 else { return "0m" }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60

        if hours > 0 {
            return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
        }
        return "\(max(minutes, 1))m"
    }
}

private struct HomeChainLinkStrip: View {
    let nodes: [HomeChainVisualNode]
    let overflowCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("已完成链节")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .tracking(1.6)
                        .foregroundStyle(StudioTheme.textTertiary)
                    Text(nodes.isEmpty ? "第一节会在完成后点亮。" : "越靠右越新，最近完成的链节保持最高亮度。")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(StudioTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                if overflowCount > 0 {
                    StudioCapsuleLabel(title: "更早 \(overflowCount) 节")
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 0) {
                    if overflowCount > 0 {
                        HomeChainOverflowNode(count: overflowCount)
                        HomeChainConnector(tone: .muted)
                    }

                    if nodes.isEmpty {
                        ForEach(0..<3, id: \.self) { index in
                            HomeChainGhostNode(index: index + 1)
                            if index < 2 {
                                HomeChainConnector(tone: .muted)
                            }
                        }
                    } else {
                        ForEach(Array(nodes.enumerated()), id: \.element.id) { offset, node in
                            HomeChainLinkNode(
                                node: node,
                                isLatest: offset == nodes.count - 1,
                                verticalLift: offset.isMultiple(of: 2) ? 0 : -12
                            )

                            if offset < nodes.count - 1 {
                                HomeChainConnector(tone: offset == nodes.count - 2 ? .active : .normal)
                            }
                        }
                    }
                }
                .padding(.vertical, 6)
                .animation(.spring(response: 0.62, dampingFraction: 0.84), value: nodes.count)
            }
        }
    }
}

private struct HomeChainLinkNode: View {
    let node: HomeChainVisualNode
    let isLatest: Bool
    let verticalLift: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("#\(node.chainIndex)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(isLatest ? StudioTheme.deepInk : StudioTheme.textTertiary)

            Text(node.title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(StudioTheme.textPrimary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            HStack {
                Text("\(max(node.durationSec / 60, 1))m")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(StudioTheme.textPrimary)
                    .monospacedDigit()
                Spacer()
                Text(node.completedAt.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(StudioTheme.textTertiary)
            }

            Text(node.proofSnippet)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(StudioTheme.textTertiary)
        }
        .padding(14)
        .frame(width: 114, height: 136, alignment: .topLeading)
        .background(background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        }
        .shadow(color: isLatest ? StudioTheme.accent.opacity(0.24) : .black.opacity(0.14), radius: 16, y: 10)
        .offset(y: verticalLift)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("链节 \(node.chainIndex)，\(node.title)")
    }

    private var background: LinearGradient {
        if isLatest {
            return LinearGradient(
                colors: [
                    StudioTheme.accent.opacity(0.92),
                    StudioTheme.cool.opacity(0.76)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        return LinearGradient(
            colors: [
                .white.opacity(0.07),
                .white.opacity(0.04)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var borderColor: Color {
        isLatest ? .clear : .white.opacity(0.08)
    }
}

private struct HomeChainGhostNode: View {
    let index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("#\(index)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(StudioTheme.textTertiary)
            Text("等待完成")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(StudioTheme.textSecondary)
            Spacer()
            Text("下一次高质量专注会点亮这里")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(StudioTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 114, height: 136, alignment: .topLeading)
        .background(.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [5, 7]))
                .foregroundStyle(.white.opacity(0.10))
        }
    }
}

private struct HomeChainOverflowNode: View {
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ARCHIVE")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(StudioTheme.textTertiary)
            Text("+\(count)")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(StudioTheme.textPrimary)
                .monospacedDigit()
            Spacer()
            Text("更早完成的链节仍然在背后提供重量。")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(StudioTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 114, height: 136, alignment: .topLeading)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct HomeChainConnector: View {
    enum Tone {
        case muted
        case normal
        case active
    }

    let tone: Tone

    var body: some View {
        ZStack {
            Capsule()
                .fill(fill)
                .frame(width: 26, height: 6)

            Circle()
                .fill(glow.opacity(0.95))
                .frame(width: 10, height: 10)
                .blur(radius: 1)
                .offset(x: tone == .muted ? 0 : 8)
        }
        .frame(width: 32, height: 136)
        .accessibilityHidden(true)
    }

    private var fill: LinearGradient {
        switch tone {
        case .muted:
            LinearGradient(colors: [.white.opacity(0.08), .white.opacity(0.04)], startPoint: .leading, endPoint: .trailing)
        case .normal:
            LinearGradient(colors: [StudioTheme.cool.opacity(0.32), StudioTheme.accent.opacity(0.24)], startPoint: .leading, endPoint: .trailing)
        case .active:
            LinearGradient(colors: [StudioTheme.cool.opacity(0.58), StudioTheme.accent.opacity(0.88)], startPoint: .leading, endPoint: .trailing)
        }
    }

    private var glow: Color {
        switch tone {
        case .muted:
            .white.opacity(0.10)
        case .normal:
            StudioTheme.cool.opacity(0.42)
        case .active:
            StudioTheme.accent.opacity(0.72)
        }
    }
}

private struct HomeChainPulseBar: View {
    let pulse: HomeChainDailyPulse
    let width: CGFloat
    let maxFocusSeconds: Int

    var body: some View {
        VStack(spacing: 8) {
            VStack(spacing: 4) {
                Capsule()
                    .fill(fill)
                    .frame(width: width, height: barHeight)
                    .overlay(alignment: .top) {
                        if pulse.completedCount > 0 {
                            Circle()
                                .fill(.white.opacity(pulse.contributesToCurrentChain ? 0.9 : 0.24))
                                .frame(width: 5, height: 5)
                                .padding(.top, 6)
                        }
                    }
                    .shadow(color: shadowColor, radius: 12, y: 6)
                    .animation(.spring(response: 0.7, dampingFraction: 0.86), value: pulse.totalFocusSeconds)

                Text(pulse.completedCount == 0 ? " " : "\(pulse.completedCount)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(StudioTheme.textTertiary)
                    .monospacedDigit()
            }

            Text(pulse.dayStart.formatted(.dateTime.day(.defaultDigits)))
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(StudioTheme.textTertiary)
                .frame(width: width + 4)
        }
        .frame(width: width, alignment: .bottom)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(pulse.dayStart.formatted(date: .abbreviated, time: .omitted))，完成 \(pulse.completedCount) 次")
    }

    private var fill: LinearGradient {
        if pulse.totalFocusSeconds == 0 {
            return LinearGradient(
                colors: [.white.opacity(0.05), .white.opacity(0.03)],
                startPoint: .top,
                endPoint: .bottom
            )
        }

        if pulse.contributesToCurrentChain {
            return LinearGradient(
                colors: [StudioTheme.cool.opacity(0.80), StudioTheme.accent.opacity(0.92)],
                startPoint: .top,
                endPoint: .bottom
            )
        }

        return LinearGradient(
            colors: [.white.opacity(0.26), .white.opacity(0.10)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var shadowColor: Color {
        pulse.contributesToCurrentChain ? StudioTheme.accent.opacity(0.18) : .black.opacity(0.10)
    }

    private var barHeight: CGFloat {
        guard pulse.totalFocusSeconds > 0 else { return 18 }
        let normalized = CGFloat(pulse.totalFocusSeconds) / CGFloat(maxFocusSeconds)
        return 24 + normalized * 92
    }
}

private struct HomeChainMetricBadge: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(StudioTheme.textTertiary)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(StudioTheme.textPrimary)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
    }
}

#Preview("Home Chain Showcase") {
    ZStack {
        StudioBackground()
        HomeChainShowcase(
            snapshot: HomeChainSnapshot(
                currentLength: 8,
                archivedLength: 2,
                totalCompletedSessions: 18,
                totalFocusSeconds: 14 * 3600 + 25 * 60,
                focusSecondsToday: 75 * 60,
                todayContributionCount: 2,
                shieldedSessionCount: 11,
                latestSummary: "完成：写完首页 Chain 模块",
                latestCompletionAt: .now,
                recentNodes: [
                    HomeChainVisualNode(id: UUID(), chainIndex: 3, title: "整理研究", durationSec: 25 * 60, completedAt: .now.addingTimeInterval(-3600 * 36), proofSnippet: "a9c3f0"),
                    HomeChainVisualNode(id: UUID(), chainIndex: 4, title: "处理邮件", durationSec: 30 * 60, completedAt: .now.addingTimeInterval(-3600 * 28), proofSnippet: "b4d8aa"),
                    HomeChainVisualNode(id: UUID(), chainIndex: 5, title: "写需求稿", durationSec: 45 * 60, completedAt: .now.addingTimeInterval(-3600 * 22), proofSnippet: "c1178f"),
                    HomeChainVisualNode(id: UUID(), chainIndex: 6, title: "视觉探索", durationSec: 40 * 60, completedAt: .now.addingTimeInterval(-3600 * 12), proofSnippet: "d83520"),
                    HomeChainVisualNode(id: UUID(), chainIndex: 7, title: "原型走查", durationSec: 35 * 60, completedAt: .now.addingTimeInterval(-3600 * 5), proofSnippet: "e63b9c"),
                    HomeChainVisualNode(id: UUID(), chainIndex: 8, title: "实现首页链条", durationSec: 50 * 60, completedAt: .now.addingTimeInterval(-3600), proofSnippet: "f91ca6")
                ],
                dailyPulses: (0..<12).map { offset in
                    let day = Calendar.current.date(byAdding: .day, value: offset - 11, to: .now) ?? .now
                    let seconds = [0, 1800, 3600, 5400, 4200, 0, 2400, 4800, 3000, 3600, 4500, 5100][offset]
                    return HomeChainDailyPulse(
                        dayStart: Calendar.current.startOfDay(for: day),
                        totalFocusSeconds: seconds,
                        completedCount: seconds == 0 ? 0 : max(seconds / 1800, 1),
                        contributesToCurrentChain: offset >= 6
                    )
                }
            )
        )
        .padding(20)
    }
}
