import Foundation

/// A step taken out of a manifest, with where it was, so undo can put it back in place.
struct RemovedStep: Equatable {
    let record: StepRecord
    let index: Int
}

/// Edits to a session's step list as pure value transforms. Keeping file access out of here is
/// what lets Review's undo be "swap the old manifest back" and keeps every rule unit-testable.
enum ManifestEditor {
    /// SwiftUI `onMove` semantics: `toOffset` is an index into the original array before which the
    /// moved steps land. Implemented here rather than via SwiftUI's `Array.move` so this file has
    /// no UI dependency.
    static func moving(_ m: SessionManifest, fromOffsets: IndexSet, toOffset: Int) -> SessionManifest {
        let offsets = fromOffsets.filter { $0 < m.steps.count }
        guard !offsets.isEmpty, (0...m.steps.count).contains(toOffset) else { return m }
        var steps = m.steps
        let moving = offsets.map { steps[$0] }
        let before = offsets.filter { $0 < toOffset }.count
        for index in offsets.reversed() { steps.remove(at: index) }
        steps.insert(contentsOf: moving, at: toOffset - before)
        var result = m
        result.steps = steps
        return result
    }

    static func settingCaption(_ caption: String?, forStep id: UUID, in m: SessionManifest) -> SessionManifest {
        guard let index = m.steps.firstIndex(where: { $0.id == id }) else { return m }
        let trimmed = caption?.trimmingCharacters(in: .whitespacesAndNewlines)
        var result = m
        result.steps[index].caption = (trimmed?.isEmpty ?? true) ? nil : trimmed
        return result
    }

    static func removing(ids: Set<UUID>, from m: SessionManifest) -> (SessionManifest, [RemovedStep]) {
        var removed: [RemovedStep] = []
        var kept: [StepRecord] = []
        for (index, step) in m.steps.enumerated() {
            if ids.contains(step.id) { removed.append(RemovedStep(record: step, index: index)) } else { kept.append(step) }
        }
        var result = m
        result.steps = kept
        return (result, removed)
    }

    /// Inserting in ascending original index restores each step to exactly where it was, because
    /// every earlier removed step has already been put back by the time a later one is inserted.
    static func restoring(_ removed: [RemovedStep], into m: SessionManifest) -> SessionManifest {
        var result = m
        for item in removed.sorted(by: { $0.index < $1.index }) {
            result.steps.insert(item.record, at: min(item.index, result.steps.count))
        }
        return result
    }
}
