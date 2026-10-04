import SwiftUI

/// Format, title, which steps, and the format's own options. Export hands over to the save panel;
/// Copy goes straight to the clipboard.
struct ExportSheet: View {
    @ObservedObject var model: ExportSheetModel
    let onCancel: () -> Void
    let onExport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Export Guide").font(.headline)
            Form {
                Picker("Format:", selection: $model.options.format) {
                    ForEach(GuideFormat.allCases) { format in
                        Text(format.title).tag(format)
                    }
                }
                TextField("Title:", text: $model.options.title)
                if model.selectionCount > 0 {
                    Picker("Steps:", selection: $model.useSelection) {
                        Text("Selected steps (\(model.selectionCount))").tag(true)
                        Text("All steps (\(model.totalCount))").tag(false)
                    }
                    .pickerStyle(.radioGroup)
                }
                if model.options.format == .gif {
                    LabeledContent("Frame time:") {
                        HStack {
                            Slider(value: $model.options.gifFrameSeconds, in: ExportOptions.gifFrameRange, step: 0.5)
                            Text(String(format: "%.1f s", model.options.gifFrameSeconds))
                                .monospacedDigit()
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                } else {
                    // GIF frames show only the step image, so close-ups don't apply there.
                    Toggle("Include close-ups", isOn: $model.options.includeZoom)
                }
            }
            if model.showsWebAppNote {
                Label(GuideClipboard.webAppNote, systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(model.actionTitle, action: onExport)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canExport)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}
