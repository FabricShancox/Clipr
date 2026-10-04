// Sources/Clipr/AdvancedMode/ReviewView.swift
import SwiftUI

struct ReviewView: View {
    @ObservedObject var model: ReviewModel
    let onOpenEditor: (StepRecord) -> Void
    let onRetake: (StepRecord) -> Void
    let onReplaceWithFile: (StepRecord) -> Void
    let onShowInFinder: () -> Void
    let onExport: () -> Void

    @State private var editingID: UUID?
    /// Same key as `SettingsStore.reviewLayout`, so every Review window opens in the last choice.
    @AppStorage(SettingsStore.reviewLayoutKey) private var layout: ReviewLayout = .list

    var body: some View {
        VStack(spacing: 0) {
            if let notice = model.banner ?? model.readOnlyNotice {
                Label(notice, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.12))
            }
            header
            Divider()
            if model.manifest.steps.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "rectangle.stack").font(.largeTitle).foregroundStyle(.secondary)
                    Text("No steps — press ⌘Z to undo").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                list
            }
        }
        .background(shortcuts)
        // Deleting the row being edited removes its field without a focus-loss callback, which
        // would leave editing "on" and every shortcut disabled.
        .onChange(of: model.manifest.steps.map(\.id)) { _, ids in
            if let id = editingID, !ids.contains(id) { editingID = nil }
        }
    }

    private var header: some View {
        HStack {
            Text(model.manifest.steps.count == 1 ? "1 step" : "\(model.manifest.steps.count) steps")
                .font(.headline)
            if model.selection.count > 1 {
                Text("· \(model.selection.count) selected").foregroundStyle(.secondary)
            }
            Spacer()
            Picker("View", selection: $layout) {
                ForEach(ReviewLayout.allCases) { option in
                    Image(systemName: option.symbol)
                        .help("\(option.title) (⌘\((ReviewLayout.allCases.firstIndex(of: option) ?? 0) + 1))")
                        .tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 120)
            // Switching layout rebuilds every row, and the caption field being edited with it: the
            // new field never gets focus, so the row would be stuck in edit mode.
            .disabled(editingID != nil)
            Button("Delete Selected", role: .destructive) { model.deleteSelection() }
                .disabled(model.selection.isEmpty || model.isReadOnly)
            Button("Show in Finder", action: onShowInFinder)
            Button("Export…", action: onExport)
                .disabled(model.manifest.steps.isEmpty)
                .help("Export the guide (⇧⌘E)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var list: some View {
        List(selection: $model.selection) {
            ForEach(Array(model.manifest.steps.enumerated()), id: \.element.id) { index, step in
                ReviewRow(number: index + 1, step: step, layout: layout, model: model, editingID: $editingID, onOpenEditor: onOpenEditor,
                          onRetake: onRetake, onReplaceWithFile: onReplaceWithFile)
                    .tag(step.id)
            }
            .onMove { model.move(fromOffsets: $0, toOffset: $1) }
            .moveDisabled(model.isReadOnly)
        }
        .listStyle(.inset)
        .onDeleteCommand { if editingID == nil { model.deleteSelection() } }
        .onKeyPress(.return) {
            guard editingID == nil, !model.isReadOnly, model.selection.count == 1, let id = model.selection.first else { return .ignored }
            editingID = id
            return .handled
        }
    }

    /// Keyboard commands Clipr's main menu doesn't provide. Disabled while a caption is being
    /// edited so they don't act on steps while a caption field has focus. Hidden from
    /// accessibility: they're invisible stand-ins for menu items, not controls.
    private var shortcuts: some View {
        Group {
            Button("") { model.undo() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(editingID != nil)
            Button("") { model.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(editingID != nil)
            Button("") { model.moveSelection(by: -1) }
                .keyboardShortcut(.upArrow, modifiers: .option)
                .disabled(editingID != nil || model.isReadOnly)
            Button("") { model.moveSelection(by: 1) }
                .keyboardShortcut(.downArrow, modifiers: .option)
                .disabled(editingID != nil || model.isReadOnly)
            // ⌘= covers US layouts, where "+" needs Shift; ⌘+ is kept for layouts with an unshifted "+". ⌘− as for zoom.
            Button("") { model.stepImageSize(by: 1) }
                .keyboardShortcut("=", modifiers: .command)
                .disabled(editingID != nil || model.isReadOnly || model.selection.isEmpty)
            Button("") { model.stepImageSize(by: 1) }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(editingID != nil || model.isReadOnly || model.selection.isEmpty)
            Button("") { model.stepImageSize(by: -1) }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(editingID != nil || model.isReadOnly || model.selection.isEmpty)
            Button("") { onExport() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(editingID != nil || model.manifest.steps.isEmpty)
            // ⌘1 / ⌘2 / ⌘3, as Finder does for its views.
            ForEach(Array(ReviewLayout.allCases.enumerated()), id: \.element) { index, option in
                Button("") { layout = option }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                    .disabled(editingID != nil)
            }
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
