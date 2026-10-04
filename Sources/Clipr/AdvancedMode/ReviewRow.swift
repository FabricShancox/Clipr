// Sources/Clipr/AdvancedMode/ReviewRow.swift
import SwiftUI

/// One step in the Review list: number, thumbnail, caption (rendered, or an inline editor) and
/// the step's app and kind.
struct ReviewRow: View {
    let number: Int
    let step: StepRecord
    @ObservedObject var model: ReviewModel
    @Binding var editingID: UUID?
    let onOpenEditor: (StepRecord) -> Void

    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    private var isEditing: Bool { editingID == step.id }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.accentColor.opacity(0.18)))
                .padding(.top, 4)

            Color.black.opacity(0.25)
                .aspectRatio(16.0 / 10.0, contentMode: .fit)
                .frame(width: 200)
                .overlay(
                    ThumbnailView(url: model.thumbnailURL(for: step), contentMode: .fit)
                        // New identity after the editor closes so the edited image is decoded.
                        .id("\(step.id)-\(model.refreshToken)")
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .onTapGesture(count: 2) { onOpenEditor(step) }
                .help("Double-click to edit the image")

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
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button("Edit") { onOpenEditor(step) }
                .padding(.top, 2)
        }
        .padding(.vertical, 6)
        .onChange(of: editingID) { _, newValue in
            if newValue == step.id {
                model.beginCaptionEdit(for: step.id)
                draft = step.caption ?? ""
                fieldFocused = true
            }
        }
    }

    @ViewBuilder
    private var caption: some View {
        if isEditing {
            TextField("Add a caption", text: $draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .focused($fieldFocused)
                .onChange(of: draft) { _, text in model.editCaption(text, for: step.id) }
                .onSubmit { finishEditing(commit: true) }
                .onExitCommand { finishEditing(commit: false) }
                .onChange(of: fieldFocused) { _, focused in
                    if !focused, isEditing { finishEditing(commit: true) }
                }
        } else {
            Group {
                if let text = step.caption,
                   let rendered = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                    Text(rendered)
                } else {
                    Text("Add a caption").foregroundStyle(.tertiary)
                }
            }
            .font(.body)
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
