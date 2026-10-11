import QuickLook
import SwiftUI

/// Weekly summary PDF → temp file → QuickLook.
struct HhSummaryView: View {
    let householdId: String

    private enum Phase: Equatable {
        case loading
        case ready(URL)
        case empty
        case failed(String)
    }

    @State private var phase: Phase = .loading

    var body: some View {
        content
            .navigationTitle("Weekly summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if case .ready(let url) = phase {
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                    }
                }
            }
            .task { if phase == .loading { await load() } }
            .hhOnHouseholdChange(householdId) {
                if case .ready = phase { return }
                await load()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            ProgressView("Preparing this week's summary…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .magziScreenBackground()
        case .ready(let url):
            HhQuickLookPreview(url: url)
                .ignoresSafeArea(edges: .bottom)
        case .empty:
            ScrollView {
                MagziEmptyState(
                    systemImage: "doc.richtext",
                    title: "No summary yet",
                    message: "Magzi writes one every Sunday evening."
                )
                .padding(.top, MagziDesign.Spacing.xxxl)
            }
            .magziScreenBackground()
            .refreshable { await load() }
        case .failed(let message):
            ScrollView {
                HhErrorCard(message: message) { Task { await load() } }
                    .padding(MagziDesign.Spacing.gutter)
            }
            .magziScreenBackground()
            .refreshable { await load() }
        }
    }

    private func load() async {
        if case .ready = phase {} else { phase = .loading }
        do {
            let data = try await MagziAPI.shared.summaryPDF(householdId: householdId)
            let safeId = householdId.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("magzi-summary-\(safeId)-\(HhFormat.isoWeek(Date())).pdf")
            try data.write(to: url, options: .atomic)
            phase = .ready(url)
        } catch {
            if HhErrors.isCancellation(error) { return }
            phase = HhErrors.status(error) == 404 ? .empty : .failed(HhErrors.message(error))
        }
    }
}

/// QLPreviewController wrapper for a single local file.
struct HhQuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        if context.coordinator.url != url {
            context.coordinator.url = url
            controller.reloadData()
        }
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) { self.url = url }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}
