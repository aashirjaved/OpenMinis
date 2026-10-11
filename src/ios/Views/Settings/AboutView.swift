import SwiftUI
import UIKit

struct AboutView: View {
    private let appVersion: String = {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }()

    /// When this binary was built, from the executable's modification date.
    ///
    /// Exists because the version string alone cannot answer "is the fix I
    /// just shipped actually running on that device?" — CFBundleVersion is
    /// static across rebuilds, so an OTA install that silently didn't replace
    /// the app looks identical to one that did. That ambiguity has cost real
    /// debugging time on the test devices. Same source as the debug server's
    /// `buildDate`, but visible in Release too, where no debug server exists.
    private let buildDate: String = {
        guard let url = Bundle.main.executableURL,
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let mod = attrs[.modificationDate] as? Date
        else { return "unknown" }
        let fmt = DateFormatter()
        // Local time, seconds included: this gets compared by eye against the
        // timestamp of a build that just finished.
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return fmt.string(from: mod)
    }()

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    Image("MagziLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 92, height: 92)
                        .padding(14)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .stroke(Color.accentColor.opacity(0.28), lineWidth: 1)
                        )
                    Text("Magzi")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("Version \(appVersion)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Built \(buildDate)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                    Text("Private agent. Clean interface. Serious capability.")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .listRowBackground(Color.clear)
            }

            // MARK: - Links
            Section("Links") {
                Link(destination: URL(string: "https://github.com/OpenMinis")!) {
                    Label {
                        HStack {
                            Text("GitHub Repository")
                                .foregroundStyle(Color(UIColor.label))
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "link.circle.fill")
                    }
                }
                Link(destination: URL(string: "https://github.com/OpenMinis/OpenMinis/issues")!) {
                    Label {
                        HStack {
                            Text("Report an Issue")
                                .foregroundStyle(Color(UIColor.label))
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.circle.fill")
                    }
                }
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}
