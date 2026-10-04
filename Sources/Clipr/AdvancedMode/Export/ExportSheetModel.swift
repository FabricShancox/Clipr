// Sources/Clipr/AdvancedMode/Export/ExportSheetModel.swift
import Foundation

/// The export sheet's state, seeded from the Review session and the last export's choices.
@MainActor
final class ExportSheetModel: ObservableObject {
    @Published var options: ExportOptions
    /// Export only the selected steps. Offered (and on by default) only when Review has a selection.
    @Published var useSelection: Bool

    let selectionCount: Int
    let totalCount: Int

    private let manifest: SessionManifest
    private let folder: URL
    private let selection: Set<UUID>
    private let settings: SettingsStore

    init(manifest: SessionManifest, folder: URL, selection: Set<UUID>, settings: SettingsStore) {
        let live = selection.intersection(manifest.steps.map(\.id))
        self.manifest = manifest
        self.folder = folder
        self.selection = live
        self.settings = settings
        selectionCount = live.count
        totalCount = manifest.steps.count
        options = settings.exportOptions(title: folder.lastPathComponent)
        useSelection = !live.isEmpty
    }

    var stepCount: Int { useSelection ? selectionCount : totalCount }
    var canExport: Bool { stepCount > 0 }
    var actionTitle: String { options.format == .clipboard ? "Copy" : "Export…" }
    var showsWebAppNote: Bool { options.format == .clipboard && GuideClipboard.imagesMayBeDropped }

    func makeDocument() -> GuideDocument {
        GuideDocument.make(manifest: manifest, folder: folder, selection: useSelection ? selection : [], options: options)
    }

    func rememberOptions() {
        settings.rememberExportOptions(options)
    }
}
