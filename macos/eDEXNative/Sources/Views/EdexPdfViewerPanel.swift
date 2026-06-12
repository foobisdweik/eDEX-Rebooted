import AppKit
import EdexDomainSupport
import EdexRenderingSupport
import PDFKit
import SwiftUI

/// In-app PDF viewer modal — replaces the "deferred to v0.2" notice with a
/// native PDFKit surface. The file's bytes are read off the main thread so a
/// large document doesn't hitch modal presentation; `PDFDocument` itself
/// parses lazily and pages render on demand.
struct EdexPdfViewerView: View {
    @Bindable var state: ShellState
    let theme: NativeTheme

    @State private var document: PDFDocument?
    @State private var loadFailed = false

    var body: some View {
        Group {
            if let document {
                EdexPdfKitSurface(document: document, background: NSColor(theme.terminalBackground))
            } else {
                Text(loadFailed ? "PDF could not be loaded." : "Loading…")
                    .font(.custom(theme.fonts.terminal, size: 12))
                    .foregroundStyle(theme.terminalForeground.opacity(0.72))
                    .frame(maxWidth: .infinity, minHeight: 180, maxHeight: .infinity)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .augmentedSurface(
            style: .panel(vh: 8),
            fill: theme.terminalBackground.opacity(0.7),
            stroke: theme.accent
        )
        .task(id: state.pdfViewerPath) {
            await loadDocument()
        }
    }

    private func loadDocument() async {
        document = nil
        loadFailed = false
        guard let path = state.pdfViewerPath else {
            loadFailed = true
            return
        }
        // Read + parse off the main thread (xref parsing alone can take tens
        // of ms on large files); pages still render lazily inside PDFView.
        let loaded = await Task.detached(priority: .userInitiated) { () -> PDFDocument? in
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
            return PDFDocument(data: data)
        }.value
        // The modal may have moved to another file while the load ran.
        guard state.pdfViewerPath == path else { return }
        if let loaded {
            document = loaded
        } else {
            loadFailed = true
        }
    }
}

private struct EdexPdfKitSurface: NSViewRepresentable {
    let document: PDFDocument
    let background: NSColor

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = background
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        view.backgroundColor = background
        if view.document !== document {
            view.document = document
            // Setting a document can reset the scale factor; re-assert fit.
            view.autoScales = true
        }
    }
}
