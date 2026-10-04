import Cocoa

/// The header's user actions on the open capture: rename, Save As, copy, share, and deleting a
/// Recent.
extension EditorWindowController {
    /// Renames the open capture from the header field. `annotations` are flushed synchronously
    /// against the OLD `rawURL` first — the same reason `loadCapture` does it — so an edit that
    /// hadn't reached its debounce yet is written before the files move, rather than firing
    /// afterwards against a path that no longer exists and being dropped by `autoSave`'s guard.
    ///
    /// Rebuilding the content view re-reads Recents, so the sidebar picks up the new name too.
    /// Unlike auto-save this is a direct user action, so a failure is surfaced rather than logged.
    func rename(_ url: URL, to newName: String, annotations: [AnnotationObject]) {
        guard url == rawURL else { return }
        persist(annotations)
        do {
            // A rename changes nothing about the image or its annotations, so the undo history is
            // carried across the rebuild rather than discarded.
            let history = latestHistory
            rawURL = try storage.renameCapture(rawURL: rawURL, toBaseName: newName)
            window?.contentView = makeContentView(initialAnnotations: annotations, history: history)
        } catch {
            NSLog("Clipr: rename failed: \(error)")
            Alerts.present("Couldn't rename this capture",
                           "\(url.lastPathComponent) was left unchanged.\n\n\(error.localizedDescription)", on: window)
        }
    }

    /// Exports a flattened copy wherever the user chooses, in PNG or JPEG.
    ///
    /// Separate from the capture's own file: auto-save already keeps that current in the save
    /// folder, so this is for handing a copy to someone else, in a format they can use.
    func saveAs(annotations: [AnnotationObject]) {
        guard let window else { return }
        let panel = Panels.saveFile(message: "Export a copy of this capture",
                                    name: rawURL.deletingPathExtension().lastPathComponent,
                                    types: ExportFormat.allCases.map(\.contentType))
        // Snapshot the image now. The capture hotkey is global, so a new capture (or a Recent)
        // can replace `self.image` while this sheet is up; reading it at Save time exported the
        // new image with the old capture's annotations drawn on it.
        let image = self.image

        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            // The format follows the extension the panel settled on, so picking a type in its
            // filter or typing ".jpg" both do what the user expects.
            let format = ExportFormat.allCases.first { $0.fileExtension == url.pathExtension.lowercased() }
                ?? (url.pathExtension.lowercased() == "jpeg" ? .jpeg : .png)
            let flattened = AnnotationRenderer.flatten(base: image, annotations: annotations)
            do {
                try self.storage.export(flattened, to: url, format: format)
            } catch {
                NSLog("Clipr: export failed: \(error)")
                Alerts.present("Couldn't export the image", error.localizedDescription, on: window)
            }
        }
    }

    /// Confirms, then moves a Recent capture (and its edited copy and annotations) to the Trash.
    /// The × on a thumbnail is small and sits on every tile, so one mis-click used to delete a
    /// capture permanently with no warning; a failure was swallowed and the tile hidden anyway.
    func deleteRecent(_ url: URL, then deleted: @escaping () -> Void) {
        guard let window else { return }
        Alerts.present("Move “\(url.lastPathComponent)” to the Trash?",
                       "Its edited copy and annotations go too. You can put them back from the Trash in Finder.",
                       buttons: ["Move to Trash", "Cancel"], on: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            do {
                try self.storage.deleteCapture(rawURL: url)
                ThumbnailCache.shared.remove(url)
                deleted()
            } catch {
                NSLog("Clipr: couldn't move \(url.lastPathComponent) to the Trash: \(error)")
                Alerts.present("Couldn't move this capture to the Trash",
                               "\(url.lastPathComponent) was left where it is.\n\n\(error.localizedDescription)", on: window)
            }
        }
    }

    func copy(annotations: [AnnotationObject]) {
        let flattened = AnnotationRenderer.flatten(base: image, annotations: annotations)
        storage.copyToClipboard(AnnotationRenderer.applying(settings.copyStyle, to: flattened))
    }
}
