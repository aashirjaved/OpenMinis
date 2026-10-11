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
            .lineLimit(1)
            .fixedSize()
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
