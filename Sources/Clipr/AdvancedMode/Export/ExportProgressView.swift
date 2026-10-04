import SwiftUI

/// The sheet shown while a guide exports: progress and Cancel.
struct ExportProgressView: View {
    @ObservedObject var progress: ExportProgress
    let title: String
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            // Progress only measures rendering the step images. What follows (printing the PDF,
            // writing files, converting for the clipboard) can't report its own progress, so a
            // full bar would look stuck; show an indeterminate bar instead.
            if progress.fraction < 1 {
                ProgressView(value: progress.fraction)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
                Text("Finishing…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}
