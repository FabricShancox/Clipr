import SwiftUI

/// The controls above a Large or Guide row's image: the image-size picker (or, when that doesn't
/// fit, a one-letter size menu) and the Edit split button. Everything is drawn in SwiftUI — see
/// `sizePicker` and `RowMenuEntry` for why there is no native `.segmented` Picker or `Menu` here.
struct ReviewRowImageToolbar: View {
    let step: StepRecord
    @ObservedObject var model: ReviewModel
    let imageActionsAnchor: RowMenuAnchor
    let sizeMenuAnchor: RowMenuAnchor
    let imageActionEntries: () -> [RowMenuEntry]
    let onOpenEditor: (StepRecord) -> Void

    var body: some View {
        // Full controls when they fit above the image, otherwise a one-letter size menu.
        // Both variants are drawn in SwiftUI (no native control), so measuring both is cheap.
        ViewThatFits(in: .horizontal) {
            toolbarChrome { sizePicker; imageEditMenu }
            toolbarChrome { compactSizeMenu; imageEditMenu }
        }
    }

    private func toolbarChrome<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 6) { content() }
            .controlSize(.small)
            .fixedSize()
    }

    /// A split button: "Edit" opens the editor, the arrow shows Retake and Replace.
    private var imageEditMenu: some View {
        HStack(spacing: 0) {
            Button { onOpenEditor(step) } label: {
                Text("Edit")
                    .font(.system(size: 11))
                    .padding(.horizontal, 8)
                    .frame(minHeight: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Edit the image")
            .accessibilityLabel("Edit Image")
            Divider().frame(height: 12)
            Button { RowMenu.popUp(imageActionEntries(), anchor: imageActionsAnchor) } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .frame(width: 16, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Edit, retake or replace the image")
            .background(RowMenuAnchorView(anchor: imageActionsAnchor))
            .accessibilityLabel("Image actions")
        }
        .padding(1)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(0.15)))
        .fixedSize()
    }

    private var compactSizeMenu: some View {
        let current = step.imageSize ?? .full
        return Button { RowMenu.popUp(RowMenu.sizes(current: current, isReadOnly: model.isReadOnly) { size in
            model.setImageSize(size, for: [step.id])
        }, anchor: sizeMenuAnchor) } label: {
            HStack(spacing: 3) {
                Text(current.shortLabel).font(.system(size: 11))
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
            }
            .padding(.horizontal, 7)
            .frame(minHeight: 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(RowMenuAnchorView(anchor: sizeMenuAnchor))
        .padding(1)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(0.15)))
        .fixedSize()
        .disabled(model.isReadOnly)
        .help("Image size in the guide (⌘+ / ⌘−)")
        .accessibilityLabel("Image Size")
        .accessibilityValue(current.title)
    }

    /// The size this step's image takes in the finished guide (drawn at that size in Guide;
    /// shown as a badge in Large). Drawn in SwiftUI rather than as `.segmented` Picker: the
    /// native control, inside a List row, sets accessibility attributes while the row is being
    /// updated, which re-enters the row's update and leaves SwiftUI in an attribute cycle it
    /// never exits — the whole app froze when switching to Large or Guide.
    private var sizePicker: some View {
        let current = step.imageSize ?? .full
        return HStack(spacing: 0) {
            ForEach(ImageSize.allCases) { size in
                let selected = size == current
                Button { model.setImageSize(size, for: [step.id]) } label: {
                    Text(size.shortLabel)
                        .font(.system(size: 11, weight: selected ? .semibold : .regular))
                        .frame(minWidth: 24, minHeight: 18)
                        .foregroundStyle(selected ? Color.white : Color.primary)
                        .background(RoundedRectangle(cornerRadius: 4).fill(selected ? Color.accentColor : Color.clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(size.title)
                .accessibilityLabel(size.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(1)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(0.15)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Image Size")
        .fixedSize()
        .disabled(model.isReadOnly)
        .help("Image size in the guide (⌘+ / ⌘−)")
    }
}
