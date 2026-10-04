// Sources/Clipr/AdvancedMode/Export/ExportFlowController.swift
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Drives one export from a Review window: options sheet → save panel (or folder panel, with a
/// Replace check for Markdown) → progress sheet with Cancel → reveal in Finder, or an alert.
/// Every panel and sheet is attached to the Review window, so only one export runs per window.
@MainActor
final class ExportFlowController {
    private weak var window: NSWindow?
    private let settings: SettingsStore
    private let exporter: GuideExporter
    private var sheetWindow: NSWindow?
    private var task: Task<Void, Never>?
    /// True while the save/folder panel or the Replace alert is up, between the two sheets.
    private var isChoosingDestination = false

    /// `exporter` nil means the real one; it can't be a default argument because default
    /// arguments are evaluated outside the main actor.
    init(window: NSWindow, settings: SettingsStore, exporter: GuideExporter? = nil) {
        self.window = window
        self.settings = settings
        self.exporter = exporter ?? GuideExporter()
    }

    var isActive: Bool { sheetWindow != nil || task != nil || isChoosingDestination }

    func begin(manifest: SessionManifest, folder: URL, selection: Set<UUID>) {
        guard !isActive, let window else { return }
        let model = ExportSheetModel(manifest: manifest, folder: folder, selection: selection, settings: settings)
        let sheet = ExportSheet(
            model: model,
            onCancel: { [weak self] in self?.endSheet() },
            onExport: { [weak self] in self?.confirm(model) }
        )
        present(NSHostingController(rootView: sheet), on: window)
    }

    private func present<Content: View>(_ controller: NSHostingController<Content>, on window: NSWindow) {
        let sheet = NSWindow(contentViewController: controller)
        sheetWindow = sheet
        window.beginSheet(sheet)
    }

    private func endSheet() {
        guard let sheet = sheetWindow else { return }
        window?.endSheet(sheet)
        sheetWindow = nil
    }

    private func confirm(_ model: ExportSheetModel) {
        model.rememberOptions()
        let doc = model.makeDocument()
        let options = model.options
        endSheet()
        if options.format == .clipboard { return run(doc, options: options, destination: nil) }
        isChoosingDestination = true
        // The options sheet must finish closing before the panel can attach to the same window.
        DispatchQueue.main.async { [weak self] in
            self?.chooseDestination(for: options, title: doc.title) { url in
                self?.isChoosingDestination = false
                guard let url else { return }
                self?.run(doc, options: options, destination: url)
            }
        }
    }

    private func chooseDestination(for options: ExportOptions, title: String, completion: @escaping (URL?) -> Void) {
        guard let window else { return completion(nil) }
        if options.format == .markdown {
            let panel = NSOpenPanel()
            panel.title = "Export Markdown"
            panel.message = "Choose a folder for guide.md and its images."
            panel.prompt = "Export"
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.allowsMultipleSelection = false
            panel.beginSheetModal(for: window) { [weak self] response in
                guard response == .OK, let folder = panel.url else { return completion(nil) }
                guard MarkdownGuideWriter.hasExistingGuide(in: folder) else { return completion(folder) }
                DispatchQueue.main.async { self?.confirmReplace(in: folder, completion: completion) }
            }
        } else {
            let panel = NSSavePanel()
            panel.title = "Export \(options.format.title)"
            panel.nameFieldStringValue = options.format.suggestedFileName(for: title)
            panel.allowedContentTypes = [Self.contentType(for: options.format)]
            panel.canCreateDirectories = true
            panel.beginSheetModal(for: window) { response in
                completion(response == .OK ? panel.url : nil)
            }
        }
    }

    private static func contentType(for format: GuideFormat) -> UTType {
        switch format {
        case .pdf: return .pdf
        case .html: return .html
        case .gif: return .gif
        case .markdown, .clipboard: return .folder
        }
    }

    /// Asked when the folder holds a guide.md or an images folder: Replace swaps out the whole
    /// images folder, which may be the user's own rather than an earlier export's.
    private func confirmReplace(in folder: URL, completion: @escaping (URL?) -> Void) {
        guard let window else { return completion(nil) }
        let alert = NSAlert()
        alert.messageText = "This folder already has guide.md or an images folder."
        alert.informativeText = "Replacing overwrites guide.md and the whole images folder in “\(folder.lastPathComponent)”."
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in
            completion(response == .alertFirstButtonReturn ? folder : nil)
        }
    }

    private func run(_ doc: GuideDocument, options: ExportOptions, destination: URL?) {
        guard let window else { return }
        let progress = ExportProgress()
        let title = options.format == .clipboard ? "Copying guide…" : "Exporting \(options.format.title)…"
        present(NSHostingController(rootView: ExportProgressView(
            progress: progress, title: title, onCancel: { [weak self] in self?.task?.cancel() }
        )), on: window)
        let exporter = self.exporter
        task = Task { [weak self] in
            let outcome: Result<[GuideWarning], Error>
            do {
                outcome = .success(try await exporter.export(doc, options: options, to: destination,
                                                             progress: { progress.fraction = $0 }))
            } catch {
                outcome = .failure(error)
            }
            guard let self else { return }
            self.task = nil
            self.endSheet()
            // As with the panels: let the progress sheet finish closing before an alert attaches.
            DispatchQueue.main.async { self.finish(outcome, options: options, destination: destination) }
        }
    }

    private func finish(_ outcome: Result<[GuideWarning], Error>, options: ExportOptions, destination: URL?) {
        switch outcome {
        case .success(let warnings):
            if let destination {
                let revealed = options.format == .markdown
                    ? destination.appendingPathComponent(MarkdownGuideWriter.fileName)
                    : destination
                NSWorkspace.shared.activateFileViewerSelecting([revealed])
            }
            if let summary = GuideWarning.summary(warnings) {
                showAlert("Exported with warnings", summary, style: .informational)
            }
        case .failure(let error):
            if (error as? GuideExportError) == .cancelled { return }
            showAlert(options.format == .clipboard ? "Copy Failed" : "Export Failed", error.localizedDescription, style: .warning)
        }
    }

    private func showAlert(_ message: String, _ detail: String, style: NSAlert.Style) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.alertStyle = style
        alert.beginSheetModal(for: window)
    }
}
