import SwiftUI

/// A Review row's caption: the rendered text, or an inline editor while `editingID` is this step.
/// The draft and focus live in `ReviewRow`, which starts each edit.
struct ReviewRowCaption: View {
    let step: StepRecord
    let layout: ReviewLayout
    @ObservedObject var model: ReviewModel
    @Binding var editingID: UUID?
    @Binding var draft: String
    @Binding var suppressNextDraftChange: Bool
    var fieldFocused: FocusState<Bool>.Binding

    private var isEditing: Bool { editingID == step.id }

    @ViewBuilder
    var body: some View {
        if isEditing {
            TextField("Add a caption", text: $draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .focused(fieldFocused)
                .onChange(of: draft) { _, text in
                    // Setting the initial draft when editing begins isn't a user edit.
                    if suppressNextDraftChange { suppressNextDraftChange = false; return }
                    model.editCaption(text, for: step.id)
                }
                .onSubmit { finishEditing(commit: true) }
                .onExitCommand { finishEditing(commit: false) }
                .onChange(of: fieldFocused.wrappedValue) { _, focused in
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
}
