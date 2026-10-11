import SwiftUI
import UIKit

// MARK: - Tokens

/// Magzi visual system: calm, native, light + dark. iOS 16.0+.
/// One accent (mint), neutral surfaces, hairlines instead of glows.
enum MagziDesign {

    // MARK: Color helpers

    static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> UIColor {
        UIColor(red: r, green: g, blue: b, alpha: a)
    }

    // MARK: Surfaces

    /// Page background (behind grouped content).
    static let background = adaptive(light: rgb(0.965, 0.969, 0.965), dark: rgb(0.043, 0.047, 0.051))
    /// Cards, list rows, composer.
    static let surface = adaptive(light: rgb(1, 1, 1), dark: rgb(0.086, 0.090, 0.098))
    /// Nested fills: input fields, inner wells, inactive chips, assistant bubbles.
    static let surfaceSecondary = adaptive(light: rgb(0.937, 0.941, 0.937), dark: rgb(0.129, 0.133, 0.145))
    /// Sheets / popovers over surface.
    static let surfaceElevated = adaptive(light: rgb(1, 1, 1), dark: rgb(0.122, 0.125, 0.137))

    // MARK: Lines

    static let hairline = adaptive(light: rgb(0, 0, 0, 0.07), dark: rgb(1, 1, 1, 0.08))
    static let hairlineStrong = adaptive(light: rgb(0, 0, 0, 0.12), dark: rgb(1, 1, 1, 0.14))

    // MARK: Text

    static let label = adaptive(light: rgb(0.067, 0.075, 0.082), dark: rgb(0.953, 0.957, 0.953))
    static let labelSecondary = adaptive(light: rgb(0.067, 0.075, 0.082, 0.62), dark: rgb(0.953, 0.957, 0.953, 0.64))
    static let labelTertiary = adaptive(light: rgb(0.067, 0.075, 0.082, 0.40), dark: rgb(0.953, 0.957, 0.953, 0.40))

    // MARK: Accent + semantic (identical hue in both modes, tuned for contrast)

    /// Matches Assets AccentColor (light 0,0.71,0.58 / dark 0.31,0.96,0.76).
    static let mint = adaptive(light: rgb(0.000, 0.710, 0.580), dark: rgb(0.310, 0.960, 0.760))
    /// Foreground on a solid mint fill.
    static let onAccent = adaptive(light: rgb(1, 1, 1), dark: rgb(0.020, 0.090, 0.070))
    /// Soft accent wash for selected rows, user bubbles, focus.
    static let mintSoft = adaptive(light: rgb(0.000, 0.710, 0.580, 0.10), dark: rgb(0.310, 0.960, 0.760, 0.14))

    static let blue = adaptive(light: rgb(0.000, 0.478, 1.000), dark: rgb(0.039, 0.518, 1.000))
    static let amber = adaptive(light: rgb(0.850, 0.540, 0.000), dark: rgb(1.000, 0.700, 0.250))
    static let rose = adaptive(light: rgb(0.880, 0.190, 0.290), dark: rgb(1.000, 0.380, 0.450))
    static let violet = adaptive(light: rgb(0.450, 0.330, 0.900), dark: rgb(0.640, 0.540, 1.000))

    static let success = mint
    static let warning = amber
    static let danger = rose
    static let info = blue

    // MARK: Spacing (4-pt grid)

    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 28
        static let xxxl: CGFloat = 40
        /// Horizontal page gutter.
        static let gutter: CGFloat = 20
        /// Vertical gap between Home sections.
        static let section: CGFloat = 28
    }

    // MARK: Radii (always .continuous)

    enum Radius {
        static let chip: CGFloat = 8
        static let control: CGFloat = 12
        static let card: CGFloat = 18
        static let sheet: CGFloat = 24
        static let bubble: CGFloat = 20
    }

    // MARK: Typography (system fonts, Dynamic Type via text styles)

    enum Typography {
        static let display = Font.system(.largeTitle, design: .rounded, weight: .bold)
        static let title = Font.system(.title2, design: .rounded, weight: .semibold)
        static let headline = Font.system(.headline, design: .default, weight: .semibold)
        static let body = Font.system(.body)
        static let callout = Font.system(.callout)
        static let subheadline = Font.system(.subheadline)
        static let footnote = Font.system(.footnote)
        static let caption = Font.system(.caption, design: .default, weight: .medium)
        /// Small-caps style eyebrow above sections ("TODAY").
        static let eyebrow = Font.system(.caption2, design: .default, weight: .semibold)
        /// Big numbers in metric cards and the Reality ring.
        static let metric = Font.system(.title, design: .rounded, weight: .semibold)
        static let mono = Font.system(.footnote, design: .monospaced)
    }

    // MARK: Shadows (light mode only; dark mode relies on surface contrast)

    struct Shadow {
        let lightOpacity: Double
        let radius: CGFloat
        let y: CGFloat
    }

    enum Shadows {
        static let none = Shadow(lightOpacity: 0, radius: 0, y: 0)
        static let card = Shadow(lightOpacity: 0.05, radius: 12, y: 4)
        static let floating = Shadow(lightOpacity: 0.10, radius: 24, y: 10)
    }

    // MARK: Motion

    enum Motion {
        static let quick = Animation.easeOut(duration: 0.18)
        static let standard = Animation.spring(response: 0.32, dampingFraction: 0.86)
        static let gentle = Animation.easeInOut(duration: 0.45)
    }

    // MARK: - Legacy names (kept so existing call sites compile; prefer the new names)

    static let ink = background
    static let obsidian = surface
    static let graphite = surfaceSecondary
    static let line = hairline
    static let lineStrong = hairlineStrong
    static let text = label
    static let secondary = labelSecondary
    static let tertiary = labelTertiary

    static var appBackground: some View {
        background.ignoresSafeArea()
    }

    static func glass(cornerRadius: CGFloat = Radius.card) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(surface)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(hairline, lineWidth: 1)
            )
    }

    static func solid(cornerRadius: CGFloat = Radius.card) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(surfaceSecondary)
    }

    /// Flat accent expressed as a gradient for legacy call sites.
    static var primaryGradient: LinearGradient {
        LinearGradient(colors: [mint, mint], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Modifiers

private struct MagziShadowModifier: ViewModifier {
    let shadow: MagziDesign.Shadow
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content.shadow(
            color: Color.black.opacity(scheme == .dark ? 0 : shadow.lightOpacity),
            radius: shadow.radius,
            x: 0,
            y: shadow.y
        )
    }
}

private struct MagziCardModifier: ViewModifier {
    let padding: CGFloat
    let radius: CGFloat
    let fill: Color

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(MagziDesign.hairline, lineWidth: 1)
            )
            .modifier(MagziShadowModifier(shadow: MagziDesign.Shadows.card))
    }
}

extension View {
    /// Standard Magzi card: surface fill, 18pt continuous corners, hairline, soft light-mode shadow.
    func magziCard(
        padding: CGFloat = MagziDesign.Spacing.l,
        radius: CGFloat = MagziDesign.Radius.card,
        fill: Color = MagziDesign.surface
    ) -> some View {
        modifier(MagziCardModifier(padding: padding, radius: radius, fill: fill))
    }

    func magziShadow(_ shadow: MagziDesign.Shadow) -> some View {
        modifier(MagziShadowModifier(shadow: shadow))
    }

    /// Page chrome: grouped background behind scroll content.
    func magziScreenBackground() -> some View {
        background(MagziDesign.background.ignoresSafeArea())
    }
}

// MARK: - Components

/// Small tinted capsule: status, channel, runtime badges.
struct MagziPill: View {
    let title: String
    let systemImage: String?
    let tint: Color

    init(title: String, systemImage: String? = nil, tint: Color = MagziDesign.mint) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(.caption2, design: .default, weight: .semibold))
                    .foregroundStyle(tint)
            }
            Text(title)
                .font(MagziDesign.Typography.caption)
                .foregroundStyle(MagziDesign.label)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule(style: .continuous).fill(tint.opacity(0.12)))
        .accessibilityElement(children: .combine)
    }
}

/// Section title row: "Today" ............ "See all".
struct MagziSectionHeader: View {
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?

    init(_ title: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(MagziDesign.Typography.headline)
                .foregroundStyle(MagziDesign.label)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: MagziDesign.Spacing.s)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(MagziDesign.Typography.subheadline)
                    .foregroundStyle(MagziDesign.mint)
            }
        }
        .padding(.horizontal, MagziDesign.Spacing.xs)
    }
}

/// Quiet, centered empty / error state.
struct MagziEmptyState: View {
    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    init(systemImage: String, title: String, message: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: MagziDesign.Spacing.m) {
            Image(systemName: systemImage)
                .font(.system(.title2, design: .default, weight: .regular))
                .foregroundStyle(MagziDesign.labelTertiary)
                .frame(width: 56, height: 56)
                .background(Circle().fill(MagziDesign.surfaceSecondary))
            Text(title)
                .font(MagziDesign.Typography.headline)
                .foregroundStyle(MagziDesign.label)
            Text(message)
                .font(MagziDesign.Typography.subheadline)
                .foregroundStyle(MagziDesign.labelSecondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(MagziCompactButtonStyle())
                    .padding(.top, MagziDesign.Spacing.xs)
            }
        }
        .frame(maxWidth: 320)
        .padding(.vertical, MagziDesign.Spacing.xxxl)
        .frame(maxWidth: .infinity)
    }
}

enum MagziStatus: Equatable {
    case live        // connected, streaming-capable
    case ok          // healthy
    case attention   // degraded / needs a look
    case problem     // failing
    case off         // paused / disabled / offline

    var color: Color {
        switch self {
        case .live, .ok: return MagziDesign.mint
        case .attention: return MagziDesign.amber
        case .problem: return MagziDesign.rose
        case .off: return MagziDesign.labelTertiary
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .live: return "Live"
        case .ok: return "Healthy"
        case .attention: return "Needs attention"
        case .problem: return "Problem"
        case .off: return "Off"
        }
    }
}

/// 8pt status dot. `.live` breathes softly unless Reduce Motion is on.
struct MagziStatusDot: View {
    let status: MagziStatus
    var size: CGFloat = 8

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe = false

    init(_ status: MagziStatus, size: CGFloat = 8) {
        self.status = status
        self.size = size
    }

    var body: some View {
        ZStack {
            if status == .live && !reduceMotion {
                Circle()
                    .fill(status.color.opacity(0.35))
                    .frame(width: size, height: size)
                    .scaleEffect(breathe ? 2.2 : 1)
                    .opacity(breathe ? 0 : 1)
            }
            Circle()
                .fill(status.color)
                .frame(width: size, height: size)
        }
        .frame(width: size * 2.2, height: size * 2.2)
        .onAppear {
            guard status == .live, !reduceMotion else { return }
            withAnimation(.easeOut(duration: 2.4).repeatForever(autoreverses: false)) {
                breathe = true
            }
        }
        .accessibilityElement()
        .accessibilityLabel(status.accessibilityLabel)
    }
}

/// Rounded-square icon used by rows and capability tiles.
struct MagziIconBadge: View {
    let systemImage: String
    var tint: Color = MagziDesign.mint
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(tint.opacity(0.12))
            )
            .accessibilityHidden(true)
    }
}

/// Number + label tile. Two or three per row.
struct MagziMetricCard: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color
    let caption: String?

    init(title: String, value: String, systemImage: String, tint: Color = MagziDesign.mint, caption: String? = nil) {
        self.title = title
        self.value = value
        self.systemImage = systemImage
        self.tint = tint
        self.caption = caption
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MagziDesign.Spacing.s) {
            Image(systemName: systemImage)
                .font(.system(.subheadline, design: .default, weight: .semibold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(value)
                .font(MagziDesign.Typography.metric)
                .foregroundStyle(MagziDesign.label)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(MagziDesign.Typography.footnote)
                    .foregroundStyle(MagziDesign.labelSecondary)
                    .lineLimit(1)
                if let caption {
                    Text(caption)
                        .font(MagziDesign.Typography.caption)
                        .foregroundStyle(MagziDesign.labelTertiary)
                        .lineLimit(1)
                }
            }
        }
        .magziCard(padding: 14)
        .accessibilityElement(children: .combine)
    }
}

/// List row: icon badge, title/subtitle, trailing detail + optional accessory.
struct MagziRow<Accessory: View>: View {
    let title: String
    let subtitle: String?
    let systemImage: String?
    let tint: Color
    let detail: String?
    let showsChevron: Bool
    let accessory: Accessory

    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String? = nil,
        tint: Color = MagziDesign.mint,
        detail: String? = nil,
        showsChevron: Bool = false,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.detail = detail
        self.showsChevron = showsChevron
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: MagziDesign.Spacing.m) {
            if let systemImage {
                MagziIconBadge(systemImage: systemImage, tint: tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(MagziDesign.Typography.body)
                    .foregroundStyle(MagziDesign.label)
                    .lineLimit(2)
                if let subtitle {
                    Text(subtitle)
                        .font(MagziDesign.Typography.footnote)
                        .foregroundStyle(MagziDesign.labelSecondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: MagziDesign.Spacing.s)
            if let detail {
                Text(detail)
                    .font(MagziDesign.Typography.subheadline)
                    .foregroundStyle(MagziDesign.labelSecondary)
                    .lineLimit(1)
            }
            accessory
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(.footnote, design: .default, weight: .semibold))
                    .foregroundStyle(MagziDesign.labelTertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

extension MagziRow where Accessory == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String? = nil,
        tint: Color = MagziDesign.mint,
        detail: String? = nil,
        showsChevron: Bool = false
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            tint: tint,
            detail: detail,
            showsChevron: showsChevron
        ) { EmptyView() }
    }
}

/// Progress ring (Reality: done vs planned).
struct MagziRing: View {
    let progress: Double
    var lineWidth: CGFloat = 8
    var tint: Color = MagziDesign.mint

    var body: some View {
        ZStack {
            Circle()
                .stroke(MagziDesign.surfaceSecondary, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1)) // 0 draws nothing (a round cap would leave a dot)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(MagziDesign.Motion.gentle, value: progress)
        }
        .accessibilityElement()
        .accessibilityValue("\(Int((progress * 100).rounded())) percent")
    }
}
