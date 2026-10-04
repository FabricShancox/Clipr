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
    @State private var imageActionsAnchor = RowMenuAnchor()
    @State private var sizeMenuAnchor = RowMenuAnchor()
    @State private var editMenuAnchor = RowMenuAnchor()

    private var isSelected: Bool { model.selection.contains(step.id) }

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

    /// List: just the thumbnail (its controls are the ⋯ menu beside the caption). Large and
    /// Guide: the image with its controls on a slim bar directly above its top-right edge —
    /// aligned to the image, not the row, and never covering the picture.
    @ViewBuilder
    private var image: some View {
        if layout == .list {
            imageBox
        } else {
            let showControls = isHovering || isSelected
            VStack(alignment: .trailing, spacing: 6) {
                ReviewRowImageToolbar(
                    step: step, model: model, imageActionsAnchor: imageActionsAnchor, sizeMenuAnchor: sizeMenuAnchor,
                    imageActionEntries: { imageActionEntries }, onOpenEditor: onOpenEditor
                )
                // Space stays reserved while hidden so rows don't jump as the pointer moves;
                // shown on hover and on selected rows so the rest reads like the finished guide.
                // Hidden by opacity only: the controls stay in the accessibility tree, since
                // flipping accessibility attributes on hover changes them during the row's update.
                .opacity(showControls ? 1 : 0)
                .allowsHitTesting(showControls)
                imageBox
            }
            .onHover { isHovering = $0 }
        }
    }

    /// The step's image in a 16:10 box, fitted, so every row in a layout has the same shape.
    private var imageBox: some View {
        Color.black.opacity(0.25)
            .aspectRatio(16.0 / 10.0, contentMode: .fit)
            .overlay(
                ThumbnailView(
                    url: model.thumbnailURL(for: step), contentMode: .fit,
                    maxPixelSize: layout == .list ? ThumbnailCache.maxPixelSize : ThumbnailCache.largePixelSize
                )
                // New identity after the editor closes so the edited image is decoded.
                .id("\(step.id)-\(model.refreshToken)-\(model.imageVersion(of: step.id))-\(layout.rawValue)")
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .onTapGesture(count: 2) { onOpenEditor(step) }
            .help("Double-click to edit the image")
    }

    /// The row's menus are popped up from SwiftUI-drawn buttons as native `NSMenu`s — see
    /// `RowMenuEntry` for why there is no `Menu` (an `NSPopUpButton`) in a List row.
    private var imageActionEntries: [RowMenuEntry] {
        RowMenu.imageActions(
            isReadOnly: model.isReadOnly, isInEditor: model.stepsInEditor.contains(step.id),
            onEdit: { onOpenEditor(step) }, onRetake: { onRetake(step) }, onReplace: { onReplaceWithFile(step) }
        )
    }

    /// Acts on the whole selection when this row is part of it, like the context menu.
    private var imageSizeEntries: [RowMenuEntry] {
        let targets = model.selection.contains(step.id) ? model.selection : [step.id]
        return RowMenu.sizes(current: step.imageSize ?? .full, isReadOnly: model.isReadOnly) { size in
            model.setImageSize(size, for: targets)
        }
    }

    /// List layout: one small ⋯ menu beside the caption (Edit Image first), since the thumbnail
    /// is too small to carry the image toolbar.
    private var compactEditMenu: some View {
        Button {
            RowMenu.popUp(imageActionEntries + [.separator, .submenu("Image Size", enabled: !model.isReadOnly, imageSizeEntries)], anchor: editMenuAnchor)
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(RowMenuAnchorView(anchor: editMenuAnchor))
        .fixedSize()
        .help("Edit, retake, replace or resize the image")
        .accessibilityLabel("Image options")
        .padding(.top, 2)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            ReviewRowCaption(
                step: step, layout: layout, model: model, editingID: $editingID,
                draft: $draft, suppressNextDraftChange: $suppressNextDraftChange, fieldFocused: $fieldFocused
            )
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

    private var kindLabel: String {
        switch step.kind {
        case .click: return "Click"
        case .typing: return "Typing"
        case .manual: return "Manual"
        }
    }
}
