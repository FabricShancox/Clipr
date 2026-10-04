// Sources/Clipr/AdvancedMode/ReviewRow.swift
import SwiftUI

/// One step in the Review list: number, thumbnail, caption (rendered, or an inline editor) and
/// the step's app and kind.
struct ReviewRow: View {
    let number: Int
    let step: StepRecord
    let layout: ReviewLayout
    @ObservedObject var model: ReviewModel
    @Binding var editingID: UUID?
    let onOpenEditor: (StepRecord) -> Void
    let onRetake: (StepRecord) -> Void
    let onReplaceWithFile: (StepRecord) -> Void

    @State private var draft = ""
    @State private var suppressNextDraftChange = false
    @FocusState private var fieldFocused: Bool
    @State private var isHovering = false

    private var isSelected: Bool { model.selection.contains(step.id) }

    private var isEditing: Bool { editingID == step.id }

    private static let largeDetailsMinWidth: CGFloat = 180
    /// What else shares a Large row with the image and caption: the number badge, the gaps
    /// between the three, and the list's own row insets.
    private static let largeChromeWidth: CGFloat = 26 + 16 * 2 + 40

    var body: some View {
        content
            .padding(.vertical, layout == .list ? 6 : 10)
            .contextMenu {
                imageActions
                Divider()
                imageSizeMenu
            }
        .onChange(of: editingID) { _, newValue in
            if newValue == step.id {
                model.beginCaptionEdit(for: step.id)
                // Only when it will actually change: an equal value fires no onChange and would
                // leave the flag set to swallow the first real keystroke.
                suppressNextDraftChange = draft != (step.caption ?? "")
                draft = step.caption ?? ""
                // Next run loop: the field only exists once this state change has rendered.
                DispatchQueue.main.async { fieldFocused = true }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch layout {
        case .list:
            HStack(alignment: .top, spacing: 14) {
                numberBadge
                image.frame(width: 200)
                details
                compactEditMenu
            }
        case .large:
            HStack(alignment: .top, spacing: 16) {
                numberBadge
                // About two-thirds of the row: big enough to read the step, leaving room for the
                // caption beside it. In a narrow window the image gives way first, so the caption
                // column never drops below `largeDetailsMinWidth` and wraps a word per line.
                image.containerRelativeFrame(.horizontal) { width, _ in
                    max(120, min(width * 0.62, width - Self.largeDetailsMinWidth - Self.largeChromeWidth))
                }
                details
                    .frame(minWidth: Self.largeDetailsMinWidth)
            }
        case .guide:
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    numberBadge
                    details
                }
                // Guide is the layout that previews the finished document, so only it draws each
                // step at its own size; List and Large keep rows uniform and show a badge instead.
                image
                    .containerRelativeFrame(.horizontal) { width, _ in
                        // Measured: this width already matches the row's content width, so Full
                        // fills the row as the image did before sizes existed.
                        max(120, width * (step.imageSize ?? .full).widthFraction)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var numberBadge: some View {
        Text("\(number)")
            .font(.system(size: 12, weight: .semibold).monospacedDigit())
            .frame(width: 26, height: 26)
            .background(Circle().fill(Color.accentColor.opacity(0.18)))
            .padding(.top, 4)
    }

    /// The step's image in a 16:10 box, fitted, so every row in a layout has the same shape.
    private var image: some View {
        Color.black.opacity(0.25)
            .aspectRatio(16.0 / 10.0, contentMode: .fit)
            .overlay(
                ThumbnailView(
                    url: model.thumbnailURL(for: step), contentMode: .fit,
                    maxPixelSize: layout == .list ? ThumbnailCache.maxPixelSize : ThumbnailCache.largePixelSize
                )
                // New identity after the editor closes so the edited image is decoded.
                .id("\(step.id)-\(model.refreshToken)-\(layout.rawValue)")
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
            // The controls act on the image, so they sit on it — leaving the caption the full
            // width. Shown while the pointer is over the image and on selected rows, so the rest
            // of the list reads like the finished guide. (List thumbnails are too small for this;
            // that layout keeps a compact menu beside the caption.)
            .overlay(alignment: .topTrailing) {
                if layout != .list, isHovering || isSelected {
                    imageToolbar.padding(8)
                }
            }
            .onHover { isHovering = $0 }
            .onTapGesture(count: 2) { onOpenEditor(step) }
            .help("Double-click to edit the image")
    }

    private var imageToolbar: some View {
        HStack(spacing: 6) {
            sizePicker
            Menu {
                imageActions
            } label: {
                Text("Edit")
            } primaryAction: {
                onOpenEditor(step)
            }
            .menuStyle(.borderedButton)
            .fixedSize()
        }
        .controlSize(.small)
        .padding(5)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.12)))
        .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
    }

    /// List layout: one small ⋯ menu beside the caption (Edit Image first), since the thumbnail
    /// is too small to carry the image toolbar.
    private var compactEditMenu: some View {
        Menu {
            imageActions
            Divider()
            imageSizeMenu
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Edit, retake, replace or resize the image")
        .accessibilityLabel("Image options")
        .padding(.top, 2)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            caption
            HStack(spacing: 6) {
                if let app = step.appName {
                    Text(app)
                }
                Text(kindLabel)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.secondary.opacity(0.18)))
                if layout != .guide, let size = step.imageSize, size != .full {
                    Text(size.shortLabel)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.accentColor.opacity(0.18)))
                        .help("Image size: \(size.title)")
                        .accessibilityLabel("Image size: \(size.title)")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var imageActions: some View {
        Button("Edit Image…") { onOpenEditor(step) }
        Divider()
        // Not while an image editor is open on this step: it would write the old image back.
        Button("Retake Screenshot…") { onRetake(step) }
            .disabled(model.isReadOnly || model.stepsInEditor.contains(step.id))
        Button("Replace with File…") { onReplaceWithFile(step) }
            .disabled(model.isReadOnly || model.stepsInEditor.contains(step.id))
    }

    /// The size this step's image takes in the finished guide (drawn at that size in Guide;
    /// shown as a badge in Large).
    private var sizePicker: some View {
        Picker("Image Size", selection: Binding(
            get: { step.imageSize ?? .full },
            set: { model.setImageSize($0, for: [step.id]) }
        )) {
            ForEach(ImageSize.allCases) { size in
                Text(size.shortLabel).help(size.title).accessibilityLabel(size.title).tag(size)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .disabled(model.isReadOnly)
        .help("Image size in the guide (⌘+ / ⌘−)")
    }

    /// Acts on the whole selection when the clicked row is part of it, as Finder's context menu
    /// does; otherwise on the clicked step alone.
    private var imageSizeMenu: some View {
        let targets = model.selection.contains(step.id) ? model.selection : [step.id]
        let current = step.imageSize ?? .full
        return Menu("Image Size") {
            ForEach(ImageSize.allCases) { size in
                Toggle(size.title, isOn: Binding(
                    get: { current == size },
                    set: { _ in model.setImageSize(size, for: targets) }
                ))
            }
        }
        .disabled(model.isReadOnly)
    }

    @ViewBuilder
    private var caption: some View {
        if isEditing {
            TextField("Add a caption", text: $draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .focused($fieldFocused)
                .onChange(of: draft) { _, text in
                    // Setting the initial draft when editing begins isn't a user edit.
                    if suppressNextDraftChange { suppressNextDraftChange = false; return }
                    model.editCaption(text, for: step.id)
                }
                .onSubmit { finishEditing(commit: true) }
                .onExitCommand { finishEditing(commit: false) }
                .onChange(of: fieldFocused) { _, focused in
                    if !focused, isEditing { finishEditing(commit: true) }
                }
        } else {
            Group {
                if let text = step.caption {
                    Text(CaptionText.rendered(text))
                } else {
                    Text("Add a caption").foregroundStyle(.tertiary)
                }
            }
            .font(layout == .list ? .body : .title3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { if !model.isReadOnly { editingID = step.id } }
        }
    }

    /// Esc asks the model to restore the caption as it was when the edit session began, including
    /// undoing any debounced save that already landed while typing.
    private func finishEditing(commit: Bool) {
        editingID = nil
        if commit { model.commitCaption(draft, for: step.id) } else { model.cancelCaptionEdit(for: step.id) }
    }

    private var kindLabel: String {
        switch step.kind {
        case .click: return "Click"
        case .typing: return "Typing"
        case .manual: return "Manual"
        }
    }
}

extension ImageSize {
    var title: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        case .full: return "Full"
        }
    }

    var shortLabel: String {
        switch self {
        case .small: return "S"
        case .medium: return "M"
        case .large: return "L"
        case .full: return "Full"
        }
    }
}
