# Magzi iOS Design Spec

Status: implementation-ready. Supersedes the "obsidian + mint glass" direction in `src/ios/Shared/MagziDesign.swift`, `MagziButtonStyles.swift`, `MagziHomeDashboard.swift`.
Scope: iPhone first, iOS 16.0 deployment target, light + dark, Dynamic Type through XXXL (accessibility sizes reflow to single column).
Product context: `docs/magzi-mobile-ui-requirements.md`.

---

## 1. Design principles

- **Quiet by default.** Neutral surfaces, one accent (mint), hairlines instead of glows. Colour appears only when it means something: mint = healthy/primary, amber = needs you, rose = problem. No gradients, no blur stacks, no monospaced "terminal" chrome.
- **One glance, one action.** Every screen answers "what needs me now?" in the first viewport and offers one primary action. Everything else is a row you can tap into.
- **Magzi is a person, not a dashboard.** Status is expressed as a sentence ("Magzi is here · all quiet") with a single dot, not a grid of gauges. Admin/ops detail lives behind More.
- **Native first.** System fonts and text styles, SF Symbols, `List`/`Form` where data is list-shaped, swipe actions, context menus, sheets with detents, `.refreshable`. If Apple Home or Reminders has a pattern for it, use that pattern.
- **Calm motion, honest state.** Motion only confirms an action or shows liveness (streaming, live dot). Every async surface has an explicit loading, empty and error state; nothing silently shows zeros.

---

## 2. Tokens and components (Swift)

### 2.1 Replace `src/ios/Shared/MagziDesign.swift` with this file

Type-checked with `xcrun -sdk iphonesimulator swiftc -typecheck -target arm64-apple-ios16.0-simulator` together with the button styles in 2.2 and a call-site harness covering every existing usage. Uses only iOS 16 APIs (`Font.system(_:design:weight:)` is 16.0).

```swift
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
                .trim(from: 0, to: max(0.001, min(progress, 1)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(MagziDesign.Motion.gentle, value: progress)
        }
        .accessibilityElement()
        .accessibilityValue("\(Int((progress * 100).rounded())) percent")
    }
}
```

### 2.2 Replace `src/ios/Shared/MagziButtonStyles.swift` with this file

Initializers `MagziPrimaryButtonStyle()` and `MagziSecondaryButtonStyle()` are unchanged. `MagziCompactButtonStyle` is new (referenced by `MagziEmptyState`, so both files land together).

```swift
import SwiftUI

/// Full-width solid mint. One per screen.
struct MagziPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .default, weight: .semibold))
            .foregroundStyle(MagziDesign.onAccent)
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, MagziDesign.Spacing.l)
            .background(
                RoundedRectangle(cornerRadius: MagziDesign.Radius.control + 2, style: .continuous)
                    .fill(MagziDesign.mint)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(MagziDesign.Motion.quick, value: configuration.isPressed)
    }
}

/// Full-width neutral fill.
struct MagziSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .default, weight: .semibold))
            .foregroundStyle(MagziDesign.label)
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, MagziDesign.Spacing.l)
            .background(
                RoundedRectangle(cornerRadius: MagziDesign.Radius.control + 2, style: .continuous)
                    .fill(MagziDesign.surfaceSecondary)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(MagziDesign.Motion.quick, value: configuration.isPressed)
    }
}

/// Inline capsule button for card actions ("Done", "Approve").
struct MagziCompactButtonStyle: ButtonStyle {
    var tint: Color = MagziDesign.mint
    var prominent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .default, weight: .semibold))
            .foregroundStyle(prominent ? MagziDesign.onAccent : tint)
            .padding(.horizontal, 14)
            .frame(minHeight: 34)
            .background(
                Capsule(style: .continuous)
                    .fill(prominent ? tint : tint.opacity(0.12))
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(MagziDesign.Motion.quick, value: configuration.isPressed)
    }
}
```

### 2.3 Compatibility and required call-site changes

Every existing public name keeps compiling. Verified call sites (grep of `src/ios`):

| Symbol | Call sites | Status |
|---|---|---|
| `MagziDesign.text / secondary / tertiary / graphite / obsidian / ink / mint / blue / amber / rose / line / lineStrong` | ContentView, AIChatView, MagziHomeDashboard, MagziRemoteLoginView | Kept as aliases; now adaptive |
| `MagziDesign.appBackground`, `.glass(cornerRadius:)`, `.solid(cornerRadius:)`, `.primaryGradient` | ContentView, AIChatView, MagziRemoteLoginView, MagziHomeDashboard, button styles | Kept; render flat surfaces |
| `MagziPill(title:systemImage:tint:)` | MagziHomeDashboard:50-51, ContentView:6493, AIChatView:2119 | Kept (systemImage now optional) |
| `MagziMetricCard(title:value:systemImage:tint:)` | MagziHomeDashboard:95-97 | Kept (+ optional `caption:`) |
| `MagziPrimaryButtonStyle()`, `MagziSecondaryButtonStyle()` | MagziRemoteLoginView | Kept |

Call sites that must change (they hard-code dark colours and break in light mode once the tokens become adaptive):

1. `src/ios/Views/ContentView.swift` lines 7-15, the private `Color` extension. Replace the body with aliases:
   ```swift
   private extension Color {
       static let magziInk = MagziDesign.background
       static let magziPanel = MagziDesign.surface
       static let magziCard = MagziDesign.surfaceSecondary
       static let magziLine = MagziDesign.hairlineStrong
       static let magziMint = MagziDesign.mint
       static let magziBlue = MagziDesign.blue
       static let magziViolet = MagziDesign.violet
   }
   ```
2. `ContentView.swift:3255` — soul name `LinearGradient(colors: [.white, .magziMint], …)` → `.foregroundStyle(MagziDesign.label)`.
3. `ContentView.swift:3877-3910` (provider-setup `emptyState`) — delete the gradient + two blurred circles + mint shadow; use `MagziDesign.background` and a plain `MagziIconBadge(systemImage: "sparkles", size: 56)`.
4. `ContentView.swift:3994-3998` — step-indicator gradient → `Circle().fill(MagziDesign.mint)` (done) / `Circle().strokeBorder(MagziDesign.hairlineStrong)` (todo).
5. `ContentView.swift:6393-6397` — provider icon gradient → `RoundedRectangle(cornerRadius: 12, style: .continuous).fill(iconBackgroundColor.opacity(0.12))`.
6. `src/ios/Shared/MagziHomeDashboard.swift` — delete the file; replaced by `MagziHomeView` (§4.1). The `MagziHomeDashboard(...)` call in ContentView (≈ line 1897) becomes `AdhocEmptyState` (§4.4).
7. `MagziRemoteLoginView.swift` — restyle into `MagziConnectCard` (§4.1 unpaired) and drop `appBackground`/`glass` usage there.

Rules for new code: never use `Color.white`/`.black` for text or fills; never use `LinearGradient`/`RadialGradient`/`.blur` for chrome; use `MagziDesign.Typography.*` (never fixed point sizes, so Dynamic Type works); every corner uses `style: .continuous`.

---

## 3. Information architecture

### 3.1 Root

`MinisApp` → `WindowGroup { MagziRootView() }`. `MagziRootView` is a `TabView(selection:)` with 5 tabs; each tab owns its own `NavigationStack` (Ad-hoc keeps ContentView's `NavigationSplitView`). Tab bar uses system appearance (`.toolbarBackground(.visible, for: .tabBar)` with default material); tint = `MagziDesign.mint`.

| # | Tab | Label | SF Symbol | Root view | Badge |
|---|---|---|---|---|---|
| 0 | Home | Home | `house` | `MagziHomeView` | none |
| 1 | Magzi | Magzi | `bubble.left.and.bubble.right` | `MagziChatView` | unread proactive count |
| 2 | Household | Household | `person.2` | `HouseholdView` | pending approvals count |
| 3 | Ad-hoc | Ad-hoc | `sparkles` | existing `ContentView` | none |
| 4 | More | More | `ellipsis.circle` | `MoreView` | dot when Admin status ≠ ok (admins only) |

State shared via `@StateObject MagziAppModel` (environment object): `auth` (paired/unpaired/role), `bootstrap`, `selectedHouseholdId`, `socketState`, `selectedTab`, `pendingChatPrefill: String?`. Deep links: `magzi://chat?prefill=…`, `magzi://household/approvals`, `magzi://item/<id>`, `magzi://adhoc/new`.

Unpaired: Home shows the Connect card; Magzi and Household show `MagziEmptyState` with "Connect to Magzi" button (opens the same connect sheet); Ad-hoc works fully; More shows only Ad-hoc settings and "Connect to Magzi".

Role gating: `me.role == "admin"` shows Admin row in More. Ops row is visible to admins; it has its own login.

### 3.2 Navigation map (screen → endpoints)

Base: `{server}/mobile/v1` with `Authorization: Bearer`. Ops: `{cockpit}/api` with its own session.

| Screen | Path | Endpoints |
|---|---|---|
| Connect (sheet) | Home → Connect | `POST /login/request {email}`, `POST /login/verify {email, code}`, then `GET /bootstrap`, `POST /me/devices` (push token) |
| Home | Tab 0 | `GET /bootstrap`, `GET /me`, `GET /households`, `GET /households/:id/rota`, `GET /households/:id/items`, `GET /households/:id/bills`, `GET /households/:id/approvals`, `GET /households/:id/presence`, `GET /households/:id/reality`, `WS /ws` |
| Magzi chat | Tab 1 | `GET /sessions`, `GET /conversations/:id/messages` (`mobile:<userId>` / `person:<id>`), `POST /messages`, `WS /ws` (`message.delta`, `message.final`, `tool.*`, `approval.requested`), `POST /approvals/:id/approve|deny` |
| Household overview | Tab 2 | `GET /households`, `GET /households/:id/reality`, `GET /households/:id/items`, `GET /households/:id/approvals` |
| Items | Household → Items | `GET /households/:id/items`, `POST /households/:id/items` (capture), `PATCH /items/:id {householdId, action: done|drop|claim}`, `POST /items/:id/progress {action: drop|park|schedule|delegate, …}`, `POST /items/:id/reopen` |
| Item detail | Items → row | same as Items |
| Rota | Household → Rota | `GET /households/:id/rota`, `POST /items/:id/swap`, `POST /items/:id/skip` |
| Meals | Household → Meals | `GET /households/:id/meals` |
| Bills | Household → Bills | `GET /households/:id/bills` |
| Approvals | Household → Approvals | `GET /households/:id/approvals`, `POST /approvals/:id/approve`, `POST /approvals/:id/deny` |
| Reality | Household → Reality | `GET /households/:id/reality`, `POST /items/:id/reopen` (undo inferred closure), `POST /items/:id/progress` |
| Group thread | Household → Thread | `GET /households/:id/thread`, `POST /households/:id/thread {text}` |
| Facts | Household → Facts | `GET /households/:id/facts`, `POST /households/:id/facts` |
| Activity log | Household → Activity | `GET /households/:id/events` |
| Weekly summary | Household → Summary | `GET /households/:id/summary/latest` (PDF → QuickLook) |
| Members | Household → Members | `GET /households` (members), `GET /households/:id/presence`, `POST /households/:id/invites`, `POST /invites/accept`, `POST /households/:id/members/remove`, `POST /households/:id/leave` |
| Ad-hoc | Tab 3 | local (existing ContentView + 9router provider) |
| More | Tab 4 | `GET /me` |
| Me → Memory | More → Me | `GET /me/memory`, `PATCH /me/memory/:id`, `DELETE /me/memory/:id` |
| Me → Activity | More → Me | `GET /me/activity` |
| Me → Preferences | More → Me | `GET /me`, `PATCH /me/preferences` |
| Me → My week | More → Me | `GET /me/time` |
| Me → Timeline | More → Me | `GET /me/timeline`, `POST /me/timeline/:id/confirm`, `POST /me/timeline/:id/correct` |
| Me → Places | More → Me | `GET /me/places`, `PUT /me/places/:id` |
| Me → Privacy | More → Me | `GET /me/context/sharing`, `PUT /me/context/sharing` |
| Me → Devices | More → Me | `POST /me/devices` (register/refresh this device) |
| Capabilities | More → Capabilities, Home strip | none (deep-links to Magzi chat with prefill) |
| Admin | More → Admin | `GET /admin/status`, `POST /admin/pause`, `GET /admin/qr`, `GET /users`, `POST /users`, `POST /users/disable` |
| Ops login | More → Ops | `POST /api/login` (code sent over WhatsApp), `POST /api/verify {code}`, `POST /api/logout` |
| Ops cockpit | Ops → tabs | `GET /api/state`, `GET /api/usage`, `GET /api/sessions`, `GET /api/session?id=`, `GET /api/watch` (stream), `POST /api/allow`, `POST /api/deny`, `POST /api/pause`, `POST /api/capability`, `POST /api/config`, `POST /api/config/rollback`, `GET/POST /api/admin-instructions`, `POST /api/admin-instructions/approve`, `POST /api/admin-instructions/accept`, `POST /api/restart` |
| Settings | More → Settings | local + `GET /bootstrap` (server health), sign out |

---

## 4. Screens

Shared conventions for every screen:
- Background `MagziDesign.background`; content in `ScrollView` + `LazyVStack(spacing: Spacing.section)` with `.padding(.horizontal, Spacing.gutter)`, or `List` with `.listStyle(.insetGrouped)` + `.scrollContentBackground(.hidden)` + `.background(MagziDesign.background)` for long lists.
- Navigation titles: Home uses no large title (custom greeting); all other roots use `.navigationBarTitleDisplayMode(.large)`; pushed screens `.inline`.
- Loading: first load shows `.redacted(reason: .placeholder)` skeletons of the real layout (never a centered spinner on a root). Refresh = `.refreshable`.
- Error: inline `magziCard` with `MagziStatusDot(.problem)`, one-line message, "Try again" compact button. Copy: "Couldn't reach Magzi. Check you're on the home network or Tailscale." Offline cached data stays visible with a footnote "Updated 12 min ago".
- Destructive actions: swipe + `confirmationDialog`. Reversible actions: no dialog; show an "Undo" toast (§6) for 4 s.
- Hit targets ≥ 44pt. All rows are `Button`s or `NavigationLink`s with `.buttonStyle(.plain)`.

### 4.1 Home (`MagziHomeView`)

Purpose: calm landing page. Answers "is Magzi OK, what needs me today, how is the house doing", and starts anything in one tap.

Layout top → bottom (ScrollView, gutter 20, section gap 28):

1. **Greeting header** (no nav bar title; `.toolbar(.hidden, for: .navigationBar)` is iOS 16 OK).
   - Line 1 `Typography.footnote`, `labelSecondary`: date — "Saturday, 10 October".
   - Line 2 `Typography.display`, `label`: "Good morning, Aashir" (morning < 12:00, afternoon < 17:00, evening otherwise).
   - Line 3 `HStack(spacing: 6)`: `MagziStatusDot` + `Typography.subheadline` `labelSecondary` status sentence:
     - socket live + admin status ok → `.live`, "Magzi is here · all quiet"
     - live + N pending approvals → `.attention`, "Magzi is here · 2 things need you"
     - socket reconnecting → `.attention`, "Reconnecting…"
     - unreachable → `.off`, "Magzi is offline · showing last update"
   - Trailing: 36pt circular avatar (user initial on `surfaceSecondary`) → pushes Me.
2. **Ask Magzi composer entry** — a single 52pt-tall `magziCard(padding: 0)` button styled like a text field: leading `sparkle` (mint), placeholder "Ask Magzi anything…" `labelTertiary`, trailing `mic` (labelSecondary). Tap → switch to Magzi tab and focus composer. Tap on mic → Magzi tab + start dictation.
3. **Today** — `MagziSectionHeader("Today", actionTitle: "Household", action: → Household tab)`. One `magziCard(padding: 0)` containing up to 5 `MagziRow`s separated by inset hairlines (leading inset 58), ordered: approvals, my chores due today, items assigned to me / unclaimed, bills due ≤ 3 days.
   - Approval: `checkmark.shield` amber, title = approval summary, subtitle "Needs your OK", accessory = two compact buttons "Deny" (tint labelSecondary) / "Approve" (prominent mint).
   - Chore: `arrow.triangle.2.circlepath` mint, title = chore, subtitle "Today · you", accessory = 28pt circular check button (`circle` → `checkmark.circle.fill`), tap = `PATCH /items/:id {action: done}`.
   - Item: `checklist` blue, title, subtitle "Unclaimed" or due text; swipe leading "Done", trailing "Claim".
   - Bill: `creditcard` amber, title = payee, detail = "£42 · Tue".
   - If more than 5: footer row "4 more in Household" chevron.
   - Empty: inside the card, `Typography.subheadline` `labelSecondary` centered, 20pt padding: "Nothing needs you today." with `checkmark.circle` mint above.
4. **At home** (presence) — `MagziSectionHeader("At home")`. Horizontal `ScrollView` of member chips: 40pt avatar circle + name (`caption`) + state dot below avatar (home = mint, out = labelTertiary, away = amber, unknown = none). Coarse states only, never locations. Hidden if household has 1 member.
5. **This week** (Reality) — `magziCard`. `HStack(spacing: 16)`: `MagziRing(progress: done/planned)` 64pt with centered `Typography.headline` "68%"; trailing `VStack`: `Typography.headline` "17 of 25 done", `footnote labelSecondary` "3 slipping · 2 parked", and a fair-load mini bar (one 6pt capsule per member, widths proportional to share, colours mint/blue/violet/amber in member order). Whole card → Reality screen.
6. **Quick capabilities** — `MagziSectionHeader("Ask about", actionTitle: "All", action: → Capabilities)`. Horizontal scroll of 6 tiles (72×84: `MagziIconBadge` size 36 + `caption` label): Agenda, Weather, Portfolio, Research, Gmail, Home. Tap = prefill Magzi chat (§4.7 prompts).
7. **Start a task with 9router** — `magziCard`, `MagziRow(title: "Start a task", subtitle: "On-device agent · runs through 9router", systemImage: "sparkles", tint: MagziDesign.violet, showsChevron: true)`. Tap → Ad-hoc tab + new local session (`magzi://adhoc/new`), default model group `magzi-agent`.
8. Bottom padding 32.

Unpaired state (replaces sections 2-6; 7 stays):
- **Connect card** (`MagziConnectCard`, `magziCard(padding: 20)`):
  - `MagziIconBadge(systemImage: "house", size: 44)`
  - Title `Typography.title`: "Connect to Magzi"
  - Body `subheadline labelSecondary`: "Your household's assistant runs on your home server. Sign in with the email your admin added."
  - Field "Server" — `TextField` on `surfaceSecondary`, radius 12, placeholder `https://magzi.your-tailnet.ts.net`, `.keyboardType(.URL)`, `.textInputAutocapitalization(.never)`, prefilled from `MagziAuthStore`.
  - Field "Email" — `.textContentType(.emailAddress)`.
  - Primary button "Send code".
  - Step 2 (same card, cross-fade): "We sent a 6-digit code to a…@gmail.com" + one `TextField` with `.textContentType(.oneTimeCode)`, `.keyboardType(.numberPad)`, `.font(.system(.title2, design: .rounded, weight: .semibold))`, letter-spaced; auto-submits at 6 digits. Secondary text buttons "Resend" (enabled after 30 s) and "Change email".
  - Copy on request success (never reveals existence): "If that email is enabled, a code is on its way."
  - Error copy: "That code didn't work. Check it and try again." / "Can't reach that server. Are you on Tailscale?"
- Under the card, footnote `labelTertiary`: "No server? You can still use Ad-hoc below."

### 4.2 Magzi chat (`MagziChatView`)

- Nav bar inline title: `VStack(spacing: 0)` "Magzi" (`headline`) + status line (`caption labelSecondary`, "Online" / "Typing…" / "Offline"). Trailing toolbar: `magnifyingglass` (search thread), `ellipsis.circle` menu: "Unified thread (app + WhatsApp)" toggle that switches `mobile:<userId>` ↔ `person:<id>`, "Capabilities", "Clear draft".
- Body: message list per §5. Pull-to-load older messages (`GET /conversations/:id/messages?before=`).
- Composer pinned to bottom (§5.6). `pendingChatPrefill` is consumed on appear: text inserted, keyboard focused, cursor at end. Never auto-sent.
- Empty (no messages): `MagziEmptyState(systemImage: "sparkle", title: "Say hi to Magzi", message: "Magzi knows your household, remembers what matters and can act for you.")` plus 3 suggestion chips below (capsules on `surfaceSecondary`): "What's on today?", "Add milk to the list", "How's the week going?".
- Offline: banner under nav bar, `surfaceSecondary`, `wifi.slash`, "Offline — messages will send when Magzi is back." Queued messages show a `clock` glyph.
- Unpaired: `MagziEmptyState(systemImage: "link", title: "Not connected", message: "Connect to your home server to chat with Magzi.", actionTitle: "Connect")`.

### 4.3 Household (`HouseholdView`)

Root of tab 2. Nav title = household name, large. If > 1 household: title is a `Menu` (chevron.down) to switch. Toolbar trailing: `plus` → Capture sheet.

Layout:
1. **Capture field** — one-line `magziCard(padding: 12)` "Add something for the house…" (leading `plus.circle` mint). Return = `POST /households/:id/items {text}`. Success: row inserts at top of Open items with `.success` haptic.
2. **Needs you** (only if approvals > 0): card with approval rows (same as Home) → "See all" → Approvals.
3. **Overview grid** — 2-column `LazyVGrid` of `MagziMetricCard`:
   - "Open items" `checklist` blue, value = count, caption "3 unclaimed" → Items.
   - "This week" `chart.pie` mint, value "68%", caption "17 of 25" → Reality.
   - "Bills" `creditcard` amber, value = count due ≤ 30 d, caption "Next: Tue" → Bills.
   - "Dinner" `fork.knife` violet, value = tonight's meal (lineLimit 1, minimumScaleFactor), caption "Tonight" → Meals.
   At accessibility text sizes the grid becomes 1 column.
4. **Sections list** — `magziCard(padding: 0)` of `MagziRow(showsChevron: true)`:
   - Rota `arrow.triangle.2.circlepath` mint, detail "You: bins today"
   - Group chat `bubble.left.and.bubble.right` blue, detail unread count → Thread
   - Facts `book.closed` labelSecondary
   - Activity `clock.arrow.circlepath` labelSecondary
   - Weekly summary `doc.richtext` labelSecondary, detail "Week 41"
   - Members `person.2` labelSecondary, detail "4"

Screens pushed from Household:

**Items** — `List(.insetGrouped)`. Segmented `Picker` at top: Open / Mine / Done. Sections: "Unclaimed", "Claimed", "Parked". Row: leading 22pt check circle (tap = done), title `body`, subtitle `footnote labelSecondary` "Claimed by Sara · due Fri". Swipe leading: Done (mint). Swipe trailing: Claim (blue), More (labelSecondary → progress action sheet: Drop, Park, Schedule…, Delegate…). Schedule opens a `DatePicker(.graphical)` sheet with medium detent; Delegate opens a member picker. Done tab rows show "Reopen" swipe → `POST /items/:id/reopen`. Empty Open: `MagziEmptyState(systemImage: "checkmark.circle", title: "All clear", message: "Nothing open for the house.")`.

**Item detail** — inline title. Header card: title `Typography.title`, pills (status, owner, due). Body rows: Created by, Created, Source channel (pill). Bottom: primary button "Mark done"; secondary row of compact buttons Claim / Park / Schedule / Delegate; destructive text button "Drop" with confirmation "Drop this item? Magzi will stop tracking it."

**Rota** — 7-day horizontal day picker (capsules, today selected mint) above a list of chores for the selected day. Row: chore title, assignee avatar + name as detail, accessory check button for own chores. Context menu / swipe trailing: Swap… (member picker → `POST /items/:id/swap`), Skip (`POST /items/:id/skip`, undo toast "Skipped bins today"). Empty day: "No chores on Sunday."

**Meals** — Section "This week": 7 rows, day as `Typography.eyebrow` uppercase leading column (44pt), meal title `body`; empty day shows "—" `labelTertiary`. Section "Saved": rows with `bookmark` icon. Footer button "Plan with Magzi" → Magzi chat prefill "Plan dinners for the rest of this week using our saved meals. Keep it simple on weekdays."

**Bills** — Segmented: "Next 30 days" / "Renewals". 30-day list grouped by week ("This week", "Next week", "Later"), row: payee, subtitle date, detail amount (`.monospacedDigit()`), overdue → amber detail + `exclamationmark.circle`. Renewals: 12-month list grouped by month, detail amount + yearly cost. Header summary card: "£612 due in the next 30 days".

**Approvals** — `List`. Row card: `checkmark.shield` amber badge, title, body text (risk explanation, `subheadline labelSecondary`, max 4 lines then "More"), requested by + time `caption`. Buttons full-width pair: "Deny" (secondary) / "Approve" (primary). After action, row collapses with `.success` haptic and moves to "Recently decided" section (greyed, pill "Approved"/"Denied"). Empty: `MagziEmptyState(systemImage: "checkmark.shield", title: "No approvals waiting", message: "When Magzi needs a yes before acting, it shows up here.")`.

**Reality** — the week, honestly.
1. Hero card: `MagziRing` 120pt, center "68%" `Typography.metric` + "done" caption; to the right "17 of 25 planned things got done this week."
2. **Fair load** card: one row per member — name, horizontal capsule bar (8pt, member colour), detail "41%". Footnote: "Share of completed household work this week."
3. **Slipping** card: rows of items with `exclamationmark.triangle` amber, subtitle "Planned Tue · not done"; swipe/compact actions Park / Schedule / Delegate (`POST /items/:id/progress`).
4. **Parked** card: rows, compact "Unpark" (`progress {action: schedule}` with date sheet).
5. **Magzi closed these** card (inferred closures): row title, subtitle "Looked done from WhatsApp · Wed", accessory compact button "Undo" → `POST /items/:id/reopen`.
6. **Follow-through** card: the server's driver sentence (`body`), e.g. "Most slips happen on Thursdays." `lightbulb` icon, labelSecondary.
Empty week: "Nothing planned yet this week."

**Group chat (Thread)** — read + post to the household WhatsApp group. Uses the chat renderer (§5) in "group mode": every message shows sender name above the bubble (`caption` in member colour), no assistant/user distinction except own messages right-aligned. Banner at top `footnote labelSecondary`: "This is your family WhatsApp group. Messages you send here post to the group." Composer placeholder "Message the group".

**Facts** — `List`, searchable (`.searchable`). Rows: fact text, subtitle "Added by Sara · Mar 4". Toolbar `plus` → sheet with multiline `TextField` "Something Magzi should know about the house" + Save.

**Activity** — `List` of events grouped by day; row icon by event kind (item `checklist`, approval `checkmark.shield`, member `person`, bill `creditcard`, system `gearshape`), text `subheadline`, time `caption labelTertiary` trailing.

**Weekly summary** — pushes a `QLPreviewController` wrapper of the downloaded PDF; toolbar `square.and.arrow.up` (ShareLink, iOS 16). Loading: centered `ProgressView("Preparing this week's summary…")`. Empty (404): "No summary yet. Magzi writes one every Sunday evening."

**Members** — Section "Members": avatar, name, role pill, presence dot. Admin swipe trailing on others: "Remove" (destructive, confirm "Remove Sara from the household? Their personal data stays with them."). Section "Invite": row "Invite someone" `person.badge.plus` → `POST /invites` → sheet with code (`Typography.metric`, monospacedDigit) + `ShareLink("Share invite", item: link)`. Row "Join with a code" → sheet with code field → `POST /invites/accept`. Footer destructive button "Leave household" with confirmation.

### 4.4 Ad-hoc (existing ContentView)

Keep ContentView, its sessions sidebar and AIChatView. Changes:
- Replace the `MagziHomeDashboard` detail placeholder with `AdhocEmptyState`: `MagziEmptyState(systemImage: "sparkles", title: "Start a task", message: "Runs on this iPhone through your household 9router gateway. Pick a model, attach files, let it work.", actionTitle: "New task")`, plus a model pill row below (`MagziPill` for current model group, e.g. "magzi-agent", tint violet).
- Sidebar title "Ad-hoc"; new-session button label "New task".
- Session row runtime pill stays (ContentView:6493) — tint becomes `MagziDesign.violet` for local/9router, `MagziDesign.mint` for homecloud.
- AIChatView:2119 "9router" pill stays, tint violet.
- All existing colours re-themed through §2.3; no layout changes.

### 4.5 More (`MoreView`)

`List(.insetGrouped)`, large title "More".
- Header row (section 1): 52pt avatar, name `headline`, email `footnote labelSecondary`, role pill → Me.
- Section 2: Capabilities `square.grid.2x2` mint; Ad-hoc models `cpu` violet (opens existing provider settings).
- Section 3 (admins only): Admin `shield.lefthalf.filled` amber with trailing `MagziStatusDot` from `/admin/status`; Ops cockpit `gauge.with.dots.needle.33percent` labelSecondary.
- Section 4: Settings `gearshape`; About `info.circle`.

### 4.6 Me (`MeView`)

Large title = first name. Sections as `magziCard` blocks in a ScrollView:
1. **My week** — horizontal stacked bar (12pt capsule, segments by category colour: Work blue, Home mint, Family violet, Health rose, Other labelTertiary) + legend rows with hours (`monospacedDigit`). → Timeline. Source `GET /me/time`. Empty: "Magzi will learn your week as you share context."
2. **Rows card** (chevrons): Memory `brain` ("128 things"), Timeline `calendar.day.timeline.left`, Places `mappin.and.ellipse`, Activity `list.bullet.rectangle`, Preferences `slider.horizontal.3`, Privacy `hand.raised`, Devices `iphone`.

**Memory** — `List`, `.searchable("Search memories")`. Row: memory text (`body`, 3 lines), subtitle source + date. Tap → edit sheet (multiline field, Save → `PATCH`). Swipe trailing "Forget" (destructive, confirm "Forget this? Magzi won't use it again." → `DELETE`). Empty: "Nothing remembered yet."

**Activity** — read-only list grouped by day, same row style as household Activity.

**Preferences** — `Form`:
- Section "Daily brief": Toggle "Morning brief"; `DatePicker("Time", displayedComponents: .hourAndMinute)`.
- Section "Quiet hours": Toggle; From / To time pickers. Footer: "Magzi holds non-urgent messages during quiet hours."
- Section "Channel": `Picker` "Reach me on" — App / WhatsApp (`.pickerStyle(.inline)`).
- Section "Nudges": Picker "Style" Gentle / Direct / Playful (segmented); `Stepper("Up to 3 nudges a day", in: 0...10)`.
Every change PATCHes immediately (debounced 600 ms); failure reverts the control and shows error toast.

**Timeline** — day picker (same as Rota). Vertical list of episodes: leading time column (`caption monospacedDigit`, 52pt), 2pt vertical hairline track with 8pt category-coloured dot, card with title ("Gym · 1h 10m"), place subtitle. Unconfirmed episodes show compact buttons "Right" (`confirm`) / "Fix…" (sheet with category picker + title field → `correct`). Confirmed show a small `checkmark` labelTertiary.

**Places** — `List`. Row: `MagziIconBadge` by kind (home `house`, work `briefcase`, gym `figure.run`, school `graduationcap`, other `mappin`), name, subtitle visit count; trailing "Shared" pill if shared. Tap → edit sheet: Name field, Kind picker, Toggle "Share with household" (footer: "Household sees only the place name, never your location.") → `PUT`.

**Privacy** — `Form`, one Toggle per sharing switch from `GET /me/context/sharing` (Location visits, Activities, Workouts, Presence). Each has a footer sentence. Header card above form: `hand.raised` + "You decide what Magzi can sense. Household members only ever see coarse presence." Changes → `PUT` immediately.

**Devices** — this device card: name, "Notifications on/off" status pill, button "Re-register for notifications" (`POST /me/devices`). If notifications denied: row "Turn on in Settings" → `UIApplication.openSettingsURLString`.

### 4.7 Capabilities (`CapabilitiesView`)

Large title "Capabilities". Subtitle text under title (`subheadline labelSecondary`): "Things Magzi can do. Tap one to start a conversation." `.searchable`.
Grouped sections; each a 3-column `LazyVGrid` (2 columns at accessibility sizes) of tiles: `magziCard(padding: 12)` with `MagziIconBadge` (size 36) top-leading and title `footnote` `label` below, min height 88. Tap → `pendingChatPrefill = prompt`, switch to Magzi tab. Long-press context menu: "Ask now" (sends immediately), "Copy prompt".

| Section | Tile | Symbol | Tint | Prompt |
|---|---|---|---|---|
| Today | Agenda | `calendar` | blue | What's on my agenda today? Include calendar events, reminders, chores and anything due. |
| Today | Reminders | `bell` | amber | Remind me to |
| Today | Tasks & goals | `target` | mint | Show my open tasks and goals, and suggest the one thing I should do next. |
| Today | Weather | `cloud.sun` | blue | What's the weather today and tomorrow where I am? Anything I should plan around? |
| Today | Directions | `map` | blue | How long will it take to get to |
| Money | Portfolio | `chart.line.uptrend.xyaxis` | mint | Give me a quick portfolio check: total value, today's move, and anything unusual. |
| Money | Crypto wallet | `bitcoinsign.circle` | amber | What's in my crypto wallet right now, and how has it changed this week? |
| Money | Trader desk | `bell.badge` | rose | Show my active trader desk alerts and anything that triggered in the last 24 hours. |
| Money | Markets | `globe` | blue | Give me your current market world-view in five bullets, with the news driving it. |
| Know | Research | `magnifyingglass` | violet | Research this for me and come back with a short brief and sources: |
| Know | News brief | `newspaper` | labelSecondary | Brief me on the news that matters to me today. Keep it under two minutes to read. |
| Know | Recall | `brain` | violet | What do you remember about |
| Work | Gmail | `envelope` | rose | Summarise my unread email. Flag anything that needs a reply today. |
| Work | Calendar | `calendar.badge.plus` | blue | Find a free hour this week and hold it for |
| Work | Drive | `folder` | blue | Find the document in my Drive about |
| Create | Instagram studio | `camera` | rose | Draft an Instagram post about |
| Create | Image | `photo` | violet | Make an image of |
| Create | Read aloud | `speaker.wave.2` | labelSecondary | Read this aloud for me: |
| Home | Home Assistant | `lightbulb` | amber | What's the state of the house right now? Lights, heating, doors. |
| Home | Media request | `film` | violet | Add this to Magziflex: |
| Home | Nextcloud | `externaldrive` | blue | Find in Nextcloud: |
| Home | Homecloud | `server.rack` | labelSecondary | Which homecloud services are running, and is anything unhealthy? |
| Automate | Automations | `clock.arrow.2.circlepath` | mint | List my scheduled automations with their next run, and tell me if any failed recently. |
| Automate | New automation | `plus.circle` | mint | Every weekday at 8am, |
| Automate | Browser task | `safari` | blue | Go to this website and |
| Automate | Skills | `wand.and.stars` | violet | What skills have you learned recently, and did any of them need fixing? |

Prompts ending in a fragment ("Remind me to") are intentional: the cursor lands at the end for the user to finish. Home's quick strip uses Agenda, Weather, Portfolio, Research, Gmail, Home Assistant (label "Home").

### 4.8 Admin (`AdminView`, role admin)

Large title "Admin". ScrollView:
1. **Status card** — `MagziStatusDot` (map server `status`: ok → `.ok`, degraded/warn → `.attention`, down/error → `.problem`) + `headline` status word + `Text(text)` rendered as-is (`.font(MagziDesign.Typography.mono)`, `labelSecondary`, selectable via `.textSelection(.enabled)`). Footnote "Updated 10:42 · pull to refresh". The server returns `{status, text}`; do not parse `text` into gauges.
2. **Helper groups** card — Toggle row "Helper groups active" (`pause.circle`) → `POST /admin/pause {paused}`. Footer: "Pausing stops Magzi posting in household WhatsApp groups. Direct chats keep working." Turning off asks confirmation.
3. **WhatsApp pairing** row `qrcode` → sheet: QR image (`GET /admin/qr`, rendered at 240pt on white rounded square in both modes for scanner contrast), caption "Open WhatsApp → Linked devices → Link a device." Auto-refresh every 20 s while open. Error: "WhatsApp is already linked." when server says so.
4. **Users** row `person.3` → Users list.

**Users** — `List`, searchable. Row: name, email subtitle, role pill (admin amber, user labelSecondary), "Disabled" pill rose when disabled. Toolbar `plus` → sheet `Form`: Email, Display name, Role picker (User / Admin) → `POST /users`. Swipe trailing "Disable" → confirm "Disable Sara? They'll be signed out on all devices." → `POST /users/disable`.

### 4.9 Ops cockpit (`OpsView`, admins, separate login)

**Ops login** — centred card like Connect: `MagziIconBadge("gauge.with.dots.needle.33percent")`, title "Ops cockpit", body "We'll send a one-time code to the owner's WhatsApp." Field "Cockpit URL" (defaults to server host, cockpit port; stored separately). Primary "Send code" → `POST /api/login`; then code field (`.oneTimeCode`) → `POST /api/verify`. Session is kept in Keychain separately; "Sign out of Ops" in toolbar menu → `/api/logout`.

**Ops home** — inline title "Ops"; a segmented `Picker` under the nav bar switches 5 panes (no nested tab bar): Overview · Usage · Sessions · Watch · Config.

- **Overview** (`/api/state`): Card "Agent": status dot + "Running"/"Paused"; buttons "Pause agent" (secondary, confirm) and "Restart service" (destructive text, confirm "Restart magzid? Chats pause for about 20 seconds."). Card "Features": rows per feature with `MagziStatusDot` (on `.ok`, off `.off`, attention `.attention`), name, detail reason; trailing Toggle → `POST /api/capability {name, enabled}`. Card "Pending tool approvals": rows with Allow / Deny compact buttons → `/api/allow`, `/api/deny`.
- **Usage** (`/api/usage`): `MagziMetricCard` pair "Tokens today" / "Cost today"; then `List` of models: name (`mono`), detail tokens (`monospacedDigit`), thin horizontal bar of share. Range picker Today / 7 days.
- **Sessions** (`/api/sessions`): list rows: channel pill, conversation id (mono, truncated middle), last activity. Tap → trace detail (`/api/session?id=`): vertical timeline of turns; each turn card with model pill, latency, token count, collapsed tool calls (`DisclosureGroup`).
- **Watch** (`/api/watch` stream): live audit list, newest at top, rows `mono footnote`: time, actor, action, status dot. Header `MagziStatusDot(.live)` "Live" with a pause button (`pause.fill`) that freezes the list. Keep last 500 rows. Auto-reconnect with "Reconnecting…" banner.
- **Config**: list of editable keys (from state). Tap → sheet with key name (mono), current value in `TextEditor` (mono), "Save" primary → `POST /api/config {key, value}`; success shows toast with "Roll back" → `POST /api/config/rollback`. Section "Improvement instructions" (`/api/admin-instructions`): composer "Tell Magzi how to improve…" + Submit; list rows with state pill (submitted → amber "Pending", approved → blue "Approved", accepted → mint "Accepted"); compact actions Approve / Accept per state.

### 4.10 Settings (`SettingsView`)

`Form`:
- "Magzi server": server URL (read-only, copyable), connection row with `MagziStatusDot` + "Connected"/"Offline", button "Test connection" (`GET /bootstrap`), signed-in email, destructive "Sign out".
- "Notifications": status + "Open iOS Settings".
- "Appearance": `Picker` System / Light / Dark (applies `.preferredColorScheme`), app icon picker (existing alternate icons).
- "Ad-hoc": links to existing provider/model/9router settings screens from ContentView (unchanged).
- "About": version, build, "Acknowledgements".

---

## 5. Chat visual spec

Applies to Magzi chat and household Thread (group mode). New SwiftUI view `MagziMessageList` built on `ScrollViewReader` + `LazyVStack` (iOS 16 safe; anchor bottom via `scrollTo(lastId, anchor: .bottom)`). Ad-hoc keeps its existing `CollectionViewMessageListV3`, re-themed only.

### 5.1 Layout
- Horizontal gutter 16. Max bubble width = 78% of container width.
- Message groups: consecutive messages from the same sender within 3 min share a group; 4pt gap inside group, 16pt between groups.
- Day separator: centred `caption labelTertiary` "Today", "Yesterday", "Mon 6 Oct", 24pt vertical margin.
- Timestamp: not shown per message; long-press a message shows time + channel in the context menu header. Last message of a group shows `caption2 labelTertiary` time under it only if > 10 min from the next group.

### 5.2 User messages
- Right aligned. Fill `MagziDesign.mintSoft`, text `MagziDesign.label`, `Typography.body`. Padding 12h × 9v. Corner radius 20 continuous, with the bottom-trailing corner 6 on the last message of a group (build the shape in a plain helper `func bubbleShape(isTail: Bool) -> AnyShape` — not a `@ViewBuilder` — that returns `AnyShape(UnevenRoundedRectangle(...))` inside `if #available(iOS 17, *)` and `AnyShape(RoundedRectangle(cornerRadius: 20, style: .continuous))` otherwise; `AnyShape` is iOS 16).
- Delivery state under last user bubble (`caption2 labelTertiary`): "Sending…" → (nothing once accepted) ; failed → rose `exclamationmark.circle` + "Not sent · Tap to retry".

### 5.3 Magzi messages
- No bubble. Left aligned, full width minus gutter, `Typography.body`, `label`, markdown rendered (existing markdown renderer), line spacing 3.
- Group header (first message only): 20pt Magzi avatar (app logo, 6pt radius) + "Magzi" `caption` semibold `labelSecondary`, 6pt below.
- Code blocks: `surfaceSecondary` fill, radius 12, `mono`, horizontal scroll, copy button top-right (`doc.on.doc`).
- Tool activity (`tool.start/update/result`): one compact row per turn above the reply text: `caption labelSecondary` "Checking calendar…" with a 12pt `ProgressView` while running; when done collapses to "Used 3 tools" + `chevron.right`; tap expands a list of tool rows (icon `checkmark.circle` mint / `xmark.circle` rose, tool name, summary). Never shows raw args by default.

### 5.4 Streaming
- Before the first `message.delta`: typing indicator — three 6pt dots in `labelTertiary`, sequential opacity 0.3→1, 1.2 s cycle (static three dots at 0.5 opacity under Reduce Motion).
- During deltas: text appends in place; no per-character animation. A 6pt mint `MagziStatusDot`-style dot sits inline after the last character while streaming (static under Reduce Motion).
- Autoscroll only if the user is within 80pt of the bottom; otherwise show a floating 36pt circular `surfaceElevated` button with `arrow.down` (+ mint dot if new content) bottom-trailing above the composer.
- `message.final` replaces the streamed text (same id, no flash) and removes the dot. Haptic: none for normal replies.

### 5.5 Proactive messages (Magzi-initiated: briefs, nudges, check-ins)
- Rendered as a card, not plain text: `magziCard(padding: 14)` full width.
- Eyebrow row: `sparkle` mint + `Typography.eyebrow` uppercase `labelSecondary`: "MORNING BRIEF", "CHECK-IN", "HEADS UP" (from message kind; default "FROM MAGZI"), trailing time `caption2 labelTertiary`.
- Body markdown as §5.3. Optional actions from payload render as a row of `MagziCompactButtonStyle` buttons (first prominent).
- Unread proactive messages increment the Magzi tab badge; opening the tab clears it.

### 5.6 Approval and alert cards in chat
- `approval.requested`: `magziCard` with 3pt leading amber rule (an `overlay(alignment: .leading)` `Rectangle` inside the clip shape), `checkmark.shield` amber + "Needs your OK" eyebrow, title `headline`, risk sentence `subheadline labelSecondary`, buttons Deny (`MagziSecondaryButtonStyle`) / Approve (`MagziPrimaryButtonStyle`) side by side, each 44pt min height. After decision: card dims to 60% opacity, buttons replaced by pill "Approved" (mint) / "Denied" (labelSecondary).
- Alerts: same card, rose rule, `exclamationmark.triangle` rose, actions from payload.

### 5.7 Channel badges (unified `person:<id>` thread)
- Every message in the unified thread that did not originate in this app shows a `MagziPill` under the message (user) or after the group header (Magzi), `tint: MagziDesign.labelSecondary`:
  - WhatsApp: title "WhatsApp", symbol `message`.
  - Telegram: "Telegram", `paperplane`.
  - Email: "Email", `envelope`.
  - Other app device: "iPad" / "Mac", `ipad` / `laptopcomputer`.
- App-originated messages show no badge. Badges appear only on the first message of a group.

### 5.8 Composer
- Pinned bar, `surface` background with top hairline, 8pt vertical padding, safe-area aware, keyboard-attached.
- Leading `plus` button (36pt, labelSecondary) → menu: Photo, Camera, File, Capabilities.
- Text field: `TextField(axis: .vertical)` (iOS 16), `lineLimit(1...6)`, `surfaceSecondary` fill, radius 20, padding 10h × 8v, placeholder "Message Magzi".
- Trailing: when empty → `mic` (labelSecondary, dictation); when text → 32pt circular mint send button with `arrow.up` `onAccent` (weight bold). While streaming → `stop.fill` in a `surfaceSecondary` circle (cancels).

---

## 6. Motion and haptics

Motion (all respect `accessibilityReduceMotion` → replace with opacity cross-fade or no animation):
- Default transition: `MagziDesign.Motion.standard` (spring 0.32 / 0.86) for insert/remove of rows and cards; `.transition(.opacity.combined(with: .move(edge: .top)))` for new list items.
- Button press: scale 0.98 + opacity (built into button styles), `Motion.quick`.
- Completion check: circle → `checkmark.circle.fill` with scale 0.8 → 1 spring; row fades out of "open" lists 0.6 s later.
- Ring/bars: animate value changes with `Motion.gentle`; animate from 0 only on first appearance per session.
- Live dot breathing (2.4 s) only for `.live`; typing dots (1.2 s); nothing else loops.
- Connect card step change: cross-fade 0.25 s; no slides.
- Undo toast: slides up from bottom above tab bar, `surfaceElevated`, radius 14, `magziShadow(Shadows.floating)`, text + "Undo" mint button, auto-dismiss 4 s.
- No parallax, no confetti, no gradient shimmer (skeletons use `.redacted` without shimmer).

Haptics (`UIImpactFeedbackGenerator` / `UINotificationFeedbackGenerator`; `sensoryFeedback` is iOS 17 and not used):
- Item/chore done, approval approved, capture saved: `.notificationOccurred(.success)`.
- Approval denied, item dropped, member removed: `.impactOccurred(.medium)`.
- Swipe action threshold, segmented/day picker change, tab-to-chat from capability tile: `UISelectionFeedbackGenerator().selectionChanged()`.
- Send message: `.impactOccurred(.light)`.
- Errors (send failed, action failed): `.notificationOccurred(.error)`.
- Proactive message arrival while app is foreground: none (badge only). Streaming tokens: none.
