import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// Admin → WhatsApp pairing. Polls `GET /admin/qr` every 5 s while visible.
struct MeAdminPairingView: View {
    @State private var qr: MagziAdminQR?
    @State private var error: Error?
    @State private var image: UIImage?
    @State private var lastPayload: String?

    private var payload: String? { qr?.pairing?.qr?.magziNonEmpty }
    private var state: String { qr?.whatsappState?.magziNonEmpty ?? "unknown" }
    private var isLinked: Bool {
        let s = state.lowercased()
        return payload == nil && (s.contains("open") || s.contains("connected"))
    }

    var body: some View {
        MeAreaScroll(refresh: load) {
            if let error, qr == nil {
                MeAreaErrorCard(error: error) { Task { await load() } }
            } else {
                card.redacted(reason: qr == nil ? .placeholder : [])
            }
        }
        .navigationTitle("WhatsApp pairing")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    private var card: some View {
        VStack(spacing: MagziDesign.Spacing.l) {
            HStack(spacing: MagziDesign.Spacing.s) {
                MagziStatusDot(isLinked ? .ok : (payload != nil ? .attention : .off))
                Text("WhatsApp: \(MeAreaFormat.humanize(state))")
                    .font(MagziDesign.Typography.headline)
                    .foregroundStyle(MagziDesign.label)
                Spacer()
            }
            if let image, payload != nil {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 240, height: 240)
                    .padding(MagziDesign.Spacing.l)
                    .background(RoundedRectangle(cornerRadius: MagziDesign.Radius.card, style: .continuous).fill(Color.white))
                    .accessibilityLabel("WhatsApp pairing QR code")
                Text("Open WhatsApp → Linked devices → Link a device.")
                    .font(MagziDesign.Typography.subheadline)
                    .foregroundStyle(MagziDesign.labelSecondary)
                    .multilineTextAlignment(.center)
                if let at = qr?.pairing?.at {
                    Text("Code from \(MeAreaFormat.time(at)) · refreshes every 5 s")
                        .font(MagziDesign.Typography.caption)
                        .foregroundStyle(MagziDesign.labelTertiary)
                }
            } else if isLinked {
                MagziEmptyState(systemImage: "checkmark.seal", title: "WhatsApp is already linked.",
                                message: "Nothing to pair. A new code appears here if WhatsApp asks to be linked again.")
            } else {
                MagziEmptyState(systemImage: "qrcode", title: "No pairing code yet",
                                message: "Magzi shows a code here when WhatsApp needs to be linked. This page checks every 5 seconds.")
            }
            if let error, qr != nil {
                MeAreaBanner(text: MeAreaFailure.message(error), tint: MagziDesign.amber)
            }
        }
        .magziCard()
    }

    private func load() async {
        do {
            let r = try await MagziAPI.shared.adminQR()
            qr = r
            error = nil
            let p = r.pairing?.qr?.magziNonEmpty
            if p != lastPayload {
                lastPayload = p
                image = p.flatMap(Self.render)
            }
        } catch is CancellationError {
        } catch {
            self.error = error
        }
    }

    private static func render(_ string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
