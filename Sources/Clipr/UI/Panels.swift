import Cocoa
import UniformTypeIdentifiers

/// Configured open and save panels. Each returns the panel rather than running it, so callers
/// still choose app-modal or sheet and handle the result themselves. Anything left nil keeps
/// AppKit's default.
enum Panels {
    /// Picks one existing file of `types`.
    static func chooseFile(title: String, prompt: String? = nil, types: [UTType]) -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.title = title
        if let prompt { panel.prompt = prompt }
        panel.allowedContentTypes = types
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        return panel
    }

    /// Picks one folder.
    static func chooseFolder(title: String? = nil, message: String? = nil, prompt: String? = nil,
                             canCreateDirectories: Bool? = nil, startingAt directory: URL? = nil) -> NSOpenPanel {
        let panel = NSOpenPanel()
        if let title { panel.title = title }
        if let message { panel.message = message }
        if let prompt { panel.prompt = prompt }
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        if let canCreateDirectories { panel.canCreateDirectories = canCreateDirectories }
        panel.allowsMultipleSelection = false
        if let directory { panel.directoryURL = directory }
        return panel
    }

    /// Saves one file of `types`, suggesting `name`; new folders can be made from the panel.
    static func saveFile(title: String? = nil, message: String? = nil, name: String, types: [UTType]) -> NSSavePanel {
        let panel = NSSavePanel()
        if let title { panel.title = title }
        if let message { panel.message = message }
        panel.allowedContentTypes = types
        panel.nameFieldStringValue = name
        panel.canCreateDirectories = true
        return panel
    }
}
