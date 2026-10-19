
#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers

struct OfflineMediaDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.mpeg4Movie, .quickTimeMovie, .movie, .item] }

    let sourceURL: URL

    init(sourceURL: URL) {
        self.sourceURL = sourceURL
    }

    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.fileReadUnsupportedScheme)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        try FileWrapper(url: sourceURL, options: [])
    }
}
#endif

#if os(iOS)
import SwiftUI
import PleviCore

extension View {
    /// Presents "Save a Copy…" for `OfflineLibrary.pendingExport`. Attached to the root screen, and
    /// again to the Downloads sheet: a sheet that is up hides the screen beneath it, so an exporter
    /// presented only from the root never appeared when "Save a Copy…" was chosen from the sheet.
    func offlineCopyExporter(_ offlineLibrary: OfflineLibrary) -> some View {
        fileExporter(
            isPresented: Binding(
                get: { offlineLibrary.pendingExport != nil },
                set: { if !$0 { offlineLibrary.pendingExport = nil } }
            ),
            document: offlineLibrary.pendingExport.map { OfflineMediaDocument(sourceURL: $0.sourceURL) },
            contentType: offlineLibrary.pendingExport.flatMap { UTType(filenameExtension: $0.sourceURL.pathExtension) } ?? .mpeg4Movie,
            defaultFilename: offlineLibrary.pendingExport?.suggestedFilename
        ) { _ in
            offlineLibrary.pendingExport = nil
        }
    }
}
#endif
